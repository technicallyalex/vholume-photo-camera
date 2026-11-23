local execute,time=os.execute,os.time
local launched={}
local clock=1000
os.time=function() return clock end
os.execute=function(command) launched[#launched+1]=command;return true end
local function write(path,body) local f=assert(io.open(path,'wb'));f:write(body);f:close() end
local factory=dofile(scripts..'photo_folder.lua')
local photos=factory(scripts);photos.load(fixture)
assert(photos.open()=='OPENING PHOTO FOLDER')
assert(photos.poll()==nil,'Open reported success before the helper acknowledged Explorer')
assert(photos.open()=='WAIT FOR THE FOLDER ACTION')
assert(launched[1]:find('-ResultPathBase64 ',1,true))
write(fixture..'/VHOLUMEPhotoCamera.output-folder.open-1000-1','OPENED')
assert(photos.poll()=='PHOTO FOLDER OPENED')
assert(photos.open()=='OPENING PHOTO FOLDER')
write(fixture..'/VHOLUMEPhotoCamera.output-folder.open-1000-2','ERROR')
assert(photos.poll()=='COULD NOT OPEN PHOTO FOLDER')
assert(photos.open()=='OPENING PHOTO FOLDER')
clock=1013
assert(photos.poll()=='COULD NOT OPEN PHOTO FOLDER','Unresponsive helper did not time out')
assert(photos.choose()=='CHOOSE A PHOTO FOLDER')
write(fixture..'/VHOLUMEPhotoCamera.output-folder.choose-1013-4','CANCELLED')
assert(photos.poll()=='PHOTO FOLDER UNCHANGED')
os.execute,os.time=execute,time
print('PASS: folder actions wait for acknowledgment; error/timeout feedback; duplicate launch blocking; chooser cancellation.')
