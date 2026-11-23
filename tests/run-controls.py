from pathlib import Path
import ctypes,ctypes.util,json,os,sys

root=Path(__file__).resolve().parents[1]
work=root/'.work'
work.mkdir(exist_ok=True)
fixture=work/'binding-fixture'
fixture.mkdir(exist_ok=True)
for file in fixture.glob('VHOLUMEPhotoCamera.keys*'):
    file.unlink()
scripts=root/'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts'
native=sys.platform!='win32'
library=(os.environ.get('VHOLUME_QA_LUA_LIBRARY') or ctypes.util.find_library('lua5.4')) if native else 'C:/Program Files/Blackmagic Design/DaVinci Resolve/lua5.1.dll'
assert library,'Lua 5.4 library not found'
lua=ctypes.CDLL(library)
lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_openlibs.argtypes=[ctypes.c_void_p]
if native:
    lua.luaL_loadfilex.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p]
    loadfile=lambda state,path:lua.luaL_loadfilex(state,path,None)
else:
    lua.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    loadfile=lua.luaL_loadfile
lua.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
if native:
    lua.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
    pcall=lambda state,a,b,c:lua.lua_pcallk(state,a,b,c,0,None)
else:
    lua.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
    pcall=lua.lua_pcall
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_settop.argtypes=[ctypes.c_void_p,ctypes.c_int]
state=lua.luaL_newstate();lua.luaL_openlibs(state)
def check(result):
    if result:raise RuntimeError(lua.lua_tolstring(state,-1,None).decode())
def run(code):
    check(lua.luaL_loadstring(state,code.encode('utf-8')) or pcall(state,0,0,0))
for path in scripts.glob('*.lua'):
    check(loadfile(state,str(path).encode()));lua.lua_settop(state,0)
run('table.unpack=table.unpack or unpack; local natural=math.log; math.log=function(n,b) return b and natural(n)/natural(b) or natural(n) end; FName=function(value) return value end')
run('scripts='+json.dumps(scripts.as_posix()+'/')+'; fixture='+json.dumps(fixture.as_posix()))
check(loadfile(state,str(root/'tests/controls.lua').encode()) or pcall(state,0,0,0))
print(f'PASS: all {len(list(scripts.glob("*.lua")))} runtime scripts parse.')
for file in fixture.glob('VHOLUMEPhotoCamera.capture*'):
    file.unlink()
check(loadfile(state,str(root/'tests/capture.lua').encode()) or pcall(state,0,0,0))
for file in fixture.glob('VHOLUMEPhotoCamera.output-folder*'):
    file.unlink()
if native:
    run('realFixture=fixture; fixture="Z:"..fixture; realOpen,realRemove=io.open,os.remove;io.open=function(p,...)return realOpen((p:gsub("^Z:","")),...)end;os.remove=function(p)return realRemove((p:gsub("^Z:","")))end')
check(loadfile(state,str(root/'tests/photo-folder.lua').encode()) or pcall(state,0,0,0))
if native:
    run('fixture=realFixture;io.open,os.remove=realOpen,realRemove')

for file in fixture.glob('*dng*'):
    if file.is_file(): file.unlink()
check(loadfile(state,str(root/'tests/dng-jobs.lua').encode()) or pcall(state,0,0,0))

check(loadfile(state,str(root/'tests/exposure.lua').encode()) or pcall(state,0,0,0))
