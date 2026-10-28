using System;
using System.IO;
using System.Linq;
using System.Buffers.Binary;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using EHR.Generated;
using EHR.SourceHost;
using Il2CppInterop.Runtime.InteropTypes.Arrays;

namespace EHR.SourceAudio;

// No AudioSource, SoundManager, Play, network, account or Main invocation exists
// in this probe. The source Windows guard is intentionally left unchanged.
internal static unsafe class SourceAudioDataProbe
{
    private static string error="";
    private static readonly BindingSpec GetData=new("UnityEngine.AudioModule.dll","UnityEngine","AudioClip","GetData",false,false,"System.Boolean",["System.Single[]","System.Int32"]);
    private static int Property(UnityEngine.AudioClip clip,string name)
    {
        using var result=FacadeRuntime.Invoke(new("UnityEngine.AudioModule.dll","UnityEngine","AudioClip",name,false,false,"System.Int32",[]),clip.Token,null,0);
        return FacadeRuntime.ReadValue<int>(result);
    }
    private static bool Read(UnityEngine.AudioClip clip,Il2CppStructArray<float> target,int offset)
    {
        NativeArgument* arguments=stackalloc NativeArgument[2];arguments[0]=FacadeRuntime.Reference(target);arguments[1]=FacadeRuntime.Value(&offset,"System.Int32");
        using var result=FacadeRuntime.Invoke(GetData,clip.Token,arguments,2);return FacadeRuntime.ReadValue<bool>(result);
    }
    private static bool Same(Il2CppStructArray<float> actual,ReadOnlySpan<float> expected)
    {
        if(actual.Length!=expected.Length)return false;
        for(int i=0;i<expected.Length;i++)if(Math.Abs(actual[i]-expected[i])>0.000001f)return false;
        return true;
    }
    internal static byte[] WaveFixture(int bits)
    {
        int sampleBytes=bits/8;var bytes=new byte[44+4*sampleBytes];"RIFF"u8.CopyTo(bytes);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(4),checked((uint)bytes.Length-8));"WAVEfmt "u8.CopyTo(bytes.AsSpan(8));
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(16),16);BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(20),1);BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(22),2);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(24),22050);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(28),(uint)(22050*2*sampleBytes));BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(32),(ushort)(2*sampleBytes));BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(34),(ushort)bits);"data"u8.CopyTo(bytes.AsSpan(36));BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(40),(uint)(4*sampleBytes));
        // Two stereo frames: left=-1,+0.5; right=0,0. Left selection is explicit.
        if(bits==16){BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(44),short.MinValue);BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(48),16384);}
        else{bytes[46]=128;bytes[52]=64;}
        return bytes;
    }
    private static void Resources(int* proof)
    {
        var assembly=typeof(SourceAudioDataProbe).Assembly;
        string[] resources=assembly.GetManifestResourceNames().Where(n=>n.StartsWith("EHR.Resources.Sounds.",StringComparison.Ordinal)&&n.EndsWith(".wav",StringComparison.Ordinal)).ToArray();
        int supported=0,pcm24=0,large=0;
        foreach(string name in resources)
        {
            using var stream=assembly.GetManifestResourceStream(name)??throw new InvalidOperationException("owned WAV resource absent");
            using var memory=new MemoryStream();stream.CopyTo(memory);
            var wav=new PcmWaveData(memory.ToArray());
            if(wav.LeftChunk(0,Math.Min(64,wav.SampleCount)).All(float.IsFinite))supported++;
            if(name.EndsWith(".Line.wav",StringComparison.Ordinal)&&wav.BitsPerSample==24&&wav.SampleCount==29104)pcm24++;
            if(name.EndsWith(".Boom.wav",StringComparison.Ordinal)&&wav.SampleCount==67685&&wav.LeftChunk(65536,65536).Length==2149)large++;
        }
        proof[9]=supported==18&&resources.Length==18?1:0;proof[10]=pcm24==1&&large==1?1:0;proof[13]=resources.Length;
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_audio_data_probe_v1",CallConvs=[typeof(CallConvCdecl)])]
    internal static int Probe(int* proof,nuint count)
    {
        if(proof==null||count!=16)return 4;for(int i=0;i<16;i++)proof[i]=0;
        UnityEngine.AudioClip? clip=null;
        try
        {
            FacadeRuntime.RequireReady();proof[2]=1;
            var pcm16=new PcmWaveData(WaveFixture(16));var pcm24=new PcmWaveData(WaveFixture(24));
            proof[7]=pcm16.Channels==2&&pcm16.SampleCount==2&&pcm16.Left(0)==-1&&pcm16.Left(1)==0.5f?1:0;
            proof[8]=pcm24.Channels==2&&pcm24.SampleCount==2&&pcm24.Left(0)==-1&&pcm24.Left(1)==0.5f?1:0;
            Resources(proof);proof[2]=2;
            string ownRoot=SourcePlatformPaths.DataRoot;
            bool invalid=false;try{SourceAudioPaths.SoundFile(ownRoot,"../outside");}catch(ArgumentException){invalid=true;}
            string safe=SourceAudioPaths.SoundFile(ownRoot,"EHR_Audio_Probe");
            proof[11]=invalid&&safe.StartsWith(Path.GetFullPath(ownRoot)+Path.DirectorySeparatorChar,StringComparison.Ordinal)?1:0;proof[2]=3;
            FacadeRuntime.Resolve(GetData);
            FacadeRuntime.Resolve(new("UnityEngine.AudioModule.dll","UnityEngine","AudioClip","Create",true,false,"UnityEngine.AudioClip",["System.String","System.Int32","System.Int32","System.Int32","System.Boolean","System.Boolean"]));
            FacadeRuntime.Resolve(new("UnityEngine.AudioModule.dll","UnityEngine","AudioClip","SetData",false,false,"System.Boolean",["System.Single[]","System.Int32"]));proof[3]=1;proof[2]=4;
            clip=UnityEngine.AudioClip.Create("EHR silent data probe",8,1,22050,false,false)??throw new InvalidOperationException("actual AudioClip.Create returned null");
            proof[4]=FacadeRuntime.ObjectClass(clip)==FacadeRuntime.Class("UnityEngine.AudioModule.dll","UnityEngine","AudioClip")&&Property(clip,"get_samples")==8&&Property(clip,"get_channels")==1&&Property(clip,"get_frequency")==22050?1:0;proof[2]=5;
            float[] expected=[0,0.25f,-0.25f,0.5f,-0.5f,0.75f,-1,32767/32768f];
            using Il2CppStructArray<float> input=expected;using var output=new Il2CppStructArray<float>(8);
            proof[5]=clip.SetData(input,0)&&Read(clip,output,0)&&Same(output,expected)?1:0;proof[2]=6;
            float[] patch=[0.125f,-0.125f,0.875f,-0.875f];using Il2CppStructArray<float> offset=patch;
            patch.CopyTo(expected,4);proof[6]=clip.SetData(offset,4)&&Read(clip,output,0)&&Same(output,expected)?1:0;proof[2]=7;
            ulong root=clip.Token;UnityEngine.Object.Destroy(clip);clip.Dispose();clip=null;
            proof[12]=!FacadeRuntime.TokenIsValid(root)?1:0;proof[2]=8;
            proof[14]=(RuntimeFeature.IsDynamicCodeSupported?1:0)|(RuntimeFeature.IsDynamicCodeCompiled?2:0);proof[0]=proof[2]==8&&proof[13]==18&&proof[14]==0?1:0;
            for(int i=3;i<=12;i++)proof[0]&=proof[i];error="";return proof[0]==1?0:7;
        }
        catch(Exception exception)
        {
            error=exception.ToString();proof[1]=exception is RuntimeGatewayException gateway?gateway.Status:6;
            if(exception is NativeGameException game)try{game.Dispose();}catch{}
            return proof[1];
        }
        finally{if(clip is not null){try{UnityEngine.Object.Destroy(clip);}catch{}try{clip.Dispose();}catch{}}}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_audio_copy_error_v1",CallConvs=[typeof(CallConvCdecl)])]
    internal static int CopyError(byte* output,nuint capacity,nuint* required)
    {
        if(required==null)return 4;
        try{byte[] utf8=Encoding.UTF8.GetBytes(error);*required=(nuint)utf8.Length+1;if(output==null||capacity<*required){if(output!=null&&capacity>0)*output=0;return 8;}utf8.CopyTo(new Span<byte>(output,utf8.Length));output[utf8.Length]=0;return 0;}
        catch{*required=0;return 6;}
    }
}
