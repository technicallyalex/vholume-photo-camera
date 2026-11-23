"""Translate Proton RAW jobs and run the bundled native Linux DNG converter."""
import base64
import os
import re
import subprocess
import sys
import threading
from pathlib import Path


def decode(value):
    return base64.b64decode(value, validate=True).decode('utf-8')


def encode(value):
    return base64.b64encode(str(value).encode('utf-8')).decode('ascii')


def reply(path, message):
    # Keep a completed worker's reply if a duplicate/stale request arrives.
    if path.exists():
        return
    temp = path.with_name(path.name + '.host-tmp')
    temp.write_text(message, encoding='utf-8')
    if not path.exists():
        temp.replace(path)
    else:
        temp.unlink(missing_ok=True)


class NativeDngService:
    def __init__(self, ipc, config, env, unix_path, prefix_path, helper=None):
        self.ipc, self.config, self.env = ipc, config, dict(env)
        self.unix_path, self.prefix_path = unix_path, prefix_path
        self.helper = helper or Path(__file__).resolve().parent / 'Native/PhotoCameraDng'
        self.children = {}
        self.stop = threading.Event()

    def job(self, encoded):
        prefix = self.prefix_path(self.config, self.env)
        path = self.unix_path(decode(encoded), prefix)
        if not re.fullmatch(r'VHOLUMEPhotoCamera\.dng-job-\d+-\d+-\d+', path.name):
            raise ValueError('Invalid DNG job name')
        if [v.lower() for v in path.parent.parts[-2:]] != ['vholume', 'saved']:
            raise ValueError('DNG job must be in the game Saved directory')
        if not path.is_file():
            return None  # A queued request can outlive an already acknowledged/cancelled job.
        if path.is_symlink() or path.stat().st_size > 65536:
            raise ValueError('Invalid DNG job file')
        fields = {}
        for line in path.read_text(encoding='utf-8').splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                if key in fields:
                    raise ValueError('Duplicate DNG job field')
                fields[key] = value
        if fields.get('version') != '1':
            raise ValueError('Unsupported DNG job')
        source = self.unix_path(decode(fields['source']), prefix)
        destination = self.unix_path(decode(fields['destination']), prefix)
        result = self.unix_path(decode(fields['result']), prefix)
        if not source.name.startswith('VHOLUME_') or not source.name.endswith('.part.exr'):
            raise ValueError('Invalid HDR source')
        if destination != Path(str(source)[:-9] + '.part.dng') or result != Path(str(path) + '.result'):
            raise ValueError('DNG job paths do not match')
        for name, value in [('source', source), ('destination', destination), ('result', result), ('control', path)]:
            fields[name] = encode(value)
        body = ''.join(key + '=' + value + '\n' for key, value in fields.items())
        return path, result, encode(body)

    def process(self, request):
        if not re.fullmatch(r'dng-request-\d+-\d+-\d+\.txt', request.name) or request.is_symlink():
            return
        result = None
        try:
            if request.stat().st_size > 45000:
                raise ValueError('Oversized DNG request')
            job = self.job(request.read_text(encoding='ascii'))
            if job is None:
                return
            path, result, data = job
            if path in self.children or result.exists():
                return
            # Native AOT: no Wine, Windows .NET, system SDK, or Python image libraries.
            child = subprocess.Popen([str(self.helper), '--job-data', data], env=self.env,
                                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.PIPE, start_new_session=True)
            self.children[path] = (child, result)
        except Exception as error:
            print('Photo Camera DNG helper:', error, file=sys.stderr)
            if result is not None:
                reply(result, 'ERROR\nLinux helper: ' + str(error))
        finally:
            request.unlink(missing_ok=True)

    def poll(self):
        for path, (child, result) in list(self.children.items()):
            if child.poll() is None:
                continue
            _, stderr = child.communicate()
            # Exit 4 means an earlier native converter owns this job's lock.
            if child.returncode not in (0, 4) and not result.exists():
                reply(result, 'ERROR\nLinux converter exited ' + str(child.returncode) + ': ' + stderr.decode('utf-8', 'replace')[:2000])
            self.children.pop(path)
        if not self.children:
            for request in sorted(self.ipc.glob('dng-request-*.txt')):
                self.process(request)
                if self.children:
                    break

    def worker(self):
        while not self.stop.wait(.1):
            try:
                self.poll()
            except OSError as error:
                print('Photo Camera DNG request I/O:', error, file=sys.stderr)

    def close(self):
        # The active native conversion survives game exit, like the Windows worker.
        self.stop.set()
