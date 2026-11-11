"""Fixture tests; these do not claim a live Linux/Proton gameplay session."""

import contextlib
import ctypes
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import types
import unittest
import zipfile
from pathlib import Path
from pathlib import PurePosixPath
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / 'ue4ss/Mods/VHOLUMEPhotoCamera'
PACKAGE = ROOT / '.work/linux-package'
WORK = ROOT / '.work'
WORK.mkdir(exist_ok=True)


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    value = importlib.util.module_from_spec(spec)
    exec(compile(file.read_bytes(), str(file), 'exec'), value.__dict__)
    return value


installer = module('linux_installer', ROOT / 'installer/linux/install-linux.py')
bridge = module('linux_bridge', MOD / 'Proton/bridge.py')


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}


class Fixtures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='linux-test-', dir=WORK)
        self.root = Path(self.temp.name)
        assert self.root.parent.resolve() == WORK.resolve()
        self.addCleanup(self.temp.cleanup)
        self.prefix = self.root / 'pfx'
        (self.prefix / 'drive_c').mkdir(parents=True)

    def game(self, name='Game With Spaces'):
        path = self.root / name / 'VHOLUME/Binaries/Win64'
        path.mkdir(parents=True)
        (path / 'VHOLUME-Win64-Shipping.exe').write_bytes(b'not an executable; test fixture')
        return path

    def service(self):
        ipc = self.root / 'ipc'
        ipc.mkdir()
        return bridge.FolderService(ipc, {'prefix': str(self.prefix)}, {})


class InstallerTests(Fixtures):
    def test_fresh_and_upgrade_preserve_every_old_file(self):
        bin_path = self.game()
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(PACKAGE, bin_path, self.prefix, running_check=lambda: False)
        target = bin_path / 'ue4ss/Mods/VHOLUMEPhotoCamera'
        self.assertTrue((target / 'Proton/install.json').is_file())
        self.assertFalse((target / 'Scripts/Photo-Folder.ps1').exists())
        self.assertEqual(installer.digest(bin_path / 'ue4ss/UE4SS.dll'), installer.LOADER_DLL_SHA256)
        (target / 'user-owned.txt').write_text('keep previous mod intact')
        settings = bin_path / 'ue4ss/VHOLUMEPhotoCamera.keys.input-preview'
        settings.write_text('custom user settings')
        original = hashes(target)
        loader_before = (bin_path / 'ue4ss/UE4SS-settings.ini').read_bytes()
        with contextlib.redirect_stdout(io.StringIO()):
            backup = installer.install(PACKAGE, bin_path, self.prefix, running_check=lambda: False)
        self.assertEqual(hashes(backup), original)
        self.assertEqual(settings.read_text(), 'custom user settings')
        self.assertEqual((bin_path / 'ue4ss/UE4SS-settings.ini').read_bytes(), loader_before)
        self.assertNotIn('user-owned.txt', hashes(target))
        self.assertFalse(list(bin_path.glob('.PhotoCamera-install-*')))
        option = (bin_path / 'ue4ss/PhotoCamera-Linux-Launch-Options.txt').read_text()
        self.assertTrue(option.startswith('python3 '))
        self.assertTrue(option.endswith(' %command%\n'))

    def test_dry_run_writes_nothing(self):
        bin_path = self.game()
        before = hashes(bin_path)
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(PACKAGE, bin_path, self.prefix, True, lambda: False)
        self.assertEqual(before, hashes(bin_path))

    def test_reject_running_game(self):
        bin_path = self.game()
        with self.assertRaisesRegex(RuntimeError, 'Close VHOLUME'):
            installer.install(PACKAGE, bin_path, running_check=lambda: True)
        self.assertFalse((bin_path / 'ue4ss').exists())

    def test_race_start_aborts_before_modifications(self):
        bin_path = self.game()
        calls = iter((False, True))
        with self.assertRaisesRegex(RuntimeError, 'started during'):
            installer.install(PACKAGE, bin_path, running_check=lambda: next(calls))
        self.assertFalse((bin_path / 'ue4ss').exists())
        self.assertFalse(list(bin_path.glob('.PhotoCamera-install-*')))

    def test_reject_partial_loader(self):
        bin_path = self.game()
        (bin_path / 'dwmapi.dll').write_bytes(b'custom loader')
        with self.assertRaisesRegex(ValueError, 'Partial or custom'):
            installer.install(PACKAGE, bin_path, running_check=lambda: False)
        self.assertEqual((bin_path / 'dwmapi.dll').read_bytes(), b'custom loader')

    def test_corrupt_package_rejected(self):
        bin_path = self.game()
        with patch.object(installer, 'MOD_SHA256', '0' * 64):
            with self.assertRaisesRegex(ValueError, 'damaged archive'):
                installer.install(PACKAGE, bin_path, running_check=lambda: False)
        self.assertFalse((bin_path / 'ue4ss').exists())

    def test_restore_old_mod_if_commit_fails(self):
        bin_path = self.game()
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(PACKAGE, bin_path, self.prefix, running_check=lambda: False)
        old = bin_path / 'ue4ss/Mods/VHOLUMEPhotoCamera'
        before = hashes(old)
        rename = Path.rename
        def fail_commit(path, destination):
            if path.parent.name.startswith('.PhotoCamera-install-'):
                raise OSError('simulated final move failure')
            return rename(path, destination)
        with patch.object(Path, 'rename', fail_commit):
            with self.assertRaisesRegex(OSError, 'simulated'):
                installer.install(PACKAGE, bin_path, self.prefix, running_check=lambda: False)
        self.assertEqual(before, hashes(old))
        self.assertFalse(list(bin_path.glob('.PhotoCamera-install-*')))

    def test_steam_library_with_spaces(self):
        steam = self.root / 'home/.local/share/Steam'
        (steam / 'steamapps').mkdir(parents=True)
        library = self.root / 'Extra Library'
        game = library / 'steamapps/common/VHOLUME/VHOLUME/Binaries/Win64'
        game.mkdir(parents=True)
        (game / 'VHOLUME-Win64-Shipping.exe').write_bytes(b'fixture')
        (library / 'steamapps/appmanifest_4131730.acf').write_text('"installdir" "VHOLUME"')
        encoded = str(library).replace('\\', '\\\\')
        (steam / 'steamapps/libraryfolders.vdf').write_text('"path" "' + encoded + '"')
        self.assertEqual(installer.steam_games(self.root / 'home'), [game.resolve()])

    def test_reject_archive_traversal(self):
        bad = self.root / 'bad.zip'
        with zipfile.ZipFile(bad, 'w') as z:
            z.writestr('ue4ss/Mods/VHOLUMEPhotoCamera/../../../outside.txt', b'bad')
        with zipfile.ZipFile(bad) as z, self.assertRaisesRegex(ValueError, 'Unsafe path'):
            installer.extract_mod(z, self.root / 'target')
        self.assertFalse((self.root / 'outside.txt').exists())


class BridgeTests(Fixtures):
    def test_unix_z_drive_and_specific_drive_mapping(self):
        class VirtualPath(PurePosixPath):
            def exists(self):
                return str(self) in ('/pfx/dosdevices', '/pfx/drive_c', '/pfx/dosdevices/z:', '/pfx/dosdevices/p:')
            is_dir = exists
            def iterdir(self):
                return iter((VirtualPath('/pfx/dosdevices/z:'), VirtualPath('/pfx/dosdevices/p:')))
            def resolve(self):
                value = str(self)
                for link, target in (('/pfx/dosdevices/z:', ''), ('/pfx/dosdevices/p:', '/home/alex/Pictures')):
                    if value == link or value.startswith(link + '/'):
                        return VirtualPath(target + value[len(link):] or '/')
                return self
        prefix = VirtualPath('/pfx')
        self.assertEqual(bridge.unix_path('Z:/home/alex/Pictures/Camera/', prefix), VirtualPath('/home/alex/Pictures/Camera'))
        with patch.object(bridge, 'Path', VirtualPath):
            self.assertEqual(bridge.windows_path('/home/alex/Pictures/Camera', prefix), 'P:/Camera/')
            self.assertEqual(bridge.windows_path('/other folder/photo', prefix), 'Z:/other folder/photo/')

    def test_dll_override_preserves_other_libraries(self):
        self.assertEqual(bridge.dll_overrides('dxgi=n,b;dwmapi.dll,winmm=b'), 'dxgi=n,b;winmm=b;dwmapi=n,b')
        self.assertEqual(bridge.dll_overrides(''), 'dwmapi=n,b')

    def test_prefix_prefers_steam_environment(self):
        data = self.root / 'custom compatdata'
        (data / 'pfx/drive_c').mkdir(parents=True)
        result = bridge.prefix_path({'prefix': str(self.prefix)}, {'STEAM_COMPAT_DATA_PATH': str(data)})
        self.assertEqual(result, (data / 'pfx').resolve())

    def test_path_round_trip_spaces_unicode(self):
        value = 'C:/Photos/café ; literal $name/'
        path = bridge.unix_path(value, self.prefix)
        self.assertEqual(path, (self.prefix / 'drive_c/Photos/café ; literal $name').resolve())
        self.assertEqual(bridge.windows_path(path, self.prefix), value)

    def test_reject_unmapped_drive_and_bad_path(self):
        for value in ('relative/path', 'Q:/missing', 'C:/bad\npath', '//server/share'):
            with self.assertRaises(ValueError):
                bridge.unix_path(value, self.prefix)

    def test_prepare_creates_only_requested_folder(self):
        service = self.service()
        self.assertEqual(service.handle('Prepare', 'C:/Photos/'), 'OK\nC:/Photos/')
        self.assertTrue((self.prefix / 'drive_c/Photos').is_dir())
        self.assertFalse(list((self.prefix / 'drive_c/Photos').iterdir()))

    def test_choose_and_cancel(self):
        service = self.service()
        chosen = self.prefix / 'drive_c/Photos'
        with patch.object(bridge.shutil, 'which', return_value='/usr/bin/zenity'), patch.object(service, 'run_tool', return_value=(0, str(chosen), '')):
            self.assertEqual(service.handle('Choose', 'C:/'), 'OK\nC:/Photos/')
        with patch.object(bridge.shutil, 'which', return_value='/usr/bin/zenity'), patch.object(service, 'run_tool', return_value=(1, '', '')):
            self.assertEqual(service.handle('Choose', 'C:/'), 'CANCELLED')

    def test_missing_desktop_tools(self):
        service = self.service()
        with patch.object(bridge.shutil, 'which', return_value=None):
            self.assertEqual(service.handle('Choose', 'C:/'), 'NO_DIALOG')
            self.assertEqual(service.handle('Open', 'C:/Photos'), 'NO_OPENER')

    def test_open_uses_argument_list_and_uri(self):
        service = self.service()
        with patch.object(bridge.shutil, 'which', return_value='/usr/bin/xdg-open'), patch.object(service, 'run_tool', return_value=(0, '', '')) as tool:
            self.assertEqual(service.handle('Open', 'C:/Photo Folder/'), 'OK\nC:/Photo Folder/')
            self.assertEqual(tool.call_args.args[0][0], 'xdg-open')
            self.assertIn('Photo%20Folder', tool.call_args.args[0][1])

    def test_atomic_request_reply_and_unknown_action(self):
        service = self.service()
        request = service.ipc / 'request-100-1.txt'
        request.write_text('Prepare\nC:/Photos/', encoding='utf-8')
        service.process(request)
        self.assertFalse(request.exists())
        self.assertEqual((service.ipc / 'reply-100-1.txt').read_text(), 'OK\nC:/Photos/')
        with self.assertRaisesRegex(ValueError, 'Unknown'):
            service.handle('Unknown', 'C:/ShouldNotExist/')
        self.assertFalse((self.prefix / 'drive_c/ShouldNotExist').exists())

    def test_launcher_preserves_arguments_and_exit_code(self):
        base = self.root / 'Proton'
        base.mkdir()
        (base / 'install.json').write_text(json.dumps({'prefix': str(self.prefix)}))
        result = self.root / 'child result.json'
        child = "import os,sys,json,pathlib;pathlib.Path(sys.argv[1]).write_text(json.dumps({'override':os.environ['WINEDLLOVERRIDES'],'args':sys.argv[2:]}));sys.exit(7)"
        fake_fcntl = types.SimpleNamespace(LOCK_EX=1, LOCK_NB=2, flock=lambda *args: None)
        with patch.dict(sys.modules, {'fcntl': fake_fcntl}), patch.dict(os.environ, {'WINEDLLOVERRIDES': 'winmm=n,b'}):
            self.assertEqual(bridge.launch([sys.executable, '-c', child, str(result), 'argument with spaces'], base), 7)
        actual = json.loads(result.read_text())
        self.assertEqual(actual, {'override': 'winmm=n,b;dwmapi=n,b', 'args': ['argument with spaces']})
        self.assertFalse((base / 'ipc/ready').exists())

    def test_lua_folder_protocol(self):
        if sys.platform != 'win32':
            self.skipTest('This harness uses the development workstation Lua DLL')
        lua_dll = Path('C:/Program Files/Blackmagic Design/DaVinci Resolve/lua5.1.dll')
        if not lua_dll.is_file():
            self.skipTest('Lua 5.1 DLL unavailable')
        lua = ctypes.CDLL(str(lua_dll))
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_close.argtypes = [ctypes.c_void_p]
        state = lua.luaL_newstate()
        lua.luaL_openlibs(state)
        self.addCleanup(lambda: lua.lua_close(state))
        def run(code):
            error = lua.luaL_loadstring(state, code.encode('utf-8')) or lua.lua_pcall(state, 0, 0, 0)
            if error:
                self.fail(lua.lua_tolstring(state, -1, None).decode())
        scripts = self.root / 'Scripts'
        ipc = self.root / 'Proton/ipc'
        saved = self.root / 'Saved'
        for path in (scripts, ipc, saved):
            path.mkdir(parents=True)
        name = str(saved).replace('\\', '/')
        source = str(MOD / 'Scripts/photo_folder.lua').replace('\\', '/')
        run('photos=dofile(' + json.dumps(source) + ')(' + json.dumps(str(scripts).replace('\\', '/') + '/') + '); photos.load(' + json.dumps(name) + ')')
        request = next(ipc.glob('request-*.txt'))
        self.assertEqual(request.read_text(), 'Prepare\n' + name + '/Screenshots/Windows/')
        request.with_name(request.name.replace('request-', 'reply-')).write_bytes(('OK\n' + name + '/Screenshots/Windows/').encode())
        request.unlink()
        (ipc / 'ready').write_text(str(int(__import__('time').time())))
        run('assert(photos.poll()==nil);assert(photos.prepare());assert(photos.choose()=="CHOOSE A PHOTO FOLDER")')
        choose = next(ipc.glob('request-*.txt'))
        selected = name + '/Selected/'
        choose.with_name(choose.name.replace('request-', 'reply-')).write_bytes(('OK\n' + selected).encode())
        choose.unlink()
        run('assert(photos.poll()=="PHOTO FOLDER UPDATED");assert(photos.directory()==' + json.dumps(selected) + ');assert(photos.prepare())')
        self.assertEqual((saved / 'VHOLUMEPhotoCamera.output-folder').read_text(), selected)
        run('assert(photos.choose()=="CHOOSE A PHOTO FOLDER")')
        choose = next(ipc.glob('request-*.txt'))
        choose.with_name(choose.name.replace('request-', 'reply-')).write_text('CANCELLED')
        choose.unlink()
        run('assert(photos.poll()=="PHOTO FOLDER UNCHANGED");assert(photos.directory()==' + json.dumps(selected) + ')')
        (ipc / 'ready').unlink()
        run('assert(not photos.prepare());assert(photos.open()=="USE THE LINUX STEAM LAUNCH OPTION")')


if __name__ == '__main__':
    unittest.main(verbosity=1)
