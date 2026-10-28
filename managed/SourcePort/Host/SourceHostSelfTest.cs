using System;
using System.IO;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Unity.IL2CPP;

namespace EHR.SourceHost;

public static class SourceHostSelfTest
{
    private enum Mode { First, Second }
    private sealed class Fixture : BasePlugin
    {
        public int Loads, Finished;
        public override void Load()
        {
            ++Loads;
            Config.Bind("HostFixture","Bool",false).Value = true;
            Config.Bind("HostFixture","Int",0).Value = 42;
            Config.Bind("HostFixture","Single",0f).Value = 1.25f;
            Config.Bind("HostFixture","String","").Value = "native source host Ω 日本語";
            Config.Bind("HostFixture","Enum",Mode.First).Value = Mode.Second;
            IL2CPPChainloader.Instance.Finished += () => ++Finished;
            Log.LogInfo("SourceHost config/startup fixture");
        }
    }
    private sealed class FailedFixture : BasePlugin
    {
        public override void Load() => throw new ApplicationException("expected host fixture failure");
    }
    private sealed class ComponentFixture : BasePlugin
    {
        public override void Load() => AddComponent<object>();
    }
    private sealed class ReentrantFixture : BasePlugin
    {
        public Action? Action;
        public override void Load() => Action!();
    }
    public static void Run(SourceHostOptions options, Span<int> proof)
    {
        if (proof.Length != 16) throw new ArgumentException("Proof requires sixteen integers");
        IL2CPPChainloader? previous = IL2CPPChainloader.Active;
        try
        {
        proof.Clear(); proof[2] = 1;
        int logs = 0;
        SourceHostOptions configured = new()
        {
            DataRoot=options.DataRoot, NativeModulePath=options.NativeModulePath,
            IsMainThread=options.IsMainThread,
            LogSink=(level,text)=>{++logs;options.LogSink?.Invoke(level,text);}
        };
        BepInPlugin Metadata(string suffix) => new("org.ehr.sourcehost.selftest."+suffix,"EHRSourceHostSelfTest","1.0.0");
        SourcePluginHost host = new(configured,Metadata("success"));
        int factories = 0;
        Fixture fixture = (Fixture)host.Load(()=>{++factories;return new Fixture();});
        BasePlugin again = host.Load(()=>{++factories;return new Fixture();});
        proof[4] = fixture.Loads == 1 && factories == 1 && ReferenceEquals(again,fixture) ? 1:0;
        proof[5] = fixture.Finished;
        proof[6] = logs;
        proof[2] = 2;
        ConfigFile read = new(fixture.Config.ConfigFilePath,false);
        if (read.Bind("HostFixture","Bool",false).Value) ++proof[3];
        if (read.Bind("HostFixture","Int",0).Value == 42) ++proof[3];
        if (read.Bind("HostFixture","Single",0f).Value == 1.25f) ++proof[3];
        if (read.Bind("HostFixture","String","").Value == "native source host Ω 日本語") ++proof[3];
        if (read.Bind("HostFixture","Enum",Mode.First).Value == Mode.Second) ++proof[3];
        PluginInfo actual=host.Chainloader.Plugins[Metadata("success").GUID];
        proof[7] = ReferenceEquals(actual.Instance,fixture) && actual.Metadata.GUID == Metadata("success").GUID &&
            actual.Location == options.NativeModulePath && actual.TypeName == typeof(Fixture).FullName ? 1:0;
        proof[8] = host.Chainloader.Plugins.Count == 1 && !host.Chainloader.Plugins.ContainsKey("gg.reactor.api") ? 1:0;
        proof[15] = Paths.ConfigPath == Path.Combine(host.DataRoot,"config") &&
            Paths.BepInExConfigPath == Path.Combine(host.DataRoot,"config","BepInEx.cfg") &&
            SourcePlatformPaths.DataRoot == host.DataRoot ? 1:0;
        proof[14] = !fixture.Unload() ? 1:0;
        proof[2] = 3;
        SourcePluginHost failed = new(configured,Metadata("failure"));
        try { failed.Load(()=>new FailedFixture()); } catch(ApplicationException) { }
        bool retryRejected=false;
        try { failed.Load(()=>new FailedFixture()); } catch(InvalidOperationException) { retryRejected=true; }
        proof[9] = failed.State == SourceHostState.Failed && failed.Chainloader.Plugins.Count == 0 && retryRejected ? 1:0;
        SourcePluginHost reentrant = new(configured,Metadata("reentrant"));
        bool nestedRejected=false;
        reentrant.Load(()=>new ReentrantFixture { Action=()=>
        {try {reentrant.Load(()=>new Fixture());}catch(InvalidOperationException){nestedRejected=true;}}});
        proof[10] = nestedRejected && reentrant.State == SourceHostState.Loaded ? 1:0;
        proof[11] = Task.Run(()=>
        {try{host.Load(()=>new Fixture());return 0;}catch(InvalidOperationException){return 1;}}).GetAwaiter().GetResult();
        SourcePluginHost missing = new(configured,Metadata("component"));
        try { missing.Load(()=>new ComponentFixture()); } catch(PlatformNotSupportedException) { }
        proof[12] = missing.State == SourceHostState.Failed && missing.Chainloader.Plugins.Count == 0 ? 1:0;
        proof[13] = (RuntimeFeature.IsDynamicCodeSupported?1:0) | (RuntimeFeature.IsDynamicCodeCompiled?2:0);
        proof[2] = 4;
        proof[0] = proof[3]==5 && proof[4]==1 && proof[5]==1 && proof[6]==1 && proof[7]==1 && proof[8]==1 &&
            proof[9]==1 && proof[10]==1 && proof[11]==1 && proof[12]==1 && proof[13]==0 && proof[14]==1 && proof[15]==1 ? 1:0;
        proof[1] = proof[0]==1 ? 0:1;
        }
        finally { IL2CPPChainloader.Activate(previous); }
    }
}
