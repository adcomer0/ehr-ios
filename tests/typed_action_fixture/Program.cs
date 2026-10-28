// Original host-only fixture executing the production C# typed callback path
// in NativeAOT. No game metadata, object layout or IL2CPP execution is claimed.
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
internal static unsafe class OwnHost
{
    internal sealed class Record(object? value){internal object? Value=value;internal ulong Source;internal uint ABI;internal int Status;internal bool Closed;}
    internal static readonly Dictionary<ulong,Record> Roots=new(),Entries=new();
    internal static TypedActionCallbacksV1 Callbacks;
    internal static ulong Next=1,Forgets;
    internal static bool MainThread=true;
    internal static ulong Add(Record value){ulong token=Next++;Roots.Add(token,value);return token;}
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Create(ulong source,ulong klass,uint abi,ulong* root,ulong* registration,ulong* exception)
    {
        *root=*registration=*exception=0;if(!MainThread)return 2;
        if(klass!=abi||abi<1||abi>4)return 5;
        var pair=Entries.FirstOrDefault(p=>p.Value.Source==source&&!p.Value.Closed);
        if(pair.Value!=null){if(pair.Value.ABI!=abi)return 5;*root=Add(pair.Value);*registration=pair.Key;return 0;}
        var record=new Record(null){Source=source,ABI=abi};ulong id=Next++;Entries.Add(id,record);*root=Add(record);*registration=id;return 0;
    }
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Close(ulong registration)
    {
        if(!MainThread)return 2;if(!Entries.TryGetValue(registration,out var record))return 9;
        if(record.Closed)return 0;record.Closed=true;++Forgets;return Callbacks.Forget(record.Source);
    }
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int Status(ulong registration,int* status)
    {*status=0;if(!MainThread)return 2;if(!Entries.TryGetValue(registration,out var record))return 9;*status=record.Status;return 0;}
    [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
    internal static int IsMain()=>MainThread?1:0;
    internal static void Invoke(ulong token,ulong argument)
    {
        var record=Roots[token];if(record.Closed)return;
        record.Status=record.ABI switch{
            1=>Callbacks.InvokeI32(record.Source,(int)Roots[argument].Value!),
            2=>Callbacks.InvokeU8(record.Source,(byte)Roots[argument].Value!),
            3=>Callbacks.InvokeF32(record.Source,(float)Roots[argument].Value!),
            4=>Callbacks.InvokeReference(record.Source,argument),_=>7};
    }
    internal static uint Sweep()
    {
        uint removed=0;foreach(var item in Entries.ToArray())if(!Roots.Values.Contains(item.Value))
        {if(!item.Value.Closed){item.Value.Closed=true;++Forgets;Callbacks.Forget(item.Value.Source);}Entries.Remove(item.Key);++removed;}return removed;
    }
}
internal static unsafe class Program
{
    static int Main()
    {
        TypedActionHostV1 host=new(){AbiVersion=1,ByteSize=(uint)sizeof(TypedActionHostV1),Create=&OwnHost.Create,Close=&OwnHost.Close,CallbackStatus=&OwnHost.Status,IsMainThread=&OwnHost.IsMain};
        TypedActionCallbacksV1 callbacks=default;
        delegate* unmanaged[Cdecl]<TypedActionHostV1*,nuint,TypedActionCallbacksV1*,nuint,int> bind=&TypedActionRuntime.Bind;
        bool bound=bind(&host,(nuint)sizeof(TypedActionHostV1),&callbacks,(nuint)sizeof(TypedActionCallbacksV1))==0;OwnHost.Callbacks=callbacks;
        int integer=0;byte bytes=0;float floating=0;Il2CppSystem.Object? escaped=null;
        System.Action<int> integerSource=v=>integer=v;
        using var i=new Il2CppSystem.Action<int>(integerSource);using var b=new Il2CppSystem.Action<byte>(v=>bytes=v);
        using var f=new Il2CppSystem.Action<float>(v=>floating=v);using var r=new Il2CppSystem.Action<Il2CppSystem.Object?>(v=>escaped=v);
        using var error=new Il2CppSystem.Action<int>(static _=>throw new InvalidOperationException("own typed fixture"));
        using var fresh=new Il2CppSystem.Action<int>(integerSource);bool stable=fresh.Registration==i.Registration&&OwnHost.Entries.Count==5;fresh.Dispose();
        i.Invoke(-1234567);b.Invoke(231);f.Invoke(0.375f);
        bool exact=integer==-1234567&&bytes==231&&BitConverter.SingleToInt32Bits(floating)==BitConverter.SingleToInt32Bits(0.375f);
        using var original=new Il2CppSystem.Object(OwnHost.Add(new OwnHost.Record(new object())));r.Invoke(original);
        bool retained=escaped!=null&&FacadeRuntime.TokenIsValid(escaped.Token)&&ReferenceEquals(OwnHost.Roots[original.Token],OwnHost.Roots[escaped.Token]);
        escaped?.Dispose();error.Invoke(1);bool caught=TypedActionRuntime.Status(error.Registration)==6;
        using var kept=FacadeRuntime.Retain(i);i.Dispose();TypedActionRuntime.Invoke(kept.Token,42);bool proxy=integer==42;
        i.Close();TypedActionRuntime.Invoke(kept.Token,-1);bool noop=integer==42;
        b.Close();f.Close();r.Close();error.Close();uint sourceCount=(uint)TypedActionRuntime.SourceCount;
        b.Dispose();f.Dispose();r.Dispose();error.Dispose();kept.Dispose();original.Dispose();
        OwnHost.MainThread=false;bool worker=false;try{using var rejected=new Il2CppSystem.Action<int>(static _=>{});}catch(RuntimeGatewayException e){worker=e.Status==2;}OwnHost.MainThread=true;
        uint swept=OwnHost.Sweep();bool success=bound&&stable&&exact&&retained&&caught&&proxy&&noop&&sourceCount==0&&worker&&swept==5&&OwnHost.Roots.Count==0&&OwnHost.Forgets==5;
        Console.WriteLine($"{{\"success\":{success.ToString().ToLowerInvariant()},\"stableSourceCarrier\":{stable.ToString().ToLowerInvariant()},\"scalarExact\":{exact.ToString().ToLowerInvariant()},\"referenceEscapesWithOwnedRoot\":{retained.ToString().ToLowerInvariant()},\"exceptionContained\":{caught.ToString().ToLowerInvariant()},\"proxyDisposePreservesNative\":{proxy.ToString().ToLowerInvariant()},\"closeLateNoop\":{noop.ToString().ToLowerInvariant()},\"sourceEntriesAfter\":{sourceCount},\"workerRejected\":{worker.ToString().ToLowerInvariant()},\"weakEntriesSwept\":{swept},\"forgetExactlyOnce\":{OwnHost.Forgets},\"scope\":\"production typed CSharp callback path; original simulated host only\"}}");
        return success?0:1;
    }
}
namespace EHR.Generated
{
    internal readonly record struct ActionCreation(ulong Root,ulong Registration);
    public class RuntimeGatewayException(int status,string message):Exception(message){public int Status{get;}=status;}
    public sealed class NativeGameException():RuntimeGatewayException(6,"own"),IDisposable{public void Dispose(){}}
    public class RuntimeObject:IDisposable
    {
        private ulong token;internal RuntimeObject(ulong owned){token=owned;}internal ulong Token=>token;
        internal ulong Detach(){ulong value=token;token=0;return value;}
        public void Dispose(){FacadeRuntime.Release(token);token=0;}
    }
    [StructLayout(LayoutKind.Sequential)]internal unsafe struct NativeArgument{internal uint Kind,Reserved;internal ulong Token;internal void* Bytes;internal nuint ByteCount;}
    internal sealed record BindingSpec(string Image,string Namespace,string Type,string Member,bool IsStatic,bool IsField,string ResultType,string[] Parameters);
    internal interface IElementCodec{ulong NativeClass();object? Read(RuntimeObject owned);RuntimeObject Box(object? value);}
    internal sealed class Primitive<T>(uint abi):IElementCodec
    {
        public ulong NativeClass()=>abi;
        public object? Read(RuntimeObject owned){using(owned)return OwnHost.Roots[owned.Token].Value;}
        public RuntimeObject Box(object? value)=>new(OwnHost.Add(new OwnHost.Record((T)value!)));
    }
    internal sealed class Reference:IElementCodec
    {
        public ulong NativeClass()=>4;
        public object? Read(RuntimeObject owned)=>owned.Token==0?null:new Il2CppSystem.Object(owned.Detach());
        public RuntimeObject Box(object? value)=>value==null?new(0):FacadeRuntime.Retain((RuntimeObject)value);
    }
    internal static class ElementCodecs
    {
        private static readonly Dictionary<Type,IElementCodec> codecs=new(){{typeof(int),new Primitive<int>(1)},{typeof(byte),new Primitive<byte>(2)},{typeof(float),new Primitive<float>(3)},{typeof(Il2CppSystem.Object),new Reference()}};
        internal static IElementCodec Get<T>()=>codecs[typeof(T)];
    }
    internal static class LiveReflection{internal static ulong MakeGenericClass(ulong owner,ReadOnlySpan<ulong> arguments)=>100+arguments[0];}
    internal static class NativeMethods{internal static ulong Lookup(ulong owner,string name,ReadOnlySpan<ulong> arguments,ulong returns,bool isStatic)=>owner;}
    internal static unsafe class FacadeRuntime
    {
        internal static void Require(int status,string operation){if(status!=0)throw new RuntimeGatewayException(status,operation);}
        internal static void CheckManaged(int status,ulong exception,string operation){if(exception!=0)throw new NativeGameException();Require(status,operation);}
        internal static ulong Class(string image,string space,string name)=>1;
        internal static RuntimeObject RetainToken(ulong borrowed)=>borrowed==0?new(0):new(OwnHost.Add(OwnHost.Roots[borrowed]));
        internal static RuntimeObject Retain(RuntimeObject borrowed)=>RetainToken(borrowed.Token);
        internal static void Release(ulong root){if(root!=0)OwnHost.Roots.Remove(root);}
        internal static bool TokenIsValid(ulong root)=>OwnHost.Roots.ContainsKey(root);
        internal static NativeArgument Reference(RuntimeObject? value)=>new(){Kind=1,Token=value?.Token??0};
        internal static RuntimeObject InvokeResolved(ulong method,ulong self,NativeArgument* arguments,nuint count){OwnHost.Invoke(self,arguments->Token);return new(0);}
        internal static RuntimeObject Invoke(BindingSpec spec,ulong self,NativeArgument* arguments,nuint count)=>throw new NotSupportedException("native Combine belongs to actual runtime proof");
    }
}
namespace Il2CppSystem{public class Object:EHR.Generated.RuntimeObject{internal Object(ulong owned):base(owned){}}}
