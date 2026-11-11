"""Package the release using the already-tested, bundled UE4SS archive."""

import argparse
import hashlib
import re
import zipfile
from pathlib import Path


def digest(data):
    return hashlib.sha256(data).hexdigest().upper()


def archive(path, entries):
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (2026, 11, 11, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, data, compresslevel=9)
    with zipfile.ZipFile(path) as result:
        assert result.testzip() is None, path
        assert set(result.namelist()) == set(entries), path
        for name, data in entries.items():
            assert result.read(name) == data, name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader-bundle', type=Path, required=True,
                        help='An existing installer ZIP containing the tested UE4SS archive')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    mod = root / 'ue4ss/Mods/VHOLUMEPhotoCamera'
    files = sorted(p for p in mod.rglob('*') if p.is_file())
    assert len(files) == 102, 'Unexpected release payload'
    assert not any(p.is_symlink() or p.suffix.lower() not in ('.lua', '.png', '.mp4', '.ps1', '.txt') for p in files)
    assert 'Photo Camera 1.0.2 ready' in (mod / 'Scripts/main.lua').read_text(encoding='utf-8')
    args.output.mkdir(parents=True, exist_ok=True)
    entries = {p.relative_to(root).as_posix(): p.read_bytes() for p in files}
    entries['README.md'] = (root / 'GUIDE.md').read_bytes()
    manual = args.output / 'VHOLUME-Photo-Camera.zip'
    archive(manual, entries)

    script_path = root / 'installer/Install-Photo-Camera.ps1'
    script = script_path.read_text(encoding='utf-8-sig')
    script, count = re.subn(r"(?m)^\$modHash = '[A-Fa-f0-9]{64}'",
                            lambda _: "$modHash = '" + digest(manual.read_bytes()) + "'", script)
    assert count == 1
    loader_name = 'UE4SS_v3.0.1-1011-gb50986bd.zip'
    with zipfile.ZipFile(args.loader_bundle) as source:
        loader = source.read(loader_name)
    assert digest(loader) in script, 'Bundled UE4SS hash mismatch'
    script_path.write_bytes(script.encode('utf-8-sig'))
    installer_entries = {
        'Install Photo Camera.cmd': (root / 'installer/Install Photo Camera.cmd').read_bytes(),
        'Install-Photo-Camera.ps1': script.encode('utf-8-sig'),
        loader_name: loader,
        manual.name: manual.read_bytes(),
        'README.md': entries['README.md'],
    }
    installer = args.output / 'VHOLUME-Photo-Camera-Installer.zip'
    archive(installer, installer_entries)
    sums = ''.join(f'{digest(p.read_bytes())}  {p.name}\n' for p in (manual, installer))
    (args.output / 'SHA256SUMS.txt').write_text(sums, encoding='utf-8')
    (args.output / 'RELEASE-NOTES.md').write_bytes((root / 'RELEASE-NOTES.md').read_bytes())
    print(f'Verified {len(files)} mod files, both archives, and the bundled UE4SS hash.')
    print(sums, end='')


if __name__ == '__main__':
    main()
