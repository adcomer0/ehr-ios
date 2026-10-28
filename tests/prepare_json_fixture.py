#!/usr/bin/env python3
"""Extract exact enum/property contracts from pinned source, without game code."""
from pathlib import Path
import argparse,re,json,hashlib
p=argparse.ArgumentParser();p.add_argument('--upstream-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();stage=Path(__file__).resolve().parents[1];root=a.upstream_root;out=a.output
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);used={}
def read(name):
 s=(root/name).read_text();used[name]=hashlib.sha256((root/name).read_bytes()).hexdigest();return s
def declaration(s,kind,name):
 m=re.search(r'public '+kind+r' '+name+r'\b[^\{]*\{',s);assert m,name
 start=m.start();i=m.end();depth=1
 while depth:
  if s[i]=='{':depth+=1
  if s[i]=='}':depth-=1
  i+=1
 return s[start:i]
def properties(s,name):
 body=declaration(s,'class',name);props=re.findall(r'^\s*public [\w<>, ?\[\]]+ \w+ \{ get; (?:set|init); \}',body,re.M)
 assert len(props)=={'UserData':4,'TagInfo':4,'ModNews':6,'SerializableOptionsData':3,'PresetDraftRequest':3,'PresetDraftResponse':2,'PresetDownloadResponse':3,'PresetMeta':7,'PresetListResponse':1}[name],name
 return 'public class '+name+' {\n'+'\n'.join(x.strip() for x in props)+'\n}'
contracts='using System;using System.Collections.Generic;\n'
contracts+='namespace EHR {\n'+declaration(read('CustomRoles.cs'),'enum','CustomRoles')+'\n'
contracts+='public static class Options { '+properties(read('Modules/OptionHolder.cs'),'UserData')+'}\n'
contracts+='public static class DevManager { '+properties(read('Modules/DevManager.cs'),'TagInfo')+'}\n'
contracts+=properties(read('Patches/AnnouncementPatch.cs'),'ModNews')+'}\n'
contracts+='namespace EHR.Modules {\npublic static class Achievements { '+declaration(read('Modules/Achievements.cs'),'enum','Type')+'}\n'
contracts+='public static class OptionSaver { '+properties(read('Modules/OptionSaver.cs'),'SerializableOptionsData')+'}\n'
presets=read('Modules/OnlinePresetsManager.cs');contracts+='public static class OnlinePresetsManager {\n'
for name in ['PresetDraftRequest','PresetDraftResponse','PresetDownloadResponse','PresetMeta','PresetListResponse']:contracts+=properties(presets,name)+'\n'
contracts+='}}\n'
(out/'ExactContracts.cs').write_text(contracts);(out/'EHRPortableJsonContext.cs').write_bytes((stage/'managed/EHRPortableJsonContext.cs').read_bytes());(out/'Program.cs').write_bytes((stage/'tests/JsonFixture.cs').read_bytes())
(out/'EHRPortableJsonSelfTest.cs').write_bytes((stage/'managed/EHRPortableJsonSelfTest.cs').read_bytes())
(out/'Fixture.csproj').write_text('''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable><AllowUnsafeBlocks>true</AllowUnsafeBlocks><PublishAot>true</PublishAot><InvariantGlobalization>true</InvariantGlobalization><JsonSerializerIsReflectionEnabledByDefault>false</JsonSerializerIsReflectionEnabledByDefault><WarningsAsErrors>IL2026;IL3050</WarningsAsErrors></PropertyGroup></Project>''')
(out/'contracts.json').write_text(json.dumps({'upstreamContracts':used,'gameAssembliesReferenced':False,'methodsCopied':False,'fieldsOrPropertiesRenamed':False},indent=2)+'\n');print(out)
