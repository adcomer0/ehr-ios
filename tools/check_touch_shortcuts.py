#!/usr/bin/env python3
"""Own scalar policy checks + exact current-source guard/body preservation."""
import argparse,hashlib,json,os,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--dotnet',type=Path,default=Path(os.environ.get('DOTNET','dotnet')));p.add_argument('--nativeaot',action='store_true');p.add_argument('--full-compile',action='store_true');a=p.parse_args()
stage=Path(__file__).resolve().parents[1];out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);checks=[];assertions=0
def run(name,command,env=None):
 r=subprocess.run(command,text=True,capture_output=True,env=env);(out/(name+'.log')).write_text(r.stdout+r.stderr);checks.append({'name':name,'command':command,'exitCode':r.returncode,'output':(r.stdout+r.stderr)[-6000:]})
 if r.returncode:raise RuntimeError(name+' failed: '+(r.stdout+r.stderr)[-6000:])
 return r.stdout
def require(value,message):
 global assertions
 assertions+=1
 if not value:raise AssertionError(message)
run('overlay',['python3',str(stage/'tools/prepare_touch_shortcuts.py'),'--project',str(a.project.resolve()),'--output',str(out/'overlay')])
def selected(project):
 result={}
 for element in ET.parse(project).getroot().iter('Compile'):
  value=element.get('Include')
  if not value:continue
  path=Path(value);path=path if path.is_absolute() else (project.parent/path).resolve()
  if path.name in ['ClientControlGUI.cs','ControlPatch.cs','GameOptionsMenuPatch.cs','MeetingHudPatch.cs']:result[path.name]=path
 return result
before=selected(a.project);after=selected(out/'overlay/EHR.csproj')
gui=after['ClientControlGUI.cs'].read_text();start=gui.index('        // iOS requests re-enter');end=gui.index('        bool amHost',start)
require((gui[:start]+gui[end:]).replace('        IOSTouchShortcuts.Reconcile();\n','')==before['ClientControlGUI.cs'].read_text(),'all original GUI behavior/guards must remain')
control=after['ControlPatch.cs'].read_text();original=before['ControlPatch.cs'].read_text();normalized=control.replace('            IOSTouchShortcuts.Reconcile();\n','').replace('IOSTouchShortcuts.TakeChat(IOSChatShortcut.Complete, chat) || ','').replace('(IOSTouchShortcuts.TakeChat(IOSChatShortcut.Previous, chat) || Input.GetKeyDown(KeyCode.UpArrow))','Input.GetKeyDown(KeyCode.UpArrow)').replace('(IOSTouchShortcuts.TakeChat(IOSChatShortcut.Next, chat) || Input.GetKeyDown(KeyCode.DownArrow))','Input.GetKeyDown(KeyCode.DownArrow)')
require(normalized==original,'original keyboard guards/history/effects and paste adaptation preserved')
number=after['GameOptionsMenuPatch.cs'].read_text();require(number.replace('return IOSTouchShortcuts.NumberMultiplier;','return 1;')==before['GameOptionsMenuPatch.cs'].read_text(),'all original numeric bounds/wrapping/update/sync bodies preserved')
require(number.index('KeyCode.LeftShift')<number.index('KeyCode.LeftControl')<number.index('return IOSTouchShortcuts.NumberMultiplier;'),'hardware keyboard modifier priority preserved')
require(after['MeetingHudPatch.cs']==before['MeetingHudPatch.cs'],'desktop execution/role mechanics file unchanged')
helper=(stage/'managed/IOSTouchShortcuts.cs').read_text()
effectStart='Main.PlayerStates[player.PlayerId].deathReason = PlayerState.DeathReason.Execution;'
originalMeeting=before['MeetingHudPatch.cs'].read_text();start=originalMeeting.index(effectStart);end=originalMeeting.index('__instance.CheckForEndVoting();',start)+len('__instance.CheckForEndVoting();')
startHelper=helper.index(effectStart);endHelper=helper.index('meeting.CheckForEndVoting();',startHelper)+len('meeting.CheckForEndVoting();')
normalizedEffects=helper[startHelper:endHelper].replace('Translator.GetString','GetString').replace('meeting.CheckForEndVoting','__instance.CheckForEndVoting')
require(normalizedEffects.split()==originalMeeting[start:end].split(),'new touch route must use exact original execution effects in order')
for guard in ['!OperatingSystem.IsIOS()||!GameStates.IsMeeting','client&&client.AmHost&&meeting&&meeting.playerStates!=null','area.PlayerId!=target','player&&player.Data!=null&&player.IsAlive()','state.Confirm(Id(meeting),player.PlayerId,true)','!client.AmHost||!GameStates.IsLobby||GameStates.IsCountDown||client.IsGameStarted||!menu||!menu.isActiveAndEnabled','chat&&chat.IsOpenOrOpening&&chat.freeChatField&&chat.freeChatField.textArea&&chat.freeChatField.textArea.hasFocus']:
 require(guard in helper,'required live context guard '+guard)
for forbidden in ['HighlightedFX.enabled =','.VoteForMe(','.Select(','.Confirm(','.CopyGameCode(']:
 require(forbidden not in helper or forbidden=='.Confirm(' and 'state.Confirm(' in helper and 'meeting.Confirm(' not in helper,'no synthetic/native vote selection or duplicate copy: '+forbidden)
require(helper.index('state.Confirm(Id(meeting),player.PlayerId,true)')<helper.index('Main.PlayerStates[player.PlayerId].deathReason'),'consume confirmation before effects')
require('TouchScreenKeyboard' not in helper,'reuse original keyboard synchronization, no duplicate writes')
require('SourceAccountPolicy' not in helper and 'DataManager.' not in helper,'no account/settings policy writes')

for method in ['RequestChat','TakeChat','SetNumberMultiplier','ExecutionTargets','ArmExecution','ConfirmExecution','Reconcile']:
 require('=>Gate.Run(()=>'+method+'Core(' in helper,'public touch entry must contain failures: '+method)
require('CanShowChatControls=>Gate.Run' in helper and 'CanShowSettingsSteps=>Gate.Run' in helper and 'NumberMultiplier=>Gate.Run(NumberMultiplierCore,1)' in helper,'visibility/numeric fallback gate retained')
require('catch(Exception error){Gate.Fail(error);targetName="";armed=false;return false;}' in helper,'out-parameter selector contains failure and hides stale selection')
require('ehr_ios_touch_identity_self_test_v1' in helper,'same-Id optional native probe included')
manifest=json.loads((out/'overlay/touch-shortcuts.json').read_text())
require(manifest['failureGateIncluded'] and manifest['identityProbeIncluded'] and not manifest['separateLegacyIdentityOverlayRequired'],'fresh generation must directly include current identity/failure helpers')
expectedHelpers={'IOSTouchShortcutState.cs','IOSTouchShortcuts.cs','IOSTouchShortcutSelfTest.cs','IOSTouchControlFailureGate.cs'}
require({Path(h['path']).name for h in manifest['helpers']}==expectedHelpers,'exactly four current helpers selected')

env=os.environ.copy();dotnet=str(a.dotnet)
fixture=out/'policy';fixture.mkdir()
for name in ['IOSTouchShortcutState.cs','IOSTouchShortcutSelfTest.cs']:(fixture/name).write_bytes((stage/'managed'/name).read_bytes())
(fixture/'Program.cs').write_bytes((stage/'tests/ShortcutStateFixture.cs').read_bytes())
(fixture/'Policy.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><AllowUnsafeBlocks>true</AllowUnsafeBlocks></PropertyGroup></Project>')
output=run('policy',[dotnet,'run','--project',str(fixture/'Policy.csproj'),'-c','Release'],env);policy=json.loads(next(line for line in output.splitlines() if line.startswith('{')))
native=None
if a.nativeaot:
 run('publish-own-policy',[dotnet,'publish',str(fixture/'Policy.csproj'),'-c','Release','-r','osx-arm64','-p:PublishAot=true','-o',str(fixture/'publish'),'-v:q'],env)
 output=run('own-nativeaot-policy',[str(fixture/'publish/Policy')]);native=json.loads(next(line for line in output.splitlines() if line.startswith('{')));require(native['dynamicCode'] is False,'own AOT policy must use no dynamic code')
if a.full_compile:run('full-compile',[dotnet,'build',str(out/'overlay/EHR.csproj'),'-c','Release','--nologo','-v:q','-clp:ErrorsOnly;Summary'],env)
proof={'schema':'ehr.touch-shortcuts-owned-proof.v1','sourceAssertions':assertions,'policy':policy,'nativeAotPolicy':native,'gameInvoked':False,'nativeHooksAdded':0,'checks':checks,'helpers':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in (stage/'managed').iterdir() if f.suffix=='.cs'}}
(out/'proof.json').write_text(json.dumps(proof,indent=2)+'\n');print(out/'proof.json')
