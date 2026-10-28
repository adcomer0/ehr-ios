using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)] internal struct SourceComponentManagedProof
{
 internal uint Version,Bytes;
 internal int Status,Pass,ActiveStates,Constructors,Awake,Updates,Destroyed,Ping,FieldInitializers,SameSourceIdentity,SourceCollected,Reserved;
}
internal static unsafe class SourceComponentSelfTest
{
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_source_component_proof")]
 internal static int Proof(ulong component,int phase,SourceComponentManagedProof* output,nuint bytes)
 {
  if(output==null||bytes!=(nuint)sizeof(SourceComponentManagedProof))return 4;
  *output=default;output->Version=1;output->Bytes=(uint)sizeof(SourceComponentManagedProof);
  try{SourceComponentRuntime.Ready();output->Reserved=(RuntimeFeature.IsDynamicCodeSupported||RuntimeFeature.IsDynamicCodeCompiled)?1:0;output->ActiveStates=SourceComponentRuntime.ActiveCount;
   using var owned=FacadeRuntime.RetainToken(component);
   if(phase==0){var a=SourceComponentRuntime.Lookup(typeof(EHR.NativeProbes.StaticLifecycleProbe),FacadeRuntime.Retain(owned));
    var b=SourceComponentRuntime.Lookup(typeof(EHR.NativeProbes.StaticLifecycleProbe),FacadeRuntime.Retain(owned));
    var probe=(EHR.NativeProbes.StaticLifecycleProbe)a!;output->FieldInitializers=probe.Initialized==37?1:0;output->SameSourceIdentity=ReferenceEquals(a,b)?1:0;}
   if(phase==1){GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();output->SourceCollected=Collected()?1:0;}
   output->Constructors=EHR.NativeProbes.StaticLifecycleProbe.ConstructorCount;output->Awake=EHR.NativeProbes.StaticLifecycleProbe.TotalAwake;
   output->Updates=EHR.NativeProbes.StaticLifecycleProbe.TotalUpdate;output->Destroyed=EHR.NativeProbes.StaticLifecycleProbe.TotalDestroy;output->Ping=EHR.NativeProbes.StaticLifecycleProbe.TotalPing;
   bool pass=output->Reserved==0&&(phase==0?output->ActiveStates==2&&output->FieldInitializers==1&&output->SameSourceIdentity==1&&output->Constructors==1&&output->Awake==1:
    phase==1&&output->ActiveStates==0&&output->Destroyed==1&&output->Updates>=2&&output->Ping==1&&output->SourceCollected==1);
   output->Pass=pass?1:0;return output->Status=pass?0:5;}
  catch(RuntimeGatewayException error){if(error is NativeGameException native)native.Dispose();return output->Status=error.Status;}catch{return output->Status=6;}
 }
 [MethodImpl(MethodImplOptions.NoInlining)] private static bool Collected()=>EHR.NativeProbes.StaticLifecycleProbe.Last!=null&&!EHR.NativeProbes.StaticLifecycleProbe.Last.TryGetTarget(out _);
}
