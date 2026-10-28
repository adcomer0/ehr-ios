from __future__ import annotations
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
# Stage-only tests reuse canonical read-only parsers, never load a game image.
sys.path.insert(1,str(ROOT/'tools'))
from generate_native_thunk_plans import ABIModel,plan_one,ParseError


def named(i,name):return {'id':i,'kind':'named','canonical':name}


class ABIPlans(unittest.TestCase):
 def model(self,extra=(),definitions=None,layouts=None):
  shapes=[named(0,'System.Boolean'),named(1,'System.Int32'),named(2,'System.Void'),named(3,'Own.Object'),*extra]
  defs={'Own.Object':{'is_value_type':False},**(definitions or{})}
  return ABIModel(shapes,defs,layouts)
 def test_exact_scalar_boolean_and_enum(self):
  model=self.model([named(4,'Own.ByteEnum')],{'Own.ByteEnum':{'is_value_type':True,'enum_underlying':'System.Byte'}})
  self.assertEqual(model.abi(0)['size'],1);self.assertEqual(model.abi(0)['cpp'],'bool')
  self.assertIn('managed_boolean_one_byte_normalized_0_or_1',model.abi(0)['gates'])
  self.assertEqual(model.abi(4)['cpp'],'uint8_t');self.assertEqual(model.abi(4)['size'],1)
 def test_reference_ref_out_explicitly_blocked(self):
  model=self.model([{'id':4,'kind':'byref','canonical':'Own.Object&','element':3}])
  self.assertIn('reference_ref_out_gateway_unsupported',model.abi(4)['blocked'])
 def test_unknown_value_layout_not_guessed(self):
  model=self.model([named(4,'Own.Value')],{'Own.Value':{'is_value_type':True}})
  self.assertIsNone(model.abi(4)['cpp']);self.assertEqual(model.abi(4)['blocked'],['live_value_layout_missing'])
 def test_hfa_is_recursive_exact_and_mixed_blocked(self):
  layout={'evidence_kind':'observed_public_api','value_size':8,'alignment':4,'contains_references':False,'blittable':True,'fields':[{'type':'System.Single','value_offset':0},{'type':'System.Single','value_offset':4}]}
  pair={'evidence_kind':'observed_public_api','value_size':16,'alignment':4,'contains_references':False,'blittable':True,'fields':[{'type':'Own.Vec2','value_offset':0},{'type':'Own.Vec2','value_offset':8}]}
  model=self.model([named(4,'Own.Vec2'),named(5,'Own.Pair')],{'Own.Vec2':{'is_value_type':True},'Own.Pair':{'is_value_type':True}}, {'Own.Vec2':layout,'Own.Pair':pair})
  result=model.abi(5);self.assertEqual(result['abi'],'hfa');self.assertEqual(result['layout']['homogeneous_count'],4)
  layout['contains_references']=True;self.assertIn('reference_flags_disagree_with_observed_fields',model.abi(4)['blocked'])
 def test_overlapping_and_large_aggregate_require_separate_proof(self):
  value={'evidence_kind':'observed_public_api','value_size':32,'alignment':8,'contains_references':False,'blittable':True,'fields':[{'type':'System.Int64','value_offset':0},{'type':'System.Int64','value_offset':8},{'type':'System.Int64','value_offset':16},{'type':'System.Int64','value_offset':24}]}
  model=self.model([named(4,'Own.Large')],{'Own.Large':{'is_value_type':True}},{'Own.Large':value})
  self.assertEqual(model.abi(4)['abi'],'indirect_aggregate');self.assertIn('sret_output_needs_separate_proof',model.abi(4,'return')['blocked'])
  value['fields'][1]['value_offset']=0;self.assertIn('overlapping_value_fields_unsupported',model.abi(4)['blocked'])
 def test_reference_containing_aggregate_only_native_boxed_input(self):
  value={'evidence_kind':'observed_public_api','value_size':24,'alignment':8,'contains_references':True,'blittable':False,'fields':[{'type':'Own.Object','value_offset':0,'is_value_type':False},{'type':'System.Int64','value_offset':8},{'type':'System.Int64','value_offset':16}]}
  model=self.model([named(4,'Own.Mixed'),{'id':5,'kind':'byref','canonical':'Own.Mixed&','element':4}],{'Own.Mixed':{'is_value_type':True}},{'Own.Mixed':value})
  argument=model.abi(4);self.assertEqual(argument['abi'],'indirect_aggregate');self.assertEqual(argument['blocked'],[]);self.assertIn('no_reference_payload_in_CLR_buffers',argument['gates'])
  self.assertIn('reference_containing_value_output_unsupported',model.abi(4,'return')['blocked']);self.assertIn('reference_containing_value_output_unsupported',model.abi(5)['blocked'])
 def test_coroutine_body_overrides_factory_clr_type(self):
  model=self.model();selector={'selectorId':'own','methodKind':'CoroutineMoveNext'}
  source={'instanceType':'Own.Factory','returnType':'IEnumerator','parameterTypes':[],'parameterRefKinds':[]}
  method={'declaring_type':3,'parameter_types':[],'return_type':0,'is_static':False,'canonical_signature':'bool Own.State::MoveNext()','expected_rva':'0x1000','offline_metadata_token':'0x6000001'}
  result=plan_one(selector,source,method,model,[])
  self.assertEqual(result['source_binding']['instance_type'],'global::Il2CppSystem.Object');self.assertEqual(result['source_binding']['result_type'],'bool')
  self.assertFalse(result['runtime_available']);self.assertTrue(result['hidden_context']['null_permitted']);self.assertFalse(result['hidden_context']['dereference_permitted'])
 def test_out_does_not_read_caller_storage_and_field_binding_blocks(self):
  model=self.model([{'id':4,'kind':'byref','canonical':'System.Int32&','element':1}]);selector={'selectorId':'own','methodKind':'Normal'}
  source={'instanceType':None,'returnType':'void','parameterTypes':['int'],'parameterRefKinds':['Out']}
  method={'declaring_type':3,'parameter_types':[4],'return_type':2,'is_static':True,'canonical_signature':'void Own.Foo(out int)','expected_rva':'0x1000','offline_metadata_token':'0x6000001'}
  result=plan_one(selector,source,method,model,[{'id':'callback','requiredBindings':['___field:int:ref']}])
  self.assertFalse(result['arguments'][0]['read_native_input']);self.assertTrue(result['arguments'][0]['write_native_output']);self.assertIn('instance_field_snapshot_dirty_flush_not_implemented',result['blocking_requirements'])
  source['parameterRefKinds']=['None']
  with self.assertRaises(ParseError):plan_one(selector,source,method,model,[])

if __name__=='__main__':unittest.main()
