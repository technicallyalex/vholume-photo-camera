"""Time a conversion with identical input/output and record lossless DNG size."""
import argparse,base64,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('helper',type=Path);p.add_argument('work',type=Path);p.add_argument('--label',required=True);p.add_argument('--width',type=int,default=7680);p.add_argument('--height',type=int,default=7680);a=p.parse_args()
a.work.mkdir(parents=True,exist_ok=True);job=a.work/(a.label+'.job');dest=a.work/(a.label+'.dng');result=a.work/(a.label+'.result')
def b64(p):return base64.b64encode(str(p.resolve()).encode()).decode()
fields=dict(version=1,source=b64(a.source),destination=b64(dest),result=b64(result),width=a.width,height=a.height,iso=100,aperture=2,shutter=1/125,focal=50,mode=1,captured='2026:11:22 18:00:00')
job.write_text(''.join(str(k)+'='+str(v)+'\n' for k,v in fields.items()),encoding='utf-8')
start=time.perf_counter();r=subprocess.run([str(a.helper.resolve()),b64(job)],timeout=300);elapsed=time.perf_counter()-start
assert r.returncode==0 and result.read_text()=='OK\n'+str(a.width)+'\n'+str(a.height)
report=dict(label=a.label,seconds=round(elapsed,3),bytes=dest.stat().st_size,width=a.width,height=a.height)
(a.work/(a.label+'.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
