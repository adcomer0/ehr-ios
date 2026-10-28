import hashlib,importlib.util,json,tempfile,unittest,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_set_color_argument',ROOT/'tools/prepare_set_color_argument.py');tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
class SetColorArgumentTests(unittest.TestCase):
 def source(self):return 'namespace Own;\npublic static void Postfix(PlayerControl receiver,byte bodyColor) { if (bodyColor == 255) return; /* preserved action */ }\n'+tool.OLD+'\n        try { Postfix(__ehrp0,__ehrp1); } finally {}\n    }\n'
 def project(self,p):
  source=p/'PlayerJoinAndLeftPatch.cs';source.write_text(self.source());project=p/'input.csproj';project.write_text('<Project><ItemGroup><Compile Include="PlayerJoinAndLeftPatch.cs"/><Compile Include="keep.cs"/><EmbeddedResource Include="images/item.png" LogicalName="Keep.Resource"/></ItemGroup></Project>');return project,source
 def test_exact_reversible_read_and_byte_body_preserved(self):
  source=self.source();result=tool.adapt(source);self.assertEqual(result.replace(tool.NEW,tool.OLD),source);self.assertIn('Postfix(PlayerControl receiver,byte bodyColor)',result);self.assertIn('if (bodyColor == 255) return;',result);self.assertIn('unchecked((byte)__ehrFrame.GetArgument<int>("bodyColor"))',result)
 def test_missing_or_duplicate_anchor_rejected(self):
  for source in [self.source().replace(tool.OLD,'drifted'),self.source()+tool.OLD]:
   with self.assertRaisesRegex(ValueError,'269 read anchor changed'):tool.adapt(source)
 def test_already_adapted_rejected(self):
  with self.assertRaises(ValueError):tool.adapt(tool.adapt(self.source()))
 def test_source_pin_fails_before_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project,_=self.project(p)
   with self.assertRaisesRegex(ValueError,'source pin changed'):tool.prepare(project,p/'out')
   self.assertFalse((p/'out').exists())
 def test_duplicate_source_rejected_before_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project,_=self.project(p);tree=ET.parse(project);ET.SubElement(next(tree.getroot().iter('ItemGroup')),'Compile',Include='elsewhere/PlayerJoinAndLeftPatch.cs');tree.write(project)
   with self.assertRaisesRegex(ValueError,'one selected'):tool.prepare(project,p/'out')
   self.assertFalse((p/'out').exists())
 def test_unrelated_relative_inputs_and_resource_names_preserved(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();project,source=self.project(p);expected=tool.EXPECTED;tool.EXPECTED=hashlib.sha256(source.read_bytes()).hexdigest()
   try:result=tool.prepare(project,p/'out')
   finally:tool.EXPECTED=expected
   root=ET.parse(result).getroot();self.assertIn(str(p/'keep.cs'),[x.get('Include') for x in root.iter('Compile')]);resource=next(root.iter('EmbeddedResource'));self.assertEqual(resource.get('Include'),str(p/'images/item.png'));self.assertEqual(resource.get('LogicalName'),'Keep.Resource');manifest=json.loads((p/'out/set-color-argument.json').read_text());self.assertFalse(manifest['authenticationChanged']);self.assertTrue(manifest['sentinel255Preserved']);self.assertTrue(manifest['sourceByteCallbackBodyUnchanged'])
if __name__=='__main__':unittest.main()
