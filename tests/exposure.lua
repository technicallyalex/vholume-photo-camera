local e=dofile(scripts..'exposure.lua')
local function near(a,b) assert(math.abs(a-b)<.000001,tostring(a)..' differs from '..tostring(b)) end
near(e.ev(2,125,100)-e.ev(2,125,200),1)
near(e.ev(2,250,100)-e.ev(2,125,100),1)
near(e.ev(4,125,100)-e.ev(2,125,100),2)
local cases=0
for mode=1,4 do for auto=0,1 do for ev=-4,24,.5 do
 local c={mode=mode,auto=auto==1,aperture=7,shutter=31,iso=7,minISO=3,maxISO=13,minShutter=31}
 local r=e.solve(c,ev);assert(r.aperture>=1 and r.aperture<=16 and r.speed>=1/8 and r.speed<=32000)
 if mode==1 then assert(not r.isoAuto and r.iso==e.isos[c.iso]) end
 if mode==1 or mode==2 or mode==3 then assert(r.aperture==e.apertures[c.aperture]) end
 if mode==1 or mode==2 or mode==4 then assert(r.speed==e.speeds[c.shutter]) end
 if r.isoAuto then assert(r.iso>=e.isos[c.minISO] and r.iso<=e.isos[c.maxISO]) else assert(r.iso==e.isos[c.iso]) end
 cases=cases+1
end end end
local previousIntensity,previousSize=-1,-1
for _,iso in ipairs(e.isos) do local amount,size=e.grain(iso);assert(amount>previousIntensity and size>previousSize);previousIntensity,previousSize=amount,size end
local film=dofile(scripts..'film.lua');local stockFields={}
for i=1,#film.stocks do
 local camera={PostProcessSettings={}};film.apply(camera,i,nil,.123,1.17)
 assert(camera.PostProcessSettings.FilmGrainIntensity==.123 and camera.PostProcessSettings.FilmGrainTexelSize==1.17)
end
print('PASS: '..cases..' exposure/Auto ISO cases; physical stop relationships; monotonic ISO grain; all 11 looks use supplied ISO grain.')
