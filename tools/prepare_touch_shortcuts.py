#!/usr/bin/env python3
"""Narrow current-source touch routes; no new hooks or vanilla copy duplicate."""
import argparse,hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
HELPER_NAMES=('IOSTouchShortcutState.cs','IOSTouchShortcuts.cs','IOSTouchShortcutSelfTest.cs','IOSTouchControlFailureGate.cs')
def prepare(project,output):
 project=project.resolve()
 stage=Path(__file__).resolve().parents[1];out=output.resolve()
 if out.exists():raise ValueError('fresh output required')
 tree=ET.parse(project);root=tree.getroot();selected={}
 for element in root.iter('Compile'):
  value=element.get('Include')
  if not value:continue
  path=Path(value);path=path if path.is_absolute() else (project.parent/path).resolve()
  if path.name in HELPER_NAMES:raise ValueError('touch helper already selected: '+path.name+'; use an input before the touch overlay')
  if path.name in ['ClientControlGUI.cs','ControlPatch.cs','GameOptionsMenuPatch.cs','MeetingHudPatch.cs']:
   if path.name in selected:raise ValueError('ambiguous selected '+path.name)
   selected[path.name]=(path,element)
 if len(selected)!=4:raise ValueError('all four current source inputs required')
 helper=(stage/'managed/IOSTouchShortcuts.cs').read_text()
 if 'ehr_ios_touch_identity_self_test_v1' not in helper or 'IOSTouchControlFailureGate' not in helper:raise ValueError('current identity/failure helper required')
 for name in HELPER_NAMES:
  if not (stage/'managed'/name).is_file():raise ValueError('missing current helper '+name)
 out.mkdir(parents=True);changes=[]
 def change(name,old,new):
  if current.count(old)!=1:raise ValueError(name+' anchor changed: '+old[:100])
  return current.replace(old,new)
 for name in ['ClientControlGUI.cs','ControlPatch.cs','GameOptionsMenuPatch.cs']:
  path,element=selected[name];before=path.read_text();current=before
  if name=='ClientControlGUI.cs':
   current=change(name,'        ReconcileIOSNoClip();','        ReconcileIOSNoClip();\n        IOSTouchShortcuts.Reconcile();')
   anchor='''        bool amHost     = AmongUsClient.Instance && AmongUsClient.Instance.AmHost;'''
   extra='''        // iOS requests re-enter the existing guarded keyboard handler after
        // closing this panel; free-chat focus and command policy stay intact.
        if (IOSTouchShortcuts.CanShowChatControls)
        {
            Section(ref y, "Chat editing");
            Btn(ref y, "Previous chat message", _sAction, () => IOSTouchShortcuts.RequestChat(IOSChatShortcut.Previous));
            Btn(ref y, "Next chat message", _sAction, () => IOSTouchShortcuts.RequestChat(IOSChatShortcut.Next));
            Btn(ref y, "Complete command", _sAction, () => IOSTouchShortcuts.RequestChat(IOSChatShortcut.Complete));
        }
        if (IOSTouchShortcuts.CanShowSettingsSteps)
        {
            Section(ref y, $"Number-option step: ×{IOSTouchShortcuts.NumberMultiplier}");
            Btn(ref y, "Use ×1 option steps", _sAction, () => IOSTouchShortcuts.SetNumberMultiplier(1));
            Btn(ref y, "Use ×5 option steps", _sAction, () => IOSTouchShortcuts.SetNumberMultiplier(5));
            Btn(ref y, "Use ×10 option steps", _sAction, () => IOSTouchShortcuts.SetNumberMultiplier(10));
        }
        var executionTargets = IOSTouchShortcuts.ExecutionTargets();
        if (executionTargets.Count > 0)
        {
            Section(ref y, "Host meeting execution");
            if (IOSTouchShortcuts.ExecutionMenu(out string executionName, out _))
            {
                Btn(ref y, $"Confirm execution: {executionName}", _sDanger, IOSTouchShortcuts.ConfirmExecution);
                Btn(ref y, "Cancel execution", _sAction, IOSTouchShortcuts.CancelExecution);
            }
            foreach (var executionTarget in executionTargets)
                Btn(ref y, $"Select [{executionTarget.PlayerId}] {executionTarget.Name}", _sAction, () => IOSTouchShortcuts.ArmExecution(executionTarget.PlayerId));
        }

'''
   current=change(name,anchor,extra+anchor)
  elif name=='ControlPatch.cs':
   current=change(name,'            bool isMeeting = GameStates.IsMeeting;','            bool isMeeting = GameStates.IsMeeting;\n            IOSTouchShortcuts.Reconcile();')
   current=change(name,'if (Input.GetKeyDown(KeyCode.Tab)) TextBoxPatch.OnTabPress(chat);','if (IOSTouchShortcuts.TakeChat(IOSChatShortcut.Complete, chat) || Input.GetKeyDown(KeyCode.Tab)) TextBoxPatch.OnTabPress(chat);')
   current=change(name,'if (Input.GetKeyDown(KeyCode.UpArrow) && ChatCommands.ChatHistory.Count > 0)','if ((IOSTouchShortcuts.TakeChat(IOSChatShortcut.Previous, chat) || Input.GetKeyDown(KeyCode.UpArrow)) && ChatCommands.ChatHistory.Count > 0)')
   current=change(name,'if (Input.GetKeyDown(KeyCode.DownArrow) && ChatCommands.ChatHistory.Count > 0)','if ((IOSTouchShortcuts.TakeChat(IOSChatShortcut.Next, chat) || Input.GetKeyDown(KeyCode.DownArrow)) && ChatCommands.ChatHistory.Count > 0)')
  else:
   anchor='''            if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)) return 5;
            if (Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl)) return 10;
            return 1;'''
   current=change(name,anchor,anchor.replace('return 1;','return IOSTouchShortcuts.NumberMultiplier;'))
  output=out/name;output.write_text(current);element.set('Include',str(output));changes.append({'input':str(path),'output':str(output),'inputSha256':hashlib.sha256(before.encode()).hexdigest(),'outputSha256':hashlib.sha256(current.encode()).hexdigest()})
 # Fail if execution effects drift from the pinned current callback body.
 meetingSource=selected['MeetingHudPatch.cs'][0].read_text()
 effects='''                        Main.PlayerStates[player.PlayerId].deathReason = PlayerState.DeathReason.Execution;
                        player.RpcExileV2();
                        Main.PlayerStates[player.PlayerId].SetDead();
                        Utils.AfterPlayerDeathTasks(player, true);
                        Utils.SendMessage(string.Format(GetString("Message.Executed"), player.Data.PlayerName));
                        Logger.Info($"{player.GetNameWithRole()} was executed by the host", "Execution");
                        __instance.CheckForEndVoting();'''
 if meetingSource.count(effects)!=1:raise ValueError('upstream execution effect sequence changed')
 helpers=[];group=ET.SubElement(root,'ItemGroup')
 for name in HELPER_NAMES:
  target=out/name;target.write_bytes((stage/'managed'/name).read_bytes());ET.SubElement(group,'Compile',Include=str(target));helpers.append({'path':str(target),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
 # Rebase explicit paths because the joined project lives in a fresh directory.
 for tag in ['Compile','EmbeddedResource','Content','None','AdditionalFiles','Reference']:
  for element in root.iter(tag):
   for attribute in ['Include','Update']:
    value=element.get(attribute)
    if not value or '$(' in value or '@(' in value:continue
    if tag=='Reference' and attribute=='Include':continue
    path=Path(value)
    if not path.is_absolute():element.set(attribute,str((project.parent/path).resolve()))
   for child in element:
    if child.tag=='HintPath' and child.text and '$(' not in child.text and not Path(child.text).is_absolute():child.text=str((project.parent/child.text).resolve())
 tree.write(out/'EHR.csproj',encoding='unicode',xml_declaration=False)
 manifest={'schema':'ehr.ios-touch-shortcuts-overlay.v1','projectInput':str(project.resolve()),'projectInputSha256':hashlib.sha256(project.read_bytes()).hexdigest(),'changes':changes,'helpers':helpers,'nativeHooksAdded':0,'accountPolicyChanged':False,'originalKeyboardRoutesRetained':True,'executionEffectsMatchPinnedCurrentBody':True,'executionRequiresFreshMeetingMembershipAliveAndExplicitSelectionConfirmation':True,'desktopHoverReplacedOnlyAsTouchSelectionMechanism':True,'duplicateLobbyCopyControlAdded':False,'gameInvoked':False,'failureGateIncluded':True,'identityProbeIncluded':True,'separateLegacyIdentityOverlayRequired':False}
 (out/'touch-shortcuts.json').write_text(json.dumps(manifest,indent=2)+'\n');return out/'touch-shortcuts.json'

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();print(prepare(a.project,a.output))
