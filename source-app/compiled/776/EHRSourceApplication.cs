using System;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using BepInEx;
using EHR.Generated;
using EHR.SourceHost;

namespace EHR;

[Flags]
internal enum SourceReady:uint {Core=1,Delegates=2,Components=4,Touch=8,Coroutines=16,Targets=32,Prepare=47,All=63}
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct SourceApplicationHostV1
{
    internal uint Version,Size;
    // Verifies the actual native production bindings for the requested flags.
    // It must never report a capability solely because a fixture was run.
    internal delegate* unmanaged[Cdecl]<uint,int> RequireReady;
}
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct SourceApplicationConfigV1
{
    internal uint Version,Size;
    internal byte* Root;internal nuint RootLength;
    internal byte* Module;internal nuint ModuleLength;
    internal byte* UpdateInstructions;internal nuint UpdateInstructionsLength;
}
[StructLayout(LayoutKind.Sequential)]
internal struct SourceApplicationStatusV1
{
    internal uint Version,Size,State,Status;
    internal uint SourceTypes,RoleTypes,Callbacks,Candidates,UnavailableTargets,ActiveBindings;
    internal uint HostState,LoadAttempts,DynamicCodeFlags,OptionsLoaded,OptionCount,OptionsPostLoad;
}
// Production startup state is separate from all fixture Configure/Reset paths.
// All UCO calls refer to this full EHR image, not the research ManagedRules DLL.
internal static unsafe class EHRSourceApplication
{
    private static SourceApplicationHostV1 native;
    private static bool bound;
    private static uint state,status,loadAttempts;
    private static SourcePluginHost? plugin;
    private static NativePatchTargetResolver? resolver;
    private static uint sourceTypes,roleTypes,callbacks,candidates,unavailable,active;
    private static uint optionsLoaded,optionCount,optionsPostLoad;
    private static string error="";
    [UnmanagedCallersOnly(EntryPoint="ehr_source_application_bind_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    internal static int Bind(SourceApplicationHostV1* table,nuint bytes)
    {
        if(bound||table==null||bytes!=16||table->Version!=1||table->Size!=16||table->RequireReady==null)return 4;
        if(!NativeSourceHost.IsMainThread)return 2;
        native=*table;bound=true;return 0;
    }
    private static void Ready(SourceReady flags)
    {
        if(!bound)throw new RuntimeGatewayException(1,"production source application host is not bound");
        if(!NativeSourceHost.IsMainThread)throw new RuntimeGatewayException(2,"source startup requires native main thread");
        FacadeRuntime.Require(native.RequireReady((uint)flags),"production source prerequisites "+flags);
        FacadeRuntime.RequireReady();
        SourceComponentRuntime.Ready();
        if(RuntimeFeature.IsDynamicCodeSupported||RuntimeFeature.IsDynamicCodeCompiled)throw new PlatformNotSupportedException("Source application requires NativeAOT without dynamic code.");
    }
    private static string Read(byte* bytes,nuint length,bool optional=false)
    {
        if(length==0&&optional)return "";
        if(bytes==null||length==0||length>4096)throw new ArgumentException("Invalid bounded source configuration text");
        string result=new UTF8Encoding(false,true).GetString(new ReadOnlySpan<byte>(bytes,(int)length));
        if(result.Contains('\0'))throw new ArgumentException("NUL in source configuration");
        return result;
    }
    private static int Failure(Exception exception)
    {
        error=exception.ToString();state=4;status=(uint)(exception is RuntimeGatewayException gateway?gateway.Status:6);
        if(exception is NativeGameException game)game.Dispose();
        return (int)status;
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_application_prepare_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    internal static int Prepare(SourceApplicationConfigV1* config,nuint bytes)
    {
        if(config==null||bytes!=56||config->Version!=1||config->Size!=56)return 4;
        if(state!=0)return 4;
        try
        {
            Ready(SourceReady.Prepare);
            string root=Read(config->Root,config->RootLength),module=Read(config->Module,config->ModuleLength);
            string update=Read(config->UpdateInstructions,config->UpdateInstructionsLength,true);
            var basis=NativeSourceHost.Options(root,module);
            plugin=new SourcePluginHost(new SourceHostOptions
            {
                DataRoot=basis.DataRoot,NativeModulePath=basis.NativeModulePath,
                IsMainThread=basis.IsMainThread,LogSink=basis.LogSink,
                AddComponent=type=>SourceComponentRuntime.Add(type),
                RegisterComponent=type=>SourceComponentRuntime.Register(type)
            },new BepInPlugin(Main.PluginGuid,Main.ModName,Main.PluginVersion));
            Uri? uri=update.Length==0?null:new Uri(update,UriKind.Absolute);
            SourceSignedUpdates.Configure(uri,uri==null?null:value=>UnityEngine_Application.OpenURL(value.AbsoluteUri),()=>NativeSourceHost.IsMainThread);
            // typeof/catalog operations do not instantiate roles or run Main.Load.
            sourceTypes=(uint)EHRSourceBootstrap.SourceDeclaredTypes().Length;
            roleTypes=(uint)EHRAotRegistry.RoleBaseTypes().Length;
            callbacks=(uint)EHRStaticPatchCatalog.Descriptors.Length;
            var passive=NativePatchCatalog.CreatePassive();candidates=(uint)passive.Length;
            resolver=NativePatchTargetResolver.Prepare(passive,NativePatchCatalog.Candidates);
            unavailable=0;
            foreach(var candidate in NativePatchCatalog.Candidates)
                if(!resolver.TryResolve(candidate.Source,out _,out _))unavailable++;
            state=1;status=0;error="";return 0;
        }
        catch(Exception exception){return Failure(exception);}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_application_load_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    internal static int Load()
    {
        if(state==3)return 0;
        if(state!=1||plugin==null||resolver==null)return 4;
        try
        {
            Ready(SourceReady.All);
            ProductionCoroutines.Ready();
            // Before source side effects, all pinned native candidates must have
            // independently validated installed handlers. No silent partial port.
            if(unavailable!=0)throw new RuntimeGatewayException(7,"installed native source targets are incomplete");
            state=2;loadAttempts++;
            plugin.Load(static()=>new Main());
            var bindings=EHRStaticPatchCatalog.Registration.BindRequested(resolver);
            active=(uint)bindings.Count;
            if(EHRStaticPatchCatalog.Registration.Unavailable.Any(pair=>pair.Value!="class_Prepare_returned_false"&&pair.Value!="target_Prepare_returned_false"))
                throw new RuntimeGatewayException(7,"requested source callbacks contain unavailable targets");
            resolver.Activate(NativePatchCatalog.Create(bindings));
            state=3;status=0;error="";return 0;
        }
        catch(Exception exception){return Failure(exception);}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_application_status_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    internal static int Status(SourceApplicationStatusV1* result,nuint bytes)
    {
        if(result==null||bytes!=64)return 4;
        *result=new(){Version=1,Size=64,State=state,Status=status,SourceTypes=sourceTypes,RoleTypes=roleTypes,Callbacks=callbacks,Candidates=candidates,UnavailableTargets=unavailable,ActiveBindings=active,HostState=plugin==null?0:(uint)plugin.State,LoadAttempts=loadAttempts,DynamicCodeFlags=(RuntimeFeature.IsDynamicCodeSupported?1u:0u)|(RuntimeFeature.IsDynamicCodeCompiled?2u:0u),OptionsLoaded=optionsLoaded,OptionCount=optionCount,OptionsPostLoad=optionsPostLoad};
        return 0;
    }
    // Called only by the pinned actual options coroutine, never by status reads.
    internal static void ObserveOptionsLoaded(int count){optionsLoaded=1;optionCount=(uint)Math.Max(0,count);}
    internal static void ObserveOptionsPostLoad()=>optionsPostLoad=1;
    [UnmanagedCallersOnly(EntryPoint="ehr_source_application_copy_error_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    internal static int CopyError(byte* output,nuint capacity,nuint* required)
    {
        if(required==null)return 4;byte[] utf8=Encoding.UTF8.GetBytes(error);*required=(nuint)utf8.Length+1;
        if(output==null||capacity<*required){if(output!=null&&capacity>0)*output=0;return 8;}
        utf8.CopyTo(new Span<byte>(output,utf8.Length));output[utf8.Length]=0;return 0;
    }
}
