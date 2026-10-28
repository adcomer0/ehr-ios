using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.SourceHost;
using EHR.Modules;
using EHR.Patches;
using EHR.Generated;
namespace EHR;
internal readonly record struct IOSExecutionTarget(byte PlayerId,string Name);

// UI requests enter the original guarded keyboard handler on its next update.
// Native game objects exist only in this call's locals, never in static state.
internal static unsafe class IOSTouchShortcuts
{
 private static class Production
 {
  internal static readonly IOSTouchShortcutState State=new();
  internal static readonly System.Collections.Generic.List<IOSExecutionTarget> Empty=new();
  internal static readonly IOSTouchControlFailureGate Gate=new(ClearProduction,Contain);
 }
 private static IOSTouchShortcutState state=>Production.State;
 private static IOSTouchControlFailureGate Gate=>Production.Gate;
 private static void ClearProduction(){state.ClearChat();state.SetMultiplier(0,1,false);state.ClearExecution();}
 private static int Contain(Exception error)
 {
  int status=error is RuntimeGatewayException gateway?gateway.Status:6;
  if(error is NativeGameException native)native.Dispose();
  return status==0?6:status;
 }
 private static readonly BindingSpec instanceId=new("UnityEngine.CoreModule.dll","UnityEngine","Object","GetInstanceID",false,false,"System.Int32",[]);
 private static int Id(RuntimeObject value){using var result=FacadeRuntime.Invoke(instanceId,value.Token,null,0);return FacadeRuntime.ReadValue<int>(result);}
 private static bool ChatEligible(bool allowPanel,out ChatController chat)
 {
  chat=null;
  if(!OperatingSystem.IsIOS()||!HudManager.InstanceExists)return false;
  if(!allowPanel&&ClientControlGUI.Instance&&ClientControlGUI.Instance.IsOpen)return false;
  chat=HudManager.Instance.Chat;
  return chat&&chat.IsOpenOrOpening&&chat.freeChatField&&chat.freeChatField.textArea&&chat.freeChatField.textArea.hasFocus;
 }
 internal static bool CanShowChatControls=>Gate.Run(()=>ChatEligible(true,out _),false);
 internal static void RequestChat(IOSChatShortcut action)=>Gate.Run(()=>RequestChatCore(action));
 private static void RequestChatCore(IOSChatShortcut action)
 {
  if(!ChatEligible(true,out var chat))return;
  if(ClientControlGUI.Instance)ClientControlGUI.Instance.IsOpen=false;
  if(!ChatEligible(false,out var current)||Id(current)!=Id(chat))return;
  state.PostChat(Id(current),action,Environment.TickCount64);
 }
 internal static bool TakeChat(IOSChatShortcut action,ChatController chat)=>Gate.Run(()=>TakeChatCore(action,chat),false);
 private static bool TakeChatCore(IOSChatShortcut action,ChatController chat)
 {
  bool eligible=ChatEligible(false,out var current)&&Id(current)==Id(chat);
  return state.TakeChat(eligible?Id(chat):0,action,eligible,Environment.TickCount64);
 }
 private static bool SettingsEligible(out int owner)
 {
  owner=0;if(!OperatingSystem.IsIOS())return false;
  var client=AmongUsClient.Instance;var menu=GameSettingMenu.Instance;
  if(!client||!client.AmHost||!GameStates.IsLobby||GameStates.IsCountDown||client.IsGameStarted||!menu||!menu.isActiveAndEnabled)return false;
  owner=Id(menu);return owner!=0;
 }
 internal static bool CanShowSettingsSteps=>Gate.Run(()=>SettingsEligible(out _),false);
 internal static int NumberMultiplier=>Gate.Run(NumberMultiplierCore,1);
 private static int NumberMultiplierCore(){bool eligible=SettingsEligible(out int owner);return state.Multiplier(owner,eligible);}
 internal static void SetNumberMultiplier(int multiplier)=>Gate.Run(()=>SetNumberMultiplierCore(multiplier));
 private static void SetNumberMultiplierCore(int multiplier)
 {
  bool eligible=SettingsEligible(out int owner);state.SetMultiplier(owner,multiplier,eligible);
  if(eligible&&ClientControlGUI.Instance)ClientControlGUI.Instance.IsOpen=false;
 }
 private static bool CurrentMeeting(out MeetingHud meeting)
 {
  meeting=null;if(!OperatingSystem.IsIOS()||!GameStates.IsMeeting)return false;
  var client=AmongUsClient.Instance;meeting=MeetingHud.Instance;
  return client&&client.AmHost&&meeting&&meeting.playerStates!=null;
 }
 private static bool FindTarget(MeetingHud meeting,byte target,out PlayerControl player)
 {
  player=null;int scanned=0;
  foreach(var area in meeting.playerStates)
  {
   if(++scanned>256)return false;
   if(!area||area.PlayerId!=target)continue;
   player=Utils.GetPlayerById(target);return player&&player.Data!=null&&player.IsAlive();
  }
  return false;
 }
 private static string Name(PlayerControl player){string name=(player.Data.PlayerName??"").RemoveHtmlTags();int[] elements=System.Globalization.StringInfo.ParseCombiningCharacters(name);return elements.Length>20?name[..elements[20]]+"…":name;}
 internal static System.Collections.Generic.List<IOSExecutionTarget> ExecutionTargets()=>Gate.Run(()=>ExecutionTargetsCore(),Production.Empty);
 private static System.Collections.Generic.List<IOSExecutionTarget> ExecutionTargetsCore()
 {
  var result=new System.Collections.Generic.List<IOSExecutionTarget>();if(!CurrentMeeting(out var meeting)){state.ClearExecution();return result;}
  var seen=new System.Collections.Generic.HashSet<byte>();int scanned=0;
  foreach(var area in meeting.playerStates)
  {
   if(++scanned>256)break;if(!area||!seen.Add(area.PlayerId))continue;
   var player=Utils.GetPlayerById(area.PlayerId);if(player&&player.Data!=null&&player.IsAlive())result.Add(new(player.PlayerId,Name(player)));
  }
  return result;
 }
 internal static bool ExecutionMenu(out string targetName,out bool armed)
 {
  targetName="";armed=false;if(Gate.Failed)return false;
  try{return ExecutionMenuCore(out targetName,out armed);}
  catch(Exception error){Gate.Fail(error);targetName="";armed=false;return false;}
 }
 private static bool ExecutionMenuCore(out string targetName,out bool armed)
 {
  targetName="";armed=false;
  if(!CurrentMeeting(out var meeting)||!state.TrySelection(Id(meeting),true,out byte selected)||!FindTarget(meeting,selected,out var player)){state.ClearExecution();return false;}
  targetName=$"[{player.PlayerId}] {Name(player)}";armed=true;return true;
 }
 internal static void ArmExecution(byte selected)=>Gate.Run(()=>ArmExecutionCore(selected));
 private static void ArmExecutionCore(byte selected)
 {
  bool eligible=CurrentMeeting(out var meeting)&&FindTarget(meeting,selected,out _);
  state.Arm(eligible?Id(meeting):0,selected,eligible);
 }
 internal static void CancelExecution()=>state.ClearExecution();
 internal static void ConfirmExecution()=>Gate.Run(()=>ConfirmExecutionCore());
 private static void ConfirmExecutionCore()
 {
  if(!CurrentMeeting(out var meeting)||!state.TrySelection(Id(meeting),true,out byte selected)||!FindTarget(meeting,selected,out var player)){state.ClearExecution();return;}
  if(!state.Confirm(Id(meeting),player.PlayerId,true))return;
  // Exact upstream execution effect sequence, after the fresh host/meeting/
  // same current-meeting member/alive checks above. Confirmation is consumed first.
  Main.PlayerStates[player.PlayerId].deathReason = PlayerState.DeathReason.Execution;
  player.RpcExileV2();
  Main.PlayerStates[player.PlayerId].SetDead();
  Utils.AfterPlayerDeathTasks(player, true);
  Utils.SendMessage(string.Format(Translator.GetString("Message.Executed"), player.Data.PlayerName));
  Logger.Info($"{player.GetNameWithRole()} was executed by the host", "Execution");
  meeting.CheckForEndVoting();
 }
 internal static void Reconcile()=>Gate.Run(()=>ReconcileCore());
 private static void ReconcileCore()
 {
  if(!OperatingSystem.IsIOS())return;
  bool chat=ChatEligible(false,out var current);state.ReconcileChat(chat?Id(current):0,chat,Environment.TickCount64);
  bool settings=SettingsEligible(out int owner);state.Multiplier(owner,settings);
  if(!CurrentMeeting(out var meeting)||!state.TrySelection(Id(meeting),true,out byte selected)||!FindTarget(meeting,selected,out _))state.ClearExecution();
 }

 // Optional real-native binding proof. It never touches Production, GUI, game
 // singletons, source components, players, network, or account/progress state.
 [UnmanagedCallersOnly(EntryPoint="ehr_ios_touch_identity_self_test_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
 internal static int IdentitySelfTest(int* proof,nuint count)
 {
  if(proof==null||count!=8)return 4;
  for(int i=0;i<8;i++)proof[i]=0;
  if(!NativeSourceHost.IsMainThread){proof[7]=2;return 2;}
  RuntimeObject? game=null,retained=null;bool gameDisposed=false,retainedDisposed=false;
  try
  {
   using var name=FacadeRuntime.String("EHR.TouchIdentityProbe");
   ulong gameClass=FacadeRuntime.Class("UnityEngine.CoreModule.dll","UnityEngine","GameObject");
   ulong stringClass=FacadeRuntime.Class("mscorlib.dll","System","String");
   game=new RuntimeObject(NativeConstructors.Create(gameClass,[stringClass],[name]));
   proof[1]=1;proof[2]=Id(game);proof[3]=Id(game);
   retained=FacadeRuntime.Retain(game);proof[4]=Id(retained);
  }
  catch(Exception error){RecordProbeFailure(proof,error);}
  finally
  {
   if(game!=null)
   {
    try
    {
     var destroy=new BindingSpec("UnityEngine.CoreModule.dll","UnityEngine","Object","Destroy",true,false,"System.Void",["UnityEngine.Object"]);
     NativeArgument argument=FacadeRuntime.Reference(game);
     using var result=FacadeRuntime.Invoke(destroy,0,&argument,1);proof[5]=1;
    }
    catch(Exception error){RecordProbeFailure(proof,error);}
   }
   try{retained?.Dispose();retainedDisposed=true;}catch(Exception error){RecordProbeFailure(proof,error);}
   try{game?.Dispose();gameDisposed=true;}catch(Exception error){RecordProbeFailure(proof,error);}
   proof[6]=retainedDisposed&&gameDisposed?1:0;
  }
  proof[0]=proof[1]==1&&proof[2]!=0&&proof[2]==proof[3]&&proof[2]==proof[4]&&proof[5]==1&&proof[6]==1&&proof[7]==0?1:0;
  return proof[0]==1?0:proof[7]!=0?proof[7]:7;
 }
 private static void RecordProbeFailure(int* proof,Exception error)
 {
  // Do not use the production gate: this optional probe has independent state.
  if(proof[7]==0)proof[7]=error is RuntimeGatewayException gateway&&gateway.Status!=0?gateway.Status:6;
  if(error is NativeGameException native)
  {
   try{native.Dispose();}catch{if(proof[7]==0)proof[7]=6;}
  }
 }
}
