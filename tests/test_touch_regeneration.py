import ast, hashlib, importlib.util, json, tempfile, unittest, xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_touch_shortcuts',ROOT/'tools/prepare_touch_shortcuts.py');tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
class TouchRegenerationTests(unittest.TestCase):
 def fixture(self,p):
  # Own source-shaped text tests only. No Unity/game engine emulation.
  content={'ClientControlGUI.cs':'        ReconcileIOSNoClip();\n        bool amHost     = AmongUsClient.Instance && AmongUsClient.Instance.AmHost;\n',
   'ControlPatch.cs':'            bool isMeeting = GameStates.IsMeeting;\nif (Input.GetKeyDown(KeyCode.Tab)) TextBoxPatch.OnTabPress(chat);\nif (Input.GetKeyDown(KeyCode.UpArrow) && ChatCommands.ChatHistory.Count > 0)\nif (Input.GetKeyDown(KeyCode.DownArrow) && ChatCommands.ChatHistory.Count > 0)\n',
   'GameOptionsMenuPatch.cs':'            if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)) return 5;\n            if (Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl)) return 10;\n            return 1;'}
  for node in ast.walk(ast.parse((ROOT/'tools/prepare_touch_shortcuts.py').read_text())):
   if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='effects' for t in node.targets):content['MeetingHudPatch.cs']=ast.literal_eval(node.value)
  root=ET.Element('Project');group=ET.SubElement(root,'ItemGroup')
  for name,text in content.items():(p/name).write_text(text);ET.SubElement(group,'Compile',Include=name)
  ET.SubElement(group,'EmbeddedResource',Include='data/resource.txt',LogicalName='Preserve.Resource.Name');ET.SubElement(group,'Compile',Include='unrelated.cs')
  reference=ET.SubElement(group,'Reference',Include='Preserve.Assembly');ET.SubElement(reference,'HintPath').text='lib/original.dll'
  project=p/'input.csproj';ET.ElementTree(root).write(project);return project
 def test_exact_four_current_helpers_and_manifest(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project=self.fixture(p);manifest=json.loads(tool.prepare(project,p/'out').read_text());selected=ET.parse(p/'out/EHR.csproj').getroot()
   helpers={Path(e.get('Include','')).name:e.get('Include') for e in selected.iter('Compile') if Path(e.get('Include','')).name in tool.HELPER_NAMES}
   self.assertEqual(set(helpers),set(tool.HELPER_NAMES));self.assertEqual(len(manifest['helpers']),4)
   for name,path in helpers.items():self.assertEqual(Path(path).read_bytes(),(ROOT/'managed'/name).read_bytes())
   self.assertTrue(manifest['failureGateIncluded']);self.assertTrue(manifest['identityProbeIncluded']);self.assertFalse(manifest['separateLegacyIdentityOverlayRequired'])
 def test_reject_every_preselected_helper_before_output(self):
  for name in tool.HELPER_NAMES:
   with self.subTest(name=name),tempfile.TemporaryDirectory() as temp:
    p=Path(temp).resolve();project=self.fixture(p);tree=ET.parse(project);ET.SubElement(next(tree.getroot().iter('ItemGroup')),'Compile',Include='elsewhere/'+name);tree.write(project)
    with self.assertRaisesRegex(ValueError,'helper already selected'):tool.prepare(project,p/'out')
    self.assertFalse((p/'out').exists())
 def test_second_apply_rejected_before_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project=self.fixture(p);tool.prepare(project,p/'out')
   with self.assertRaisesRegex(ValueError,'helper already selected'):tool.prepare(p/'out/EHR.csproj',p/'again')
   self.assertFalse((p/'again').exists())
 def test_unrelated_relative_paths_and_resource_names_preserved(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project=self.fixture(p);tool.prepare(project,p/'out');root=ET.parse(p/'out/EHR.csproj').getroot()
   resource=next(root.iter('EmbeddedResource'));self.assertEqual(resource.get('Include'),str(p/'data/resource.txt'));self.assertEqual(resource.get('LogicalName'),'Preserve.Resource.Name')
   self.assertIn(str(p/'unrelated.cs'),[e.get('Include') for e in root.iter('Compile')]);self.assertEqual(next(root.iter('HintPath')).text,str(p/'lib/original.dll'))
 def test_duplicate_original_source_rejected_before_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project=self.fixture(p);tree=ET.parse(project);ET.SubElement(next(tree.getroot().iter('ItemGroup')),'Compile',Include='elsewhere/ControlPatch.cs');tree.write(project)
   with self.assertRaisesRegex(ValueError,'ambiguous selected'):tool.prepare(project,p/'out')
   self.assertFalse((p/'out').exists())
if __name__=='__main__':unittest.main()
