#!/usr/bin/env python3
"""Prepare a private metadata-only XCTest overlay; no launch or value payload copy."""
from __future__ import annotations
import argparse
import hashlib
import json
import mmap
from pathlib import Path
from map_native_methods import MachO,ParseError,TypeNames,digest,find_module,find_registrations
from map_harmony_native_targets import NestedMetadata

ROOT_TYPES=('System.Guid','UnityEngine.Color','Discord.Activity','InnerNet.PlayerId','Discord.PartySize')


def spec_from_metadata(metadata,native,pins):
 rows=[]
 for name in ROOT_TYPES:
  found=[i for i in range(len(metadata.types))if metadata.type_name(i)==name]
  if len(found)!=1:raise ParseError('Requested value type is missing/ambiguous: '+name)
  index=found[0];row=metadata.types[index];outer=index;chain=[]
  while True:
   chain.append(metadata.string(metadata.types[outer][0]))
   if outer not in metadata.parents:break
   outer=metadata.parents[outer]
  rows.append({'canonical':name,'image':metadata.image_for_type(index)['name'],'namespace':metadata.string(metadata.types[outer][1]),'name':'+'.join(reversed(chain))})
 module=find_module(native,metadata,'Assembly-CSharp.dll')
 registrations,_,_=find_registrations(native,metadata,module)
 if len(registrations)!=1:raise ParseError('Metadata registration is missing/ambiguous')
 declarations=declared_value_types(metadata,TypeNames(native,metadata,registrations[0]))
 return {'schema':'ehr.public-value-abi-request.v1','framework_uuid':native.uuid,**pins,'requestedTypes':rows,'metadataDeclaredTypes':declarations}


def declared_value_types(metadata,names):
 """Capture declarations, never payloads; field types come from a unique registration."""
 by_name={}
 for i in range(len(metadata.types)):by_name.setdefault(metadata.type_name(i),[]).append(i)
 result={}
 def observe(name,depth=0):
  if name in result:return
  matches=by_name.get(name,[])
  if len(matches)!=1 or depth>16:raise ParseError('Value field declaration is missing/ambiguous: '+name)
  index=matches[0];row=metadata.types[index]
  if not row[24]&1:raise ParseError('Expected metadata value type: '+name)
  fields=[]
  result[name]={'flags':row[7],'layout_mask':row[7]&0x18,'image':metadata.image_for_type(index)['name'],'fields':fields}
  for field_index in range(row[8],row[8]+row[18]):
   field=metadata.record('fields',12,field_index,'<IiI');field_type=names.at_index(field[1])
   if field_type.startswith('unresolved_'):raise ParseError('Unresolved declared value field type')
   fields.append({'name':metadata.string(field[0]),'type':field_type})
   child=by_name.get(field_type,[])
   if len(child)==1 and metadata.types[child[0]][24]&1:observe(field_type,depth+1)
 for name in ROOT_TYPES:observe(name)
 return result


def inject(base,spec,template):
 boundary='@interface NativeRuntimeTests : XCTestCase'
 if base.count(boundary)!=1 or 'exercisePublicValueABIFacts('in base:raise ParseError('Unexpected/already-overlaid XCTest source')
 encoded=json.dumps(spec,separators=(',',':'),ensure_ascii=True)
 if ')EHRVALUES"'in encoded:raise ParseError('Unsafe own JSON literal delimiter')
 payload='\nstatic const char EHRValueABISpec[] = R"EHRVALUES('+encoded+')EHRVALUES";\n'+template+'\n'
 base='#include <mach-o/loader.h>\n#include <functional>\n#include <set>\n'+base.replace(boundary,payload+boundary)
 anchor='    NSDictionary *gateway = exerciseGateway();'
 if base.count(anchor)!=1:raise ParseError('Ready-runtime observation anchor missing')
 base=base.replace(anchor,anchor+'\n    NSDictionary *valueABIFacts = exercisePublicValueABIFacts(EHRValueABISpec);\n    XCTAssertTrue([valueABIFacts[@"success"] boolValue], @"%@", valueABIFacts);')
 anchor='        @"runtimeGateway": gateway,'
 if base.count(anchor)!=1:raise ParseError('Proof insertion anchor missing')
 return base.replace(anchor,anchor+'\n        @"publicValueABIFacts": valueABIFacts,')


def main(argv=None):
 p=argparse.ArgumentParser(description=__doc__)
 for arg in('base-test','framework','metadata','output'):p.add_argument('--'+arg,type=Path,required=True)
 args=p.parse_args(argv);output=args.output.resolve()
 if output.exists()or any((parent/'.git').exists()for parent in(output,*output.parents)):p.error('Output must be a new outside-Git artifact directory')
 paths=[args.base_test.resolve(),args.framework.resolve(),args.metadata.resolve()]
 if any(path==output or path in output.parents or output in path.parents for path in paths):p.error('Output must be independent of inputs')
 before=[(path.stat().st_size,path.stat().st_mtime_ns,digest(path))for path in paths]
 with args.framework.open('rb')as nf,args.metadata.open('rb')as mf,mmap.mmap(nf.fileno(),0,access=mmap.ACCESS_READ)as nd,mmap.mmap(mf.fileno(),0,access=mmap.ACCESS_READ)as md:
  native,metadata=MachO(nd),NestedMetadata(md)
  spec=spec_from_metadata(metadata,native,{'framework_sha256':before[1][2],'metadata_sha256':before[2][2]})
 template=(Path(__file__).resolve().parents[1]/'tests/runtime/PublicValueABIFacts.inc').read_text()
 generated=inject(args.base_test.read_text(),spec,template)
 if before!=[(path.stat().st_size,path.stat().st_mtime_ns,digest(path))for path in paths]:raise ParseError('A read-only input changed during preparation')
 output.mkdir(parents=True,exist_ok=False)
 (output/'public-value-abi-request.local.json').write_text(json.dumps(spec,indent=2)+'\n')
 (output/'NativeRuntimePublicValueABIFacts.local.mm').write_text(generated)
 manifest={'schema':'ehr.public-value-abi-overlay-generation.v1','requested_root_types':list(ROOT_TYPES),'input_sha256':dict(zip(('base_test','framework','metadata'),(v[2]for v in before))),
  'own_template_sha256':hashlib.sha256(template.encode()).hexdigest(),'overlay_sha256':hashlib.sha256(generated.encode()).hexdigest(),'target_calls':0,'payload_reads_or_copies':0,'value_box_calls':0,'runtime_execution_performed':False}
 (output/'generation-manifest.local.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print(json.dumps({'output':str(output),**manifest},indent=2))

if __name__=='__main__':main()
