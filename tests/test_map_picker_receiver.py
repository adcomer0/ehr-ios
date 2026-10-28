import hashlib,importlib.util,json,tempfile,unittest,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_map_picker_receiver',ROOT/'tools/prepare_map_picker_receiver.py');tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
class MapPickerReceiverTests(unittest.TestCase):
 def source(self):return 'namespace Own;\n'+tool.CHANGES[0][0]+'\n{\n// BODY: original guards and actions remain byte-identical\n}\n'+tool.CHANGES[1][0]+'\n// BODY: forward original source method\n'
 def project(self,p,text=None):
  source=p/'MapPickerMenuPatch.cs';source.write_text(text if text is not None else self.source());project=p/'input.csproj';project.write_text('<Project><ItemGroup><Compile Include="MapPickerMenuPatch.cs"/><Compile Include="unrelated.cs"/><EmbeddedResource Include="data/item.png" LogicalName="Keep.Name"/></ItemGroup></Project>');return project,source
 def test_only_exact_two_reversible_anchors_change(self):
  source=self.source();adapted=tool.adapt(source);restored=adapted
  for old,new in reversed(tool.CHANGES):restored=restored.replace(new,old)
  self.assertEqual(restored,source);self.assertNotIn('GetInstance<CreateGameMapPicker>',adapted);self.assertIn('GetInstance<GameOptionsMapPicker>',adapted)
 def test_changed_anchor_rejected(self):
  for old,_ in tool.CHANGES:
   with self.subTest(anchor=old),self.assertRaisesRegex(ValueError,'anchor changed'):tool.adapt(self.source().replace(old,'drifted'))
 def test_source_pin_rejects_before_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project,_=self.project(p)
   with self.assertRaisesRegex(ValueError,'source changed'):tool.prepare(project,p/'out')
   self.assertFalse((p/'out').exists())
 def test_duplicate_source_rejected_before_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project,_=self.project(p);tree=ET.parse(project);ET.SubElement(next(tree.getroot().iter('ItemGroup')),'Compile',Include='duplicate/MapPickerMenuPatch.cs');tree.write(project)
   with self.assertRaisesRegex(ValueError,'one selected'):tool.prepare(project,p/'out')
   self.assertFalse((p/'out').exists())
 def test_relocated_project_preserves_unrelated_paths_and_metadata(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project,source=self.project(p);expected=tool.EXPECTED;tool.EXPECTED=hashlib.sha256(source.read_bytes()).hexdigest()
   try:result=tool.prepare(project,p/'out')
   finally:tool.EXPECTED=expected
   root=ET.parse(result).getroot();self.assertIn(str(p/'unrelated.cs'),[e.get('Include') for e in root.iter('Compile')]);resource=next(root.iter('EmbeddedResource'));self.assertEqual(resource.get('Include'),str(p/'data/item.png'));self.assertEqual(resource.get('LogicalName'),'Keep.Name')
   manifest=json.loads((p/'out/map-picker-receiver.json').read_text());self.assertTrue(manifest['callbackBodyAndGuardsUnchanged']);self.assertFalse(manifest['authenticationChanged']);self.assertFalse(manifest['nativeHooksChanged'])
if __name__=='__main__':unittest.main()
