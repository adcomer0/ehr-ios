using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
using EHR.SourceHost;
using Il2CppInterop.Runtime.InteropTypes.Arrays;

namespace EHR.SourceAudio;

// Only the reviewed iOS source overlay calls this adapter. Upstream sound/SFX,
// host RPC and recipient checks remain at their original call sites.
internal static unsafe class SourceAudioPlayback
{
    private static readonly Dictionary<string,UnityEngine.AudioClip> cache=new(StringComparer.Ordinal);
    internal static global::SoundManager? ExistingManager()
    {
        using var type=LiveCollections.TypeObject(FacadeRuntime.Class("Assembly-CSharp.dll","","SoundManager"));
        NativeArgument argument=FacadeRuntime.Reference(type);
        using var found=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine","Object","FindObjectOfType",true,false,"UnityEngine.Object",["System.Type"]),0,&argument,1);
        if(found.Token==0)return null;
        if(FacadeRuntime.ObjectClass(found)!=FacadeRuntime.Class("Assembly-CSharp.dll","","SoundManager"))
            throw new RuntimeGatewayException(5,"existing SoundManager exact class differs");
        return new global::SoundManager(found.Detach());
    }
    internal static UnityEngine.AudioClip CreateClip(string stem,PcmWaveData wave,out int chunks)
    {
        chunks=0;UnityEngine.AudioClip? clip=null;
        try
        {
            clip=UnityEngine.AudioClip.Create(stem,wave.SampleCount,1,wave.Frequency,false,false)??
                throw new InvalidOperationException("native AudioClip.Create returned null");
            for(int offset=0;offset<wave.SampleCount;)
            {
                float[] samples=wave.LeftChunk(offset,65536);
                using Il2CppStructArray<float> native=samples;
                if(!clip.SetData(native,offset))throw new InvalidOperationException("native AudioClip.SetData rejected a bounded PCM chunk");
                chunks++;offset+=samples.Length;
            }
            var result=clip;clip=null;return result;
        }
        finally{if(clip is not null){try{UnityEngine.Object.Destroy(clip);}finally{clip.Dispose();}}}
    }
    internal static UnityEngine.AudioClip Load(string stem,out int chunks)
    {
        FacadeRuntime.RequireReady();
        // Original source has a lowercase "teleport" call as well as Teleport.
        // Preserve exact existing custom files, then select only a unique
        // authored resource spelling. Do not rewrite any source role/RPC body.
        SourceAudioPaths.SoundFile(SourcePlatformPaths.DataRoot,stem);
        stem=SourceAudioNames.Resolve(stem,
            name=>OwnedSoundFiles.ExistingExact(SourcePlatformPaths.DataRoot,name),
            typeof(SourceAudioPlayback).Assembly.GetManifestResourceNames());
        string path=SourceAudioPaths.SoundFile(SourcePlatformPaths.DataRoot,stem);
        if(cache.TryGetValue(path,out var previous))
        {
            if(previous){chunks=0;return previous;}
            cache.Remove(path);previous.Dispose();
        }
        PcmWaveData wave=OwnedSoundFiles.Load(SourcePlatformPaths.DataRoot,stem,
            name=>typeof(SourceAudioPlayback).Assembly.GetManifestResourceStream(name));
        var clip=CreateClip(stem,wave,out chunks);cache.Add(path,clip);return clip;
    }
    internal static void Play(string stem,float volume,float pitch)
    {
        FacadeRuntime.RequireReady();
        // Validate before owner lookup as names can arrive through the original
        // RPC path. Existing own custom files may use any validated basename.
        SourceAudioPaths.SoundFile(SourcePlatformPaths.DataRoot,stem);
        if(!float.IsFinite(volume)||!float.IsFinite(pitch))throw new ArgumentException("finite sound volume and pitch required");
        using var manager=ExistingManager();
        if(manager is null||!manager){global::EHR.Logger.Warn("No active sound manager", "CustomSounds");return;}
        try
        {
            UnityEngine.AudioClip clip=Load(stem,out _);
            using var source=manager.PlaySoundImmediate(clip,false,volume,pitch,null);
            global::EHR.Logger.Msg($"Playing sound: {stem}","CustomSounds");
        }
        catch(FileNotFoundException){global::EHR.Logger.Warn($"Could not find sound: {stem}","CustomSounds");}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_audio_close_v1",CallConvs=[typeof(CallConvCdecl)])]
    internal static int Close()=>CloseCore();
    private static int CloseCore()
    {
        int status=0;global::SoundManager? manager=null;
        try
        {
            FacadeRuntime.RequireReady();
            var clips=new List<UnityEngine.AudioClip>(cache.Values);cache.Clear();
            try{manager=ExistingManager();}catch(Exception error){status=Status(error);}
            foreach(var clip in clips)
            {
                try{if(clip&&manager is not null&&manager)manager.StopSound(clip);}catch(Exception error){status=Status(error);}
                try{if(clip)UnityEngine.Object.Destroy(clip);}catch(Exception error){status=Status(error);}
                try{clip.Dispose();}catch(Exception error){status=Status(error);}
            }
            return status;
        }
        catch(Exception error){return Status(error);}
        finally{try{manager?.Dispose();}catch{}}
    }
    private static int Status(Exception error)
    {if(error is NativeGameException game)try{game.Dispose();}catch{}return error is RuntimeGatewayException gateway?gateway.Status:6;}
    [UnmanagedCallersOnly(EntryPoint="ehr_source_ios_audio_loader_probe_v1",CallConvs=[typeof(CallConvCdecl)])]
    internal static int Probe(int* proof,nuint count)
    {
        if(proof==null||count!=16)return 4;for(int i=0;i<16;i++)proof[i]=0;
        bool ownsProbeCache=false;
        try
        {
            FacadeRuntime.RequireReady();proof[2]=1;
            // Never retire audio already loaded by real source commands. This
            // explicit no-playback proof runs only immediately after startup.
            if(cache.Count!=0)return proof[1]=7;
            ownsProbeCache=true;
            string[] resources=typeof(SourceAudioPlayback).Assembly.GetManifestResourceNames();
            foreach(string name in resources)
            {
                const string prefix="EHR.Resources.Sounds.";
                if(!name.StartsWith(prefix,StringComparison.Ordinal)||!name.EndsWith(".wav",StringComparison.Ordinal))continue;
                string stem=name.Substring(prefix.Length,name.Length-prefix.Length-4);
                using var embedded=typeof(SourceAudioPlayback).Assembly.GetManifestResourceStream(name)!;
                var wave=new PcmWaveData(OwnedSoundFiles.Read(embedded));
                var clip=Load(stem,out int chunks);proof[3]++;proof[4]+=chunks;proof[13]++;
                bool sameData=true;
                for(int offset=0;offset<wave.SampleCount;)
                {
                    float[] expected=wave.LeftChunk(offset,65536);
                    using var actual=new Il2CppStructArray<float>(expected.Length);
                    NativeArgument* args=stackalloc NativeArgument[2];args[0]=FacadeRuntime.Reference(actual);args[1]=FacadeRuntime.Value(&offset,"System.Int32");
                    using var got=FacadeRuntime.Invoke(new("UnityEngine.AudioModule.dll","UnityEngine","AudioClip","GetData",false,false,"System.Boolean",["System.Single[]","System.Int32"]),clip.Token,args,2);
                    if(!FacadeRuntime.ReadValue<bool>(got))sameData=false;
                    for(int i=0;i<expected.Length;i++)if(Math.Abs(actual[i]-expected[i])>0.000001f)sameData=false;
                    offset+=expected.Length;
                }
                if(sameData)proof[5]++;
                if(stem=="Line"&&wave.BitsPerSample==24&&wave.SampleCount==29104)proof[6]=1;
                if(stem=="Boom"&&wave.SampleCount==67685&&chunks==2)proof[7]=1;
                string file=SourceAudioPaths.SoundFile(SourcePlatformPaths.DataRoot,stem);
                if(File.Exists(file)&&Path.GetFullPath(file).StartsWith(Path.GetFullPath(SourcePlatformPaths.DataRoot)+Path.DirectorySeparatorChar,StringComparison.Ordinal))proof[8]++;
                var repeated=Load(stem,out int again);if(object.ReferenceEquals(clip,repeated)&&again==0)proof[9]++;
            }
            proof[2]=5;int cleanup=CloseCore();ownsProbeCache=false;
            proof[10]=cleanup==0&&cache.Count==0?1:0;proof[2]=6;
            proof[11]=(RuntimeFeature.IsDynamicCodeSupported?1:0)|(RuntimeFeature.IsDynamicCodeCompiled?2:0);
            proof[0]=proof[3]==18&&proof[4]==19&&proof[5]==18&&proof[6]==1&&proof[7]==1&&proof[8]==18&&proof[9]==18&&proof[10]==1&&proof[11]==0&&proof[12]==0&&proof[13]==18?1:0;
            return proof[0]==1?0:7;
        }
        catch(Exception error){return proof[1]=Status(error);}
        finally{if(ownsProbeCache)CloseCore();}
    }
}
