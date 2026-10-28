#!/usr/bin/env python3
"""Preserve an explicitly touch-opened role panel on iOS, with phase guards kept."""
from pathlib import Path
import argparse,hashlib,json,xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
(out/'source').mkdir(parents=True);tree=ET.parse(a.project);found=[]
for item in tree.getroot().iter():
 value=item.get('Include')
 if item.tag.split('}')[-1]!='Compile' or not value:continue
 path=Path(value);path=path if path.is_absolute() else a.project.parent/path
 if path.name!='ControlPatch.cs':continue
 found.append(path);s=path.read_text();before=s
 old='''                else
                    InGameRoleInfoMenu.Hide();
            }
            else
                InGameRoleInfoMenu.Hide();'''
 new='''                else if (!OperatingSystem.IsIOS())
                    InGameRoleInfoMenu.Hide();
            }
            else
                InGameRoleInfoMenu.Hide();'''
 if s.count(old)!=1:raise ValueError('pinned held-key role-display guard changed')
 s=s.replace(old,new)
 colliderOld='(!AmongUsClient.Instance.IsGameStarted || !GameStates.IsOnlineGame) && PlayerControl.LocalPlayer.CanMove;'
 colliderNew='(!AmongUsClient.Instance.IsGameStarted || !GameStates.IsOnlineGame) && PlayerControl.LocalPlayer.CanMove &&\n                        (!OperatingSystem.IsIOS() || (Main.IntroDestroyed && (!GameStartManager.Instance || GameStartManager.Instance.startState == GameStartManager.StartingStates.NotStarting)));'
 if s.count(colliderOld)!=1:raise ValueError('pinned desktop collider predicate changed')
 s=s.replace(colliderOld,colliderNew);target=out/'source/ControlPatch.cs';target.write_text(s);item.set('Include',str(target))
 if s.replace(new,old).replace(colliderNew,colliderOld)!=before:raise ValueError('non-mobile-input mutation')
 record={'input':str(path),'input_sha256':hashlib.sha256(before.encode()).hexdigest(),'output_sha256':hashlib.sha256(s.encode()).hexdigest()}
if len(found)!=1:raise ValueError('expected one compiled ControlPatch')
for item in tree.getroot().iter():
 for key in ['Include','Project']:
  value=item.get(key)
  if value and not value.startswith('/') and '$(' not in value and '*' not in value and item.tag.split('}')[-1] in {'Compile','EmbeddedResource','Import'}:item.set(key,str((a.project.parent/value).resolve()))
tree.write(out/'EHR.csproj',encoding='unicode');(out/'role-input-overlay.json').write_text(json.dumps({'schema':'ehr.ios-role-info-touch-persistence.v1',**record,'initialRoleAccessGuardsUnchanged':True,'outsideGameOrMovementPhaseStillHides':True,'neverOpensWithoutExistingOriginalTrigger':True,'iOSKeyboardColliderTightenedToOriginalTouchIntroCountdownGuards':True,'desktopAndAndroidBehaviorUnchanged':True,'actualGameplayVerified':False},indent=2)+'\n');print(out/'EHR.csproj')
