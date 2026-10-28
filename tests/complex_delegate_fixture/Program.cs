// Original host-only fixture executing the production C# typed callback path
// in NativeAOT. No game metadata, object layout or IL2CPP execution is claimed.
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
internal static unsafe class OwnHost
{
    internal sealed class Record(object? value){internal object? Value=value;internal ulong Source;internal uint ABI;internal int Status;internal bool Closed;}
    internal static readonly Dictionary<ulong,Record> Roots=new(),Entries=new();
    internal static TypedActionCallbacksV1 Callbacks=default;
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
        ComplexDelegateHostV1 host=new(){AbiVersion=1,ByteSize=(uint)sizeof(ComplexDelegateHostV1),Create=&ComplexHost.Create,Close=&ComplexHost.Close,Status=&OwnHost.Status,IsMain=&OwnHost.IsMain};
        ComplexDelegateCallbacksV1 callbacks=default;delegate* unmanaged[Cdecl]<ComplexDelegateHostV1*,nuint,ComplexDelegateCallbacksV1*,nuint,int> bind=&ComplexDelegateRuntime.Bind;
        bool bound=bind(&host,(nuint)sizeof(ComplexDelegateHostV1),&callbacks,(nuint)sizeof(ComplexDelegateCallbacksV1))==0;ComplexHost.Callbacks=callbacks;
        bool triple=false;var action=new Il2CppSystem.Action<string,int,OwnEnum>((text,value,kind)=>triple=text=="own"&&value==-77&&kind==OwnEnum.One);
        using var text=new RuntimeObject(OwnHost.Add(new OwnHost.Record("own")));using var kind=new RuntimeObject(OwnHost.Add(new OwnHost.Record(OwnEnum.One)));
        bool invoked=callbacks.Action3(ComplexHost.Source(action.Token),text.Token,-77,kind.Token)==0&&triple;
        using var function=new Il2CppSystem.Func<Il2CppSystem.Object?,bool>(value=>{bool found=value!=null;value?.Dispose();return found;});
        using var original=new Il2CppSystem.Object(OwnHost.Add(new OwnHost.Record(new object())));byte result=0;
        bool bools=callbacks.Function(ComplexHost.Source(function.Token),original.Token,&result)==0&&result==1&&callbacks.Function(ComplexHost.Source(function.Token),0,&result)==0&&result==0;
        using var error=new Il2CppSystem.Func<Il2CppSystem.Object?,bool>(static _=>throw new InvalidOperationException("own"));result=1;
        bool contained=callbacks.Function(ComplexHost.Source(error.Token),0,&result)==6&&result==0;
        UnityEngine_SceneManagement_Scene escaped=default;int mode=0;
        using var scene=new UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,OwnEnum>((value,kind)=>{escaped=value;mode=(int)kind;});
        using var payload=new RuntimeObject(OwnHost.Add(new OwnHost.Record(42)));
        bool sceneCalled=callbacks.Scene2(ComplexHost.Source(scene.Token),payload.Token,kind.Token)==0;
        payload.Dispose();bool escapedOwns=sceneCalled&&FacadeRuntime.TokenIsValid(escaped.NativeBox.Token)&&(int)OwnHost.Roots[escaped.NativeBox.Token].Value! ==42&&mode==1;
        escaped.NativeBox.Dispose();
        var order=new List<int>();using(var scope=new NativeCallbackScope()){scope.Own(()=>order.Add(1),()=>order.Add(3));scope.Own(()=>order.Add(2),()=>order.Add(4));scope.Dispose();scope.Dispose();}
        bool scopeOrder=order.SequenceEqual(new[]{2,1,4,3});int cleanup=0;bool failed=false;var badScope=new NativeCallbackScope();badScope.Own(()=>throw new InvalidOperationException("own"),()=>++cleanup);badScope.Own(()=>++cleanup,()=>++cleanup);try{badScope.Dispose();}catch(InvalidOperationException){failed=true;}badScope.Dispose();bool cleanupAll=failed&&cleanup==3;
        action.Close();function.Close();error.Close();scene.Close();bool forgotten=ComplexDelegateRuntime.SourceCount==0;
        action.Dispose();function.Dispose();error.Dispose();scene.Dispose();text.Dispose();kind.Dispose();original.Dispose();
        bool success=bound&&invoked&&bools&&contained&&escapedOwns&&scopeOrder&&cleanupAll&&forgotten&&OwnHost.Roots.Count==0;
        Console.WriteLine($"{{\"success\":{success.ToString().ToLowerInvariant()},\"action3Exact\":{invoked.ToString().ToLowerInvariant()},\"boolTrueFalse\":{bools.ToString().ToLowerInvariant()},\"exceptionContained\":{contained.ToString().ToLowerInvariant()},\"sceneValueEscapesOwned\":{escapedOwns.ToString().ToLowerInvariant()},\"scopeUnsubscribeThenClose\":{scopeOrder.ToString().ToLowerInvariant()},\"scopeContinuesAfterFailure\":{cleanupAll.ToString().ToLowerInvariant()},\"sourceEntriesAfter\":{ComplexDelegateRuntime.SourceCount},\"scope\":\"production complex CSharp callbacks in original simulated host\"}}");return success?0:1;

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
        private static readonly Dictionary<Type,IElementCodec> codecs=new(){{typeof(int),new Primitive<int>(1)},{typeof(byte),new Primitive<byte>(2)},{typeof(float),new Primitive<float>(3)},{typeof(Il2CppSystem.Object),new Reference()},{typeof(string),new Primitive<string>(4)},{typeof(bool),new Primitive<bool>(5)},{typeof(OwnEnum),new Primitive<OwnEnum>(6)},{typeof(UnityEngine_SceneManagement_Scene),new SceneCodec()}};
        internal static IElementCodec Get<T>()=>codecs[typeof(T)];
    }
    internal static class LiveReflection{internal static ulong MakeGenericClass(ulong owner,ReadOnlySpan<ulong> arguments)=>100+arguments[0];}
    internal static class NativeMethods{internal static ulong Lookup(ulong owner,string name,ReadOnlySpan<ulong> arguments,ulong returns,bool isStatic)=>owner;}
    internal static unsafe class FacadeRuntime
    {
        internal static void Require(int status,string operation){if(status!=0)throw new RuntimeGatewayException(status,operation);}
        internal static void CheckManaged(int status,ulong exception,string operation){if(exception!=0)throw new NativeGameException();Require(status,operation);}
        internal static ulong Class(string image,string space,string name)=>1;
        internal static ulong ObjectClass(RuntimeObject value)=>1;
        internal static T ReadValue<T>(RuntimeObject value)=>(T)OwnHost.Roots[value.Token].Value!;
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

internal enum OwnEnum:int{One=1}
internal static unsafe class ComplexHost
{
 internal static ComplexDelegateCallbacksV1 Callbacks;
 internal static ulong Source(ulong root)=>OwnHost.Roots[root].Source;
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
 internal static int Create(ulong source,uint family,ulong* types,nuint count,ulong* root,ulong* registration,ulong* exception)
 {
  *root=*registration=*exception=0;if(!OwnHost.MainThread)return 2;
  var pair=OwnHost.Entries.FirstOrDefault(p=>p.Value.Source==source&&!p.Value.Closed);
  if(pair.Value!=null){*root=OwnHost.Add(pair.Value);*registration=pair.Key;return 0;}
  var value=new OwnHost.Record(null){Source=source,ABI=family+10};ulong id=OwnHost.Next++;OwnHost.Entries.Add(id,value);*root=OwnHost.Add(value);*registration=id;return 0;
 }
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
 internal static int Close(ulong registration){if(!OwnHost.Entries.TryGetValue(registration,out var v))return 9;if(v.Closed)return 0;v.Closed=true;return Callbacks.Forget(v.Source);}
}
namespace EHR.Generated
{
 internal static class ActionRuntime{internal static void RequireMain(){if(!OwnHost.MainThread)throw new RuntimeGatewayException(2,"main");}}
 public struct UnityEngine_SceneManagement_Scene
 {
  private RuntimeObject? box;internal UnityEngine_SceneManagement_Scene(RuntimeObject owned){box=owned;}public RuntimeObject NativeBox=>box!;
 }
 internal sealed class SceneCodec:IElementCodec
 {
  public ulong NativeClass()=>7;public object Read(RuntimeObject owned)=>new UnityEngine_SceneManagement_Scene(owned);
  public RuntimeObject Box(object? value)=>FacadeRuntime.Retain(((UnityEngine_SceneManagement_Scene)value!).NativeBox);
 }
}
