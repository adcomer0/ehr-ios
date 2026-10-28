using System;
using EHR;
static class Program
{
 static int checks;
 static void Check(bool value){checks++;if(!value)throw new Exception("failure gate check "+checks);}
 static void Main()
 {
  int clear=0,contain=0,entered=0;Exception expected=new InvalidOperationException("owned fixture");
  var gate=new IOSTouchControlFailureGate(()=>clear++,error=>{Check(ReferenceEquals(error,expected));contain++;return 7;});
  Check(gate.Run(()=>42,0)==42);Check(!gate.Failed&&clear==0&&contain==0);gate.Run(()=>entered++);Check(entered==1);
  Check(gate.Run<int>(()=>throw expected,-1)==-1);Check(gate.Failed&&gate.LastStatus==7&&gate.Failures==1&&!gate.CleanupFailed);Check(clear==1&&contain==1);
  Check(gate.Run(()=>{entered++;return 4;},-2)==-2);gate.Run(()=>entered++);Check(entered==1);gate.Fail(new Exception());Check(clear==1&&contain==1&&gate.Failures==1);
  bool pendingChat=true,pendingSelection=true;int multiplier=10,calls=0;
  var clearing=new IOSTouchControlFailureGate(()=>{pendingChat=false;pendingSelection=false;multiplier=1;},_=>6);
  clearing.Run(()=>{calls++;throw expected;});Check(!pendingChat&&!pendingSelection&&multiplier==1);clearing.Run(()=>calls++);Check(calls==1);
  foreach(bool clearThrows in new[]{false,true})foreach(bool containThrows in new[]{false,true})foreach(int status in new[]{0,2,4,6,7})
  {
   int clears=0,contains=0,reentrant=0;IOSTouchControlFailureGate? local=null;
   local=new(()=>{clears++;Check(local!.Failed);Check(local.Run(()=>{reentrant++;return 1;},0)==0);if(clearThrows)throw new Exception("clear");},_=>{contains++;Check(local!.Failed);if(containThrows)throw new Exception("contain");return status;});
   Check(local.Run<int>(()=>throw expected,9)==9);Check(clears==1&&contains==1&&reentrant==0);Check(local.Failures==1&&local.Failed);
   Check(local.CleanupFailed==(clearThrows||containThrows));Check(local.LastStatus==(containThrows||status==0?6:status));
   local.Fail(expected);Check(local.Failures==1&&clears==1&&contains==1);Check(local.Run(()=>true,false)==false);
  }
  Console.WriteLine("{\"ownedFailureGateChecks\":"+checks+",\"gameInvoked\":false}");
 }
}
