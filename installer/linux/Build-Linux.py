"""Build the self-contained, experimental Linux/Proton installer ZIP."""

import argparse
import hashlib
import re
import zipfile
from pathlib import Path


def archive(path, entries):
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (2026, 11, 11, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
            output.writestr(info, data, compresslevel=9)
    with zipfile.ZipFile(path) as result:
        assert result.testzip() is None
        assert set(result.namelist()) == set(entries)
        for name, data in entries.items():
            assert result.read(name) == data, name


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader-bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    mod = root / 'ue4ss/Mods/VHOLUMEPhotoCamera'
    files = sorted(p for p in mod.rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    assert len(files) == 102, len(files)
    assert all(p.suffix in ('.lua', '.png', '.mp4', '.txt', '.ps1') and not p.is_symlink() for p in files)
    args.output.mkdir(parents=True, exist_ok=True)
    work = root / '.work/linux-package'
    work.mkdir(parents=True, exist_ok=True)
    payload_name = 'VHOLUME-Photo-Camera-Linux-Mod.zip'
    payload = work / payload_name
    entries = {p.relative_to(root).as_posix(): p.read_bytes() for p in files}
    prefix = 'ue4ss/Mods/VHOLUMEPhotoCamera/'
    del entries[prefix + 'Scripts/Photo-Folder.ps1']
    overlay = root / 'platforms/linux'
    for path in sorted(overlay.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            entries[prefix + path.relative_to(overlay).as_posix()] = path.read_bytes()
    main_path = prefix + 'Scripts/main.lua'
    assert b'Photo Camera 1.0.2 ready' in entries[main_path]
    entries[main_path] = entries[main_path].replace(b'Photo Camera 1.0.2 ready', b'Photo Camera 1.0.2 Linux/Proton preview ready')
    assert len(entries) == 103, len(entries)
    archive(payload, entries)
    source = root / 'installer/linux/install-linux.py'
    body = source.read_text(encoding='utf-8')
    body, count = re.subn(r"(?m)^MOD_SHA256 = '[^']+'", "MOD_SHA256 = '" + digest(payload.read_bytes()) + "'", body)
    assert count == 1
    source.write_bytes(body.encode('utf-8'))
    loader_name = 'UE4SS_v3.0.1-1011-gb50986bd.zip'
    with zipfile.ZipFile(args.loader_bundle) as old:
        loader = old.read(loader_name)
    assert digest(loader) == 'aa181789dc7226bcec94f13f054ff10477d7383321ffb98dbc3666a159b182a8'
    entries = {'install-linux.py': body.encode('utf-8'),
        'Install Photo Camera.sh': (root / 'installer/linux/Install Photo Camera.sh').read_bytes(),
        'README.md': (root / 'LINUX.md').read_bytes(), payload_name: payload.read_bytes(), loader_name: loader}
    entries['SHA256SUMS.txt'] = ''.join(f'{digest(data)}  {name}\n' for name, data in sorted(entries.items())).encode()
    output = args.output / 'VHOLUME-Photo-Camera-v1.0.2-linux.2-Linux-Proton.zip'
    archive(output, entries)
    # Use an ignored extracted copy for installer QA.
    with zipfile.ZipFile(output) as built:
        built.extractall(work)
    (args.output / 'SHA256SUMS.txt').write_text(digest(output.read_bytes()) + '  ' + output.name + '\n', encoding='utf-8')
    (args.output / 'README.md').write_bytes(entries['README.md'])
    print(f'Built and verified Linux/Proton preview: 103 mod files; {output.stat().st_size} bytes.')


if __name__ == '__main__':
    main()
