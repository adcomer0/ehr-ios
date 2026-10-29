// Own simulated host executes the production NativeAOT dispatcher/fixture code.
// No game objects, framework, metadata, methods or layout claims.
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR;
using EHR.Generated;
internal static unsafe class OwnHost
{
 internal static readonly Dictionary<ulong,object> Roots=new();internal static ulong Next=1;internal static uint Calls;internal static bool EndFailure,NativeFailure;internal static Action? Reentrant;
 internal static ulong Root(object value){ulong id=Next++;Roots.Add(id,value);return id;}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int Register(ulong id,ulong method,ulong rva)=>id==method&&id is 1 or 2&&rva==id?0:5;
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int Begin(ulong id,ulong method,ulong* result){*result=id;return id==method?0:5;}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int Invoke(ulong invocation,ulong target,ulong method,ulong receiver,NativeArgument* args,nuint count,ByRefOutput* refs,nuint refCount,ulong* result,ulong* exception,OriginalProof* proof,nuint bytes)
 {*result=*exception=0;*proof=new(){AbiVersion=1,ByteSize=24,RequestAccepted=1,RuntimeEntered=1,PermitConsumed=1,HookConsumptions=1};++Calls;var action=Reentrant;Reentrant=null;action?.Invoke();if(NativeFailure){*exception=Root(new object());return 6;}*result=Root(target==1?(object)10:false);return 0;}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int End(ulong invocation)=>EndFailure?4:0;
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int IsValue(ulong klass,int* result){*result=1;return 0;}
}
internal static unsafe class Program
{
 static int diagnosticChecks;
 static void Check(bool value){diagnosticChecks++;if(!value)throw new Exception("own numeric failure check "+diagnosticChecks);}
 static void Origin(EHRPatchFailureStage stage,uint callback,uint kind,uint original,int status=6)
 {
  delegate* unmanaged<ulong,uint*,nuint,int> copy=&NativePatchRuntime.CopyFailure;
  uint* words=stackalloc uint[12];Check(copy(1,words,12)==0);
  Check(words[0]==1&&words[1]==12&&words[2]!=0&&words[4]==1&&words[5]==0);
  Check(words[6]==(uint)stage&&words[7]==callback&&words[8]==0&&words[9]==kind&&words[10]==(uint)status&&words[11]==original);
 }
 static EHRStaticPatchDescriptor Callback(EHRStaticPatchKind kind,int index,Action<EHRStaticPatchFrame> action)
  =>new("own."+index,"own","own.fixture",kind,400,index,false,true,[],[],[],action,null);
 static void Configure(params EHRStaticPatchDescriptor[] callbacks)
  =>NativePatchRuntime.Configure([new(1,"own.origin",new("Assembly-CSharp.dll","","Constants","GetBroadcastVersion",true,false,"System.Int32",[]),null,[],[],[],[],typeof(int),1,new("own.origin",callbacks))]);
 static void Nested()
 {
  Configure(Callback(EHRStaticPatchKind.Postfix,88,_=>throw new InvalidCastException()));
  delegate* unmanaged<ulong,ulong,ulong*,nuint,ulong*,ulong*,ulong*,nuint,NativePatchDispatchProofV2*,nuint,int> dispatch=&NativePatchRuntime.DispatchV2;
  ulong result=0,error=0;NativePatchDispatchProofV2 proof=default;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&proof,32)==6);
  Origin(EHRPatchFailureStage.Postfix,89,3,1);
 }
 static int Main()
 {
  NativePatchHostTable table=new(){AbiVersion=1,ByteSize=48,Register=&OwnHost.Register,Begin=&OwnHost.Begin,Invoke=&OwnHost.Invoke,End=&OwnHost.End,ClassIsValue=&OwnHost.IsValue};
  delegate* unmanaged<NativePatchHostTable*,nuint,int> bind=&NativePatchRuntime.Bind;
  delegate* unmanaged<ulong,ulong,int> setup=&NativePatchFixture.Setup;
  delegate* unmanaged<ulong,ulong,uint,int> failureSetup=&NativePatchFixture.FailureSetup;
  delegate* unmanaged<ulong,ulong,ulong*,nuint,ulong*,ulong*,ulong*,nuint,NativePatchDispatchProofV2*,nuint,int> dispatch=&NativePatchRuntime.DispatchV2;
  bool ready=bind(&table,48)==0&&setup(1,2)==0;ulong result=0,error=0;NativePatchDispatchProofV2 p=default;
  int status=dispatch(1,0,null,0,&result,&error,null,0,&p,32);bool version=status==0&&p.AbiVersion==2&&p.ByteSize==32&&p.TargetFound==1&&p.DispatcherEntered==1&&p.OriginalAttempted==1&&p.RuntimeEntered==1&&p.PermitConsumed==1&&p.HookConsumptions==1&&(int)OwnHost.Roots[result]==17&&OwnHost.Calls==1;FacadeRuntime.Release(result);
  status=dispatch(2,0,null,0,&result,&error,null,0,&p,32);bool skipped=status==0&&p.OriginalAttempted==0&&p.RuntimeEntered==0&&p.HookConsumptions==0&&(bool)OwnHost.Roots[result]&&OwnHost.Calls==1;FacadeRuntime.Release(result);
  failureSetup(1,2,1);status=dispatch(1,0,null,0,&result,&error,null,0,&p,32);bool prefix=status==6&&p.DispatcherEntered==1&&p.OriginalAttempted==0&&p.RuntimeEntered==0&&OwnHost.Calls==1&&result==0&&error==0;
  Origin(EHRPatchFailureStage.Prefix,3,6,0);
  failureSetup(1,2,2);status=dispatch(1,0,null,0,&result,&error,null,0,&p,32);bool postfix=status==6&&p.DispatcherEntered==1&&p.OriginalAttempted==1&&p.RuntimeEntered==1&&p.HookConsumptions==1&&OwnHost.Calls==2&&result==0&&error==0;
  Origin(EHRPatchFailureStage.Postfix,1,6,1);
  setup(1,2);OwnHost.EndFailure=true;status=dispatch(1,0,null,0,&result,&error,null,0,&p,32);OwnHost.EndFailure=false;
  bool cleanup=status==4&&p.OriginalAttempted==1&&p.RuntimeEntered==1&&p.PermitConsumed==1&&p.HookConsumptions==1&&OwnHost.Calls==3&&result==0&&error==0;
  Origin(EHRPatchFailureStage.Original,0,2,1,4);
  byte* bytes=stackalloc byte[80];new Span<byte>(bytes,80).Fill(0x5a);ulong sentinel=0x11223344;
  status=dispatch(1,0,null,0,(ulong*)(bytes+8),&sentinel,null,0,(NativePatchDispatchProofV2*)(bytes+4),32);
  bool alias=status==4&&sentinel==0x11223344;for(int i=0;i<80;++i)alias&=bytes[i]==0x5a;
  status=dispatch(ulong.MaxValue,0,null,0,&result,&error,null,0,(NativePatchDispatchProofV2*)(bytes+4),32);
  bool four=status==3&&((NativePatchDispatchProofV2*)(bytes+4))->AbiVersion==2&&((NativePatchDispatchProofV2*)(bytes+4))->TargetFound==0&&result==0&&error==0;
  // Exact public GameStart callback ordinals, with own throw actions only.
  foreach(int ordinal in new[]{87,88,131})
  {
   EHRStaticPatchKind kind=ordinal==87?EHRStaticPatchKind.Prefix:EHRStaticPatchKind.Postfix;
   Configure(Callback(kind,ordinal,_=>throw new NativeGameException()));
   Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);
   Origin(kind==EHRStaticPatchKind.Prefix?EHRPatchFailureStage.Prefix:EHRPatchFailureStage.Postfix,(uint)ordinal+1,1,ordinal==87?0u:1u);
  }
  Configure();OwnHost.NativeFailure=true;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);OwnHost.NativeFailure=false;
  Origin(EHRPatchFailureStage.Original,0,1,1);
  // An exception-path finalizer throw must not relabel a surviving original.
  Configure(Callback(EHRStaticPatchKind.Finalizer,20,_=>throw new InvalidOperationException()));OwnHost.NativeFailure=true;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);OwnHost.NativeFailure=false;
  Origin(EHRPatchFailureStage.Original,0,1,1);
  // A finalizer that explicitly replaces the surviving exception owns origin.
  Configure(Callback(EHRStaticPatchKind.Finalizer,21,f=>f.Exception=new ArgumentException()));OwnHost.NativeFailure=true;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);OwnHost.NativeFailure=false;
  Origin(EHRPatchFailureStage.Finalizer,22,4,1);
  Configure(Callback(EHRStaticPatchKind.Postfix,131,_=>throw new NativeGameException()));OwnHost.Reentrant=Nested;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);
  Origin(EHRPatchFailureStage.Postfix,132,1,1); // outer publication follows nested work
  Configure();FacadeRuntime.BoxFailure=true;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);FacadeRuntime.BoxFailure=false;
  Origin(EHRPatchFailureStage.ResultBox,0,6,1);
  Configure(Callback(EHRStaticPatchKind.Postfix,131,_=>throw new NativeGameException()));FacadeRuntime.ExportFailure=true;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==6);FacadeRuntime.ExportFailure=false;
  Origin(EHRPatchFailureStage.NativeExceptionExport,0,6,1);
  delegate* unmanaged<ulong,uint*,nuint,int> copy=&NativePatchRuntime.CopyFailure;
  uint* snapshot=stackalloc uint[12];Check(copy(1,snapshot,12)==0);uint sequence=snapshot[2];
  Check(copy(2,snapshot,12)==3&&new ReadOnlySpan<uint>(snapshot,12).IndexOfAnyExcept(0u)==-1);
  Check(copy(1,snapshot,12)==0&&snapshot[2]==sequence); // read-only, not consumed
  new Span<uint>(snapshot,12).Fill(0x12345678);Check(copy(1,snapshot,11)==4&&snapshot[0]==0x12345678);
  Check(copy(1,(uint*)((byte*)snapshot+1),12)==4&&snapshot[0]==0x12345678);
  Check(dispatch(1,0,null,0,&result,&error,null,0,null,32)==4);
  Check(copy(1,snapshot,12)==3); // reject a stale failure after a new invalid call
  // A suppressed failure produces success and no failing-dispatch record.
  Configure(Callback(EHRStaticPatchKind.Finalizer,22,f=>f.Exception=null));OwnHost.NativeFailure=true;
  Check(dispatch(1,0,null,0,&result,&error,null,0,&p,32)==0);OwnHost.NativeFailure=false;
  FacadeRuntime.Release(result);Check(copy(1,snapshot,12)==3);
  bool success=ready&&version&&skipped&&prefix&&postfix&&cleanup&&alias&&four&&OwnHost.Roots.Count==0;
  Console.WriteLine("{\"managedFailureOriginChecks\":"+diagnosticChecks+",\"gameInvoked\":false}");
  Console.WriteLine($"{{\"success\":{success.ToString().ToLowerInvariant()},\"oneOriginal\":{version.ToString().ToLowerInvariant()},\"skippingPrefix\":{skipped.ToString().ToLowerInvariant()},\"prefixFailureProof\":{prefix.ToString().ToLowerInvariant()},\"postfixFailureProof\":{postfix.ToString().ToLowerInvariant()},\"cleanupFailurePreservesProof\":{cleanup.ToString().ToLowerInvariant()},\"overlapLeavesOutputsUntouched\":{alias.ToString().ToLowerInvariant()},\"fourByteProofAlignment\":{four.ToString().ToLowerInvariant()},\"ownedRootsAfter\":{OwnHost.Roots.Count},\"scope\":\"production NativeAOT patch dispatcher with own simulated host\"}}");return success?0:1;
 }
}
namespace EHR.Generated
{
 public class RuntimeGatewayException(int status,string operation):Exception(operation){public int Status{get;}=status;}
 public sealed class NativeGameException():RuntimeGatewayException(6,"own native failure"),IDisposable{internal static NativeGameException FromBorrowed(ulong token,string operation)=>new();internal RuntimeObject RetainNativeException()=>FacadeRuntime.ExportFailure?throw new InvalidOperationException():new(0);public void Dispose(){}}
 public sealed class RuntimeObject(ulong token):IDisposable{internal ulong Token=token;internal ulong Detach(){ulong value=Token;Token=0;return value;}public void Dispose(){FacadeRuntime.Release(Token);Token=0;}}
 internal sealed record BindingSpec(string Image,string Namespace,string Type,string Member,bool IsStatic,bool IsField,string ResultType,string[] Parameters);
 [StructLayout(LayoutKind.Sequential)]internal unsafe struct NativeArgument{internal uint Kind,Reserved;internal ulong Token;internal void* Bytes;internal nuint ByteCount;}
 [StructLayout(LayoutKind.Sequential)]internal unsafe struct ByRefOutput{internal uint ArgumentIndex,Reserved;internal ulong ValueClass;internal void* Bytes;internal nuint ByteCount;}
 [StructLayout(LayoutKind.Sequential)]internal struct OriginalProof{internal uint AbiVersion,ByteSize,RequestAccepted,RuntimeEntered,PermitConsumed,HookConsumptions;}
 internal interface IElementCodec{ulong NativeClass();RuntimeObject Box(object? value);object? Read(RuntimeObject owned);}
 internal sealed class OwnCodec(ulong klass):IElementCodec
 {public ulong NativeClass()=>klass;public RuntimeObject Box(object? value)=>FacadeRuntime.BoxFailure?throw new InvalidOperationException():new(OwnHost.Root(value!));public object Read(RuntimeObject owned){using(owned)return OwnHost.Roots[owned.Token];}}
 internal static class ElementCodecs{internal static IElementCodec Get(Type type)=>new OwnCodec(type==typeof(bool)?2u:1u);}
 internal static class FacadeRuntime
 {
  internal static bool BoxFailure,ExportFailure;
  internal static void RequireReady(){}internal static void Require(int status,string operation){if(status!=0)throw new RuntimeGatewayException(status,operation);}
  internal static ulong Resolve(BindingSpec spec)=>spec.Member=="IsVersionModded"?2u:1u;
  internal static int RawValueSize(ulong klass)=>klass==2?1:4;
  internal static RuntimeObject BoxRawValue(ulong klass,ReadOnlySpan<byte> bytes)=>new(OwnHost.Root(klass==2?(object)(bytes[0]!=0):BitConverter.ToInt32(bytes)));
  internal static void CopyRawValue(RuntimeObject value,Span<byte> target)=>throw new NotSupportedException("own no-ref fixture");
  internal static RuntimeObject Retain(RuntimeObject value)=>RetainToken(value.Token);
  internal static RuntimeObject RetainToken(ulong token)=>new(token==0?0:OwnHost.Root(OwnHost.Roots[token]));
  internal static void Release(ulong token){if(token!=0)OwnHost.Roots.Remove(token);}
 }
}
