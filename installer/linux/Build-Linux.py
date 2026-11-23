"""Package the current camera runtime and native Linux host adapters."""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path


def archive(path, entries):
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as output:
        for name,data in sorted(entries.items()):
            info=zipfile.ZipInfo(name,(2026,11,23,0,0,0));info.create_system=3
            info.compress_type=zipfile.ZIP_DEFLATED
            executable=name.endswith('.sh') or name.endswith('/Native/PhotoCameraDng')
            info.external_attr=(0o100755 if executable else 0o100644)<<16
            output.writestr(info,data,compresslevel=9)
    with zipfile.ZipFile(path) as result:
        assert result.testzip() is None and set(result.namelist())==set(entries)
        for name,data in entries.items():assert result.read(name)==data,name


def digest(data):return hashlib.sha256(data).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader-bundle',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--version',default='1.1.0')
    args=parser.parse_args();assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?',args.version)
    root=Path(__file__).resolve().parents[2];mod=root/'ue4ss/Mods/VHOLUMEPhotoCamera'
    files=sorted(p for p in mod.rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    assert len(files)==109,len(files)
    assert all(not p.is_symlink() for p in files)
    prefix='ue4ss/Mods/VHOLUMEPhotoCamera/'
    entries={prefix+p.relative_to(mod).as_posix():p.read_bytes() for p in files}
    del entries[prefix+'Scripts/Photo-Folder.ps1'];del entries[prefix+'Tools/PhotoCameraDng.exe']
    overlay=root/'platforms/linux'
    for p in sorted(overlay.rglob('*')):
        if not p.is_file() or '__pycache__' in p.parts:continue
        name=p.relative_to(overlay).as_posix()
        if name.startswith('Proton/Native/') and p.name not in ('PhotoCameraDng','DOTNET-LICENSE.txt','DOTNET-THIRD-PARTY-NOTICES.txt'):continue
        assert not p.is_symlink(),p
        entries[prefix+name]=p.read_bytes()
    assert ('Photo Camera '+args.version+' ready').encode() in entries[prefix+'Scripts/main.lua']
    native=entries[prefix+'Proton/Native/PhotoCameraDng']
    assert native[:4]==b'\x7fELF' and native[18:20]==b'\x3e\x00','Expected Linux x86-64 native DNG converter'
    proof=json.loads((root/'tools/dng/NATIVE-BUILD.json').read_text())
    assert digest(native)==proof['sha256'],'Native helper differs from verified build'
    for filename,key in [('LinearDng.cs','source_sha256'),('NativeDng.csproj','project_sha256')]:
        assert digest((root/'tools/dng'/filename).read_bytes())==proof[key],'Rebuild Linux helper after source changes'

    assert not any(name.endswith(('.exe','.ps1','.pyc')) for name in entries)
    mod_count=len(entries)
    args.output.mkdir(parents=True,exist_ok=True)
    work=root/'.work/linux-package';work.mkdir(parents=True,exist_ok=True)
    payload_name='VHOLUME-Photo-Camera-Linux-Mod.zip';payload=work/payload_name;archive(payload,entries)
    source=root/'installer/linux/install-linux.py';body=source.read_text(encoding='utf-8')
    body,n=re.subn(r"(?m)^MOD_SHA256 = '[^']+'", "MOD_SHA256 = '"+digest(payload.read_bytes())+"'",body);assert n==1
    body,n=re.subn(r'(?m)^EXPECTED_MOD_FILES = \d+', 'EXPECTED_MOD_FILES = '+str(mod_count),body);assert n==1
    body,n=re.subn(r"(?m)^VERSION = '[^']+'", "VERSION = '"+args.version+"'",body);assert n==1
    source.write_bytes(body.encode('utf-8'))
    loader_name='UE4SS_v3.0.1-1011-gb50986bd.zip'
    with zipfile.ZipFile(args.loader_bundle) as old:loader=old.read(loader_name)
    assert digest(loader)=='aa181789dc7226bcec94f13f054ff10477d7383321ffb98dbc3666a159b182a8'
    bundle={'install-linux.py':body.encode(),'Install Photo Camera.sh':(root/'installer/linux/Install Photo Camera.sh').read_bytes(),
        'README.md':(root/'LINUX.md').read_bytes(),'GUIDE.md':(root/'GUIDE.md').read_bytes(),
        'RELEASE-NOTES.md':(root/'RELEASE-NOTES.md').read_bytes(),payload_name:payload.read_bytes(),loader_name:loader}
    for name in ('LinearDng.cs','NativeDng.csproj','Build-Linux.sh','NATIVE-BUILD.json','LICENSE.txt','README.md'):
        bundle['source/DNG/'+name]=(root/'tools/dng'/name).read_bytes()
    bundle['SHA256SUMS.txt']=''.join(digest(data)+'  '+name+'\n' for name,data in sorted(bundle.items())).encode()
    output=args.output/('VHOLUME-Photo-Camera-v'+args.version+'-Linux-Proton.zip');archive(output,bundle)
    with zipfile.ZipFile(output) as z:z.extractall(work)
    (args.output/'SHA256SUMS.txt').write_bytes((digest(output.read_bytes())+'  '+output.name+'\n').encode())
    print('Built and verified Linux/Proton '+args.version+': '+str(mod_count)+' mod files; '+str(output.stat().st_size)+' bytes.')


if __name__=='__main__':main()
