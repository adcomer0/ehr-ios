using System;
using System.IO;
using System.Linq;
using System.Buffers.Binary;
using EHR.SourceAudio;
int checks=0;
void Check(bool condition,string name){if(!condition)throw new Exception(name);checks++;}
void Reject(byte[] bytes,string name){try{new PcmWaveData(bytes);throw new Exception("accepted "+name);}catch(FormatException){checks++;}catch(NotSupportedException){checks++;}}
byte[] Fixture(int bits,int channels=2)
{
    using var memory=new MemoryStream();using var writer=new BinaryWriter(memory);
    int sampleBytes=bits/8;writer.Write("RIFF"u8);writer.Write(36+sampleBytes*channels*2);writer.Write("WAVEfmt "u8);writer.Write(16);writer.Write((ushort)1);writer.Write((ushort)channels);writer.Write(22050);writer.Write(22050*sampleBytes*channels);writer.Write((ushort)(sampleBytes*channels));writer.Write((ushort)bits);writer.Write("data"u8);writer.Write(sampleBytes*channels*2);
    foreach(int value in new[]{-1,1})for(int channel=0;channel<channels;channel++)
    {
        if(bits==16)writer.Write((short)(channel==0?(value<0?short.MinValue:16384):8192));
        else if(bits==24){int sample=channel==0?(value<0?-(1<<23):1<<22):0;writer.Write((byte)sample);writer.Write((byte)(sample>>8));writer.Write((byte)(sample>>16));}
        else writer.Write(0);
    }
    return memory.ToArray();
}
var sixteen=new PcmWaveData(Fixture(16));Check(sixteen.Left(0)==-1&&sixteen.Left(1)==0.5f&&sixteen.SampleCount==2,"PCM16 left samples");
var twentyfour=new PcmWaveData(Fixture(24));Check(twentyfour.Left(0)==-1&&twentyfour.Left(1)==0.5f&&twentyfour.SampleCount==2,"PCM24 sign/scale");
Check(sixteen.LeftChunk(1,65536).SequenceEqual(new[]{0.5f})&&sixteen.LeftChunk(2,1).Length==0,"chunk endpoint");
foreach(int bits in new[]{16,24})foreach(int channels in new[]{1,2}){var wav=new PcmWaveData(Fixture(bits,channels));Check(wav.Channels==channels&&wav.BitsPerSample==bits&&wav.Frequency==22050,"fmt fields");}
Reject(new byte[4],"short header");var malformed=Fixture(16);malformed[4]--;Reject(malformed,"RIFF mismatch");
malformed=Fixture(16);BinaryPrimitives.WriteUInt32LittleEndian(malformed.AsSpan(40),uint.MaxValue);Reject(malformed,"out of bounds chunk");
malformed=Fixture(16);BinaryPrimitives.WriteUInt16LittleEndian(malformed.AsSpan(20),3);Reject(malformed,"IEEE float WAV");
malformed=Fixture(16);BinaryPrimitives.WriteUInt16LittleEndian(malformed.AsSpan(22),3);Reject(malformed,"channels");
malformed=Fixture(16);BinaryPrimitives.WriteUInt16LittleEndian(malformed.AsSpan(32),1);Reject(malformed,"frame alignment");
malformed=Fixture(16);BinaryPrimitives.WriteUInt32LittleEndian(malformed.AsSpan(28),1);Reject(malformed,"byte rate");
malformed=Fixture(16);BinaryPrimitives.WriteUInt16LittleEndian(malformed.AsSpan(34),32);Reject(malformed,"unsupported sample bits");
foreach(string value in new[]{"../escape","x/y","x\\y","x.wav","",":","A\0B"}){try{SourceAudioPaths.SoundFile(Path.GetTempPath(),value);throw new Exception("path accepted");}catch(ArgumentException){checks++;}}
Check(SourceAudioPaths.SoundFile(Path.GetTempPath(),"MarioJump").EndsWith(Path.Combine("resources","sounds","MarioJump.wav"),StringComparison.Ordinal),"owned path");
int nativeResources=0,legacy16=0,pcm24=0,large=0;
foreach(string path in Directory.GetFiles(args[0],"*.wav").Order())
{
    byte[] bytes=File.ReadAllBytes(path);var wav=new PcmWaveData(bytes);nativeResources++;
    Check(wav.LeftChunk(0,Math.Min(wav.SampleCount,64)).All(float.IsFinite),"finite authored PCM");
    if(wav.BitsPerSample==16)
    {
        var legacy=new AudioFixture.LegacyWav(bytes);
        bool equal=wav.Channels==legacy.ChannelCount&&wav.SampleCount==legacy.SampleCount&&wav.Frequency==legacy.Frequency;
        for(int i=0;equal&&i<wav.SampleCount;i++)equal=wav.Left(i)==legacy.LeftChannel[i];
        Check(equal,"exact unchanged upstream PCM16 parser parity: "+Path.GetFileName(path));legacy16++;
    }
    else{Check(Path.GetFileName(path)=="Line.wav"&&wav.SampleCount==29104,"actual PCM24 resource");pcm24++;}
    if(wav.SampleCount>65536){Check(Path.GetFileName(path)=="Boom.wav"&&wav.LeftChunk(65536,65536).Length==2149,"bounded final native-array chunk");large++;}
}
Check(nativeResources==18&&legacy16==17&&pcm24==1&&large==1,"complete pinned authored resource inventory");
Console.WriteLine($"PASS {checks} checks; 18 resources, exact full-frame PCM16 parity17, PCM24 support1, large-native-array split1; no audio/runtime/game/account/network operations");
