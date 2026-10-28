using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)]
internal struct TypedActionProofV1
{
    internal uint AbiVersion,ByteSize,Pass,Status;
    internal uint Int32Exact,ByteExact,FloatExact,ReferenceIdentity;
    internal uint OptionNull,GameObjectNull,ExceptionContained,ProxyDisposePreservesNative;
    internal uint CloseLateNoop,CombineRemove,SourceEntriesAfter,RootsReleased;
    internal uint CaseId,LookupStep,Reserved0,Reserved1;
}
internal static unsafe class TypedActionSelfTest
{
    private sealed class Effects{internal int Int,First,Second;internal byte Byte;internal float Float;internal bool Reference,Option,GameObject;}
    [UnmanagedCallersOnly(EntryPoint="ehr_typed_action_self_test",CallConvs=[typeof(CallConvCdecl)])]
    internal static int Run(TypedActionProofV1* proof,nuint bytes)
    {
        if(proof==null||bytes!=(nuint)sizeof(TypedActionProofV1))return 4;
        *proof=new(){AbiVersion=1,ByteSize=(uint)sizeof(TypedActionProofV1)};
        var roots=new List<RuntimeObject>();var tokens=new List<ulong>();var closes=new List<System.Action>();
        T Keep<T>(T value,System.Action? close=null)where T:RuntimeObject{roots.Add(value);tokens.Add(value.Token);if(close!=null)closes.Add(close);return value;}
        try
        {
            TypedActionRuntime.RequireMain();var effects=new Effects();
            proof->CaseId=1;
            var integer=Keep(new Il2CppSystem.Action<int>(value=>effects.Int=value));closes.Add(integer.Close);
            integer.Invoke(-1234567);proof->Int32Exact=effects.Int==-1234567?1u:0u;
            var retained=Keep(FacadeRuntime.Retain(integer));integer.Dispose();TypedActionRuntime.Invoke(retained.Token,42);
            proof->ProxyDisposePreservesNative=effects.Int==42?1u:0u;
            integer.Close();TypedActionRuntime.Invoke(retained.Token,-1);proof->CloseLateNoop=effects.Int==42?1u:0u;
            proof->CaseId=2;
            var bytesAction=Keep(new Il2CppSystem.Action<byte>(value=>effects.Byte=value));closes.Add(bytesAction.Close);
            bytesAction.Invoke(231);proof->ByteExact=effects.Byte==231?1u:0u;
            proof->CaseId=3;
            var floating=Keep(new Il2CppSystem.Action<float>(value=>effects.Float=value));closes.Add(floating.Close);
            floating.Invoke(0.375f);proof->FloatExact=BitConverter.SingleToInt32Bits(effects.Float)==BitConverter.SingleToInt32Bits(0.375f)?1u:0u;
            proof->CaseId=4;
            using var constructed=LiveReflection.Construct(FacadeRuntime.Class("mscorlib.dll","System","Object"),[]);
            var original=Keep(new Il2CppSystem.Object(constructed.Detach()));
            var reference=Keep(new Il2CppSystem.Action<Il2CppSystem.Object?>(value=>{if(value!=null){effects.Reference=NativeLifetime.Same(original,value);value.Dispose();}}));closes.Add(reference.Close);
            reference.Invoke(original);proof->ReferenceIdentity=effects.Reference?1u:0u;
            proof->CaseId=5;
            var option=Keep(new Il2CppSystem.Action<OptionBehaviour?>(value=>effects.Option=value is null));closes.Add(option.Close);option.Invoke(null);
            var gameObject=Keep(new Il2CppSystem.Action<UnityEngine_GameObject?>(value=>effects.GameObject=value is null));closes.Add(gameObject.Close);gameObject.Invoke(null);
            proof->OptionNull=effects.Option?1u:0u;proof->GameObjectNull=effects.GameObject?1u:0u;
            proof->CaseId=6;
            var error=Keep(new Il2CppSystem.Action<int>(static _=>throw new InvalidOperationException("own typed callback failure")));closes.Add(error.Close);error.Invoke(7);
            proof->ExceptionContained=TypedActionRuntime.Status(error.Registration)==6?1u:0u;
            proof->CaseId=7;
            var first=Keep(new Il2CppSystem.Action<int>(value=>effects.First=value));var second=Keep(new Il2CppSystem.Action<int>(value=>effects.Second=value));closes.Add(first.Close);closes.Add(second.Close);
            var combined=Keep((first+second)??throw new InvalidOperationException("missing native combined delegate"));combined.Invoke(4);
            var removed=Keep((combined-first)??throw new InvalidOperationException("missing native removed delegate"));removed.Invoke(7);
            proof->CombineRemove=effects.First==4&&effects.Second==7?1u:0u;
            proof->CaseId=8;
            foreach(var close in closes)close();foreach(var root in roots)root.Dispose();
            proof->SourceEntriesAfter=(uint)TypedActionRuntime.SourceCount;
            bool released=true;foreach(var token in tokens)released&=!FacadeRuntime.TokenIsValid(token);proof->RootsReleased=released?1u:0u;
            proof->Pass=proof->Int32Exact==1&&proof->ByteExact==1&&proof->FloatExact==1&&proof->ReferenceIdentity==1&&proof->OptionNull==1&&proof->GameObjectNull==1&&
                proof->ExceptionContained==1&&proof->ProxyDisposePreservesNative==1&&proof->CloseLateNoop==1&&proof->CombineRemove==1&&proof->SourceEntriesAfter==0&&proof->RootsReleased==1?1u:0u;
            return proof->Pass==1?0:4;
        }
        catch(NativeGameException error){try{error.Dispose();}catch{}return (int)(proof->Status=6);}
        catch(RuntimeGatewayException error){proof->LookupStep=(uint)NativeMethods.LastLookupStep;return (int)(proof->Status=(uint)error.Status);}
        catch{return (int)(proof->Status=4);}
        finally{foreach(var close in closes)try{close();}catch{}foreach(var root in roots)try{root.Dispose();}catch{}}
    }
}
