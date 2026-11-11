"""Run Proton with UE4SS and service the camera's native Linux folder requests."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path, PureWindowsPath


def dll_overrides(value):
    kept = []
    for entry in value.split(';'):
        if '=' not in entry:
            continue
        names, rule = entry.split('=', 1)
        names = [n for n in names.split(',') if n.strip().lower().removesuffix('.dll') != 'dwmapi']
        if names:
            kept.append(','.join(names) + '=' + rule)
    return ';'.join(kept + ['dwmapi=n,b'])


def prefix_path(config, env):
    candidates = []
    if env.get('STEAM_COMPAT_DATA_PATH'):
        candidates.append(Path(env['STEAM_COMPAT_DATA_PATH']) / 'pfx')
    if env.get('WINEPREFIX'):
        candidates.append(Path(env['WINEPREFIX']))
    if config.get('prefix'):
        candidates.append(Path(config['prefix']))
    for path in candidates:
        if (path / 'drive_c').is_dir():
            return path.resolve()
    raise RuntimeError('Proton prefix unavailable. Run VHOLUME once, then check the installer --prefix option.')


def unix_path(value, prefix):
    if any(c in value for c in '\x00\r\n'):
        raise ValueError('Invalid folder path')
    path = PureWindowsPath(value)
    if not re.fullmatch(r'[A-Za-z]:', path.drive) or not path.is_absolute():
        raise ValueError('Expected an absolute Proton drive path')
    devices = prefix / 'dosdevices'
    if not devices.is_dir():
        if path.drive.lower() != 'c:':
            raise ValueError('This drive is not mapped in the Proton prefix')
        drive = prefix / 'drive_c'
    else:
        drive = devices / path.drive.lower()
        if not drive.exists() and path.drive.lower() == 'c:':
            drive = prefix / 'drive_c'
    if not drive.exists():
        raise ValueError('This drive is not mapped in the Proton prefix')
    return drive.joinpath(*path.parts[1:]).resolve()


def windows_path(value, prefix):
    path = Path(value).resolve()
    roots = [('c:', prefix / 'drive_c')]
    if (prefix / 'dosdevices').is_dir():
        roots += [(p.name, p) for p in (prefix / 'dosdevices').iterdir()
                  if re.fullmatch(r'[a-zA-Z]:', p.name) and p.exists()]
    matches = []
    for drive, root in roots:
        root = root.resolve()
        try:
            relative = path.relative_to(root)
        except ValueError:
            continue
        suffix = '' if relative == Path('.') else relative.as_posix()
        matches.append((len(root.parts), drive.upper() + '/' + suffix))
    if not matches:
        raise ValueError('The selected folder is outside the drives mapped by Proton')
    result = max(matches)[1].rstrip('/') + '/'
    if any(c in result for c in '\x00\r\n"<>|?*') or ':' in result[2:]:
        raise ValueError('The selected folder cannot be used as a Windows screenshot path')
    return result


def prepare(path):
    path.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix='.photo-camera-', dir=path):
        pass


class FolderService:
    def __init__(self, ipc, config, env=None):
        self.ipc, self.config = ipc, config
        self.env = dict(os.environ if env is None else env)
        # Desktop tools must use their system libraries, not Steam's injected ones.
        for key in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'PYTHONHOME', 'PYTHONPATH'):
            self.env.pop(key, None)
        self.child = None
        self.child_lock = threading.Lock()
        self.stop = threading.Event()
        self.failed_requests = set()

    def run_tool(self, args):
        with self.child_lock:
            if self.stop.is_set():
                return 1, '', 'Game session ended'
            child = subprocess.Popen(args, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True)
            self.child = child
        try:
            stdout, stderr = child.communicate()
            return child.returncode, stdout.strip(), stderr.strip()
        finally:
            with self.child_lock:
                if self.child is child:
                    self.child = None

    def close(self):
        self.stop.set()
        with self.child_lock:
            child = self.child
        if child and child.poll() is None:
            try:
                child.terminate()
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=2)
            except ProcessLookupError:
                pass

    def choose(self, initial):
        if shutil.which('zenity'):
            args = ['zenity', '--file-selection', '--directory', '--title=VHOLUME photo folder',
                    '--filename=' + str(initial) + '/']
        elif shutil.which('kdialog'):
            args = ['kdialog', '--title', 'VHOLUME photo folder', '--getexistingdirectory', str(initial)]
        else:
            return 'NO_DIALOG'
        code, value, _ = self.run_tool(args)
        if code == 1:
            return 'CANCELLED'
        if code or not value or not Path(value).is_absolute():
            return 'ERROR'
        prefix = prefix_path(self.config, self.env)
        selected = windows_path(value, prefix)
        prepare(Path(value))
        return 'OK\n' + selected

    def handle(self, action, value):
        if action not in ('Choose', 'Open', 'Prepare'):
            raise ValueError('Unknown folder request')
        prefix = prefix_path(self.config, self.env)
        path = unix_path(value, prefix)
        if action == 'Choose':
            return self.choose(path)
        prepare(path)
        if action == 'Open':
            if shutil.which('xdg-open'):
                code, _, _ = self.run_tool(['xdg-open', path.as_uri()])
            elif shutil.which('gio'):
                code, _, _ = self.run_tool(['gio', 'open', path.as_uri()])
            else:
                return 'NO_OPENER'
            if code:
                return 'ERROR'
        return 'OK\n' + value

    def process(self, request):
        if not re.fullmatch(r'request-\d+-\d+\.txt', request.name) or request.is_symlink():
            return
        reply = request.with_name(request.name.replace('request-', 'reply-', 1))
        try:
            if request.stat().st_size > 32780:
                raise ValueError('Oversized folder request')
            action, value = request.read_text(encoding='utf-8').split('\n', 1)
            answer = self.handle(action, value)
        except Exception as error:
            print('Photo Camera folder helper:', error, file=sys.stderr)
            answer = 'ERROR'
        temp = reply.with_suffix('.tmp')
        temp.write_text(answer, encoding='utf-8')
        temp.replace(reply)
        request.unlink(missing_ok=True)

    def worker(self):
        while not self.stop.wait(.1):
            for request in sorted(self.ipc.glob('request-*.txt')):
                if self.stop.is_set():
                    return
                if request.name in self.failed_requests:
                    continue
                try:
                    self.process(request)
                except OSError as error:
                    # A failed reply must not terminate the worker or block later requests.
                    self.failed_requests.add(request.name)
                    print('Photo Camera request I/O:', error, file=sys.stderr)


def launch(argv, base=None):
    import fcntl

    if not argv:
        raise RuntimeError('Use the complete Steam launch option printed by the Linux installer.')
    base = base or Path(__file__).resolve().parent
    config = json.loads((base / 'install.json').read_text(encoding='utf-8'))
    ipc = base / 'ipc'
    ipc.mkdir(mode=0o700, exist_ok=True)
    if ipc.is_symlink():
        raise RuntimeError('The helper request directory must not be a symlink')
    with (base / '.bridge.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('A Photo Camera game session is already running')
        for pattern in ('request-*.txt', 'reply-*.txt', '*.tmp', 'ready'):
            for path in ipc.glob(pattern):
                if path.is_file() or path.is_symlink():
                    path.unlink()
        service = FolderService(ipc, config)
        worker = threading.Thread(target=service.worker, daemon=True)
        env = dict(os.environ)
        env['WINEDLLOVERRIDES'] = dll_overrides(env.get('WINEDLLOVERRIDES', ''))
        env['VHOLUME_PHOTO_LINUX'] = '1'
        game = None
        worker.start()
        try:
            game = subprocess.Popen(argv, env=env)
            while game.poll() is None:
                (ipc / 'ready.tmp').write_text(str(int(time.time())), encoding='ascii')
                (ipc / 'ready.tmp').replace(ipc / 'ready')
                time.sleep(.3)
            return game.returncode
        except KeyboardInterrupt:
            if game and game.poll() is None:
                game.terminate()
                game.wait()
            return 130
        finally:
            service.close()
            worker.join(timeout=2)
            (ipc / 'ready').unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        sys.exit(launch(sys.argv[1:]))
    except Exception as error:
        print('VHOLUME Photo Camera:', error, file=sys.stderr)
        sys.exit(1)
