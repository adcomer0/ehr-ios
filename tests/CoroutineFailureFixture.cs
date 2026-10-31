// Owned facades/host only. Compile the unchanged production coroutine source;
// real callbacks are captured from its real registration table, not reflection.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
namespace EHR.Generated {
 internal class RuntimeGatewayException(int status,string operation):Exception(operation){internal int Status=>status;}
 internal sealed class NativeGameException():RuntimeGatewayException(6,"OWN-NATIVE-FAILURE"),IDisposable {internal static int Disposals;public void Dispose()=>++Disposals;internal RuntimeObject RetainNativeException()=>new(1);}
 public class RuntimeObject(ulong token):IDisposable {internal ulong Token=>token;internal ulong Detach()=>token;public void Dispose(){}}
 internal interface INativeValue {RuntimeObject NativeBox{get;}}
 internal sealed record BindingSpec(string Image,string Namespace,string Type,string Member,bool IsStatic,bool IsField,string ResultType,string[] Parameters);
 internal struct NativeArgument {internal ulong Token;}
 internal static class NativeLifetime {internal static bool Same(RuntimeObject a,RuntimeObject b)=>a.Token==b.Token;}
 internal static unsafe class FacadeRuntime {
  internal static bool IsReady=true;
  internal static void RequireReady(){if(!IsReady)throw new RuntimeGatewayException(1,"OWN-NOT-READY");}
  internal static void Require(int status,string operation){if(status!=0)throw new RuntimeGatewayException(status,operation);}
  internal static ulong Class(string a,string b,string c)=>1;
  internal static ulong ObjectClass(RuntimeObject value)=>1;
  internal static RuntimeObject Invoke(BindingSpec spec,ulong owner,NativeArgument* args,nuint count)=>new(2);
  internal static NativeArgument Reference(RuntimeObject value)=>new(){Token=value.Token};
  internal static RuntimeObject Retain(RuntimeObject value)=>new(value.Token);
  internal static RuntimeObject String(string text)=>new(3);
  internal static string ReadString(RuntimeObject value)=>"OWN";
  internal static T ReadValue<T>(RuntimeObject value)=>default!;
  internal static void Release(ulong token){}
 }
 internal static class LiveReflection {internal static RuntimeObject Construct(ulong klass,NativeArgument[] args)=>new(1);}
 internal sealed class OwnCodec {internal RuntimeObject Box(object value)=>new(4);}
 internal static class ElementCodecs {internal static OwnCodec Get(Type type)=>new();}
}
namespace Il2CppSystem.Collections {public class IEnumerator(ulong token):RuntimeObject(token){public RuntimeObject? Current=>null;public bool MoveNext()=>false;public void Reset(){}}}

namespace EHR.OwnCoroutineFailure {
 internal sealed class FaultSource(int fault,bool cleanupFault=false):IEnumerator,IDisposable {
  internal int Disposed;
  public bool MoveNext(){if(fault==1)throw new NullReferenceException("OWN-PRIVATE-CANARY");if(fault==4)throw new NativeGameException();return fault!=3;}
  public object? Current=>fault==2?throw new InvalidOperationException("OWN-CURRENT"):fault==5?new object():null;
  public void Reset()=>throw new NotSupportedException();
  public void Dispose(){++Disposed;if(cleanupFault)throw new ArgumentException("OWN-CLEANUP");if(fault==3)throw new IndexOutOfRangeException("OWN-FINISH");}
 }
 internal sealed class ParentSource:IEnumerator,IDisposable {
  internal int Steps,Disposed;private readonly FaultSource child=new(0,true);
  public bool MoveNext()=>++Steps==1;public object Current=>child;public void Reset()=>throw new NotSupportedException();public void Dispose()=>++Disposed;
 }
 internal static unsafe class Program {
  private static int checks;private static bool main=true;private static ulong lastSource,lastRegistration,next,capturedTypeHash;
  private static readonly Dictionary<ulong,(ulong Source,ProductionIteratorCallbacksV1 Callbacks)> calls=new();
  private static void Check(bool okay){++checks;if(!okay)throw new Exception("Owned coroutine diagnostic check failed");}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Register(ulong carrier,ulong source,ProductionIteratorCallbacksV1* callbacks,ulong* registration){lastSource=source;lastRegistration=++next;calls.Add(lastRegistration,(source,*callbacks));*registration=lastRegistration;return 0;}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Acquire(ulong registration,ulong* root){*root=2;return 0;}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Close(ulong registration){if(!calls.Remove(registration,out var item))return 0;return item.Callbacks.Cancel(item.Source);}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Associate(ulong r,ulong o,ulong c)=>0;
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int CloseMatching(uint k,ulong o,uint* n){*n=0;return 0;}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Sweep(uint m,uint* s,uint* p){*s=*p=0;return 0;}
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int IsMain()=>main?1:0;
  [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]private static int Status(void* value,nuint size)=>0;
  private static int Step(){var item=calls[lastRegistration];int moved=99;ulong current=99;int status=item.Callbacks.Step(item.Source,&moved,&current);Check(moved==0&&current==0);return status;}
  private static int Copy(ulong source,ulong* words)=>((delegate* unmanaged[Cdecl]<ulong,ulong*,nuint,int>)&ProductionCoroutines.CopyFailure)(source,words,12);
  private static void Retire(){Check(((delegate* unmanaged[Cdecl]<ulong,int>)&Close)(lastRegistration)==0);}
  private static void Failure(int fault,ulong phase,ulong kind,int expected,bool cleanup=false){
   int returned=cleanup?6:expected;
   var source=new FaultSource(fault,cleanup);using var carrier=ProductionCoroutines.Wrap(source);ulong id=lastSource;Check(Step()==returned);ulong* words=stackalloc ulong[12];Check(Copy(id,words)==0);
   Check(words[0]==1&&words[1]==12&&words[2]==id&&words[3]!=0);if(capturedTypeHash==0)capturedTypeHash=words[3];Check(words[3]==capturedTypeHash);Check(words[4]==phase&&words[5]==kind&&words[6]==(ulong)expected&&words[7]==(ulong)returned&&words[8]!=0&&words[11]==0);
   Check(words[9]==(cleanup?8UL:0)&&words[10]==(cleanup?6UL:0));Check(source.Disposed==1);
   for(int i=0;i<12;++i)words[i]=ulong.MaxValue;Check(Copy(id+999,words)==3);for(int i=0;i<12;++i)Check(words[i]==ulong.MaxValue);
   Retire();Check(Copy(id,words)==3);for(int i=0;i<12;++i)Check(words[i]==ulong.MaxValue);
  }
  internal static int Main(){
   ulong* words=stackalloc ulong[12];for(int i=0;i<12;++i)words[i]=ulong.MaxValue;Check(Copy(1,words)==1);
   ProductionIteratorHostV1 table=new(){Version=1,Size=72,Register=&Register,Acquire=&Acquire,Close=&Close,Associate=&Associate,CloseMatching=&CloseMatching,Sweep=&Sweep,IsMain=&IsMain,CopyStatus=&Status};
   Check(((delegate* unmanaged[Cdecl]<ProductionIteratorHostV1*,nuint,int>)&ProductionCoroutines.Bind)(&table,72)==0);
   Check(sizeof(ProductionIteratorHostV1)==72&&sizeof(ProductionIteratorCallbacksV1)==32);
   Check(((delegate* unmanaged[Cdecl]<ulong,ulong*,nuint,int>)&ProductionCoroutines.CopyFailure)(1,words,11)==4);Check(Copy(0,words)==4);Check(Copy(1,words)==3);
   Failure(1,3,3,6);Failure(2,4,9,6);Failure(3,6,4,6);Failure(4,3,1,6);Check(NativeGameException.Disposals==1);Failure(5,5,5,7);Failure(1,3,3,6,true);Failure(5,5,5,7,true);
   using(var carrier=ProductionCoroutines.Wrap(new FaultSource(1))){main=false;Check(Copy(lastSource,words)==2);main=true;FacadeRuntime.IsReady=false;Check(Step()==1);FacadeRuntime.IsReady=true;Check(Copy(lastSource,words)==0&&words[4]==1&&words[5]==2&&words[6]==1);Retire();}
   using(var carrier=ProductionCoroutines.Wrap(new FaultSource(0))){var item=calls[lastRegistration];int moved=0;ulong current=0;Check(item.Callbacks.Step(item.Source,&moved,&current)==0&&moved==1&&current==0);Check(Copy(lastSource,words)==3);Retire();}
   var parent=new ParentSource();using(var carrier=ProductionCoroutines.Wrap(parent)){ulong id=lastSource,registration=lastRegistration;var callback=calls[registration];int moved=0;ulong current=0;Check(callback.Callbacks.Step(id,&moved,&current)==0&&moved==1&&current!=0);Check(callback.Callbacks.Step(id,&moved,&current)==6&&moved==0&&current==0);Check(Copy(id,words)==0&&words[4]==2&&words[5]==2&&words[6]==6);Check(parent.Disposed==1);lastRegistration=registration;Retire();}
   using(var first=ProductionCoroutines.Wrap(new FaultSource(1))){ulong firstId=lastSource,firstRegistration=lastRegistration;Check(Step()==6);Check(Copy(firstId,words)==0);ulong sequence=words[8];using(var second=ProductionCoroutines.Wrap(new FaultSource(2))){Check(Step()==6);Check(Copy(lastSource,words)==0&&words[8]>sequence);for(int i=0;i<12;++i)words[i]=ulong.MaxValue;Check(Copy(firstId,words)==3);for(int i=0;i<12;++i)Check(words[i]==ulong.MaxValue);Retire();}lastRegistration=firstRegistration;Retire();}
   Check(ProductionCoroutines.ActiveSources==0&&calls.Count==0);
   Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{schema="ehr.coroutine-failure-owned-proof.v1",pass=true,checks,actualGameCalls=0,actualNetworkRequests=0,tableBytes=sizeof(ProductionIteratorHostV1),callbackBytes=sizeof(ProductionIteratorCallbacksV1),faultSourceType=typeof(FaultSource).FullName,faultSourceTypeHash=capturedTypeHash.ToString(System.Globalization.CultureInfo.InvariantCulture)}));return 0;
  }
 }
}
