// SPDX-License-Identifier: MIT
// This product includes DNG technology under license by Adobe.
// The input is Unreal's lossless ZIP/half-float, scanline OpenEXR output.
// The DNG stores scene-linear RGB as lossless, normalized float32 samples.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Reflection;
using System.Threading.Tasks;

[assembly: AssemblyTitle("VHOLUME Linear DNG Converter")]
[assembly: AssemblyVersion("1.0.3.7")]

internal static class LinearDng
{
    static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    static string cancelPath, progressPath, ownedWriting;
    static int lastProgress=-1;
    static int Main(string[] args)
    {
        string result = null, output = null;
        bool published=false;
        FileStream conversionLock=null;string lockPath=null;
        try
        {
            if(args.Length==1 && args[0]=="--version"){Console.WriteLine("VHOLUME Photo Camera DNG 1.0.3-rc.2");return 0;}
            bool inline=args.Length==2 && args[0]=="--job-data";
            if (!inline && args.Length != 1) return 2;
            string jobPath=inline ? null : Utf8.GetString(System.Convert.FromBase64String(args[0]));
            string[] lines=inline ? Utf8.GetString(System.Convert.FromBase64String(args[1])).Split('\n') : File.ReadAllLines(jobPath,Utf8);
            var job = new Dictionary<string,string>();
            foreach (string item in lines)
            {
                string line=item.TrimEnd('\r');
                int at = line.IndexOf('=');
                if (at > 0) job.Add(line.Substring(0,at),line.Substring(at+1));
            }
            if (job["version"] != "1") throw new InvalidDataException("Unsupported raw job.");
            result = Decode(job["result"]); output = Decode(job["destination"]);
            string control=job.ContainsKey("control") ? Decode(job["control"]) : jobPath;
            cancelPath = control + ".cancel"; progressPath = control + ".progress";
            lockPath=control+".lock";
            try{conversionLock=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
            catch(IOException){return 4;}

            if (File.Exists(output) || File.Exists(output+".writing")) throw new IOException("DNG output already exists.");
            CheckCancel();
            int width,height;
            using (var exr = new Exr(Decode(job["source"])))
            {
                if (exr.Width != Number(job,"width") || exr.Height != Number(job,"height"))
                    throw new InvalidDataException("HDR dimensions differ from the capture.");
                width=exr.Width;height=exr.Height;
                Convert(exr, output+".writing", job);
                CheckCancel();
                File.Move(output+".writing",output);published=true;
            }
            return Result(result,"OK\n"+width+"\n"+height) ? 0 : 1;
        }
        catch (OperationCanceledException)
        {
            Delete(ownedWriting);
            if (published) Delete(output);
            if (result != null) Result(result,"CANCELLED");
            return 3;
        }
        catch (Exception error)
        {
            Delete(ownedWriting);
            // Existing destination files are never removed on an ordinary failure.
            if (result != null) Result(result,"ERROR\n"+error.GetType().Name+": "+error.Message);
            return 1;
        }
        finally{if(conversionLock!=null){conversionLock.Dispose();Delete(lockPath);}}
    }
    static string Decode(string value) { return Utf8.GetString(System.Convert.FromBase64String(value)); }
    static int Number(Dictionary<string,string> job,string name) { return int.Parse(job[name],System.Globalization.CultureInfo.InvariantCulture); }
    static double Real(Dictionary<string,string> job,string name) { return double.Parse(job[name],System.Globalization.CultureInfo.InvariantCulture); }
    static void Delete(string path) { if (path != null) { try { File.Delete(path); } catch {} } }
    static void CheckCancel() { if (File.Exists(cancelPath)) throw new OperationCanceledException(); }
    static bool Result(string path,string body)
    {
        try { File.WriteAllText(path+".tmp",body,Utf8); File.Move(path+".tmp",path);return true; } catch {return false;}
    }
    static void Progress(int value) { CheckCancel(); if(value!=lastProgress){File.WriteAllText(progressPath,value.ToString(),Utf8);lastProgress=value;} }

    sealed class Exr : IDisposable
    {
        readonly BinaryReader reader;
        readonly List<string> channels = new List<string>();
        readonly long[] offsets;
        readonly int lines, compression;
        public readonly int Width, Height;
        static string Word(BinaryReader reader)
        {
            var text=new List<byte>();
            for (int i=0;i<256;i++) { byte b=reader.ReadByte(); if (b==0) return Encoding.ASCII.GetString(text.ToArray()); text.Add(b); }
            throw new InvalidDataException("EXR attribute name is too long.");
        }
        public Exr(string path)
        {
            reader=new BinaryReader(new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read));
            try
            {
                if (reader.ReadUInt32()!=20000630 || reader.ReadUInt32()!=2) throw new InvalidDataException("Unsupported EXR layout.");
                var attributes=new Dictionary<string,byte[]>();
                for (;;)
                {
                    string name=Word(reader); if (name.Length==0) break;
                    Word(reader);int size=reader.ReadInt32();
                    if (size<0 || size>1048576) throw new InvalidDataException("Invalid EXR attribute size.");
                    byte[] data=reader.ReadBytes(size);if (data.Length!=size) throw new EndOfStreamException();
                    attributes.Add(name,data);
                }
                byte[] window=attributes["dataWindow"];
                if (window.Length!=16 || BitConverter.ToInt32(window,0)!=0 || BitConverter.ToInt32(window,4)!=0)
                    throw new InvalidDataException("EXR must have a zero-origin data window.");
                Width=checked(BitConverter.ToInt32(window,8)+1);Height=checked(BitConverter.ToInt32(window,12)+1);
                if (Width<1 || Height<1 || Width>7680 || Height>7680) throw new InvalidDataException("Unsupported EXR size.");
                compression=attributes["compression"][0];
                if (compression!=3) throw new InvalidDataException("EXR needs Unreal lossless ZIP16 data.");
                lines=compression==3 ? 16 : 1;
                using (var channelReader=new BinaryReader(new MemoryStream(attributes["channels"])))
                {
                    for (;;)
                    {
                        string name=Word(channelReader);if (name.Length==0) break;
                        if (channelReader.ReadInt32()!=1) throw new InvalidDataException("EXR channels must be float16.");
                        channelReader.ReadBytes(4);
                        if (channelReader.ReadInt32()!=1 || channelReader.ReadInt32()!=1) throw new InvalidDataException("Subsampled EXR channels are unsupported.");
                        if (name!="R" && name!="G" && name!="B" && name!="A") throw new InvalidDataException("Unexpected EXR channel.");
                        if (channels.Contains(name)) throw new InvalidDataException("Duplicate EXR channel.");
                        channels.Add(name);
                    }
                }
                if (!channels.Contains("R") || !channels.Contains("G") || !channels.Contains("B")) throw new InvalidDataException("EXR needs RGB channels.");
                offsets=new long[(Height+lines-1)/lines];
                for (int i=0;i<offsets.Length;i++) offsets[i]=reader.ReadInt64();
                long first=reader.BaseStream.Position;
                foreach (long offset in offsets) if (offset<first || offset>reader.BaseStream.Length-8) throw new InvalidDataException("Invalid EXR offset.");
            }
            catch { reader.Dispose();throw; }
        }
        public void Blocks(Action<int,int,float[]> consume)
        {
            for (int block=0;block<offsets.Length;block++)
            {
                CheckCancel();reader.BaseStream.Position=offsets[block];
                int y=reader.ReadInt32(), size=reader.ReadInt32();
                if (y!=block*lines || size<1 || reader.BaseStream.Position+size>reader.BaseStream.Length) throw new InvalidDataException("Invalid EXR scanline block.");
                int rows=Math.Min(lines,Height-y), length=checked(Width*rows*channels.Count*2);
                if (size>length) throw new InvalidDataException("EXR block exceeds raw size.");
                byte[] data=reader.ReadBytes(size);
                if (size<length)
                {
                    if (compression==0 || size<6 || ((data[0]<<8)|data[1])%31!=0 || (data[1]&32)!=0)
                        throw new InvalidDataException("Invalid EXR ZIP header.");
                    byte[] filtered=new byte[length];
                    using (var packed=new MemoryStream(data,2,size-6))
                    using (var inflate=new DeflateStream(packed,CompressionMode.Decompress))
                    {
                        int at=0,got;
                        while (at<length && (got=inflate.Read(filtered,at,length-at))>0) at+=got;
                        if (at!=length || inflate.ReadByte()!=-1) throw new InvalidDataException("Truncated EXR ZIP stream.");
                    }
                    uint expected=(uint)(data[size-4]<<24 | data[size-3]<<16 | data[size-2]<<8 | data[size-1]);
                    if (Adler(filtered)!=expected) throw new InvalidDataException("EXR ZIP checksum mismatch.");
                    for (int i=1;i<length;i++) filtered[i]=(byte)(filtered[i-1]+filtered[i]-128);
                    data=new byte[length];int split=(length+1)/2;
                    for (int i=0;i<length;i++) data[i]=filtered[(i%2==0 ? i/2 : split+i/2)];
                }
                float[] rgb=new float[Width*rows*3];
                for (int row=0;row<rows;row++) for (int channel=0;channel<channels.Count;channel++)
                {
                    int plane=channels[channel]=="R" ? 0 : channels[channel]=="G" ? 1 : channels[channel]=="B" ? 2 : -1;
                    if (plane<0) continue;
                    int source=(row*channels.Count+channel)*Width*2;
                    for (int x=0;x<Width;x++)
                    {
                        float value=HalfValues[(ushort)(data[source+x*2]|data[source+x*2+1]<<8)];
                        if (float.IsNaN(value) || float.IsInfinity(value)) throw new InvalidDataException("Non-finite HDR pixel.");
                        rgb[(row*Width+x)*3+plane]=value;
                    }
                }
                consume(y,rows,rgb);
            }
        }
        public void Dispose() { reader.Dispose(); }
    }
    static readonly float[] HalfValues=MakeHalves();
    static float[] MakeHalves() { var values=new float[65536];for(int i=0;i<values.Length;i++)values[i]=Half((ushort)i);return values; }
    static float Half(ushort h)
    {
        int sign=(h&0x8000)==0 ? 1 : -1, exponent=(h>>10)&31, fraction=h&1023;
        if (exponent==31) return fraction==0 ? sign*float.PositiveInfinity : float.NaN;
        if (exponent==0) return sign*fraction*(1.0f/16777216.0f);
        return (float)(sign*(1+fraction/1024.0)*Math.Pow(2,exponent-15));
    }
    static uint Adler(byte[] data)
    {
        uint a=1,b=0;
        // zlib's 5552-byte bound keeps both sums within uint32 between moduli.
        for (int start=0;start<data.Length;start+=5552)
        {
            int end=Math.Min(data.Length,start+5552);
            for(int i=start;i<end;i++){a+=data[i];b+=a;}
            a%=65521;b%=65521;
        }
        return b<<16|a;
    }
    sealed class Tag
    {
        public ushort Id,Type;public uint Count,Offset;public byte[] Data;
        public Tag(int id,int type,uint count,byte[] data) { Id=(ushort)id;Type=(ushort)type;Count=count;Data=data; }
    }
    static byte[] Bytes(Action<BinaryWriter> action) { using (var s=new MemoryStream()) { using(var w=new BinaryWriter(s)) { action(w);return s.ToArray(); } } }
    static Tag Short(int id,params ushort[] values) { return new Tag(id,3,(uint)values.Length,Bytes(w=>{foreach(ushort v in values)w.Write(v);})); }
    static Tag Long(int id,params uint[] values) { return new Tag(id,4,(uint)values.Length,Bytes(w=>{foreach(uint v in values)w.Write(v);})); }
    static Tag Text(int id,string value) { byte[] b=Encoding.ASCII.GetBytes(value+"\0");return new Tag(id,2,(uint)b.Length,b); }
    static Tag Rational(int id,bool signed,params double[] values)
    { return new Tag(id,signed?10:5,(uint)values.Length,Bytes(w=>{foreach(double v in values){long denominator=1000000000;while(Math.Abs(v)*denominator>int.MaxValue)denominator/=10;long numerator=(long)Math.Round(v*denominator);long a=Math.Abs(numerator),b=denominator;while(b!=0){long c=a%b;a=b;b=c;}if(a>0){numerator/=a;denominator/=a;}w.Write(checked((int)numerator));w.Write(checked((int)denominator));}})); }
    static uint DirectorySize(List<Tag> tags) { uint n=(uint)(6+12*tags.Count);foreach(Tag t in tags)if(t.Data.Length>4)n+=(uint)((t.Data.Length+1)&~1);return n; }
    static void Directory(BinaryWriter w,uint at,List<Tag> tags)
    {
        tags.Sort((a,b)=>a.Id.CompareTo(b.Id));w.BaseStream.Position=at;w.Write((ushort)tags.Count);
        uint extra=at+(uint)(6+12*tags.Count);
        foreach (Tag t in tags)
        {
            w.Write(t.Id);w.Write(t.Type);w.Write(t.Count);
            if (t.Data.Length<=4) { w.Write(t.Data);for(int i=t.Data.Length;i<4;i++)w.Write((byte)0); }
            else { t.Offset=extra;w.Write(extra);extra+=(uint)((t.Data.Length+1)&~1); }
        }
        w.Write((uint)0);
        foreach (Tag t in tags) if(t.Data.Length>4) { w.BaseStream.Position=t.Offset;w.Write(t.Data);if((t.Data.Length&1)!=0)w.Write((byte)0); }
    }
    static byte[] Zip(byte[] bytes)
    {
        using(var stream=new MemoryStream())
        {
            stream.WriteByte(0x78);stream.WriteByte(0x9c);
            using(var zip=new DeflateStream(stream,CompressionLevel.Fastest,true))zip.Write(bytes,0,bytes.Length);
            uint sum=Adler(bytes);stream.WriteByte((byte)(sum>>24));stream.WriteByte((byte)(sum>>16));stream.WriteByte((byte)(sum>>8));stream.WriteByte((byte)sum);
            return stream.ToArray();
        }
    }
    static byte Display(float v)
    {
        double x=Math.Max(0,Math.Min(1,v));
        return (byte)Math.Round(255*(x<=.0031308 ? 12.92*x : 1.055*Math.Pow(x,1/2.4)-.055));
    }
    static void Convert(Exr image,string output,Dictionary<string,string> job)
    {
        int width=image.Width,height=image.Height;
        int pw=Math.Max(1,(int)Math.Round(width*Math.Min(1,256.0/Math.Max(width,height))));
        int ph=Math.Max(1,(int)Math.Round(height*Math.Min(1,256.0/Math.Max(width,height))));
        byte[] preview=new byte[pw*ph*3];float peak=1;
        image.Blocks((y,rows,rgb)=>
        {
            foreach(float value in rgb)if(value>peak)peak=value;
            for(int py=0;py<ph;py++)
            {
                int sy=Math.Min(height-1,(int)((py+.5)*height/ph));if(sy<y || sy>=y+rows)continue;
                for(int px=0;px<pw;px++)
                {
                    int sx=Math.Min(width-1,(int)((px+.5)*width/pw));
                    for(int c=0;c<3;c++)preview[(py*pw+px)*3+c]=Display(rgb[((sy-y)*width+sx)*3+c]);
                }
            }
            Progress(Math.Min(40,(y+rows)*40/height));
        });
        // A power-of-two scale preserves the half-float source exactly in float32.
        // One extra stop keeps the brightest sample below the DNG saturation point.
        int exponent=(int)Math.Ceiling(Math.Log(peak,2))+1;
        float scale=(float)Math.Pow(2,exponent);
        var exif=new List<Tag>{Rational(33434,false,Real(job,"shutter")),Rational(33437,false,Real(job,"aperture")),
            Short(34855,(ushort)Number(job,"iso")),Short(34850,(ushort)(Number(job,"mode")==2?1:Number(job,"mode")==3?3:Number(job,"mode")==4?4:0)),
            Text(36867,job["captured"]),Text(36868,job["captured"]),Rational(37386,false,Real(job,"focal")),
            Text(42036,"Virtual "+job["focal"]+" mm lens")};
        int strips=(height+15)/16;uint[] offsets=new uint[strips],counts=new uint[strips];
        var raw=new List<Tag>{Long(254,0),Long(256,(uint)width),Long(257,(uint)height),Short(258,32,32,32),Short(259,8),Short(262,34892),
            Long(273,offsets),Short(277,3),Long(278,16),Long(279,counts),Short(284,1),Short(317,1),Short(339,3,3,3),
            Short(50713,1,1),Rational(50714,false,0,0,0),Long(50717,1,1,1),Rational(50718,false,1,1),
            Long(50719,0,0),Long(50720,(uint)width,(uint)height),Long(50829,0,0,(uint)height,(uint)width)};
        var root=new List<Tag>{Long(254,1),Long(256,(uint)pw),Long(257,(uint)ph),Short(258,8,8,8),Short(259,1),Short(262,2),
            Short(274,1),Short(277,3),Long(278,(uint)ph),Long(279,(uint)preview.Length),Short(284,1),
            Text(270,"Scene-linear HDR render. Optics and exposure baked; film look and grain excluded."),Text(271,"VHOLUME"),Text(272,"Photo Camera"),
            Text(305,"VHOLUME Photo Camera 1.0.3-rc.2"),Text(306,job["captured"]),
            new Tag(50706,1,4,new byte[]{1,4,0,0}),new Tag(50707,1,4,new byte[]{1,4,0,0}),
            Text(50708,"VHOLUME Photo Camera Linear HDR"),
            Rational(50721,true,3.2404542,-1.5371385,-.4985314,-.9692660,1.8760108,.0415560,.0556434,-.2040259,1.0572252),
            Rational(50964,true,.4360747,.3850649,.1430804,.2225045,.7168786,.0606169,.0139322,.0971045,.7141733),
            Short(50778,21),Rational(50728,false,1,1,1),Rational(50730,true,exponent),Rational(50731,false,.01),
            Rational(50732,false,1),Rational(50734,false,1),Text(50936,"VHOLUME Linear HDR"),Text(50934,"VHOLUME Linear HDR"),
            new Tag(50940,11,4,Bytes(w=>{w.Write(0f);w.Write(0f);w.Write(1f);w.Write(1f);})),Long(51110,1)};
        Tag sub=Long(330,0),exifOffset=Long(34665,0),previewOffset=Long(273,0);
        root.Add(sub);root.Add(exifOffset);root.Add(previewOffset);
        uint rawAt=8+DirectorySize(root), exifAt=rawAt+DirectorySize(raw), previewAt=exifAt+DirectorySize(exif);
        sub.Data=BitConverter.GetBytes(rawAt);exifOffset.Data=BitConverter.GetBytes(exifAt);previewOffset.Data=BitConverter.GetBytes(previewAt);
        using(var stream=new FileStream(output,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None))
        using(var writer=new BinaryWriter(stream))
        {
            ownedWriting=output;
            writer.Write((ushort)0x4949);writer.Write((ushort)42);writer.Write((uint)8);
            Directory(writer,8,root);Directory(writer,rawAt,raw);Directory(writer,exifAt,exif);
            stream.Position=previewAt;writer.Write(preview);
            // Bound memory and CPU use while compressing independent strips in parallel.
            int workers=Math.Max(1,Math.Min(4,Environment.ProcessorCount/2));
            var queue=new Queue<Task<byte[]>>();int written=0;
            Action drain=()=>
            {
                CheckCancel();byte[] packed=queue.Dequeue().GetAwaiter().GetResult();
                offsets[written]=checked((uint)stream.Position);counts[written]=(uint)packed.Length;
                writer.Write(packed);written++;
                Progress(40+Math.Min(height,written*16)*59/height);
            };
            image.Blocks((y,rows,rgb)=>
            {
                if(rows!=Math.Min(16,height-y) || y%16!=0)throw new InvalidDataException("DNG conversion requires ZIP16 EXR input.");
                for(int i=0;i<rgb.Length;i++)rgb[i]/=scale;
                byte[] pixels=new byte[rgb.Length*4];Buffer.BlockCopy(rgb,0,pixels,0,pixels.Length);
                queue.Enqueue(Task.Factory.StartNew(()=>Zip(pixels)));
                if(queue.Count>=workers)drain();
            });
            while(queue.Count>0)drain();
            foreach(Tag tag in raw)
            {
                if(tag.Id==273)tag.Data=Long(273,offsets).Data;
                if(tag.Id==279)tag.Data=Long(279,counts).Data;
            }
            Directory(writer,rawAt,raw);writer.Flush();stream.Flush(true);
        }
        Progress(100);
    }
}
