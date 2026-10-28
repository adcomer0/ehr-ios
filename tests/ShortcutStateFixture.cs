using System;
using EHR;
using System.Runtime.CompilerServices;
static unsafe class Program
{
 static int checks;
 static void Assert(bool condition){checks++;if(!condition)throw new Exception("Shortcut state check "+checks);}
 static void Main()
 {
  foreach(int owner in new[]{-17,1,42})foreach(var action in new[]{IOSChatShortcut.Previous,IOSChatShortcut.Next,IOSChatShortcut.Complete})
  {
   var state=new IOSTouchShortcutState();state.PostChat(owner,action,100);
   foreach(var other in new[]{IOSChatShortcut.Previous,IOSChatShortcut.Next,IOSChatShortcut.Complete})if(other!=action)Assert(!state.TakeChat(owner,other,true,200));
   Assert(state.TakeChat(owner,action,true,2100));Assert(!state.TakeChat(owner,action,true,2100));
   state.PostChat(owner,action,100);Assert(!state.TakeChat(owner,action,true,2101));Assert(!state.TakeChat(owner,action,true,100));
   state.PostChat(owner,action,100);Assert(!state.TakeChat(owner+1,action,true,101));Assert(!state.TakeChat(owner,action,true,102));
   state.PostChat(owner,action,100);state.ReconcileChat(owner,false,101);Assert(!state.TakeChat(owner,action,true,102));
   state.PostChat(owner,action,100);state.ReconcileChat(owner+1,true,101);Assert(!state.TakeChat(owner,action,true,102));
   state.PostChat(owner,action,100);state.ClearChat();Assert(!state.TakeChat(owner,action,true,102));
  }
  foreach(int owner in new[]{-17,0,1,42})foreach(int multiplier in new[]{-1,0,1,2,5,10,11})foreach(bool eligible in new[]{false,true})
  {
   var state=new IOSTouchShortcutState();state.SetMultiplier(owner,multiplier,eligible);
   int expected=eligible&&owner!=0&&(multiplier==1||multiplier==5||multiplier==10)?multiplier:1;
   Assert(state.Multiplier(owner,eligible)==expected);Assert(state.Multiplier(owner,false)==1);Assert(state.Multiplier(owner,true)==1);
   state.SetMultiplier(owner,multiplier,eligible);Assert(state.Multiplier(owner+1,true)==1);Assert(state.Multiplier(owner,true)==1);
  }
  foreach(int meeting in new[]{-17,0,1,42})foreach(byte player in new byte[]{0,1,14,127,255})foreach(bool eligible in new[]{false,true})
  {
   var state=new IOSTouchShortcutState();state.Arm(meeting,player,eligible);bool expected=meeting!=0&&eligible;
   Assert(state.IsArmed(meeting,player,eligible)==expected);Assert(state.Confirm(meeting,player,eligible)==expected);Assert(!state.Confirm(meeting,player,true));
   state.Arm(meeting,player,eligible);Assert(!state.Confirm(meeting+1,player,true));Assert(!state.Confirm(meeting,player,true));
   state.Arm(meeting,player,eligible);Assert(!state.Confirm(meeting,(byte)(player+1),true));Assert(!state.Confirm(meeting,player,true));
   state.Arm(meeting,player,eligible);Assert(!state.IsArmed(meeting,player,false));Assert(!state.Confirm(meeting,player,true));
   state.Arm(meeting,player,eligible);state.ClearExecution();Assert(!state.Confirm(meeting,player,true));
   state.Arm(meeting,player,eligible);Assert(state.TrySelection(meeting,eligible,out byte chosen)==expected);if(expected)Assert(chosen==player);Assert(!state.TrySelection(meeting+1,true,out _));Assert(!state.Confirm(meeting,player,true));
  }
  int* proof=stackalloc int[12];delegate* unmanaged[Cdecl]<int*,nuint,int> selftest=&IOSTouchShortcutSelfTest.Run;
  Assert(selftest(proof,11)==4);int status=selftest(proof,12);for(int i=1;i<=10;i++)Assert(proof[i]==1);
  bool dynamic=RuntimeFeature.IsDynamicCodeSupported||RuntimeFeature.IsDynamicCodeCompiled;Assert(proof[11]==(dynamic?1:0));Assert(status==(dynamic?7:0));Assert(proof[0]==(dynamic?0:1));
  Console.WriteLine("{\"ownedShortcutStateChecks\":"+checks+",\"gameInvoked\":false,\"nativeObjectsRetained\":false,\"dynamicCode\":"+dynamic.ToString().ToLowerInvariant()+"}");
 }
}
