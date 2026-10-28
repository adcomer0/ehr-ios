using System;
using System.Buffers.Binary;
using System.IO;

namespace EHR.SourceAudio;

// Original bounded decoder for the exact authored PCM formats in EHR resources.
// Mono playback deliberately selects the left channel, matching upstream EHR.
internal sealed class PcmWaveData
{
    private readonly byte[] bytes;
    private readonly int dataOffset,frameBytes,sampleBytes;
    internal int Channels{get;}
    internal int Frequency{get;}
    internal int BitsPerSample{get;}
    internal int SampleCount{get;}
    internal PcmWaveData(ReadOnlySpan<byte> input)
    {
        if(input.Length<44||input.Length>8*1024*1024||!input[..4].SequenceEqual("RIFF"u8)||!input.Slice(8,4).SequenceEqual("WAVE"u8))throw new FormatException("bounded RIFF/WAVE required");
        long declared=8L+BinaryPrimitives.ReadUInt32LittleEndian(input.Slice(4,4));
        if(declared!=input.Length)throw new FormatException("RIFF length differs from exact input");
        int fmt=-1,fmtLength=0,data=-1,dataLength=0;
        for(int cursor=12;cursor<input.Length;)
        {
            if(input.Length-cursor<8)throw new FormatException("truncated WAV chunk header");
            uint size=BinaryPrimitives.ReadUInt32LittleEndian(input.Slice(cursor+4,4));
            if(size>int.MaxValue||size>input.Length-cursor-8)throw new FormatException("WAV chunk outside input");
            int start=cursor+8,length=(int)size;
            if(input.Slice(cursor,4).SequenceEqual("fmt "u8))
            {if(fmt>=0)throw new FormatException("duplicate WAV fmt chunk");fmt=start;fmtLength=length;}
            if(input.Slice(cursor,4).SequenceEqual("data"u8))
            {if(data>=0)throw new FormatException("duplicate WAV data chunk");data=start;dataLength=length;}
            long next=(long)start+length+(length&1);
            if(next>input.Length)throw new FormatException("missing WAV odd-chunk padding");
            cursor=(int)next;
        }
        if(fmt<0||fmtLength<16||data<0)throw new FormatException("WAV fmt/data missing");
        ushort kind=BinaryPrimitives.ReadUInt16LittleEndian(input.Slice(fmt,2));
        Channels=BinaryPrimitives.ReadUInt16LittleEndian(input.Slice(fmt+2,2));
        uint frequency=BinaryPrimitives.ReadUInt32LittleEndian(input.Slice(fmt+4,4));
        uint byteRate=BinaryPrimitives.ReadUInt32LittleEndian(input.Slice(fmt+8,4));
        int alignment=BinaryPrimitives.ReadUInt16LittleEndian(input.Slice(fmt+12,2));
        BitsPerSample=BinaryPrimitives.ReadUInt16LittleEndian(input.Slice(fmt+14,2));
        if(kind!=1||Channels is not(1 or 2)||BitsPerSample is not(16 or 24))throw new NotSupportedException("only authored mono/stereo PCM16/PCM24 is supported");
        if(frequency<1||frequency>192000)throw new FormatException("WAV frequency out of bounds");
        Frequency=(int)frequency;sampleBytes=BitsPerSample/8;frameBytes=Channels*sampleBytes;
        if(alignment!=frameBytes||byteRate!=frequency*frameBytes||dataLength<frameBytes||dataLength%frameBytes!=0)throw new FormatException("WAV PCM frame layout differs");
        SampleCount=dataLength/frameBytes;
        if(SampleCount>4*1024*1024)throw new FormatException("WAV frame limit");
        dataOffset=data;bytes=input.ToArray();
    }
    internal float Left(int frame)
    {
        if((uint)frame>=(uint)SampleCount)throw new ArgumentOutOfRangeException(nameof(frame));
        int offset=dataOffset+frame*frameBytes;
        if(sampleBytes==2)return BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(offset,2))/32768f;
        int value=bytes[offset]|bytes[offset+1]<<8|bytes[offset+2]<<16;
        if((value&0x800000)!=0)value|=unchecked((int)0xff000000);
        return value/8388608f;
    }
    internal float[] LeftChunk(int start,int maximum)
    {
        if(start<0||start>SampleCount||maximum<1||maximum>65536)throw new ArgumentOutOfRangeException();
        int count=Math.Min(maximum,SampleCount-start);var result=new float[count];
        for(int i=0;i<count;i++)result[i]=Left(start+i);return result;
    }
}
internal static class SourceAudioPaths
{
    internal static string SoundFile(string ownRoot,string sound)
    {
        if(!Path.IsPathFullyQualified(ownRoot)||sound.Length is <1 or >80)throw new ArgumentException("absolute owned root and sound name required");
        foreach(char value in sound)if(!char.IsLetterOrDigit(value)&&value!='_'&&value!='-')throw new ArgumentException("sound name is a single resource basename");
        string directory=Path.Combine(Path.GetFullPath(ownRoot),"resources","sounds");
        string result=Path.GetFullPath(Path.Combine(directory,sound+".wav"));
        if(!result.StartsWith(directory+Path.DirectorySeparatorChar,StringComparison.Ordinal))throw new ArgumentException("sound path escaped owned root");
        return result;
    }
}
