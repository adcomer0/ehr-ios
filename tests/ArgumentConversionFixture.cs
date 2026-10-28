using System;
using EHR;
static class ArgumentConversionFixture
{
 static int checks;
 static void Check(bool value){++checks;if(!value)throw new Exception("argument conversion check "+checks);}
 static void Main()
 {
  for(int value=0;value<=255;value++)
  {
   var frame=new EHRStaticPatchFrame(new EHR.OwnBindingFixture.OwnReceiver(),[value],["bodyColor"]);bool rejected=false;
   try{_ = frame.GetArgument<byte>("bodyColor");}catch(InvalidCastException){rejected=true;}Check(rejected);
   byte converted=unchecked((byte)frame.GetArgument<int>("bodyColor"));Check(converted==value);Check((converted==255)==(value==255));Check((int)frame.Arguments[0]! ==value);
   int calls=EHR.OwnBindingFixture.ActualCallback269Fixture.Calls;EHR.OwnBindingFixture.ActualCallback269Fixture.__EHRStaticCallback_269(frame);Check(EHR.OwnBindingFixture.ActualCallback269Fixture.Seen==converted);Check(EHR.OwnBindingFixture.ActualCallback269Fixture.Calls==calls+1);
  }
  foreach(int value in new[]{int.MinValue,int.MaxValue,-65537,-65536,-257,-256,-255,-1,256,257,511,512,65535,65536,65537})
  {
   var frame=new EHRStaticPatchFrame(new EHR.OwnBindingFixture.OwnReceiver(),[value],["bodyColor"]);byte converted=unchecked((byte)frame.GetArgument<int>("bodyColor"));Check(converted==(byte)(value&255));Check((converted==255)==((value&255)==255));Check((int)frame.Arguments[0]! ==value);
   int calls=EHR.OwnBindingFixture.ActualCallback269Fixture.Calls;EHR.OwnBindingFixture.ActualCallback269Fixture.__EHRStaticCallback_269(frame);Check(EHR.OwnBindingFixture.ActualCallback269Fixture.Seen==converted);Check(EHR.OwnBindingFixture.ActualCallback269Fixture.Calls==calls+1);
  }
  // Use the production dispatcher for post-original and one-invocation order.
  int originals=0,callbacks=0,sentinel=0;byte observed=0;
  var patch=new EHRStaticPatchDescriptor("own.color.postfix","own.color","own.fixture",EHRStaticPatchKind.Postfix,400,0,false,true,[],[],[],frame=>{observed=unchecked((byte)frame.GetArgument<int>("bodyColor"));callbacks++;if(observed==255)sentinel++;},null);
  var binding=new EHRStaticPatchBinding("own.color",[patch]);
  foreach(int value in new[]{0,17,254,255}){var frame=new EHRStaticPatchFrame(new EHR.OwnBindingFixture.OwnReceiver(),[value],["bodyColor"]);binding.Execute(frame,_=>originals++);Check(frame.OriginalEntered&&frame.Consumed&&frame.Exception==null);Check(observed==value);}
  Check(originals==4&&callbacks==4&&sentinel==1);
  Console.WriteLine("{\"pass\":true,\"checks\":"+checks+",\"validByteValues\":256,\"sourceSentinel\":255,\"productionFrameCompiled\":true,\"productionBindingCompiled\":true,\"actualGeneratedWrapperCompiled\":true,\"sourceBodyAndGameInvoked\":false,\"nativeObjectsCreated\":0}");
 }
}
