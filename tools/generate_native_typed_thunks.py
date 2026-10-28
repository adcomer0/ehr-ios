#!/usr/bin/env python3
"""Emit native typed thunks or pinned install evidence into private new output."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import uuid
from generate_native_thunk_plans import ParseError,SCALARS
from map_native_methods import MachO
from patch_native_entries import Image,branch,indirect_stub,read,relocate_first_instruction


def ident(name):return hashlib.sha256(name.encode()).hexdigest()[:16]
def quote(value):return json.dumps(value,ensure_ascii=True)
def cpp_type(value):
 if value['abi']=='byref_pointer':return cpp_type(value['element'])+' *'
 if not value.get('cpp'):raise ParseError('Unresolved native ABI type')
 return value['cpp']
def unwrap(value):return value['element']if value['abi']=='byref_pointer'else value
def kind(value):return 0 if value['abi']=='void'else 1 if value['abi']=='gpr_reference'else 2
def size(value):return 0 if kind(value)==0 else 8 if kind(value)==1 else value.get('size',value.get('layout',{}).get('size'))
def alignment(value):return 1 if kind(value)==0 else 8 if kind(value)==1 else value.get('alignment',value.get('layout',{}).get('alignment'))


def runtime_names(documents,expected_uuid=None):
 result={}
 for document in documents:
  audit=document.get('allHarmonyRuntimeBindings',document)
  if audit.get('success')is not True or audit.get('failures'):raise ParseError('Runtime type audit did not succeed')
  if expected_uuid and uuid.UUID(audit.get('frameworkUuid',''))!=uuid.UUID(expected_uuid):raise ParseError('Runtime type audit image UUID differs')
  for row in audit.get('types',[]):
   if row.get('success')is not True or not row.get('runtimeName'):raise ParseError('Unresolved observed runtime type spelling')
   name,value=row['canonical'],row['runtimeName']
   if name in result and result[name]!=value:raise ParseError('Conflicting observed runtime type spelling')
   result[name]=value
 return result


def catalog_rows(catalog):
 if catalog.get('schema')!='ehr.native-source-patch-candidates.v1':raise ParseError('Unexpected native source catalog schema')
 rows=catalog['candidates'];ids=set();selectors=set()
 for row in rows:
  if not re.fullmatch('[0-9a-f]{20}',row['selectorId'])or type(row['targetId'])is not int or not 0<row['targetId']<2**64:raise ParseError('Invalid selector/target identity')
  if row['targetId']in ids or row['selectorId']in selectors:raise ParseError('Repeated catalog identity')
  ids.add(row['targetId']);selectors.add(row['selectorId'])
 return rows


def emit_thunks(report,catalog,names):
 if report.get('schema')!='ehr.native-thunk-abi-plans.v1'or report.get('missing'):raise ParseError('Incomplete native thunk plans')
 plans={p['selector_id']:p for p in report['plans']};rows=catalog_rows(catalog)
 if set(plans)!={r['selectorId']for r in rows}:raise ParseError('Catalog/plan identity sets differ')
 layouts=report.get('observed_type_layouts',{});values={};aggregates={}
 def register(value):
  value=unwrap(value);name=value['canonical']
  if name in values:
   if cpp_type(values[name])!=cpp_type(value):raise ParseError('Inconsistent exact type ABI')
   return
  if name not in names and kind(value)!=0:raise ParseError('No actual runtime spelling for '+name)
  values[name]=value
  if 'layout'in value:
   def visit(name,layout):
    if name in aggregates:return
    for member in layout['fields']:
     if member['cpp'].startswith('ehr_value_'):
      raw=layouts.get(member['type'])
      if not raw:raise ParseError('Nested aggregate layout missing')
      # Only recursive members already validated by the planner are emitted.
      nested_fields=[]
      for f in raw['fields']:
       if f.get('is_static'):continue
       typename=f['type'];cpp=SCALARS[typename][0]if typename in SCALARS else 'void *'if f.get('is_value_type')is False else 'ehr_value_'+ident(typename)
       if raw.get('is_enum'):cpp=SCALARS[raw['enum_underlying']][0]
       if typename in layouts and layouts[typename].get('is_enum'):cpp=SCALARS[layouts[typename]['enum_underlying']][0]
       nested_fields.append({'cpp':cpp,'type':typename,'offset':f['value_offset'],'size':f['field_size'],'alignment':f['field_alignment']})
      visit(member['type'],{'size':raw['value_size'],'alignment':raw['alignment'],'fields':nested_fields})
    aggregates[name]=layout
   visit(name,value['layout'])
 for plan in plans.values():
  for value in ([plan['owner']]if plan['owner']else[])+plan['arguments']+[plan['result']]:register(value)
 types=['#pragma once\n#include <stdint.h>\n#include <stddef.h>\n#include <type_traits>\n']
 for name,layout in aggregates.items():
  typename='ehr_value_'+ident(name);types.append(f'struct alignas({layout["alignment"]}) {typename} {{\n');cursor=0
  for index,field in enumerate(layout['fields']):
   offset=field['offset']
   if offset<cursor:raise ParseError('Aggregate fields overlap or are unordered')
   if offset>cursor:types.append(f'    uint8_t pad_{index}[{offset-cursor}];\n')
   types.append(f'    {field["cpp"]} f_{index};\n');cursor=offset+field['size']
  if cursor<layout['size']:types.append(f'    uint8_t tail[{layout["size"]-cursor}];\n')
  types.append(f'}};\nstatic_assert(sizeof({typename})=={layout["size"]}&&alignof({typename})=={layout["alignment"]});\nstatic_assert(std::is_trivially_copyable_v<{typename}>);\n')
  for index,field in enumerate(layout['fields']):types.append(f'static_assert(offsetof({typename},f_{index})=={field["offset"]});\n')
 source=['// Generated from exact metadata, observed public layouts and runtime names.\n#include "EHRNativePatchThunks.h"\n#include "EHRRuntimeOriginal.h"\n#include "EHRNativeThunkTypes.generated.h"\n#include "EHRNativeThunkSites.generated.h"\n']
 uuid_bytes=uuid.UUID(report['input_pins']['framework_uuid']).bytes
 source.append('static const uint8_t EHRNativeThunkUUID[16]={'+','.join(str(v)for v in uuid_bytes)+'};\n')
 for name,value in values.items():
  code=ident(name);layout=layouts.get(name);fields=[]
  if 'layout'in value:
   fields=[f for f in layout['fields']if not f.get('is_static')]
   source.append(f'static const EHRNativePatchFieldV1 fields_{code}[]={{\n')
   for field in fields:source.append('{'+quote(field['name'])+','+quote(field['runtime_type_name'])+','+str(field['value_offset'])+'},\n')
   source.append('};\n')
  flags=0
  if kind(value)==2:
   flags|=4 if name=='System.Boolean'else 8 if name=='System.Char'else 0
   if value['abi']=='gpr_enum':flags|=16
   if layout:flags|=(1 if layout['contains_references']else 0)|(2 if layout['blittable']else 0)|32
  source.append(f'static const EHRNativePatchTypeV1 type_{code}={{'+','.join((quote(names.get(name,'System.Void')),str(kind(value)),str(size(value)),str(alignment(value)),str(flags),quote(value['enum_underlying'])if value.get('enum_underlying')else'nullptr',f'fields_{code}'if fields else'nullptr',str(len(fields))))+'};\n')
 contracts={};specs=[];blocked=[]
 for row in rows:
  selector=row['selectorId'];plan=plans[selector];target=row['targetId']
  if int(plan['expected_rva'],16)!=int(row['nativeRva'],16):raise ParseError('Catalog/plan method RVA differs')
  function='ehr_full_hook_'+selector;site='site_'+selector;parameter_types=[cpp_type(a)for a in plan['arguments']];return_type=cpp_type(plan['result'])
  declarations=(['void *self']if plan['owner']else[])+[t+' a'+str(i)for i,t in enumerate(parameter_types)]+['const void *methodInfo']
  prototype_types=(['void *']if plan['owner']else[])+parameter_types+['const void *']
  signature_flags=(1 if plan['owner']else 0)|(2 if kind(plan['result'])else 0)|(4 if kind(plan['result'])==2 else 0)
  source.append(f'extern "C" {return_type} {function}('+','.join(declarations)+');\n')
  if plan['arguments']:
   source.append(f'static const EHRNativePatchParameterV1 params_{selector}[]={{\n')
   for arg in plan['arguments']:
    flags=(1 if kind(unwrap(arg))==2 else 0)|(2 if arg['abi']=='byref_pointer'else 0)|(4 if arg['source_ref_kind']=='Out'else 0)|(8 if arg['source_ref_kind']=='In'else 0)
    source.append('{&type_'+ident(unwrap(arg)['canonical'])+','+str(flags)+'},\n')
   source.append('};\n')
  supported=not plan['blocking_requirements']
  if not supported:blocked.append({'selectorId':selector,'requirements':plan['blocking_requirements']})
  source.append(f'static const EHRNativePatchSiteV1 {site}={{UINT64_C({target}),UINT64_C({int(plan["expected_rva"],16)}),{int(plan["metadata_token"],16)},{signature_flags},EHRNativeThunkUUID,reinterpret_cast<const void *>(&{function}),EHR_NATIVE_INSTALL_{selector},'+('&type_'+ident(plan['owner']['canonical'])if plan['owner']else'nullptr')+',&type_'+ident(plan['result']['canonical'])+','+(f'params_{selector}'if plan['arguments']else'nullptr')+','+str(len(plan['arguments']))+','+('true'if supported else'false')+'};\n')
  source.append(f'extern "C" __attribute__((visibility("default"))) {return_type} {function}('+','.join(declarations)+') {\n')
  source.append('    using Original='+return_type+' (*)('+','.join(prototype_types)+');\n'+f'    auto original=reinterpret_cast<Original>(EHRNativePatchOriginal({site}));\n')
  call=','.join((['self']if plan['owner']else[])+['a'+str(i)for i in range(len(parameter_types))]+['methodInfo']);original_call=('return 'if return_type!='void'else'')+'original('+call+');'+(' return;'if return_type=='void'else'')
  source.append(f'    if(EHRTryConsumeOriginalInvocation(UINT64_C({target}),methodInfo)||!EHRNativePatchShouldDispatch({site})) {{ {original_call} }}\n')
  if plan['arguments']:
   source.append('    EHRNativePatchArgumentV1 arguments[]={\n')
   for i,arg in enumerate(plan['arguments']):
    ref=arg['abi']=='byref_pointer';pointer='a'+str(i)if ref else'&a'+str(i);output='a'+str(i)if ref and arg['write_native_output']else'nullptr'
    source.append('{'+pointer+',sizeof('+cpp_type(unwrap(arg))+'),'+output+'},\n')
   source.append('    };\n')
  if return_type!='void':source.append('    '+return_type+' result{};\n')
  source.append(f'    auto outcome=EHRNativePatchInvokePrepared({site},'+('self'if plan['owner']else'nullptr')+','+('arguments'if plan['arguments']else'nullptr')+','+str(len(parameter_types))+','+('&result,sizeof(result)'if return_type!='void'else'nullptr,0')+');\n')
  source.append('    if(!outcome.dispatcher_entered) { '+original_call+' }\n    EHRNativePatchFinish(outcome);\n'+('    return result;\n'if return_type!='void'else'')+'}\n')
  key='ehr.full.'+selector;contracts[key]={'declaring_type':row['nativeNamespace']+'.'+row['nativeType']if row['nativeNamespace']else row['nativeType'],'name':row['nativeMethod'],'return':row['nativeReturn'],'parameters':row['nativeParameters'],'static':row['isStatic'],'symbol':'_'+function};specs.append('&'+site)
 source.append('EHRRuntimeStatus EHRNativeGeneratedRegisterCompiled() {\n    static const EHRNativePatchSiteV1 *const sites[]={'+','.join(specs)+'};\n    return EHRNativePatchRegisterCompiled(sites,sizeof(sites)/sizeof(sites[0]));\n}\n')
 if 'Discord.Activity'in values:
  value=layouts['Discord.Activity'];source.append('#ifdef __OBJC__\nextern "C" __attribute__((visibility("default"))) NSDictionary *ehr_native_patch_value_box_selftest() { return EHRNativePatchBoxedReferenceSelfTest(type_'+ident('Discord.Activity')+','+quote(value['image'])+',"Discord","Activity","Name"); }\n#endif\n')
 empty_sites='#pragma once\n// No install evidence supplied: Validate returns NOT_READY; nothing activates.\n'+''.join('#define EHR_NATIVE_INSTALL_'+row['selectorId']+' nullptr\n'for row in rows)
 return {'EHRNativeThunkTypes.generated.h':''.join(types),'EHRNativeTypedThunks.generated.inc':''.join(source),'EHRNativeThunkSites.generated.h':empty_sites,'native-thunk-contracts.local.json':json.dumps({'schema':'ehr.native-hook-contracts.v1','methods':contracts},indent=2)+'\n','native-thunk-generation.local.json':json.dumps({'schema':'ehr.native-typed-thunk-generation.v1','input_pins':report['input_pins'],'count':len(rows),'blocked_source_bindings':blocked,'runtime_execution_performed':False,'handlers_activated':False,'install_evidence_supplied':False},indent=2)+'\n'}


def emit_sites(catalog,manifest,data):
 rows=catalog_rows(catalog);image=Image(data,allow_instrumented=True);native=MachO(data)
 if manifest.get('output_uuid')!=native.uuid:raise ParseError('Patched manifest/framework UUID differs')
 if hashlib.sha256(data).hexdigest()!=manifest.get('output_sha256'):raise ParseError('Patched framework differs from exact unsigned manifest output')
 hooks={h['method']:h for h in manifest['hooks']};output=['#pragma once\n#include "EHRNativePatchThunks.h"\n'];installed=[]
 for row in rows:
  selector=row['selectorId'];hook=hooks.get('ehr.full.'+selector)
  if not hook:output.append('#define EHR_NATIVE_INSTALL_'+selector+' nullptr\n');continue
  expected_symbol='_ehr_full_hook_'+selector
  if hook['handler_symbol']!=expected_symbol or int(hook['method_rva'],16)!=int(row['nativeRva'],16):raise ParseError('Hook identity differs from catalog')
  method,stub,trampoline,got=(int(hook[k],16)for k in('method_rva','stub_rva','trampoline_rva','got_preferred_va'))
  got-=image.preferred_base;count=hook['relocation']['trampoline_bytes'];word=int(hook['entry_branch'],16)
  if count<8 or count>48 or count%4 or trampoline!=stub+16 or word!=branch(image.preferred_base+method,image.preferred_base+stub):raise ParseError('Unsupported installed slot geometry')
  if read(data,'<I',image.va_to_file(image.preferred_base+method))[0]!=word:raise ParseError('Installed entry branch differs')
  offset=image.va_to_file(image.preferred_base+stub);stub_data=data[offset:offset+16]
  if stub_data!=indirect_stub(image.preferred_base+stub,image.preferred_base+got):raise ParseError('Installed entry stub differs')
  offset=image.va_to_file(image.preferred_base+trampoline);trampoline_data=data[offset:offset+count]
  if len(trampoline_data)!=count:raise ParseError('Truncated installed trampoline')
  relocated,details=relocate_first_instruction(int(hook['first_instruction'],16),image.preferred_base+method,image.preferred_base+trampoline)
  if relocated!=trampoline_data or details['trampoline_bytes']!=count:raise ParseError('Installed relocated trampoline differs from strict reconstruction')
  def digest_bytes(value):return '{'+','.join(str(n)for n in hashlib.sha256(value).digest())+'}'
  output.append('static const EHRNativePatchInstallV1 install_'+selector+'={'+','.join(str(v)for v in(method,stub,trampoline,got,word,count))+','+digest_bytes(stub_data)+','+digest_bytes(trampoline_data)+'};\n#define EHR_NATIVE_INSTALL_'+selector+' (&install_'+selector+')\n');installed.append({'selectorId':selector,'targetId':row['targetId']})
 return ''.join(output),installed


def main(argv=None):
 parser=argparse.ArgumentParser(description=__doc__);commands=parser.add_subparsers(dest='mode',required=True)
 thunks=commands.add_parser('thunks');sites=commands.add_parser('sites')
 for command in(thunks,sites):
  command.add_argument('--catalog',type=Path,required=True);command.add_argument('--output',type=Path,required=True)
 thunks.add_argument('--plans',type=Path,required=True);thunks.add_argument('--runtime-type-proof',type=Path,action='append',required=True)
 sites.add_argument('--patch-manifest',type=Path,required=True);sites.add_argument('--patched-framework',type=Path,required=True)
 args=parser.parse_args(argv);output=args.output.resolve()
 if output.exists()or any((p/'.git').exists()for p in(output,*output.parents)):parser.error('Output must be a new private outside-Git directory')
 catalog=json.loads(args.catalog.read_text())
 if args.mode=='thunks':
  plans=json.loads(args.plans.read_text());files=emit_thunks(plans,catalog,runtime_names([json.loads(p.read_text())for p in args.runtime_type_proof],plans['input_pins']['framework_uuid']))
 else:
  header,installed=emit_sites(catalog,json.loads(args.patch_manifest.read_text()),args.patched_framework.read_bytes());files={'EHRNativeThunkSites.generated.h':header,'native-thunk-installed-sites.local.json':json.dumps({'schema':'ehr.native-thunk-installed-sites.v1','sites':installed,'handlers_activated':False},indent=2)+'\n'}
 output.mkdir(parents=True)
 for name,text in files.items():(output/name).write_text(text)
 print(json.dumps({'output':str(output),'files':list(files),'runtime_execution_performed':False,'handlers_activated':False},indent=2))


if __name__=='__main__':main()
