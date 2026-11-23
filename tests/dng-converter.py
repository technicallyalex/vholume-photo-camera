"""Check the standalone Windows converter's failure and path handling."""
import argparse,base64,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('work',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1];exe=root/'ue4ss/Mods/VHOLUMEPhotoCamera/Tools/PhotoCameraDng.exe'
def b64(s):return base64.b64encode(str(s).encode()).decode()
with tempfile.TemporaryDirectory(prefix='dng-check-',dir=a.work) as directory:
 d=Path(directory);out=d/'DNG café & samples';out.mkdir();job=d/'job';dest=out/'capture.part.dng';result=d/'result'
 def run(source,width=1280,cancel=False):
  for suffix in ('','.tmp'):result.with_name(result.name+suffix).unlink(missing_ok=True)
  job.with_name(job.name+'.cancel').unlink(missing_ok=True)
  if cancel:job.with_name(job.name+'.cancel').write_text('cancel')
  fields=dict(version=1,source=b64(source.resolve()),destination=b64(dest.resolve()),result=b64(result.resolve()),width=width,height=720,iso=6400,aperture=1,shutter=1/32000,focal=600,mode=2,captured='2026:11:22 12:00:00')
  job.write_text(''.join(str(k)+'='+str(v)+'\n' for k,v in fields.items()),encoding='utf-8')
  process=subprocess.run([str(exe),b64(job.resolve())],timeout=30)
  return process.returncode,result.read_text(encoding='utf-8')
 code,reply=run(a.source);assert code==0 and reply=='OK\n1280\n720' and dest.is_file();original=dest.read_bytes()
 code,reply=run(a.source);assert code==1 and reply.startswith('ERROR') and dest.read_bytes()==original
 dest.unlink();code,reply=run(a.source,1281);assert code==1 and reply.startswith('ERROR') and not dest.exists()
 code,reply=run(a.source,cancel=True);assert code==3 and reply=='CANCELLED' and not dest.exists()
 broken=d/'broken.exr';broken.write_bytes(a.source.read_bytes()[:300]);code,reply=run(broken)
 assert code==1 and reply.startswith('ERROR') and not dest.exists() and not Path(str(dest)+'.writing').exists()
 print('PASS converter: Unicode/symbol output paths, existing-file preservation, dimension mismatch, cancellation, truncated source, and unfinished-file cleanup.')
