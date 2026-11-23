from pathlib import Path
import ctypes,json

root=Path(__file__).resolve().parents[1]
work=root/'.work'
work.mkdir(exist_ok=True)
fixture=work/'binding-fixture'
fixture.mkdir(exist_ok=True)
for file in fixture.glob('VHOLUMEPhotoCamera.keys*'):
    file.unlink()
scripts=root/'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts'
lua=ctypes.CDLL('C:/Program Files/Blackmagic Design/DaVinci Resolve/lua5.1.dll')
lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_openlibs.argtypes=[ctypes.c_void_p]
lua.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lua.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lua.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_settop.argtypes=[ctypes.c_void_p,ctypes.c_int]
state=lua.luaL_newstate();lua.luaL_openlibs(state)
def check(result):
    if result:raise RuntimeError(lua.lua_tolstring(state,-1,None).decode())
def run(code):
    check(lua.luaL_loadstring(state,code.encode('utf-8')) or lua.lua_pcall(state,0,0,0))
for path in scripts.glob('*.lua'):
    check(lua.luaL_loadfile(state,str(path).encode()));lua.lua_settop(state,0)
run('table.unpack=unpack; FName=function(value) return value end')
run('scripts='+json.dumps(scripts.as_posix()+'/')+'; fixture='+json.dumps(fixture.as_posix()))
check(lua.luaL_loadfile(state,str(root/'tests/controls.lua').encode()) or lua.lua_pcall(state,0,0,0))
print(f'PASS: all {len(list(scripts.glob("*.lua")))} runtime scripts parse.')
for file in fixture.glob('VHOLUMEPhotoCamera.capture*'):
    file.unlink()
check(lua.luaL_loadfile(state,str(root/'tests/capture.lua').encode()) or lua.lua_pcall(state,0,0,0))
for file in fixture.glob('VHOLUMEPhotoCamera.output-folder*'):
    file.unlink()
check(lua.luaL_loadfile(state,str(root/'tests/photo-folder.lua').encode()) or lua.lua_pcall(state,0,0,0))
