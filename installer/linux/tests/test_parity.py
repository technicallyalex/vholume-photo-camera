"""Native Linux parity checks: real converter, prefix translation, and shared Lua queue."""
import array
import base64
import contextlib
import ctypes
import ctypes.util
import hashlib
import importlib.util
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
PROTON=ROOT/'platforms/linux/Proton'
HELPER=PROTON/'Native/PhotoCameraDng'

def module(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

bridge=module('parity_bridge',PROTON/'bridge.py')
native=module('parity_native',PROTON/'native_dng.py')

def encode(value):return base64.b64encode(str(value).encode()).decode()

def source_exr(path,width=32,height=19):
    values=[0.,2**-24,.001,.18,1.,2.,32.,100.,65504.]
    pixels=[tuple(struct.unpack('<e',struct.pack('<e',values[(x+y+c)%len(values)]))[0] for c in range(3)) for y in range(height) for x in range(width)]
    def attr(name,kind,data):return name.encode()+b'\0'+kind.encode()+b'\0'+struct.pack('<I',len(data))+data
    channels=b''.join(n.encode()+b'\0'+struct.pack('<i4xii',1,1,1) for n in ('A','B','G','R'))+b'\0'
    window=struct.pack('<iiii',0,0,width-1,height-1)
    header=struct.pack('<II',20000630,2)+attr('channels','chlist',channels)+attr('compression','compression',b'\x03')+attr('dataWindow','box2i',window)+attr('displayWindow','box2i',window)+attr('lineOrder','lineOrder',b'\0')+attr('pixelAspectRatio','float',struct.pack('<f',1))+attr('screenWindowCenter','v2f',b'\0'*8)+attr('screenWindowWidth','float',struct.pack('<f',1))+b'\0'
    chunks=[]
    for y in range(0,height,16):
        raw=b''.join(struct.pack('<e',1. if c==3 else pixels[row*width+x][c]) for row in range(y,min(height,y+16)) for c in (3,2,1,0) for x in range(width))
        shuffled=raw[::2]+raw[1::2]
        predictor=bytes([shuffled[0]])+bytes((shuffled[i]-shuffled[i-1]+128)%256 for i in range(1,len(shuffled)))
        packed=zlib.compress(predictor);data=packed if len(packed)<len(raw) else raw
        chunks.append(struct.pack('<ii',y,len(data))+data)
    at=len(header)+len(chunks)*8;offsets=[]
    for c in chunks:offsets.append(at);at+=len(c)
    path.write_bytes(header+b''.join(struct.pack('<Q',n) for n in offsets)+b''.join(chunks));return pixels


def constant_exr(path,width,height):
    def attr(name,kind,data):return name.encode()+b'\0'+kind.encode()+b'\0'+struct.pack('<I',len(data))+data
    channels=b''.join(n.encode()+b'\0'+struct.pack('<i4xii',1,1,1) for n in ('A','B','G','R'))+b'\0'
    window=struct.pack('<iiii',0,0,width-1,height-1)
    header=struct.pack('<II',20000630,2)+attr('channels','chlist',channels)+attr('compression','compression',b'\x03')+attr('dataWindow','box2i',window)+attr('displayWindow','box2i',window)+b'\0'
    row=b''.join(struct.pack('<e',v)*width for v in (1.,2.,.18,100.));chunks=[];cached={}
    for y in range(0,height,16):
        rows=min(16,height-y)
        if rows not in cached:
            raw=row*rows;shuffled=raw[::2]+raw[1::2]
            predictor=bytes([shuffled[0]])+bytes((shuffled[i]-shuffled[i-1]+128)%256 for i in range(1,len(shuffled)))
            cached[rows]=zlib.compress(predictor)
        packed=cached[rows];chunks.append(struct.pack('<ii',y,len(packed))+packed)
    at=len(header)+len(chunks)*8;offsets=[]
    for chunk in chunks:offsets.append(at);at+=len(chunk)
    path.write_bytes(header+b''.join(struct.pack('<Q',v) for v in offsets)+b''.join(chunks))


class Dng:
    def __init__(self,path):self.f=open(path,'rb');assert self.f.read(4)==b'II*\0';self.root=self.directory(struct.unpack('<I',self.f.read(4))[0]);self.raw=self.directory(self.values(self.root[330])[0])
    def directory(self,offset):
        self.f.seek(offset);n=struct.unpack('<H',self.f.read(2))[0];return {v[0]:v[1:] for v in (struct.unpack('<HHI4s',self.f.read(12)) for _ in range(n))}
    def data(self,t):
        kind,n,b=t;size={1:1,2:1,3:2,4:4,5:8,10:8,11:4}[kind]*n
        if size<=4:return b[:size]
        self.f.seek(struct.unpack('<I',b)[0]);return self.f.read(size)
    def values(self,t):return struct.unpack('<'+{3:'H',4:'I',5:'I',10:'i',11:'f'}[t[0]]*(t[1]*(2 if t[0] in (5,10) else 1)),self.data(t))
    def strips(self):
        for offset,count in zip(self.values(self.raw[273]),self.values(self.raw[279])):
            self.f.seek(offset);yield zlib.decompress(self.f.read(count))
    def close(self):self.f.close()


@unittest.skipUnless(sys.platform=='linux','Requires real Linux executable, POSIX drives and locks')
class NativeParity(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='vholume-parity-',dir=ROOT/'.work');self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.prefix=self.root/'pfx';self.saved=self.prefix/'drive_c/users/steamuser/AppData/Local/VHOLUME/Saved';self.saved.mkdir(parents=True)
        (self.prefix/'dosdevices').mkdir();(self.prefix/'dosdevices/z:').symlink_to('/',target_is_directory=True)
        self.output=self.root/'photos cafÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â© & literal $text';self.output.mkdir()
        self.source=self.output/'VHOLUME_fixture.part.exr';self.pixels=source_exr(self.source)
        self.job=self.saved/'VHOLUMEPhotoCamera.dng-job-100-1-123456';self.dest=self.output/'VHOLUME_fixture.part.dng';self.result=Path(str(self.job)+'.result')
        self.fields=dict(version='1',source=encode(self.source),destination=encode(self.dest),result=encode(self.result),control=encode(self.job),width='32',height='19',iso='1600',aperture='1.4',shutter='0.00003125',focal='600',mode='2',captured='2026:11:23 12:00:00')
        self.job.write_text(self.body())
    def body(self):return ''.join(k+'='+v+'\n' for k,v in self.fields.items())
    def run_job(self,inline=False):
        args=['--job-data',encode(self.body())] if inline else [encode(self.job)]
        return subprocess.run([str(HELPER),*args],capture_output=True,timeout=30)
    def test_native_output_precision_and_metadata(self):
        self.assertEqual(self.run_job().returncode,0)
        self.assertEqual(self.result.read_text(),'OK\n32\n19')
        d=Dng(self.dest);self.addCleanup(d.close)
        ev=d.values(d.root[50730]);gain=2**(ev[0]/ev[1])
        data=b''.join(d.strips());expected=b''.join(struct.pack('<f',value/gain) for pixel in self.pixels for value in pixel)
        self.assertEqual(data,expected)
        exif=d.directory(d.values(d.root[34665])[0])
        self.assertEqual(d.values(exif[34855]),(1600,));self.assertEqual(d.values(exif[37386]),(600,1));self.assertEqual(d.values(exif[33434]),(1,32000))
        self.assertEqual(d.values(d.raw[258]),(32,32,32))
    def test_6k_and_8k_dimensions_and_exact_hdr_pixels(self):
        for width,height in ((5760,3840),(7680,7680)):
            with self.subTest(size=(width,height)):
                constant_exr(self.source,width,height);self.fields.update(width=str(width),height=str(height));self.job.write_text(self.body())
                self.assertEqual(self.run_job().returncode,0)
                d=Dng(self.dest)
                try:
                    self.assertEqual(d.values(d.raw[256]),(width,));self.assertEqual(d.values(d.raw[257]),(height,))
                    ev=d.values(d.root[50730]);gain=2**(ev[0]/ev[1]);v=struct.unpack('<e',struct.pack('<e',.18))[0]
                    pixel=struct.pack('<fff',100/gain,v/gain,2/gain);total=0
                    for block in d.strips():
                        self.assertEqual(block,pixel*(len(block)//12));total+=len(block)
                    self.assertEqual(total,width*height*12)
                finally:d.close()
                self.dest.unlink();self.result.unlink()

    def test_inline_protocol_cancel_and_existing_output(self):
        Path(str(self.job)+'.cancel').write_text('cancel');self.assertEqual(self.run_job(True).returncode,3)
        self.assertEqual(self.result.read_text(),'CANCELLED');self.assertFalse(self.dest.exists())
        Path(str(self.job)+'.cancel').unlink();self.result.unlink()
        self.assertEqual(self.run_job(True).returncode,0);before=hashlib.sha256(self.dest.read_bytes()).hexdigest()
        self.result.unlink();self.assertEqual(self.run_job(True).returncode,1)
        self.assertEqual(hashlib.sha256(self.dest.read_bytes()).hexdigest(),before)
        self.assertFalse(Path(str(self.job)+'.lock').exists())
    def test_cross_process_lock_preserves_other_worker(self):
        import fcntl
        with open(str(self.job)+'.lock','w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            self.assertEqual(self.run_job(True).returncode,4)
            self.assertFalse(self.result.exists())
        self.assertEqual(self.run_job(True).returncode,0)
    def test_native_bridge_translation_and_exit_survival(self):
        self.fields.pop('control');self.fields['source']=encode('Z:'+str(self.source));self.fields['destination']=encode('Z:'+str(self.dest))
        winjob='C:/users/steamuser/AppData/Local/VHOLUME/Saved/'+self.job.name;self.fields['result']=encode(winjob+'.result');self.job.write_text(self.body())
        ipc=self.root/'ipc';ipc.mkdir();request=ipc/'dng-request-100-1-123456.txt';request.write_text(encode(winjob))
        service=native.NativeDngService(ipc,{'prefix':str(self.prefix)},{},bridge.unix_path,bridge.prefix_path)
        service.poll();self.assertFalse(request.exists());self.assertEqual(len(service.children),1)
        service.close()  # The game/launcher ends; the native child must finish rather than be killed.
        child=next(iter(service.children.values()))[0];self.assertEqual(child.wait(timeout=30),0)
        self.assertEqual(self.result.read_text(),'OK\n32\n19');service.poll()
        self.assertFalse(service.children)
    def test_shared_lua_queue_native_worker_recovery_and_failure_isolation(self):
        self.job.unlink()
        library=ctypes.CDLL(os.environ.get('VHOLUME_QA_LUA_LIBRARY') or ctypes.util.find_library('lua5.4'))
        library.luaL_newstate.restype=ctypes.c_void_p;state=library.luaL_newstate()
        library.luaL_openlibs.argtypes=[ctypes.c_void_p];library.luaL_openlibs(state)
        library.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
        library.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
        library.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];library.lua_tolstring.restype=ctypes.c_char_p
        library.lua_close.argtypes=[ctypes.c_void_p];self.addCleanup(lambda:library.lua_close(state))
        def run(code):
            error=library.luaL_loadstring(state,code.encode()) or library.lua_pcallk(state,0,0,0,0,None)
            if error:self.fail(library.lua_tolstring(state,-1,None).decode())
        mod=self.root/'mod';scripts=mod/'Scripts';ipc=mod/'Proton/ipc';scripts.mkdir(parents=True);ipc.mkdir(parents=True)
        shutil.copy2(ROOT/'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/dng.lua',scripts/'dng.lua')
        shutil.copy2(ROOT/'platforms/linux/Scripts/platform.lua',scripts/'platform.lua')
        drive=str(self.prefix/'drive_c')
        run('local open,rename,remove=io.open,os.rename,os.remove; local function p(s) s=s:gsub("^C:",'+json.dumps(drive)+');return (s:gsub("^Z:","")) end;io.open=function(s,...) return open(p(s),...) end;os.rename=function(a,b)return rename(p(a),p(b))end;os.remove=function(s)return remove(p(s))end')
        code='factory=dofile('+json.dumps(str(scripts/'dng.lua'))+');raw=factory('+json.dumps(str(scripts)+'/')+',function()end);raw.load("C:/users/steamuser/AppData/Local/VHOLUME/Saved")'
        run(code)
        outputs=[]
        for j in range(1,9):
            source=self.output/('VHOLUME_queue_'+str(j)+'.part.exr');source.write_bytes(self.source.read_bytes() if j!=3 else b'bad middle input')
            base='Z:'+str(source)[:-9];outputs.append(Path(str(source)[:-9]+'.part.dng'))
            run('raw.begin({base='+json.dumps(base,ensure_ascii=False)+',partPath='+json.dumps(base+'.part.png',ensure_ascii=False)+',exrPartPath='+json.dumps(base+'.part.exr',ensure_ascii=False)+',dngPartPath='+json.dumps(base+'.part.dng',ensure_ascii=False)+',width=32,height=19,iso='+str(j*100)+',aperture=2,shutterSeconds=.008,focalLength=50,exposureMode=1,captured="2026:11:23 12:00:00",film="Neutral",method="Dedicated render",samples=5,keepEXR=true})')
        run('assert(raw.count()==8 and raw.full());raw.poll();assert(raw.status(raw.shots()[1])=="queued")')
        self.assertFalse(list(ipc.glob('dng-request-*')),'Unavailable launcher must retain photos instead of failing them')
        run('raw=factory('+json.dumps(str(scripts)+'/')+',function()end);raw.load("C:/users/steamuser/AppData/Local/VHOLUME/Saved");assert(raw.count()==8);assert(raw.shots()[2].iso==200)')
        (ipc/'ready').write_text(str(int(time.time())))
        service=native.NativeDngService(ipc,{'prefix':str(self.prefix)},{},bridge.unix_path,bridge.prefix_path)
        self.addCleanup(service.close)
        done=[];deadline=time.monotonic()+30
        run('finished=0;failed=0')
        while time.monotonic()<deadline:
            run('raw.poll();for _,s in ipairs(raw.shots()) do local status=raw.status(s);if status=="done" then raw.release(s);finished=finished+1 elseif status=="error" then raw.cancel(s);failed=failed+1 end end')
            service.poll();self.assertLessEqual(len(service.children),1)
            if not list(self.saved.glob('VHOLUMEPhotoCamera.dng-job-*')):break
            time.sleep(.01)
        run('assert(raw.count()==0 and finished==7 and failed==1)')
        for j,path in enumerate(outputs,1):
            if j==3:self.assertFalse(path.exists());continue
            self.assertTrue(path.exists());d=Dng(path)
            try:self.assertEqual(d.values(d.directory(d.values(d.root[34665])[0])[34855]),(j*100,))
            finally:d.close()
        self.assertFalse((self.saved/'VHOLUMEPhotoCamera.dng-active').exists())

    def test_bad_request_never_executes_commands(self):
        ipc=self.root/'ipc';ipc.mkdir();r=ipc/'dng-request-1-1-1.txt';r.write_text(encode('Z:/tmp/not-a-camera-job'))
        service=native.NativeDngService(ipc,{'prefix':str(self.prefix)},{},bridge.unix_path,bridge.prefix_path)
        with open(os.devnull,'w') as sink, contextlib.redirect_stderr(sink):service.poll()
        self.assertFalse(service.children);self.assertFalse(r.exists())


if __name__=='__main__':unittest.main(verbosity=2)
