#!/usr/bin/env python3
"""Read-only exact native thunk ABI plans; never emits executable availability.

Binding facts/selector/source-type contents stay in a private outside-Git output.
No game bytes, native execution, patching or guessing aggregate layouts.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
import mmap
from pathlib import Path
import re

from map_native_methods import MachO, ParseError, digest, find_module, find_registrations
from map_harmony_native_targets import NestedMetadata, TypeCatalog, ExactTypeNames

SCALARS = {
 'System.Boolean':('bool',1,1),'System.Char':('uint16_t',2,2),
 'System.SByte':('int8_t',1,1),'System.Byte':('uint8_t',1,1),
 'System.Int16':('int16_t',2,2),'System.UInt16':('uint16_t',2,2),
 'System.Int32':('int32_t',4,4),'System.UInt32':('uint32_t',4,4),
 'System.Int64':('int64_t',8,8),'System.UInt64':('uint64_t',8,8),
 'System.Single':('float',4,4),'System.Double':('double',8,8),
 'System.IntPtr':('intptr_t',8,8),'System.UIntPtr':('uintptr_t',8,8),
}


class ABIModel:
 def __init__(self, shapes, definitions, layouts=None):
  self.shapes={s['id']:s for s in shapes};self.definitions=definitions;self.layouts=layouts or {}
  if len(self.shapes)!=len(shapes):raise ParseError('Duplicate type shape IDs')
 def shape(self,index):
  if index not in self.shapes:raise ParseError('Missing exact type shape')
  return self.shapes[index]
 def definition(self,shape):
  if shape['kind']=='generic':shape=self.shape(shape['definition'])
  if shape['kind']!='named' or shape['canonical'] not in self.definitions:raise ParseError('Missing exact metadata definition')
  item=self.definitions.get('#'+str(shape.get('metadata_type_index')),self.definitions[shape['canonical']])
  if item.get('ambiguous')or item.get('canonical',shape['canonical'])!=shape['canonical']:raise ParseError('Ambiguous/mismatched exact metadata definition')
  return item
 def aggregate(self,name,stack=()):
  if name in stack or len(stack)>16:raise ParseError('Recursive/excessively deep value layout')
  value=self.layouts.get(name)
  if not value:return None,'live_value_layout_missing'
  if value.get('evidence_kind')!='observed_public_api':return None,'layout_is_not_observed_public_api'
  size,alignment=value.get('value_size'),value.get('alignment')
  if type(size)is not int or type(alignment)is not int or size<=0 or size>1048576 or alignment not in (1,2,4,8):return None,'value_size_or_alignment_unsupported'
  if value.get('metadata_declaration_matches')is False:return None,'runtime_metadata_declarations_differ'
  references=value.get('contains_references');blittable=value.get('blittable')
  if type(references)is not bool or type(blittable)is not bool:return None,'value_reference_flags_missing'
  if not references and not blittable:return None,'mixed_or_nonblittable_value_unsupported'
  fields=value.get('fields')
  if not isinstance(fields,list) or not fields:return None,'value_field_layout_missing'
  atoms=[];ranges=[];members=[];observed_references=False
  for field in fields:
   if field.get('is_static'):continue
   field_type=field.get('type');offset=field.get('value_offset')
   if type(offset)is not int or offset<0:return None,'field_value_offset_missing'
   if field_type in SCALARS:
    cpp,width,align=SCALARS[field_type];parts=[(offset,cpp,width)]
   elif field.get('is_value_type')is False or self.definitions.get(field_type,{}).get('is_value_type')is False:
    cpp,width,align='void *',8,8;parts=[(offset,cpp,width)];observed_references=True
   else:
    definition=self.definitions.get(field_type,{})
    underlying=definition.get('enum_underlying')
    if underlying in SCALARS:
     cpp,width,align=SCALARS[underlying];parts=[(offset,cpp,width)]
    else:
     nested,reason=self.aggregate(field_type,(*stack,name))
     if not nested:return None,reason
     cpp='ehr_value_'+hashlib.sha256(field_type.encode()).hexdigest()[:16]
     width,align=nested['size'],nested['alignment'];parts=[(offset+p[0],p[1],p[2]) for p in nested['atoms']];observed_references|=nested['contains_references']
   if offset%align or offset+width>size:return None,'field_alignment_or_bounds_mismatch'
   if any(offset<end and begin<offset+width for begin,end in ranges):return None,'overlapping_value_fields_unsupported'
   ranges.append((offset,offset+width));atoms.extend(parts);members.append({'cpp':cpp,'type':field_type,'offset':offset,'size':width,'alignment':align})
  if not atoms:return None,'value_has_no_instance_fields'
  if observed_references!=references:return None,'reference_flags_disagree_with_observed_fields'
  atoms.sort();floating=atoms[0][1]
  hfa=floating in ('float','double') and 1<=len(atoms)<=4 and all(cpp==floating for _,cpp,_ in atoms) and all(offset==i*atoms[0][2] for i,(offset,_,_) in enumerate(atoms)) and size==len(atoms)*atoms[0][2]
  return {'size':size,'alignment':alignment,'atoms':atoms,'fields':members,'contains_references':references,'blittable':blittable,'kind':'hfa' if hfa else 'indirect_aggregate' if size>16 else 'gpr_aggregate','homogeneous_count':len(atoms)if hfa else 0,'homogeneous_scalar':floating if hfa else None},None
 def abi(self,index,role='argument'):
  shape=self.shape(index);name=shape['canonical'];kind=shape['kind']
  base={'canonical':name,'gates':[],'blocked':[]}
  if kind=='byref':
   element=self.abi(shape['element'],'byref_element');base.update(cpp='void *',abi='byref_pointer',element=element)
   if element.get('abi')=='gpr_reference':base['blocked'].append('reference_ref_out_gateway_unsupported')
   base['gates']+=['exact_public_byref_element_class','public_parameter_out_attribute','nonoverlap_bounded_copyback_buffers','copyback_before_native_rethrow']
   base['blocked']+=element['blocked'];return base
  if kind=='vector':base.update(cpp='void *',abi='gpr_reference');base['gates']+=['exact_runtime_vector_class','borrowed_object_promoted_to_owned_root'];return base
  if kind not in ('named','generic'):raise ParseError('Unsupported exact type shape')
  if name=='System.Void':
   base.update(cpp='void',abi='void')
   if role!='return':base['blocked'].append('void_is_not_an_argument')
   return base
  if name in SCALARS:
   cpp,size,alignment=SCALARS[name];base.update(cpp=cpp,abi='fp_scalar'if cpp in('float','double')else'gpr_scalar',size=size,alignment=alignment)
   base['gates']+=['public_value_size_alignment_exact','public_reference_free_blittable']
   if name=='System.Boolean':base['gates'].append('managed_boolean_one_byte_normalized_0_or_1')
   return base
  definition=self.definition(shape)
  if not definition['is_value_type']:base.update(cpp='void *',abi='gpr_reference');base['gates']+=['exact_public_reference_class','borrowed_object_promoted_to_owned_root'];return base
  underlying=definition.get('enum_underlying')
  if underlying:
   if underlying not in SCALARS:raise ParseError('Unknown enum underlying type')
   cpp,size,alignment=SCALARS[underlying];base.update(cpp=cpp,abi='gpr_enum',size=size,alignment=alignment,enum_underlying=underlying)
   base['gates']+=['public_enum_basetype_exact','public_value_size_alignment_exact'];return base
  aggregate,reason=self.aggregate(name)
  if aggregate:
   base.update(cpp='ehr_value_'+hashlib.sha256(name.encode()).hexdigest()[:16],abi=aggregate['kind'],layout=aggregate)
   base['gates']+=['recheck_observed_public_value_layout','compiler_size_alignment_offset_static_asserts','own_ARM64_call_fixture','actual_exact_target_entry_execution']
   if aggregate['contains_references']:
    base['gates']+=['native_frame_payload_only_public_value_box','owned_root_before_NativeAOT_entry','no_reference_payload_in_CLR_buffers']
    if role!='argument':base['blocked'].append('reference_containing_value_output_unsupported')
   if role=='return'and aggregate['kind']=='indirect_aggregate':base['blocked'].append('sret_output_needs_separate_proof')
  else:base.update(cpp=None,abi='value_aggregate_unproven');base['blocked'].append(reason)
  if role=='receiver':base['blocked'].append('mutable_value_receiver_output_missing_from_dispatch_ABI')
  return base


def metadata_definitions(native,metadata):
 module=find_module(native,metadata,'Assembly-CSharp.dll');registrations,_,_=find_registrations(native,metadata,module)
 if len(registrations)!=1:raise ParseError('Metadata registration not unique')
 names=ExactTypeNames(native,metadata,registrations[0],TypeCatalog(metadata));names.validate_nested();result={}
 for index,row in enumerate(metadata.types):
  name=metadata.type_name(index)
  item={'canonical':name,'is_value_type':bool(row[24]&1),'is_enum':bool(row[24]&2),'metadata_type_index':index}
  if item['is_enum']:
   underlying=[]
   for field_index in range(row[8],row[8]+row[18]):
    field=metadata.record('fields',12,field_index,'<IiI')
    if metadata.string(field[0])=='value__':underlying.append(names.at_index(field[1]))
   if len(underlying)!=1:raise ParseError('Enum lacks unique value__ metadata')
   item['enum_underlying']=underlying[0]
  result['#'+str(index)]=item
  result[name]=item if name not in result else {'ambiguous':True}
 return result


def plan_one(selector,source,method,model,callbacks,source_owner_evidence=None):
 coroutine=selector['methodKind']=='CoroutineMoveNext'
 owner=model.abi(method['declaring_type'],'receiver')if not method['is_static']else None
 arguments=[model.abi(i)for i in method['parameter_types']];returns=model.abi(method['return_type'],'return')
 if len(source['parameterTypes'])!=len(arguments)and not coroutine:raise ParseError('Source/native parameter arity mismatch')
 fields=[]
 for row in callbacks:
  for binding in row.get('requiredBindings',[]):
   name=binding.split(':',1)[0]
   if name.startswith('___'):fields.append({'name':name[3:],'callback_id':row['id'],'writable':binding.endswith((':ref',':out'))})
 blocked=[reason for value in ([owner]if owner else[])+arguments+[returns]for reason in value['blocked']]
 if fields:blocked.append('instance_field_snapshot_dirty_flush_not_implemented')
 source_ref=source['parameterRefKinds']if not coroutine else[]
 for index,argument in enumerate(arguments):
  byref=argument['abi']=='byref_pointer'
  if byref!=(source_ref[index]in('Ref','Out','In')):raise ParseError('Source/native reference qualifier mismatch')
  argument['source_ref_kind']=source_ref[index];argument['read_native_input']=source_ref[index]!='Out';argument['write_native_output']=byref and source_ref[index]!='In'
 if coroutine:
  if not source_owner_evidence:blocked.append('source_state_machine_wrapper_actual_owner_fields_unproven')
  source_binding={'instance_type':'global::Il2CppSystem.Object','result_type':'bool','parameter_types':[],'factory_types_ignored':source}
 else:source_binding={'instance_type':source['instanceType'],'result_type':source['returnType'],'parameter_types':source['parameterTypes']}
 return {'selector_id':selector['selectorId'],'native_signature':method['canonical_signature'],'expected_rva':method['expected_rva'],
  'metadata_token':method['offline_metadata_token'],'owner':owner,'arguments':arguments,'result':returns,'source_binding':source_binding,'instance_fields':fields,
  'hidden_context':{'cpp':'const void *','position':'last_declared_parameter','preserve_bits':True,'null_permitted':True,'dereference_permitted':False,'gate':'pinned_generated_method_ABI_and_own_actual_target_thunk_proof'},
  'original_route':{'id_allocation':'must preserve pre-existing built-in target IDs; no method aliases','exact_method_and_RVA_required':True,'exception_copybacks_before_raise':True,'fallback_after_original_entry_forbidden':True},
  'blocking_requirements':sorted(set(blocked)),
  'remaining_live_gates':['exact_method_to_native_association','all_type_metadata_and_value_checks','pre_sign_relocation_and_shared_entry_policy','main_thread_or_explicit_original_only_policy','per_dispatch_original_body_entered_outcome','native_exception_rethrow_after_NativeAOT_return'],
  'source_owner_adapter_evidence':source_owner_evidence if coroutine else None,
  'runtime_available':False,'thunk_emitted':False}


def main(argv=None):
 p=argparse.ArgumentParser(description=__doc__)
 for arg in('selectors','source-types','dispatcher-audit','framework','metadata','output'):p.add_argument('--'+arg,type=Path,required=True)
 p.add_argument('--binding-facts',type=Path,action='append',required=True);p.add_argument('--type-layouts',type=Path);p.add_argument('--source-owner-proof',type=Path)
 args=p.parse_args(argv);output=args.output.resolve()
 if output.exists()or any((parent/'.git').exists()for parent in(output.parent,*output.parents)):p.error('Output must be a new private outside-Git file')
 selectors=json.loads(args.selectors.read_text());sources=json.loads(args.source_types.read_text());audit=json.loads(args.dispatcher_audit.read_text())
 if selectors.get('schema')!='ehr.native-target-selectors.v1'or sources.get('schema')!='ehr.source-patch-clr-types.v1':raise ParseError('Unexpected selector/source type schema')
 if selectors['upstreamCommit']!=sources['upstreamCommit']or selectors['compileProfile']!=sources['compileProfile']:raise ParseError('Source selectors do not share the same pinned build')
 source_map={s['selectorId']:s for s in sources['selectors']};callback_map={r['id']:r for r in audit['rows']}
 if len(source_map)!=len(sources['selectors'])or len(callback_map)!=len(audit['rows']):raise ParseError('Duplicate source/callback identity')
 documents=[json.loads(path.read_text())for path in args.binding_facts]
 source_owner_evidence=None
 if args.source_owner_proof:
  proof=json.loads(args.source_owner_proof.read_text());owner=proof.get('managedSourceReuse',{}).get('liveFacades',{}).get('nativeStateMachines',{})
  if owner.get('status')!=0 or any(owner.get(key)!=1 for key in('pass','unmappedOwnerRejected','independentFieldWrites','realInitialStates','wrongIteratorRejected','nullNativeOwners'))or owner.get('factoriesOrMoveNextInvoked')is not False:raise ParseError('Source owner adapter proof is missing or failed')
  source_owner_evidence={'evidence_kind':'actual_isolated_source_owner_adapter','proof_sha256':digest(args.source_owner_proof),'factories_or_move_next_invoked':False,'iterator_scheduling_lifetime_proven':False}
 with args.framework.open('rb')as nf,args.metadata.open('rb')as mf:
  with mmap.mmap(nf.fileno(),0,access=mmap.ACCESS_READ)as nd,mmap.mmap(mf.fileno(),0,access=mmap.ACCESS_READ)as md:
   native,metadata=MachO(nd),NestedMetadata(md);definitions=metadata_definitions(native,metadata)
   pins={'framework_sha256':digest(args.framework),'metadata_sha256':digest(args.metadata),'framework_uuid':native.uuid}
   found={};models=[]
   layouts={}
   if args.type_layouts:
    value=json.loads(args.type_layouts.read_text());value=value.get('publicValueABIFacts',value)
    if value.get('schema')!='ehr.native-abi-layout-facts.v1'or any(value.get(k)!=v for k,v in pins.items()):raise ParseError('Public layout facts have different image pins')
    if value.get('success')is not True or value.get('failures'):raise ParseError('Public layout observation did not succeed')
    layouts=value['types']
   for document in documents:
    if document.get('schema')!='ehr.runtime-binding-audit-facts.v1'or document['framework_uuid']!=native.uuid or document['input_pins']['framework']['sha256']!=pins['framework_sha256']or document['input_pins']['metadata']['sha256']!=pins['metadata_sha256']:raise ParseError('Binding facts image pins differ')
    model=ABIModel(document['types'],definitions,layouts);models.append(model)
    for method in document['methods']:
     if method['selector_id']in found:raise ParseError('Repeated method facts identity')
     found[method['selector_id']]=(method,model)
   plans=[];missing=[]
   for selector in selectors['selectors']:
    identity=selector['selectorId'];native_id=identity+':MoveNext'if selector['methodKind']=='CoroutineMoveNext'else identity
    if native_id not in found:missing.append({'selector_id':identity,'reason':'actual_MoveNext_binding_facts_missing'if selector['methodKind']=='CoroutineMoveNext'else'exact_native_binding_facts_missing'});continue
    if identity not in source_map:raise ParseError('Source CLR binding missing')
    method,model=found[native_id]
    callbacks=[callback_map[i]for i in selector['callbackIds']]
    plans.append(plan_one(selector,source_map[identity],method,model,callbacks,source_owner_evidence))
 report={'schema':'ehr.native-thunk-abi-plans.v1','input_pins':pins,'observed_type_layouts':layouts,'selector_count':len(selectors['selectors']),'planned_count':len(plans),'missing':missing,
  'blocking_requirement_counts':dict(Counter(reason for plan in plans for reason in plan['blocking_requirements'])),'plans':plans,'native_execution_performed':False,'runtime_availability_claimed':False,'executable_thunks_emitted':False}
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({key:report[key]for key in('selector_count','planned_count','missing','blocking_requirement_counts','runtime_availability_claimed')},indent=2))

if __name__=='__main__':main()
