// Own NativeAOT host validates production resolver sequencing. No game runtime,
// metadata, patched entries, accounts, credentials or network service is used.
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;
using EHR;
internal static unsafe class OwnTargets
{
 internal static readonly List<string> Events=new();
 internal static readonly HashSet<ulong> Active=new();
 internal static bool FailActivation;
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int Validate(ulong id){Events.Add("validate"+id);return id==1?0:1;}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int Activate(ulong* ids,nuint count)
 {Events.Add("activate");for(nuint i=0;i<count;++i)Active.Add(ids[i]);return FailActivation?5:0;}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]internal static int Deactivate(){Events.Add("deactivate");Active.Clear();return 0;}
}
internal static unsafe class Program
{
 static EHRStaticTargetSpec Spec(string member="Run",string kind="Normal",string image="Own",string result="System.Void",bool exact=true,string[]? arguments=null,string[]? names=null)=>
  new("Own.Sample",member,kind,arguments??["System.Int32"],exact,image,result,false,names??["value"],"resolved_managed_reference_signature");
 static int Main()
 {
  int checks=0;void Check(bool value){if(!value)throw new Exception("Own targets contract failed at check "+checks);++checks;}
  Check(new EHRStaticPatchFrame(null,[],[]){Result=42}.GetResult<int>()==42);
  delegate* unmanaged<NativePatchTargetsTableV1*,nuint,int> bind=&NativePatchTargetResolver.Bind;
  Check(bind(null,32)==4);
  NativePatchTargetsTableV1 table=new(){AbiVersion=1,ByteSize=32,Validate=&OwnTargets.Validate,Activate=&OwnTargets.Activate,Deactivate=&OwnTargets.Deactivate};
  Check(bind(&table,32)==0);Check(bind(&table,32)==4);
  NativePatchDefinition[] definitions=[new(1),new(2)];var source=Spec();
  NativePatchCandidate[] candidates=[new(1,"first",source),new(2,"second",Spec("Other"))];
  var resolver=NativePatchTargetResolver.Prepare(definitions,candidates);
  Check(OwnTargets.Events.SequenceEqual(new[]{"deactivate","configure","validate1","validate2"}));
  Check(OwnTargets.Active.Count==0);
  Check(resolver.TryResolve(Spec(),out string key,out string reason)&&key=="first"&&reason=="");
  Check(!resolver.TryResolve(Spec("Other"),out key,out reason)&&key==""&&reason.EndsWith("status_1"));
  foreach(var different in new[]{Spec("Missing"),Spec(kind:"Getter"),Spec(image:"Other"),Spec(result:"System.Int32"),Spec(exact:false),Spec(arguments:["System.String"]),Spec(names:["other"])})
   Check(!resolver.TryResolve(different,out key,out reason));
  source.ArgumentTypeNames[0]="changed after preparation";source.ParameterNames[0]="changed";
  Check(resolver.TryResolve(Spec(),out key,out reason)&&key=="first");
  resolver.Activate([definitions[0]]);Check(OwnTargets.Active.SetEquals(new ulong[]{1}));
  Check(OwnTargets.Events.TakeLast(3).SequenceEqual(new[]{"deactivate","configure","activate"}));
  bool rejected=false;try{resolver.Activate([definitions[1]]);}catch(InvalidOperationException){rejected=true;}
  Check(rejected&&OwnTargets.Active.Count==0);
  OwnTargets.FailActivation=true;rejected=false;
  try{resolver.Activate([definitions[0]]);}catch(EHR.Generated.RuntimeGatewayException){rejected=true;}
  Check(rejected&&OwnTargets.Active.Count==0&&OwnTargets.Events.Last()=="deactivate");
  OwnTargets.FailActivation=false;resolver.Activate([]);Check(OwnTargets.Active.Count==0);
  rejected=false;try{NativePatchTargetResolver.Prepare(definitions,[candidates[0],candidates[0]]);}catch(InvalidOperationException){rejected=true;}
  Check(rejected&&OwnTargets.Active.Count==0);
  Console.WriteLine($"{{\"success\":true,\"checks\":{checks},\"activeTargets\":{OwnTargets.Active.Count},\"scope\":\"production source resolver with own simulated NativeAOT host\"}}");return 0;
 }
}
namespace EHR
{
 internal sealed class NativePatchDefinition(ulong id){internal ulong Id{get;}=id;}
 internal static class NativePatchRuntime
 {internal static void Configure(IEnumerable<NativePatchDefinition> definitions){_ = definitions.ToArray();OwnTargets.Events.Add("configure");}}
}
namespace EHR.Generated
{
 internal sealed class RuntimeGatewayException(int status,string operation):Exception(operation){internal int Status{get;}=status;}
 internal static class FacadeRuntime
 {internal static void RequireReady(){}internal static void Require(int status,string operation){if(status!=0)throw new RuntimeGatewayException(status,operation);}}
}
