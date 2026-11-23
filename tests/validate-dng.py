"""Independent DNG QA. Requires numpy, tifffile, OpenEXR, and rawpy."""
import argparse, base64, json, subprocess, sys, tempfile
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory',type=Path)
parser.add_argument('--dependencies',type=Path)
a=parser.parse_args()
if a.dependencies: sys.path.insert(0,str(a.dependencies))
import numpy as np
import tifffile,OpenEXR,rawpy
paths=sorted(a.directory.glob('VHOLUME_*.dng'))
assert paths,'No capture DNGs'
for path in paths:
 with tifffile.TiffFile(path) as f:
  root=f.pages[0];raw=root.pages[0]
  assert root.tags[50706].value==bytes([1,4,0,0])
  assert raw.photometric==34892 and raw.dtype==np.dtype('float32')
  assert all(tag in root.tags for tag in (271,272,50708,50721,50728,50730,50964))
  assert all(tag in root.tags[34665].value for tag in ('ExposureTime','FNumber','ISOSpeedRatings','FocalLength','DateTimeOriginal'))
  pixels=raw.asarray();assert np.isfinite(pixels).all()
  ev=root.tags[50730].value;ev=ev[0]/ev[1] if isinstance(ev,tuple) else ev
  exr=path.with_suffix('.exr');exact=None
  if exr.exists():
   source=OpenEXR.File(str(exr)).channels()['RGBA'].pixels[:,:,:3]
   assert source.shape==pixels.shape
   # Compare in row blocks to keep temporary memory bounded at maximum resolution.
   for y in range(0,source.shape[0],64):assert np.array_equal(source[y:y+64].astype(np.float32),pixels[y:y+64]*2**ev)
   exact=True
  print(json.dumps({'file':path.name,'size':[raw.imagewidth,raw.imagelength],'float_bits':32,'baseline_ev':ev,'finite':True,'source_rgb_exact':exact}))
  del pixels
small=next(p for p in paths if p.stat().st_size<10000000)
with rawpy.imread(str(small)) as raw:
 assert raw.sizes.width>0 and raw.color_desc.startswith(b'RGB')
 print('PASS LibRaw accepts linear DNG: '+small.name)
print('PASS independent DNG validation')
