#!/usr/bin/env python3
"""Apply only scene-carrier ownership after the UIKit source renderer overlay."""
from pathlib import Path
import argparse,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();s=a.input.read_text();original=s
old='SceneManager.add_sceneLoaded((Action<Scene, LoadSceneMode>)OnSceneLoaded);'
new='_ehrSceneCallback = EHR.Generated.SourceSceneEvents.Own(this, OnSceneLoaded, GUI.Hide);'
if s.count(old)!=1 or s.count('SceneManager.remove_sceneLoaded((Action<Scene, LoadSceneMode>)OnSceneLoaded);')!=1:raise ValueError('expected exact pinned IL2CPP scene anchors')
if 'using GUI = EHR.Generated.TouchGUI;' not in s or 'GUI.Hide();' not in s:raise ValueError('apply after explicit UIKit renderer source overlay')
s=s.replace(old,new).replace('SceneManager.remove_sceneLoaded((Action<Scene, LoadSceneMode>)OnSceneLoaded);','// Native owner scope removes this exact carrier, closes callbacks, and releases its root.')
anchor='    private Camera _cam;'
if s.count(anchor)!=1:raise ValueError('source component field anchor changed')
s=s.replace(anchor,anchor+'\n#if IL2CPP\n    private EHR.Generated.UnityEngine_Events_UnityAction<Scene, LoadSceneMode>? _ehrSceneCallback;\n#endif')
# Business actions and shortcut semantics remain byte-identical to input.
marker='    private void DrawButtons(ref float y, float w)'
if s[s.index(marker):]!=original[original.index(marker):]:raise ValueError('game action body changed')
a.output.parent.mkdir(parents=True,exist_ok=True)
if a.output.exists():raise ValueError('fresh output required')
a.output.write_text(s)
report={'schema':'ehr.gui-scene-lifetime-overlay.v1','input':str(a.input),'input_sha256':hashlib.sha256(original.encode()).hexdigest(),'output_sha256':hashlib.sha256(s.encode()).hexdigest(),'drawButtonsAndRestUnchanged':True,'existingUIKitOnDestroyHidePreserved':True,'exactNativeCarrierOwnedBySourceStateScope':True,'sourceFieldsAdded':['_ehrSceneCallback'],'SceneManagerMembersFabricated':False}
a.output.with_suffix('.ownership.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
