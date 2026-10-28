using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class SourceComponentFacadeSelfTest
{
 internal static int Unsubscribed,Closed;
 private static EHR.NativeProbes.StaticLifecycleProbe? retainedDestroyed;
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_source_component_facade_create")]
 internal static int Create(ulong owner,ulong* coroutines,ulong* probe,uint* flags)
 {
  if(coroutines==null||probe==null||flags==null||coroutines==probe)return 4;*coroutines=0;*probe=0;*flags=0;
  try{SourceComponentRuntime.Ready();using var root=FacadeRuntime.RetainToken(owner);using var game=new UnityEngine_GameObject(root.Detach());
   var a=game.AddComponent<EHR.Coroutines>();var b=game.AddComponent<EHR.NativeProbes.StaticLifecycleProbe>();
   if(a==null||b==null)return 5;retainedDestroyed=b;
   if(ReferenceEquals(a,game.GetComponent<EHR.Coroutines>()))*flags|=1;
   if(ReferenceEquals(b,game.GetComponent<EHR.NativeProbes.StaticLifecycleProbe>()))*flags|=2;
   if(ReferenceEquals(b,b.TryCast<EHR.NativeProbes.StaticLifecycleProbe>()))*flags|=4;
   SourceComponentRuntime.ScopeFor(b).Own(()=>++Unsubscribed,()=>++Closed);*flags|=8;
   using var ownedA=FacadeRuntime.Retain(a);using var ownedB=FacadeRuntime.Retain(b);
   *coroutines=ownedA.Detach();*probe=ownedB.Detach();return *flags==15?0:5;}
  catch(RuntimeGatewayException error){if(error is NativeGameException native)native.Dispose();return error.Status;}catch{return 6;}
 }
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_source_tombstone_proof")]
 internal static int Tombstone(int* output,nuint count)
 {
  if(output==null||count!=3)return 4;for(int i=0;i<3;++i)output[i]=0;
  try{SourceComponentRuntime.Ready();var source=retainedDestroyed;if(source is null)return 9;
   output[0]=source.Token==0?1:0;output[1]=!((UnityEngine_Object)source)?1:0;output[2]=source.Initialized==37?1:0;
   return output[0]==1&&output[1]==1&&output[2]==1?0:5;}
  catch(RuntimeGatewayException error){if(error is NativeGameException native)native.Dispose();return error.Status;}catch{return 6;}
  finally{retainedDestroyed=null;}
 }
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_source_component_scope_proof")]
 internal static int ScopeProof(int* output,nuint count)
 {
  if(output==null||count!=2)return 4;output[0]=Unsubscribed;output[1]=Closed;return Unsubscribed==1&&Closed==1?0:5;
 }
}
