#!/usr/bin/env python3
"""Install VHOLUME Photo Camera's Linux/Proton preview without root access."""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import sys
import tempfile
import uuid
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath

APP_ID = '4131730'
MOD_NAME = 'VHOLUMEPhotoCamera'
MOD_ARCHIVE = 'VHOLUME-Photo-Camera-Linux-Mod.zip'
LOADER_ARCHIVE = 'UE4SS_v3.0.1-1011-gb50986bd.zip'
MOD_SHA256 = '9b805f9f4bfef684be39aa37784021fd88f3db5547523a9fa9ac8b5e395fe7ae'
LOADER_SHA256 = 'aa181789dc7226bcec94f13f054ff10477d7383321ffb98dbc3666a159b182a8'
LOADER_DLL_SHA256 = '2ad348bf2025bd26b2aa63b478d9813afbd4e656c9bcfb3fdf6752c4d285f298'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def game_bin(path):
    path = Path(path).expanduser().resolve()
    for candidate in (path, path / 'VHOLUME/Binaries/Win64'):
        if (candidate / 'VHOLUME-Win64-Shipping.exe').is_file():
            return candidate
    raise ValueError('Cannot find VHOLUME-Win64-Shipping.exe in the selected game folder')


def steam_games(home=None):
    home = home or Path.home()
    roots = [home / '.local/share/Steam', home / '.steam/steam', home / '.steam/root',
             home / '.var/app/com.valvesoftware.Steam/.local/share/Steam']
    if os.environ.get('XDG_DATA_HOME'):
        roots.insert(0, Path(os.environ['XDG_DATA_HOME']) / 'Steam')
    libraries = set(p.resolve() for p in roots if p.is_dir())
    for root in list(libraries):
        vdf = root / 'steamapps/libraryfolders.vdf'
        if vdf.is_file():
            for value in re.findall(r'"path"\s*"((?:\\.|[^"\\])*)"', vdf.read_text(encoding='utf-8')):
                libraries.add(Path(value.replace('\\\\', '\\').replace('\\"', '"')).expanduser().resolve())
    found = set()
    for library in libraries:
        manifest = library / ('steamapps/appmanifest_' + APP_ID + '.acf')
        if not manifest.is_file():
            continue
        match = re.search(r'"installdir"\s*"([^"/\\]+)"', manifest.read_text(encoding='utf-8'))
        if not match or match[1] in ('.', '..'):
            continue
        try:
            found.add(game_bin(library / 'steamapps/common' / match[1]))
        except ValueError:
            pass
    return sorted(found)


def default_prefix(bin_path):
    for parent in bin_path.parents:
        if parent.name == 'steamapps':
            return parent / ('compatdata/' + APP_ID + '/pfx')
    return None


def game_running(proc=Path('/proc')):
    if not proc.is_dir():
        return False
    for path in proc.glob('[0-9]*/cmdline'):
        try:
            words = path.read_bytes().split(b'\0')
        except OSError:
            continue
        if any(word.replace(b'\\', b'/').split(b'/')[-1].lower()
               in (b'vholume.exe', b'vholume-win64-shipping.exe') for word in words):
            return True
    return False


def check_directory(path):
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        raise ValueError('Custom/symlinked mod paths require manual installation: ' + str(path))


def check_inputs(package, bin_path):
    for name, expected in ((MOD_ARCHIVE, MOD_SHA256), (LOADER_ARCHIVE, LOADER_SHA256)):
        file = package / name
        if not file.is_file() or digest(file) != expected:
            raise ValueError('Missing or damaged archive: ' + name)
    loader = bin_path / 'ue4ss'
    for path in (loader, loader / 'Mods', loader / 'Mods' / MOD_NAME):
        check_directory(path)
    proxy, core = bin_path / 'dwmapi.dll', loader / 'UE4SS.dll'
    existing = proxy.is_file() and core.is_file()
    if not existing and any(p.exists() for p in (proxy, core, bin_path / 'UE4SS.dll', bin_path / 'xinput1_3.dll')):
        raise ValueError('Partial or custom UE4SS loader found; resolve it before using this installer')
    return existing


def extract_mod(archive, destination):
    prefix = 'ue4ss/Mods/' + MOD_NAME + '/'
    count = 0
    for entry in archive.infolist():
        if not entry.filename.startswith(prefix) or entry.is_dir():
            continue
        name = PurePosixPath(entry.filename[len(prefix):])
        if not name.parts or name.is_absolute() or '..' in name.parts or '\\' in str(name):
            raise ValueError('Unsafe path in mod archive')
        if stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError('Symlink in mod archive')
        path = destination.joinpath(*name.parts)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(archive.read(entry))
        count += 1
    if count != 103 or not (destination / 'Scripts/main.lua').is_file():
        raise ValueError('Unexpected mod payload')


def launch_option(bin_path):
    return 'python3 ' + shlex.quote(str(bin_path / 'ue4ss/Mods' / MOD_NAME / 'Proton/bridge.py')) + ' %command%'


def install(package, bin_path, prefix=None, dry_run=False, running_check=game_running):
    bin_path = game_bin(bin_path)
    existing = check_inputs(package, bin_path)
    if running_check():
        raise RuntimeError('Close VHOLUME before installing')
    if existing and digest(bin_path / 'ue4ss/UE4SS.dll') != LOADER_DLL_SHA256:
        print('Notice: preserving an existing UE4SS build that differs from the bundled version.')
    prefix = Path(prefix).expanduser().resolve() if prefix else default_prefix(bin_path)
    if dry_run:
        print('Dry run OK. Game:', bin_path)
        print('Steam launch option:', launch_option(bin_path))
        return None
    loader = bin_path / 'ue4ss'
    mods = loader / 'Mods'
    destination = mods / MOD_NAME
    stage = Path(tempfile.mkdtemp(prefix='.PhotoCamera-install-', dir=bin_path))
    backup = None
    created = []
    try:
        pending = stage / MOD_NAME
        with zipfile.ZipFile(package / MOD_ARCHIVE) as archive:
            extract_mod(archive, pending)
        proton = pending / 'Proton'
        (proton / 'ipc').mkdir(mode=0o700)
        (proton / 'install.json').write_text(json.dumps({'prefix': str(prefix) if prefix else None,
            'app_id': APP_ID, 'version': '1.0.2-linux.2'}, indent=2) + '\n', encoding='utf-8')
        (proton / 'launch.sh').chmod(0o755)
        if running_check():
            raise RuntimeError('VHOLUME started during installation; close it and retry')
        mods.mkdir(parents=True, exist_ok=True)
        if not existing:
            with zipfile.ZipFile(package / LOADER_ARCHIVE) as archive:
                for name in ('dwmapi.dll', 'ue4ss/UE4SS.dll', 'ue4ss/LICENSE', 'ue4ss/UE4SS-settings.ini'):
                    target = bin_path / name
                    if target.exists() and name in ('ue4ss/LICENSE', 'ue4ss/UE4SS-settings.ini'):
                        continue
                    data = archive.read(name)
                    with target.open('xb') as stream:
                        created.append((target, hashlib.sha256(data).hexdigest()))
                        stream.write(data)
        if destination.exists():
            backup = loader / ('PhotoCamera-backup-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
            destination.rename(backup)
        pending.rename(destination)
    except BaseException:
        if backup and backup.exists() and not destination.exists():
            backup.rename(destination)
        for path, expected in reversed(created):
            if path.is_file() and digest(path) == expected:
                path.unlink()
        raise
    finally:
        if stage.parent.resolve() != bin_path.resolve() or not stage.name.startswith('.PhotoCamera-install-') or stage.is_symlink():
            raise RuntimeError('Unexpected installation staging path')
        shutil.rmtree(stage)
    option = launch_option(bin_path)
    (loader / 'PhotoCamera-Linux-Launch-Options.txt').write_text(option + '\n', encoding='utf-8')
    print('Installed Photo Camera 1.0.2 Linux/Proton preview.')
    if backup:
        print('Previous mod backed up to:', backup)
    print('Steam > VHOLUME > Properties > Launch Options:\n' + option)
    if not prefix or not (prefix / 'drive_c').is_dir():
        print('Run the game once through Proton to create its prefix. The launcher also reads Steam\'s prefix environment.')
    return backup


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-path', type=Path, help='VHOLUME folder from Steam > Browse local files')
    parser.add_argument('--prefix', type=Path, help='Custom Proton pfx directory, if needed')
    parser.add_argument('--dry-run', action='store_true', help='Validate without writing files')
    args = parser.parse_args(argv)
    if sys.platform != 'linux' or sys.version_info < (3, 9):
        raise RuntimeError('Run this installer on Linux with Python 3.9 or newer')
    bins = [game_bin(args.game_path)] if args.game_path else steam_games()
    if len(bins) != 1:
        for path in bins:
            print('Found:', path)
        raise RuntimeError('Use --game-path with the VHOLUME folder from Steam > Browse local files')
    if args.dry_run:
        return install(Path(__file__).resolve().parent, bins[0], args.prefix, True)
    import fcntl
    with (bins[0] / '.PhotoCamera-installer.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        install(Path(__file__).resolve().parent, bins[0], args.prefix)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Photo Camera installer:', error, file=sys.stderr)
        sys.exit(1)
