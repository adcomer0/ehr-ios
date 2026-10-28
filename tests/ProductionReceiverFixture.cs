using System;
using EHR;
using EHR.Generated;
namespace EHR.OwnTests;
// Compiled with actual production facades/dispatcher. Zero-token managed
// wrappers exercise CLR receiver typing only; they are not native game objects.
// The fixed actual source callback must reach the deliberately UNBOUND gateway,
// proving the bad cast is gone without making a native/game/account operation.
internal static class ProductionReceiverFixture
{
 static int checks;
 static void Check(bool value){++checks;if(!value)throw new Exception("receiver check "+checks);}
 static EHRStaticPatchFrame Frame(object instance)=>new(instance,[0],["maskLayer"]);
 static EHRStaticPatchDescriptor Postfix(Action<EHRStaticPatchFrame> action)=>new("own.receiver.postfix","own.receiver","own.fixture",EHRStaticPatchKind.Postfix,400,0,false,true,[],[],[],action,null);
 public static int Main()
 {
  using var baseReceiver=new global::GameOptionsMapPicker(0);
  using var derivedReceiver=new global::CreateGameMapPicker(0);
  Check(baseReceiver.GetType()==typeof(global::GameOptionsMapPicker));
  Check(typeof(global::CreateGameMapPicker).BaseType==typeof(global::GameOptionsMapPicker));
  Check(ReferenceEquals(Frame(baseReceiver).GetInstance<global::GameOptionsMapPicker>(),baseReceiver));
  Check(ReferenceEquals(Frame(derivedReceiver).GetInstance<global::GameOptionsMapPicker>(),derivedReceiver));
  Check(ReferenceEquals(Frame(derivedReceiver).GetInstance<global::CreateGameMapPicker>(),derivedReceiver));
  bool rejected=false;try{Frame(baseReceiver).GetInstance<global::CreateGameMapPicker>();}catch(InvalidCastException){rejected=true;}Check(rejected);
  int originals=0,bodies=0;
  var oldFrame=Frame(baseReceiver);
  var oldBinding=new EHRStaticPatchBinding("own.receiver",[Postfix(frame=>{frame.GetInstance<global::CreateGameMapPicker>();++bodies;})]);
  rejected=false;try{oldBinding.Execute(oldFrame,_=>originals++);}catch(InvalidCastException){rejected=true;}
  Check(rejected&&originals==1&&bodies==0);Check(oldFrame.OriginalEntered&&oldFrame.Consumed&&oldFrame.Exception is InvalidCastException);
  var fixedFrame=Frame(baseReceiver);
  var fixedBinding=new EHRStaticPatchBinding("own.receiver",[Postfix(global::EHR.Patches.GameOptionsMapPickerPatch.__EHRStaticCallback_191)]);
  bool reachedUnbound=false;
  try{fixedBinding.Execute(fixedFrame,_=>originals++);}
  catch(RuntimeGatewayException error){reachedUnbound=error.Status==1&&error.Message.StartsWith("gateway not bound",StringComparison.Ordinal);}
  Check(reachedUnbound);Check(originals==2&&fixedFrame.OriginalEntered&&fixedFrame.Consumed);Check(fixedFrame.Exception is RuntimeGatewayException);
  Check(baseReceiver.Token==0&&derivedReceiver.Token==0);
  global::System.Console.WriteLine("{\"pass\":true,\"checks\":"+checks+",\"actualProductionFacadeTypes\":true,\"actualProductionFrame\":true,\"actualFixedCallbackEntered\":true,\"baselinePostfixCastFailedAfterOriginal\":true,\"fixedCallbackReachedDeliberatelyUnboundGateway\":true,\"nativeGameObjectsCreated\":0,\"nativeGameCalls\":0,\"accountActions\":0,\"dynamicCodePortClaimed\":false}");return 0;
 }
}
