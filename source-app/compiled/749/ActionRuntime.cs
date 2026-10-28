// Original zero-argument native Action bridge. Native pointers never cross this
// ABI; callbacks are keyed by opaque source IDs and own dictionary references.
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated
{
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct ActionHostV1
    {
        internal uint AbiVersion,ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,ulong*,ulong*,int> Create;
        internal delegate* unmanaged[Cdecl]<ulong,int> Close;
        internal delegate* unmanaged[Cdecl]<nuint*,int> Sweep;
        internal delegate* unmanaged[Cdecl]<ulong,int*,int> CallbackStatus;
        internal delegate* unmanaged[Cdecl]<int> IsMainThread;
    }
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct ActionCallbacksV1
    {
        internal uint AbiVersion,ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong,int> Invoke;
        internal delegate* unmanaged[Cdecl]<ulong,int> Forget;
    }
    [StructLayout(LayoutKind.Sequential)]
    internal struct ActionProofV1
    {
        internal uint AbiVersion,ByteSize,Pass,Status;
        internal uint SourceEffects,CallbackExceptionContained,ClosedLateInvokeNoop,SourceEntriesAfter;
        internal uint CallbackSuccessStatus,CallbackErrorStatus,RootsReleased,ProxyDisposePreservesNative;
    }
    internal readonly record struct ActionCreation(ulong Root,ulong Registration);
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct ActionFamiliesV1
    {
        internal uint AbiVersion,ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,ulong*,ulong*,int> CreateUnityAction;
    }
    internal static unsafe class NativeActionCombination
    {
        internal static Il2CppSystem.Action? Apply(Il2CppSystem.Action? left,Il2CppSystem.Action? right,bool remove)
        {
            ActionRuntime.RequireMain();
            NativeArgument* arguments=stackalloc NativeArgument[2];arguments[0]=FacadeRuntime.Reference(left);arguments[1]=FacadeRuntime.Reference(right);
            using var result=FacadeRuntime.Invoke(new("mscorlib.dll","System","Delegate",remove?"Remove":"Combine",true,false,"System.Delegate",["System.Delegate","System.Delegate"]),0,arguments,2);
            if(result.Token==0)return null;
            if(FacadeRuntime.ObjectClass(result)!=FacadeRuntime.Class("mscorlib.dll","System","Action"))throw new RuntimeGatewayException(5,"native combined Action exact class");
            return new(result.Detach());
        }
    }
    internal static unsafe class ActionRuntime
    {
        private static ActionHostV1 host;
        private static bool bound;
        private static ActionFamiliesV1 families;
        private static bool familiesBound;
        private static ulong next=1;
        private static readonly Dictionary<ulong,System.Action> callbacks=new();
        private static readonly Dictionary<(System.Action Source,bool Unity),ulong> identities=new();
        private static readonly Dictionary<ulong,(System.Action Source,bool Unity)> identityBySource=new();
        private static readonly BindingSpec InvokeMethod=new("mscorlib.dll","System","Action","Invoke",false,false,"System.Void",[]);
        internal static int SourceCount {get{RequireMain();return callbacks.Count;}}
        internal static void RequireMain()
        {
            if(!bound)throw new RuntimeGatewayException(1,"native Action bridge unavailable");
            if(host.IsMainThread()!=1)throw new RuntimeGatewayException(2,"native Action requires Unity main thread");
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_action_bind_gateway",CallConvs=[typeof(CallConvCdecl)])]
        internal static int Bind(ActionHostV1* source,nuint bytes,ActionCallbacksV1* result,nuint resultBytes)
        {
            if(source==null||result==null||bytes!=(nuint)sizeof(ActionHostV1)||resultBytes!=(nuint)sizeof(ActionCallbacksV1)||
                source->AbiVersion!=1||source->ByteSize!=sizeof(ActionHostV1)||source->Create==null||source->Close==null||
                source->Sweep==null||source->CallbackStatus==null||source->IsMainThread==null)return 4;
            if(source->IsMainThread()!=1)return 2;
            if(bound&&((nuint)host.Create!=(nuint)source->Create||(nuint)host.Close!=(nuint)source->Close||
                (nuint)host.Sweep!=(nuint)source->Sweep||(nuint)host.CallbackStatus!=(nuint)source->CallbackStatus||
                (nuint)host.IsMainThread!=(nuint)source->IsMainThread))return 4;
            host=*source;bound=true;
            *result=new(){AbiVersion=1,ByteSize=(uint)sizeof(ActionCallbacksV1),Invoke=&InvokeSource,Forget=&ForgetSource};
            return 0;
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_action_bind_families",CallConvs=[typeof(CallConvCdecl)])]
        internal static int BindFamilies(ActionFamiliesV1* source,nuint bytes)
        {
            if(source==null||bytes!=(nuint)sizeof(ActionFamiliesV1)||source->AbiVersion!=1||source->ByteSize!=sizeof(ActionFamiliesV1)||source->CreateUnityAction==null)return 4;
            if(!bound)return 1;if(host.IsMainThread()!=1)return 2;
            if(familiesBound&&(nuint)families.CreateUnityAction!=(nuint)source->CreateUnityAction)return 4;
            families=*source;familiesBound=true;return 0;
        }
        internal static ActionCreation Create(System.Action source,bool unity=false)
        {
            ArgumentNullException.ThrowIfNull(source);RequireMain();
            if(unity&&!familiesBound)throw new RuntimeGatewayException(7,"UnityAction family unavailable");
            var key=(source,unity);bool reused=identities.TryGetValue(key,out ulong id);
            if(!reused)
            {
                if(callbacks.Count>=256||next==ulong.MaxValue)throw new RuntimeGatewayException(8,"native Action limit");
                id=next++;callbacks.Add(id,source);identities.Add(key,id);identityBySource.Add(id,key);
            }
            ulong root=0,registration=0,exception=0;
            int status=unity ? families.CreateUnityAction(id,&root,&registration,&exception) : host.Create(id,&root,&registration,&exception);
            if(status!=0||exception!=0||root==0||registration==0)
            {
                if(!reused)ForgetIdentity(id);
                FacadeRuntime.Release(root);
                FacadeRuntime.CheckManaged(status==0?4:status,exception,"create real native Action");
            }
            // Native create sweeps first. A dead weak carrier may have forgotten
            // this source; successful recreation owns the same equality key anew.
            callbacks[id]=source;identities[key]=id;identityBySource[id]=key;
            return new(root,registration);
        }
        internal static void Close(ulong registration)
        {
            RequireMain();FacadeRuntime.Require(host.Close(registration),"close native Action source");
        }
        internal static int CallbackStatus(ulong registration)
        {
            RequireMain();int status=0;FacadeRuntime.Require(host.CallbackStatus(registration,&status),"native Action callback status");return status;
        }
        internal static void InvokeNative(ulong borrowed)
        {
            RequireMain();using var result=FacadeRuntime.Invoke(InvokeMethod,borrowed,null,0);
        }
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int InvokeSource(ulong source)
        {
            if(!bound)return 1;
            if(host.IsMainThread()!=1)return 2;
            if(!callbacks.TryGetValue(source,out System.Action? callback))return 9;
            try {callback();return 0;}
            catch(NativeGameException exception){try{exception.Dispose();}catch{}return 6;}
            catch {return 6;} // No .NET exception unwinds into an IL2CPP frame.
        }
        private static void ForgetIdentity(ulong source)
        {
            callbacks.Remove(source);
            if(identityBySource.Remove(source,out var key)&&identities.TryGetValue(key,out ulong current)&&current==source)identities.Remove(key);
        }
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int ForgetSource(ulong source)
        {
            if(!bound)return 1;
            if(host.IsMainThread()!=1)return 2;
            try {ForgetIdentity(source);return 0;}catch{return 4;}
        }
        private sealed class Effects {internal uint Count;}
        [UnmanagedCallersOnly(EntryPoint="ehr_action_combination_self_test",CallConvs=[typeof(CallConvCdecl)])]
        internal static int CombinationTest(int* output,nuint count)
        {
            if(output==null||count!=6)return 4;for(int i=0;i<6;++i)output[i]=0;
            try
            {
                RequireMain();int effects=0;
                using var first=new Il2CppSystem.Action(()=>effects+=1);
                using var second=new Il2CppSystem.Action(()=>effects+=10);
                ulong firstToken=first.Token,secondToken=second.Token;
                try
                {
                    using var combined=first+second;if(combined is null)throw new RuntimeGatewayException(5,"combined Action null");
                    combined.Invoke();output[2]=effects==11?1:0;
                    using var removed=combined-first;if(removed is null)throw new RuntimeGatewayException(5,"removed Action null");
                    removed.Invoke();output[3]=effects==21?1:0;
                    using var alias=first+(Il2CppSystem.Action?)null;
                    using var empty=first-first;
                    output[4]=alias is not null&&alias.Equals(first)&&empty is null?1:0;
                }
                finally{first.Close();second.Close();first.Dispose();second.Dispose();}
                output[5]=!FacadeRuntime.TokenIsValid(firstToken)&&!FacadeRuntime.TokenIsValid(secondToken)?1:0;
                output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;return output[1]=output[0]==1?0:5;
            }
            catch(NativeGameException exception){try{exception.Dispose();}catch{}return output[1]=6;}
            catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_action_self_test",CallConvs=[typeof(CallConvCdecl)])]
        internal static int SelfTest(ActionProofV1* proof,nuint bytes)
        {
            if(proof==null||bytes!=(nuint)sizeof(ActionProofV1))return 4;
            *proof=new(){AbiVersion=1,ByteSize=(uint)sizeof(ActionProofV1)};
            try
            {
                RequireMain();var effects=new Effects();
                using var good=new Il2CppSystem.Action(()=>++effects.Count);
                using var bad=new Il2CppSystem.Action(()=>throw new InvalidOperationException("own Action fixture failure"));
                ulong goodToken=good.Token,badToken=bad.Token;
                good.Invoke();proof->CallbackSuccessStatus=(uint)CallbackStatus(good.Registration);
                bad.Invoke();proof->CallbackErrorStatus=(uint)CallbackStatus(bad.Registration);
                proof->CallbackExceptionContained=proof->CallbackErrorStatus==6?1u:0u;
                using var retained=FacadeRuntime.Retain(good);ulong retainedToken=retained.Token;
                good.Dispose();
                InvokeNative(retained.Token);
                proof->ProxyDisposePreservesNative=effects.Count==2?1u:0u;
                good.Close();bad.Close();
                InvokeNative(retained.Token);
                proof->SourceEffects=effects.Count;proof->ClosedLateInvokeNoop=effects.Count==2?1u:0u;
                proof->SourceEntriesAfter=(uint)callbacks.Count;
                good.Dispose();bad.Dispose();retained.Dispose();
                proof->RootsReleased=!FacadeRuntime.TokenIsValid(goodToken)&&!FacadeRuntime.TokenIsValid(badToken)&&!FacadeRuntime.TokenIsValid(retainedToken)?1u:0u;
                proof->Pass=proof->SourceEffects==2&&proof->CallbackSuccessStatus==0&&proof->CallbackExceptionContained==1&&
                    proof->ProxyDisposePreservesNative==1&&proof->ClosedLateInvokeNoop==1&&proof->SourceEntriesAfter==0&&proof->RootsReleased==1?1u:0u;
                return proof->Pass==1?0:4;
            }
            catch(NativeGameException exception){try{exception.Dispose();}catch{}return (int)(proof->Status=6);}
            catch(RuntimeGatewayException exception){return (int)(proof->Status=(uint)exception.Status);}
            catch{return (int)(proof->Status=4);}
        }
    }
}
namespace Il2CppSystem
{
    public sealed class Action:Object
    {
        internal ulong Registration {get;}
        private bool closed;
        public Action(System.Action source):this(EHR.Generated.ActionRuntime.Create(source)){}
        internal Action(ulong ownedToken):base(ownedToken){}
        private Action(EHR.Generated.ActionCreation created):base(created.Root){Registration=created.Registration;}
        public static implicit operator Action?(System.Action? source)=>source is null?null:new(source);
        public static Action? operator +(Action? left,Action? right)=>EHR.Generated.NativeActionCombination.Apply(left,right,false);
        public static Action? operator -(Action? left,Action? right)=>EHR.Generated.NativeActionCombination.Apply(left,right,true);
        public void Invoke()=>EHR.Generated.ActionRuntime.InvokeNative(Token);
        // Close tombstones only this source callback. Existing native Action
        // references remain valid and safely no-op after this returns.
        public void Close()
        {
            if(closed||Registration==0)return;
            EHR.Generated.ActionRuntime.Close(Registration);closed=true;
        }
        // Inherit proxy-only disposal/finalization, including deferred worker
        // release. Native owners keep the callback live until explicit Close
        // or weak-target collection; disposing this proxy must not cancel it.
    }
}
