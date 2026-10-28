"""Own metadata declarations and overlay insertion; no proprietary fixture input."""
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

ROOT=pathlib.Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('public_value_overlay',ROOT/'tools/generate_public_value_abi_overlay.py')
MODULE=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(MODULE)


class Metadata:
 def __init__(self):
  self.names=['Own.Packet','Own.Nested','System.Int32','System.String']
  self.types=[]
  for start,count,value in ((0,2,1),(2,1,1),(3,1,1),(4,0,0)):
   row=[0]*26;row[7]=0x100109;row[8]=start;row[18]=count;row[24]=value;self.types.append(row)
  self.fields=[(0,1,0),(1,3,0),(2,2,0),(3,2,0)]
  self.strings=['nested','label','count','m_value']
 def type_name(self,index):return self.names[index]
 def image_for_type(self,index):return {'name':'Own.dll'}
 def record(self,table,stride,index,fmt):
  assert (table,stride,fmt)==('fields',12,'<IiI')
  return self.fields[index]
 def string(self,index):return self.strings[index]


class Names:
 def __init__(self,metadata):self.metadata=metadata
 def at_index(self,index):return self.metadata.names[index]


class DeclarationTests(unittest.TestCase):
 def test_recursive_values_reference_fields_and_scalar_self(self):
  metadata=Metadata()
  with patch.object(MODULE,'ROOT_TYPES',('Own.Packet',)):
   result=MODULE.declared_value_types(metadata,Names(metadata))
  self.assertEqual(set(result),{'Own.Packet','Own.Nested','System.Int32'})
  self.assertEqual(result['Own.Packet']['fields'],[{'name':'nested','type':'Own.Nested'},{'name':'label','type':'System.String'}])
  self.assertEqual(result['Own.Nested']['layout_mask'],8)
  self.assertEqual(result['System.Int32']['fields'][0]['type'],'System.Int32')

 def test_ambiguous_value_type_rejected(self):
  metadata=Metadata();metadata.names.append('Own.Packet');metadata.types.append(metadata.types[0])
  with patch.object(MODULE,'ROOT_TYPES',('Own.Packet',)),self.assertRaisesRegex(MODULE.ParseError,'ambiguous'):
   MODULE.declared_value_types(metadata,Names(metadata))

 def test_reference_root_rejected(self):
  metadata=Metadata()
  with patch.object(MODULE,'ROOT_TYPES',('System.String',)),self.assertRaisesRegex(MODULE.ParseError,'Expected metadata value type'):
   MODULE.declared_value_types(metadata,Names(metadata))

 def test_unresolved_field_rejected(self):
  metadata=Metadata();metadata.names[3]='unresolved_il2cpp_kind:99'
  with patch.object(MODULE,'ROOT_TYPES',('Own.Packet',)),self.assertRaisesRegex(MODULE.ParseError,'Unresolved'):
   MODULE.declared_value_types(metadata,Names(metadata))


class OverlayTests(unittest.TestCase):
 BASE='''// Existing source component tests remain intact.
@interface NativeRuntimeTests : XCTestCase
@end
void own_test() {
    NSDictionary *gateway = exerciseGateway();
    NSDictionary *proof = @{
        @"runtimeGateway": gateway,
    };
}
'''
 def test_preserves_base_tests_and_adds_one_observation(self):
  output=MODULE.inject(self.BASE,{'requestedTypes':[]},'NSDictionary *exercisePublicValueABIFacts(const char *s);')
  self.assertIn('// Existing source component tests remain intact.',output)
  self.assertEqual(output.count('NSDictionary *valueABIFacts = exercisePublicValueABIFacts'),1)
  self.assertEqual(output.count('@"publicValueABIFacts": valueABIFacts'),1)
  self.assertIn('XCTAssertTrue([valueABIFacts[@"success"] boolValue]',output)

 def test_rejects_missing_duplicated_or_existing_overlay(self):
  for base in (self.BASE.replace('@interface NativeRuntimeTests : XCTestCase',''),self.BASE+self.BASE,self.BASE+'exercisePublicValueABIFacts('):
   with self.subTest(base=base),self.assertRaises(MODULE.ParseError):MODULE.inject(base,{},'')

 def test_requires_ready_runtime_and_proof_anchors(self):
  for fragment in ('    NSDictionary *gateway = exerciseGateway();','        @"runtimeGateway": gateway,'):
   with self.subTest(fragment=fragment),self.assertRaises(MODULE.ParseError):MODULE.inject(self.BASE.replace(fragment,''),{},'')


if __name__=='__main__':unittest.main()
