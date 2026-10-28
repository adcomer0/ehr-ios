using System;
using System.Buffers.Binary;
using System.IO;
using EHR.SourceAudio;

int checks=0;
void Check(bool value,string label){checks++;if(!value)throw new Exception(label);}
void Reject(Action action,string label){bool failed=false;try{action();}catch(ArgumentException){failed=true;}catch(IOException){failed=true;}catch(FormatException){failed=true;}catch(NotSupportedException){failed=true;}Check(failed,label);}
byte[] Wave(int bits,int count=2)
{
    int sampleBytes=bits/8;byte[] b=new byte[44+2*sampleBytes*count];
    "RIFF"u8.CopyTo(b);BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(4),(uint)b.Length-8);"WAVEfmt "u8.CopyTo(b.AsSpan(8));
    BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(16),16);BinaryPrimitives.WriteUInt16LittleEndian(b.AsSpan(20),1);BinaryPrimitives.WriteUInt16LittleEndian(b.AsSpan(22),2);
    BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(24),22050);BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(28),(uint)(22050*2*sampleBytes));BinaryPrimitives.WriteUInt16LittleEndian(b.AsSpan(32),(ushort)(2*sampleBytes));BinaryPrimitives.WriteUInt16LittleEndian(b.AsSpan(34),(ushort)bits);
    "data"u8.CopyTo(b.AsSpan(36));BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(40),(uint)b.Length-44);return b;
}
string temp=Path.Combine(Path.GetTempPath(),"ehr-own-sound-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
try
{
    string root=Path.Combine(temp,"root");Directory.CreateDirectory(root);byte[] sixteen=Wave(16),twentyFour=Wave(24);
    var wave=OwnedSoundFiles.Load(root,"Own",name=>{Check(name=="EHR.Resources.Sounds.Own.wav","exact resource name");return new MemoryStream(sixteen);});
    Check(wave.BitsPerSample==16&&wave.SampleCount==2,"embedded PCM16 loaded");
    string path=SourceAudioPaths.SoundFile(root,"Own");Check(File.ReadAllBytes(path).AsSpan().SequenceEqual(sixteen),"extraction exact bytes");
    bool resourceCalled=false;wave=OwnedSoundFiles.Load(root,"Own",_=>{resourceCalled=true;return null;});Check(!resourceCalled&&wave.SampleCount==2,"existing custom file preserved");
    File.WriteAllBytes(path,twentyFour);wave=OwnedSoundFiles.Load(root,"Own",_=>throw new Exception("existing file must win"));Check(wave.BitsPerSample==24,"custom PCM24 preferred without overwrite");
    Reject(()=>OwnedSoundFiles.Load(root,"Missing",_=>null),"missing sound explicit");Check(!File.Exists(SourceAudioPaths.SoundFile(root,"Missing")),"missing never creates file");
    Reject(()=>OwnedSoundFiles.Load(root,"Bad",_=>new MemoryStream(new byte[44])),"bad resource rejected");Check(!File.Exists(SourceAudioPaths.SoundFile(root,"Bad")),"invalid never persisted");
    Reject(()=>OwnedSoundFiles.Read(new MemoryStream(new byte[OwnedSoundFiles.MaximumBytes+1])),"bounded stream");
    foreach(string stem in new[]{"../outside","a/b","a\\b","",new string('A',81),"nul\0"})Reject(()=>OwnedSoundFiles.Load(root,stem,_=>throw new Exception("bad stem reached resource")),"invalid stem");
    Reject(()=>OwnedSoundFiles.Prepare("relative","Own"),"absolute own root only");
    string linkedRoot=Path.Combine(temp,"linked");Directory.CreateDirectory(linkedRoot);string outside=Path.Combine(temp,"outside");Directory.CreateDirectory(outside);
    Directory.CreateSymbolicLink(Path.Combine(linkedRoot,"resources"),outside);
    Reject(()=>OwnedSoundFiles.Load(linkedRoot,"Own",_=>new MemoryStream(sixteen)),"linked resources rejected");Check(Directory.GetFileSystemEntries(outside).Length==0,"no external extraction");
    string target=Path.Combine(outside,"Target.wav");File.WriteAllBytes(target,sixteen);string link=SourceAudioPaths.SoundFile(root,"Link");File.CreateSymbolicLink(link,target);
    Reject(()=>OwnedSoundFiles.Load(root,"Link",_=>null),"linked custom file rejected");
    var large=new PcmWaveData(Wave(16,67685));Check(large.LeftChunk(0,65536).Length==65536&&large.LeftChunk(65536,65536).Length==2149,"large clip two bounded chunks");
    Check(File.ReadAllBytes(path).AsSpan().SequenceEqual(twentyFour),"custom bytes unmodified");
    Console.WriteLine($"PASS {checks} owned PCM/file checks; no Unity, playback, account, network or official files");
}
finally{Directory.Delete(temp,true);}
