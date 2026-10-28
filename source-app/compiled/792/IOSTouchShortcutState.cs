using System;
namespace EHR;

internal enum IOSChatShortcut { None, Previous, Next, Complete }
// Owned scalar state only. No native object, callback, or root is retained here.
internal sealed class IOSTouchShortcutState
{
 private IOSChatShortcut chat;private int chatOwner;private long chatUntil;
 private int settingsOwner,settingsMultiplier=1;
 private int meetingOwner;private byte executionTarget;private bool armed;
 internal void PostChat(int owner,IOSChatShortcut action,long now)
 {
  ClearChat();if(owner==0||action is <IOSChatShortcut.Previous or >IOSChatShortcut.Complete)return;
  chatOwner=owner;chat=action;chatUntil=now+2000;
 }
 internal bool TakeChat(int owner,IOSChatShortcut action,bool eligible,long now)
 {
  if(!eligible||owner==0||owner!=chatOwner||now>chatUntil){ClearChat();return false;}
  if(chat!=action)return false;ClearChat();return true;
 }
 internal void ReconcileChat(int owner,bool eligible,long now)
 {if(!eligible||owner!=chatOwner||now>chatUntil)ClearChat();}
 internal void ClearChat(){chat=IOSChatShortcut.None;chatOwner=0;chatUntil=0;}
 internal void SetMultiplier(int owner,int multiplier,bool eligible)
 {
  if(!eligible||owner==0||multiplier is not (1 or 5 or 10)){ClearMultiplier();return;}
  settingsOwner=owner;settingsMultiplier=multiplier;
 }
 internal int Multiplier(int owner,bool eligible)
 {if(!eligible||owner==0||owner!=settingsOwner)ClearMultiplier();return settingsMultiplier;}
 private void ClearMultiplier(){settingsOwner=0;settingsMultiplier=1;}
 internal void Arm(int meeting,byte player,bool eligible)
 {ClearExecution();if(!eligible||meeting==0)return;meetingOwner=meeting;executionTarget=player;armed=true;}
 internal bool IsArmed(int meeting,byte player,bool eligible)
 {if(!eligible||meeting==0||meeting!=meetingOwner||player!=executionTarget)ClearExecution();return armed;}
 internal bool Confirm(int meeting,byte player,bool eligible)
 {bool allowed=IsArmed(meeting,player,eligible);ClearExecution();return allowed;}
 internal bool TrySelection(int meeting,bool eligible,out byte player)
 {player=0;if(!eligible||meeting==0||meeting!=meetingOwner)ClearExecution();if(!armed)return false;player=executionTarget;return true;}
 internal void ClearExecution(){armed=false;meetingOwner=0;executionTarget=0;}
}
