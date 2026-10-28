using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR;
internal static unsafe class IOSTouchShortcutSelfTest
{
 // Pure owned scalar policy only: no global production state/native game calls.
 [UnmanagedCallersOnly(EntryPoint="ehr_ios_touch_shortcuts_self_test_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
 internal static int Run(int* proof,nuint count)
 {
  if(proof==null||count!=12)return 4;for(int i=0;i<12;i++)proof[i]=0;
  try{
   var s=new IOSTouchShortcutState();s.PostChat(1,IOSChatShortcut.Previous,100);
   proof[1]=s.TakeChat(1,IOSChatShortcut.Previous,true,101)&&!s.TakeChat(1,IOSChatShortcut.Previous,true,102)?1:0;
   s.PostChat(1,IOSChatShortcut.Next,100);proof[2]=!s.TakeChat(1,IOSChatShortcut.Next,true,2101)?1:0;
   s.PostChat(1,IOSChatShortcut.Complete,100);proof[3]=!s.TakeChat(2,IOSChatShortcut.Complete,true,101)&&!s.TakeChat(1,IOSChatShortcut.Complete,true,102)?1:0;
   s.PostChat(1,IOSChatShortcut.Previous,100);s.ReconcileChat(1,false,101);proof[4]=!s.TakeChat(1,IOSChatShortcut.Previous,true,102)?1:0;
   s.SetMultiplier(1,5,true);bool five=s.Multiplier(1,true)==5;s.SetMultiplier(1,10,true);proof[5]=five&&s.Multiplier(1,true)==10?1:0;
   proof[6]=s.Multiplier(2,true)==1&&s.Multiplier(1,true)==1?1:0;
   s.Arm(1,0,true);proof[7]=s.Confirm(1,0,true)&&!s.Confirm(1,0,true)?1:0;
   s.Arm(1,1,true);proof[8]=!s.Confirm(1,1,false)&&!s.Confirm(1,1,true)?1:0;
   s.Arm(1,1,true);proof[9]=!s.Confirm(1,2,true)&&!s.Confirm(1,1,true)?1:0;
   s.Arm(1,1,true);s.ClearExecution();proof[10]=!s.Confirm(1,1,true)?1:0;
   proof[11]=RuntimeFeature.IsDynamicCodeSupported||RuntimeFeature.IsDynamicCodeCompiled?1:0;
   proof[0]=proof[11]==0?1:0;for(int i=1;i<=10;i++)proof[0]&=proof[i];return proof[0]==1?0:7;
  }catch{return 6;}
 }
}
