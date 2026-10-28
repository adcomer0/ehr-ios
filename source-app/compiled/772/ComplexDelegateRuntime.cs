using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated
{
 [StructLayout(LayoutKind.Sequential)]internal unsafe struct ComplexDelegateHostV1
 {
  internal uint AbiVersion,ByteSize;
  internal delegate* unmanaged[Cdecl]<ulong,uint,ulong*,nuint,ulong*,ulong*,ulong*,int> Create;
  internal delegate* unmanaged[Cdecl]<ulong,int> Close;
  internal delegate* unmanaged[Cdecl]<ulong,int*,int> Status;
  internal delegate* unmanaged[Cdecl]<int> IsMain;
 }
 [StructLayout(LayoutKind.Sequential)]internal unsafe struct ComplexDelegateCallbacksV1
 {
  internal uint AbiVersion,ByteSize;
  internal delegate* unmanaged[Cdecl]<ulong,ulong,int,ulong,int> Action3;
  internal delegate* unmanaged[Cdecl]<ulong,ulong,byte*,int> Function;
  internal delegate* unmanaged[Cdecl]<ulong,ulong,ulong,int> Scene2;
  internal delegate* unmanaged[Cdecl]<ulong,int> Forget;
 }
 internal static unsafe class ComplexDelegateRuntime
 {
  private abstract class Entry(Delegate source)
  {
   internal Delegate Source{get;}=source;
   internal virtual void Action3(ulong first,int middle,ulong last)=>throw new RuntimeGatewayException(5,"wrong delegate family");
   internal virtual bool Function(ulong first)=>throw new RuntimeGatewayException(5,"wrong delegate family");
   internal virtual void Scene2(ulong first,ulong last)=>throw new RuntimeGatewayException(5,"wrong delegate family");
  }
  private sealed class Triple<T1,T2,T3>(System.Action<T1,T2,T3> source):Entry(source)
  {internal override void Action3(ulong first,int middle,ulong last)=>source((T1)Read<T1>(first)!,(T2)(object)middle,(T3)Read<T3>(last)!);}
  private sealed class FunctionEntry<T,TResult>(System.Func<T,TResult> source):Entry(source)
  {internal override bool Function(ulong first)=>(bool)(object)source((T)Read<T>(first)!)!;}
  private sealed class SceneEntry<T1,T2>(System.Action<T1,T2> source):Entry(source)
  {internal override void Scene2(ulong first,ulong last)=>source((T1)Read<T1>(first)!,(T2)Read<T2>(last)!);}
  private static ComplexDelegateHostV1 host;private static bool bound;private static ulong next=0x434f4d5000000001;
  private static readonly Dictionary<ulong,Entry> sources=new();
  private static readonly Dictionary<(uint Family,Delegate Source),ulong> identities=new();
  private static readonly Dictionary<(uint,Type,Type,Type?),ulong> classes=new();
  internal static void RequireMain(){if(!bound)throw new RuntimeGatewayException(1,"complex native delegates unavailable");if(host.IsMain()!=1)throw new RuntimeGatewayException(2,"native delegates require Unity main thread");}
  internal static int SourceCount{get{RequireMain();return sources.Count;}}
  private static object? Read<T>(ulong borrowed)
  {
   // IElementCodec.Read CONSUMES its owned root. NativeValueCodec transfers
   // the RuntimeObject itself into the boxed-value facade, so do not dispose
   // that RuntimeObject after successful transfer or escaped structs go stale.
   var owned=borrowed==0?new RuntimeObject(0):FacadeRuntime.RetainToken(borrowed);
   try{return ElementCodecs.Get<T>().Read(owned);}catch{owned.Dispose();throw;}
  }
  private static bool Reference<T>()=>typeof(T)==typeof(string)||typeof(RuntimeObject).IsAssignableFrom(typeof(T));
  private static void Enum32<T>(){if(!typeof(T).IsEnum||Enum.GetUnderlyingType(typeof(T))!=typeof(int))throw new RuntimeGatewayException(7,"delegate requires Int32 enum");}
  private static ulong NativeClass(uint family,Type first,Type second,Type? third,ulong[] arguments)
  {
   RequireMain();var key=(family,first,second,third);if(classes.TryGetValue(key,out ulong found))return found;
   string image=family==3?"UnityEngine.CoreModule.dll":"mscorlib.dll",space=family==3?"UnityEngine.Events":"System",name=family==1?"Action`3":family==2?"Func`2":"UnityAction`2";
   found=LiveReflection.MakeGenericClass(FacadeRuntime.Class(image,space,name),arguments);classes.Add(key,found);return found;
  }
  internal static ulong TripleClass<T1,T2,T3>(){RequireMain();if(!Reference<T1>()||typeof(T2)!=typeof(int))throw new RuntimeGatewayException(7,"Action3 ABI unsupported");Enum32<T3>();return NativeClass(1,typeof(T1),typeof(T2),typeof(T3),[ElementCodecs.Get<T1>().NativeClass(),ElementCodecs.Get<T2>().NativeClass(),ElementCodecs.Get<T3>().NativeClass()]);}
  internal static ulong FunctionClass<T,TResult>(){RequireMain();if(!Reference<T>()||typeof(TResult)!=typeof(bool))throw new RuntimeGatewayException(7,"Func ABI unsupported");return NativeClass(2,typeof(T),typeof(TResult),null,[ElementCodecs.Get<T>().NativeClass(),ElementCodecs.Get<TResult>().NativeClass()]);}
  internal static ulong SceneClass<T1,T2>(){RequireMain();if(typeof(T1)!=typeof(UnityEngine_SceneManagement_Scene))throw new RuntimeGatewayException(7,"UnityAction2 ABI unsupported");Enum32<T2>();return NativeClass(3,typeof(T1),typeof(T2),null,[ElementCodecs.Get<T1>().NativeClass(),ElementCodecs.Get<T2>().NativeClass()]);}
  private static ActionCreation Create(uint family,Entry entry,ulong[] arguments)
  {
   RequireMain();var key=(family,entry.Source);bool reused=identities.TryGetValue(key,out ulong id);
   if(!reused){if(sources.Count>=256||next==ulong.MaxValue)throw new RuntimeGatewayException(8,"complex delegate limit");id=next++;sources.Add(id,entry);identities.Add(key,id);}
   ulong root=0,registration=0,exception=0;int status;fixed(ulong* types=arguments)status=host.Create(id,family,types,(nuint)arguments.Length,&root,&registration,&exception);
   if(status!=0||exception!=0||root==0||registration==0){if(!reused)ForgetIdentity(id);FacadeRuntime.Release(root);FacadeRuntime.CheckManaged(status==0?4:status,exception,"create native delegate");}
   sources[id]=entry;identities[key]=id;return new(root,registration);
  }
  internal static ActionCreation CreateTriple<T1,T2,T3>(System.Action<T1,T2,T3> source){ArgumentNullException.ThrowIfNull(source);TripleClass<T1,T2,T3>();return Create(1,new Triple<T1,T2,T3>(source),[ElementCodecs.Get<T1>().NativeClass(),ElementCodecs.Get<T2>().NativeClass(),ElementCodecs.Get<T3>().NativeClass()]);}
  internal static ActionCreation CreateFunction<T,TResult>(System.Func<T,TResult> source){ArgumentNullException.ThrowIfNull(source);FunctionClass<T,TResult>();return Create(2,new FunctionEntry<T,TResult>(source),[ElementCodecs.Get<T>().NativeClass(),ElementCodecs.Get<TResult>().NativeClass()]);}
  internal static ActionCreation CreateScene<T1,T2>(System.Action<T1,T2> source){ArgumentNullException.ThrowIfNull(source);SceneClass<T1,T2>();return Create(3,new SceneEntry<T1,T2>(source),[ElementCodecs.Get<T1>().NativeClass(),ElementCodecs.Get<T2>().NativeClass()]);}
  internal static void Close(ulong registration){RequireMain();FacadeRuntime.Require(host.Close(registration),"close native delegate");}
  internal static int Status(ulong registration){RequireMain();int status=0;FacadeRuntime.Require(host.Status(registration,&status),"native delegate callback status");return status;}
  internal static NativeArgument Argument<T>(RuntimeObject box)=>Reference<T>()?FacadeRuntime.Reference(box):new(){Kind=3,Token=box.Token};
  internal static void InvokeTriple<T1,T2,T3>(ulong token,T1 first,T2 middle,T3 last)
  {
   ulong klass=TripleClass<T1,T2,T3>();var c1=ElementCodecs.Get<T1>();var c2=ElementCodecs.Get<T2>();var c3=ElementCodecs.Get<T3>();
   ulong method=NativeMethods.Lookup(klass,"Invoke",[c1.NativeClass(),c2.NativeClass(),c3.NativeClass()],FacadeRuntime.Class("mscorlib.dll","System","Void"),false);
   using var a=c1.Box(first);using var b=c2.Box(middle);using var c=c3.Box(last);NativeArgument* args=stackalloc NativeArgument[3];args[0]=Argument<T1>(a);args[1]=Argument<T2>(b);args[2]=Argument<T3>(c);
   using var result=FacadeRuntime.InvokeResolved(method,token,args,3);
  }
  internal static TResult InvokeFunction<T,TResult>(ulong token,T first)
  {
   ulong klass=FunctionClass<T,TResult>();var codec=ElementCodecs.Get<T>();ulong method=NativeMethods.Lookup(klass,"Invoke",[codec.NativeClass()],FacadeRuntime.Class("mscorlib.dll","System","Boolean"),false);
   using var value=codec.Box(first);NativeArgument argument=Argument<T>(value);using var result=FacadeRuntime.InvokeResolved(method,token,&argument,1);return (TResult)(object)FacadeRuntime.ReadValue<bool>(result);
  }
  internal static void InvokeScene<T1,T2>(ulong token,T1 first,T2 second)
  {
   ulong klass=SceneClass<T1,T2>();var c1=ElementCodecs.Get<T1>();var c2=ElementCodecs.Get<T2>();ulong method=NativeMethods.Lookup(klass,"Invoke",[c1.NativeClass(),c2.NativeClass()],FacadeRuntime.Class("mscorlib.dll","System","Void"),false);
   using var a=c1.Box(first);using var b=c2.Box(second);NativeArgument* args=stackalloc NativeArgument[2];args[0]=Argument<T1>(a);args[1]=Argument<T2>(b);using var result=FacadeRuntime.InvokeResolved(method,token,args,2);
  }
  internal static RuntimeObject Combine(RuntimeObject? left,RuntimeObject? right,bool remove,ulong expectedClass)
  {RequireMain();var result=TypedActionRuntime.Combine(left,right,remove);if(result.Token!=0&&FacadeRuntime.ObjectClass(result)!=expectedClass){result.Dispose();throw new RuntimeGatewayException(5,"combined native delegate type");}return result;}
  [UnmanagedCallersOnly(EntryPoint="ehr_complex_delegate_bind_gateway",CallConvs=[typeof(CallConvCdecl)])]
  internal static int Bind(ComplexDelegateHostV1* source,nuint bytes,ComplexDelegateCallbacksV1* callbacks,nuint callbackBytes)
  {
   if(source==null||callbacks==null||bytes!=(nuint)sizeof(ComplexDelegateHostV1)||callbackBytes!=(nuint)sizeof(ComplexDelegateCallbacksV1)||source->AbiVersion!=1||source->ByteSize!=sizeof(ComplexDelegateHostV1)||source->Create==null||source->Close==null||source->Status==null||source->IsMain==null)return 4;
   if(source->IsMain()!=1)return 2;if(bound&&((nuint)host.Create!=(nuint)source->Create||(nuint)host.Close!=(nuint)source->Close||(nuint)host.Status!=(nuint)source->Status||(nuint)host.IsMain!=(nuint)source->IsMain))return 4;
   host=*source;bound=true;*callbacks=new(){AbiVersion=1,ByteSize=(uint)sizeof(ComplexDelegateCallbacksV1),Action3=&OnAction3,Function=&OnFunction,Scene2=&OnScene2,Forget=&Forget};return 0;
  }
  private static int Preflight(ulong id,out Entry? entry){entry=null;if(!bound)return 1;if(host.IsMain()!=1)return 2;return sources.TryGetValue(id,out entry)?0:9;}
  private static int Failure(Exception error){if(error is NativeGameException native){try{native.Dispose();}catch{}return 6;}return error is RuntimeGatewayException gateway?gateway.Status:6;}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int OnAction3(ulong id,ulong first,int value,ulong last){int s=Preflight(id,out var e);if(s!=0)return s;try{e!.Action3(first,value,last);return 0;}catch(Exception error){return Failure(error);}}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int OnFunction(ulong id,ulong first,byte* result){if(result==null)return 4;*result=0;int s=Preflight(id,out var e);if(s!=0)return s;try{*result=e!.Function(first)?(byte)1:(byte)0;return 0;}catch(Exception error){return Failure(error);}}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int OnScene2(ulong id,ulong first,ulong last){int s=Preflight(id,out var e);if(s!=0)return s;try{e!.Scene2(first,last);return 0;}catch(Exception error){return Failure(error);}}
  private static void ForgetIdentity(ulong id){if(sources.Remove(id,out Entry? e))for(uint family=1;family<=3;++family){var key=(family,e.Source);if(identities.TryGetValue(key,out ulong current)&&current==id)identities.Remove(key);}}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Forget(ulong id){if(!bound)return 1;if(host.IsMain()!=1)return 2;try{ForgetIdentity(id);return 0;}catch{return 4;}}
 }
 public sealed class UnityEngine_Events_UnityAction<T1,T2>:Il2CppSystem.Object
 {
  internal ulong Registration{get;}private bool closed;
  public UnityEngine_Events_UnityAction(System.Action<T1,T2> source):this(ComplexDelegateRuntime.CreateScene(source)){}
  internal UnityEngine_Events_UnityAction(ulong owned):base(owned){}
  private UnityEngine_Events_UnityAction(ActionCreation created):base(created.Root){Registration=created.Registration;}
  public void Invoke(T1 first,T2 second)=>ComplexDelegateRuntime.InvokeScene(Token,first,second);
  public void Close(){if(closed||Registration==0)return;ComplexDelegateRuntime.Close(Registration);closed=true;}
  public static implicit operator global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>?(System.Action<T1,T2>? source)=>source==null?null:new(source);
  public static global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>? operator +(global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>? left,global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>? right){using var result=ComplexDelegateRuntime.Combine(left,right,false,ComplexDelegateRuntime.SceneClass<T1,T2>());return result.Token==0?null:new(result.Detach());}
  public static global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>? operator -(global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>? left,global::EHR.Generated.UnityEngine_Events_UnityAction<T1,T2>? right){using var result=ComplexDelegateRuntime.Combine(left,right,true,ComplexDelegateRuntime.SceneClass<T1,T2>());return result.Token==0?null:new(result.Detach());}
 }
}
namespace Il2CppSystem
{
 public sealed class Action<T1,T2,T3>:Object
 {
  internal ulong Registration{get;}private bool closed;
  public Action(System.Action<T1,T2,T3> source):this(EHR.Generated.ComplexDelegateRuntime.CreateTriple(source)){}
  internal Action(ulong owned):base(owned){}
  private Action(EHR.Generated.ActionCreation created):base(created.Root){Registration=created.Registration;}
  public void Invoke(T1 first,T2 middle,T3 last)=>EHR.Generated.ComplexDelegateRuntime.InvokeTriple(Token,first,middle,last);
  public void Close(){if(closed||Registration==0)return;EHR.Generated.ComplexDelegateRuntime.Close(Registration);closed=true;}
  public static implicit operator Action<T1,T2,T3>?(System.Action<T1,T2,T3>? source)=>source==null?null:new(source);
  public static Action<T1,T2,T3>? operator +(Action<T1,T2,T3>? left,Action<T1,T2,T3>? right){using var result=EHR.Generated.ComplexDelegateRuntime.Combine(left,right,false,EHR.Generated.ComplexDelegateRuntime.TripleClass<T1,T2,T3>());return result.Token==0?null:new(result.Detach());}
  public static Action<T1,T2,T3>? operator -(Action<T1,T2,T3>? left,Action<T1,T2,T3>? right){using var result=EHR.Generated.ComplexDelegateRuntime.Combine(left,right,true,EHR.Generated.ComplexDelegateRuntime.TripleClass<T1,T2,T3>());return result.Token==0?null:new(result.Detach());}
 }
 public sealed class Func<T,TResult>:Object
 {
  internal ulong Registration{get;}private bool closed;
  public Func(System.Func<T,TResult> source):this(EHR.Generated.ComplexDelegateRuntime.CreateFunction(source)){}
  internal Func(ulong owned):base(owned){}
  private Func(EHR.Generated.ActionCreation created):base(created.Root){Registration=created.Registration;}
  public TResult Invoke(T first)=>EHR.Generated.ComplexDelegateRuntime.InvokeFunction<T,TResult>(Token,first);
  public void Close(){if(closed||Registration==0)return;EHR.Generated.ComplexDelegateRuntime.Close(Registration);closed=true;}
  public static implicit operator Func<T,TResult>?(System.Func<T,TResult>? source)=>source==null?null:new(source);
 }
}
