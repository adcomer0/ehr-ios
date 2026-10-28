using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
using Il2CppInterop.Runtime.InteropTypes.Arrays;

namespace EHR.SourceAudio;

// Explicitly invoked only after real full Load. Uses an already existing native
// SoundManager, zero-volume/all-zero own clip, and stops only that exact clip.
// Does not add a GameObject/AudioSource or alter a listener/global audio setting.
internal static unsafe class SourceMutedSoundProbe
{
    [UnmanagedCallersOnly(EntryPoint="ehr_source_muted_sound_probe_v1",CallConvs=[typeof(CallConvCdecl)])]
    internal static int Probe(int* proof,nuint count)
    {
        if(proof==null||count!=16)return 4;for(int i=0;i<16;i++)proof[i]=0;
        global::SoundManager? manager=null;UnityEngine.AudioClip? clip=null;UnityEngine.AudioSource? source=null;
        bool playbackAttempted=false;
        try
        {
            FacadeRuntime.RequireReady();proof[2]=1;
            // SoundManager has no InstanceExists API. Find the real already
            // active component through the public non-generic Unity overload;
            // never invoke a singleton getter or create a replacement owner.
            using var managerType=LiveCollections.TypeObject(FacadeRuntime.Class("Assembly-CSharp.dll","","SoundManager"));
            NativeArgument typeArgument=FacadeRuntime.Reference(managerType);
            using var found=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine","Object","FindObjectOfType",true,false,"UnityEngine.Object",["System.Type"]),0,&typeArgument,1);
            if(found.Token==0)return proof[1]=3;
            if(FacadeRuntime.ObjectClass(found)!=FacadeRuntime.Class("Assembly-CSharp.dll","","SoundManager"))throw new RuntimeGatewayException(5,"unexpected existing SoundManager class");
            manager=new global::SoundManager(found.Detach());
            if(manager is null||!manager)return proof[1]=3;
            proof[3]=1;proof[2]=2;
            FacadeRuntime.Resolve(new("Assembly-CSharp.dll","","SoundManager","PlaySoundImmediate",false,false,"UnityEngine.AudioSource",["UnityEngine.AudioClip","System.Boolean","System.Single","System.Single","UnityEngine.Audio.AudioMixerGroup"]));
            FacadeRuntime.Resolve(new("Assembly-CSharp.dll","","SoundManager","StopSound",false,false,"System.Void",["UnityEngine.AudioClip"]));
            FacadeRuntime.Resolve(new("UnityEngine.AudioModule.dll","UnityEngine","AudioSource","get_volume",false,false,"System.Single",[]));
            FacadeRuntime.Resolve(new("UnityEngine.AudioModule.dll","UnityEngine","AudioSource","get_clip",false,false,"UnityEngine.AudioClip",[]));proof[4]=1;proof[2]=3;
            clip=UnityEngine.AudioClip.Create("EHR muted probe "+global::System.Guid.NewGuid().ToString("N"),8,1,22050,false,false)??throw new InvalidOperationException("owned clip creation failed");
            using var zeros=new Il2CppStructArray<float>(8);
            if(!clip.SetData(zeros,0))throw new RuntimeGatewayException(7,"owned silent clip SetData false");
            using(var frames=FacadeRuntime.Invoke(new("UnityEngine.AudioModule.dll","UnityEngine","AudioClip","get_samples",false,false,"System.Int32",[]),clip.Token,null,0))proof[12]=FacadeRuntime.ReadValue<int>(frames);
            playbackAttempted=true;proof[13]++;source=manager.PlaySoundImmediate(clip,false,0f,1f,null);
            proof[5]=source is not null&&source&&FacadeRuntime.ObjectClass(source)==FacadeRuntime.Class("UnityEngine.AudioModule.dll","UnityEngine","AudioSource")?1:0;
            if(source is null||!source)throw new RuntimeGatewayException(7,"native SoundManager returned no source for owned muted clip");
            using(var volume=FacadeRuntime.Invoke(new("UnityEngine.AudioModule.dll","UnityEngine","AudioSource","get_volume",false,false,"System.Single",[]),source.Token,null,0))proof[6]=FacadeRuntime.ReadValue<float>(volume)==0f?1:0;
            using(var actualClip=FacadeRuntime.Invoke(new("UnityEngine.AudioModule.dll","UnityEngine","AudioSource","get_clip",false,false,"UnityEngine.AudioClip",[]),source.Token,null,0))proof[7]=actualClip.Token!=0&&NativeLifetime.Same(actualClip,clip)?1:0;
            proof[2]=5;
            manager.StopSound(clip);playbackAttempted=false;proof[8]=1;proof[2]=6;
            ulong clipRoot=clip.Token,managerRoot=manager.Token;
            UnityEngine.Object.Destroy(clip);clip.Dispose();clip=null;manager.Dispose();manager=null;
            proof[9]=!FacadeRuntime.TokenIsValid(clipRoot)?1:0;proof[10]=!FacadeRuntime.TokenIsValid(managerRoot)?1:0;proof[2]=7;
            proof[11]=(RuntimeFeature.IsDynamicCodeSupported?1:0)|(RuntimeFeature.IsDynamicCodeCompiled?2:0);
            proof[0]=proof[2]==7&&proof[11]==0&&proof[12]==8&&proof[13]==1&&proof[14]==0?1:0;
            for(int i=3;i<=10;i++)proof[0]&=proof[i];return proof[0]==1?0:7;
        }
        catch(Exception error)
        {
            proof[1]=error is RuntimeGatewayException gateway?gateway.Status:6;
            if(error is NativeGameException native)try{native.Dispose();}catch{}
            return proof[1];
        }
        finally
        {
            if(playbackAttempted&&manager is not null&&clip is not null)try{manager.StopSound(clip);}catch{}
            if(clip is not null){try{UnityEngine.Object.Destroy(clip);}catch{}try{clip.Dispose();}catch{}}
            try{source?.Dispose();}catch{}try{manager?.Dispose();}catch{}
        }
    }
}
