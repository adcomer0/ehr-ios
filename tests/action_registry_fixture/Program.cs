// ORIGINAL fixture host. This executes the production C# registry in NativeAOT;
// its tiny host models root/close behavior and makes no IL2CPP runtime claim.
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;

internal static unsafe class OwnHost
{
    internal sealed class Entry(ulong source){internal readonly ulong Source=source;internal bool Closed;internal int Status;}
    internal static ActionCallbacksV1 Callbacks;
    internal static bool Main=true;
    internal static ulong Next=1,Forgets;
    internal static readonly Dictionary<ulong,Entry> Entries=new();
    internal static readonly Dictionary<ulong,Entry> Roots=new();
    internal static ulong Retain(Entry entry){ulong token=Next++;Roots.Add(token,entry);return token;}
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Create(ulong source,ulong* root,ulong* registration,ulong* exception)
    {
        *root=*registration=*exception=0;if(!Main)return 2;
        if(Entries.Count>=256)return 8;
        var entry=new Entry(source);ulong id=Next++;Entries.Add(id,entry);
        *root=Retain(entry);*registration=id;return 0;
    }
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Close(ulong registration)
    {
        if(!Main)return 2;if(!Entries.TryGetValue(registration,out var entry))return 9;
        if(entry.Closed)return 0;entry.Closed=true;++Forgets;return Callbacks.Forget(entry.Source);
    }
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Sweep(nuint* removed)
    {
        *removed=0;if(!Main)return 2;
        foreach(var pair in Entries.ToArray())
        {
            if(Roots.Values.Contains(pair.Value))continue;
            if(!pair.Value.Closed){pair.Value.Closed=true;++Forgets;Callbacks.Forget(pair.Value.Source);}
            Entries.Remove(pair.Key);++*removed;
        }
        return 0;
    }
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Status(ulong registration,int* status)
    {
        *status=0;if(!Main)return 2;if(!Entries.TryGetValue(registration,out var entry))return 9;
        *status=entry.Status;return 0;
    }
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int IsMain()=>Main?1:0;
    internal static void Invoke(ulong token)
    {
        Entry entry=Roots[token];if(!entry.Closed)entry.Status=Callbacks.Invoke(entry.Source);
    }
}
internal static unsafe class Program
{
    static int Main()
    {
        ActionHostV1 host=new(){AbiVersion=1,ByteSize=(uint)sizeof(ActionHostV1),Create=&OwnHost.Create,Close=&OwnHost.Close,
            Sweep=&OwnHost.Sweep,CallbackStatus=&OwnHost.Status,IsMainThread=&OwnHost.IsMain};
        delegate* unmanaged[Cdecl]<ActionHostV1*,nuint,ActionCallbacksV1*,nuint,int> bind=&ActionRuntime.Bind;
        ActionCallbacksV1 callbacks=default;int status=bind(&host,(nuint)sizeof(ActionHostV1),&callbacks,(nuint)sizeof(ActionCallbacksV1));
        OwnHost.Callbacks=callbacks;
        ActionProofV1 proof=default;delegate* unmanaged[Cdecl]<ActionProofV1*,nuint,int> test=&ActionRuntime.SelfTest;
        int tested=test(&proof,(nuint)sizeof(ActionProofV1));
        bool workerRejected=false;OwnHost.Main=false;
        try{using var wrongThread=new Il2CppSystem.Action(static()=>{});}catch(RuntimeGatewayException error){workerRejected=error.Status==2;}
        OwnHost.Main=true;nuint swept=0;int sweep=host.Sweep(&swept);
        bool passed=status==0&&tested==0&&proof.Pass==1&&workerRejected&&sweep==0&&swept==2&&OwnHost.Roots.Count==0&&OwnHost.Entries.Count==0&&OwnHost.Forgets==2;
        Console.WriteLine($"{{\"success\":{passed.ToString().ToLowerInvariant()},\"sourceEffects\":{proof.SourceEffects},\"exceptionContained\":{proof.CallbackExceptionContained},\"proxyDisposePreservesNative\":{proof.ProxyDisposePreservesNative},\"closedLateInvokeNoop\":{proof.ClosedLateInvokeNoop},\"sourceEntriesAfter\":{proof.SourceEntriesAfter},\"ownedRootsReleased\":{proof.RootsReleased},\"workerRejected\":{workerRejected.ToString().ToLowerInvariant()},\"weakEntriesSwept\":{swept},\"forgetExactlyOnce\":{OwnHost.Forgets},\"scope\":\"production CSharp registry in own NativeAOT fixture; simulated host only\"}}");
        return passed?0:1;
    }
}
namespace EHR.Generated
{
    public class RuntimeGatewayException(int status,string operation):Exception(operation){public int Status{get;}=status;}
    public sealed class NativeGameException():RuntimeGatewayException(6,"own fixture"),IDisposable {public void Dispose(){}}
    public class RuntimeObject:IDisposable
    {
        private ulong token;internal RuntimeObject(ulong owned){token=owned;}
        internal ulong Token=>token;
        public void Dispose(){FacadeRuntime.Release(token);token=0;}
    }
    internal sealed record BindingSpec(string Image,string Namespace,string Type,string Member,bool IsStatic,bool IsField,string ResultType,string[] Parameters);
    internal static unsafe class FacadeRuntime
    {
        internal static void Require(int status,string operation){if(status!=0)throw new RuntimeGatewayException(status,operation);}
        internal static void CheckManaged(int status,ulong exception,string operation){if(exception!=0)throw new NativeGameException();Require(status,operation);}
        internal static RuntimeObject Retain(RuntimeObject borrowed)=>new(OwnHost.Retain(OwnHost.Roots[borrowed.Token]));
        internal static void Release(ulong token){if(token!=0)OwnHost.Roots.Remove(token);}
        internal static bool TokenIsValid(ulong token)=>OwnHost.Roots.ContainsKey(token);
        internal static RuntimeObject Invoke(BindingSpec spec,ulong borrowed,void* arguments,nuint count){OwnHost.Invoke(borrowed);return new(0);}
    }
}
namespace Il2CppSystem {public class Object:EHR.Generated.RuntimeObject {internal Object(ulong owned):base(owned){}}}
