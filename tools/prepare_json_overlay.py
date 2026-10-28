#!/usr/bin/env python3
"""Narrow exact JSON callsite lowering on already-adapted full source inputs."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--upstream-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
stage=Path(__file__).resolve().parents[1];out=a.output.resolve();project=a.project.resolve()
commit=subprocess.check_output(['git','-C',str(a.upstream_root),'rev-parse','HEAD'],text=True).strip()
if commit!='ce23f0d050f617a59507e5bb0fbfff751d4b5134':raise ValueError('expected pinned EHR v8.0.3 source')
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);tree=ET.parse(project);ns='';root=tree.getroot();compiles=[x for x in root.iter() if x.tag.split('}')[-1]=='Compile' and x.get('Include')]
context='global::EHR.SourcePort.EHRPortableJsonContext.'
rules={
'Main.cs':[
 ('JsonSerializer.Serialize(RoleHtmlColors, new JsonSerializerOptions { WriteIndented = true })','JsonSerializer.Serialize(RoleHtmlColors, '+context+'Indented.RoleColors)',1),
 ('JsonSerializer.Deserialize<Dictionary<string, string>>(json)','JsonSerializer.Deserialize(json, '+context+'Default.StringColors)',1)],
'OptionSaver.cs':[
 ('JsonSerializer.Serialize(GenerateOptionsData(), new JsonSerializerOptions { WriteIndented = true })','JsonSerializer.Serialize(GenerateOptionsData(), '+context+'Indented.OptionData)',1),
 ('JsonSerializer.Deserialize<SerializableOptionsData>(jsonString)','JsonSerializer.Deserialize(jsonString, '+context+'Default.OptionData)',1)],
'OptionHolder.cs':[
 ('JsonSerializer.Serialize(new UserData { Tag = string.Empty }, new JsonSerializerOptions { WriteIndented = true })','JsonSerializer.Serialize(new UserData { Tag = string.Empty }, '+context+'Indented.UserData)',1),
 ('JsonSerializer.Deserialize<UserData>(content)','JsonSerializer.Deserialize(content, '+context+'Default.UserData)',1)],
'Achievements.cs':[
 ('JsonSerializer.Serialize(CompletedAchievements)','JsonSerializer.Serialize(CompletedAchievements, '+context+'Default.Achievements)',1),
 ('JsonSerializer.Serialize(data)','JsonSerializer.Serialize(data, '+context+'Default.AchievementUpload)',1),
 ('JsonSerializer.Deserialize<HashSet<Type>>(json)','JsonSerializer.Deserialize(json, '+context+'Default.Achievements)',2)],
'Translator.cs':[
 ('JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(resourceStream)','JsonSerializer.Deserialize(resourceStream, '+context+'Default.Language)',1)],
'Utils.cs':[
 ('JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true })','JsonSerializer.Serialize(data, '+context+'Indented.Combos)',1),
 ('JsonSerializer.Deserialize<Dictionary<int, Dictionary<string, List<string>>>>(File.ReadAllText(path))','JsonSerializer.Deserialize(File.ReadAllText(path), '+context+'Default.Combos)',1)],
'DevManager.cs':[
 ('JsonSerializer.Deserialize<Dictionary<string, TagInfo>>(json)','JsonSerializer.Deserialize(json, '+context+'Default.Tags)',1)],
'OnlinePresetsManager.cs':[
 ('JsonSerializer.Serialize(body)','JsonSerializer.Serialize(body, '+context+'Default.PresetDraftRequest)',1),
 ('JsonSerializer.Deserialize<PresetDraftResponse>(request.downloadHandler.text)','JsonSerializer.Deserialize(request.downloadHandler.text, '+context+'Default.PresetDraftResponse)',1),
 ('JsonSerializer.Deserialize<PresetDownloadResponse>(request.downloadHandler.text)','JsonSerializer.Deserialize(request.downloadHandler.text, '+context+'Default.PresetDownloadResponse)',1),
 ('JsonSerializer.Deserialize<PresetListResponse>(request.downloadHandler.text.Trim())','JsonSerializer.Deserialize(request.downloadHandler.text.Trim(), '+context+'Default.PresetListResponse)',1)],
'AnnouncementPatch.cs':[
 ('JsonSerializer.Deserialize<List<ModNews>>(json)','JsonSerializer.Deserialize(json, '+context+'Default.News)',1)]}
seen=set();files=[]
for item in compiles:
 source=Path(item.get('Include'));source=source if source.is_absolute() else project.parent/source
 if source.name not in rules:continue
 if source.name in seen:raise ValueError('ambiguous compiled source filename: '+source.name)
 seen.add(source.name);s=source.read_text();before=s
 for old,new,count in rules[source.name]:
  if s.count(old)!=count:raise ValueError('pinned callsite changed: '+str(source)+' '+old)
  s=s.replace(old,new)
 if source.name=='Achievements.cs':
  pattern=r'(?P<indent> +)var data = new\n(?P=indent)\{\n(?P=indent)    userId,\n(?P=indent)    achievements = CompletedAchievements\n(?P=indent)\};'
  def dto(m):
   i=m['indent'];return '#if IL2CPP\n'+i+'var data = new global::EHR.SourcePort.AchievementUploadRequest\n'+i+'{\n'+i+'    userId = userId,\n'+i+'    achievements = CompletedAchievements\n'+i+'};\n#else\n'+m.group(0)+'\n#endif'
  s,n=re.subn(pattern,dto,s)
  if n!=1:raise ValueError('anonymous request contract changed')
 target=out/'source'/source.name;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(s);item.set('Include',str(target))
 files.append({'input':str(source),'input_sha256':hashlib.sha256(before.encode()).hexdigest(),'output':str(target),'output_sha256':hashlib.sha256(s.encode()).hexdigest(),'jsonCalls':sum(r[2] for r in rules[source.name])})
if seen!=set(rules):raise ValueError('compiled source files missing: '+str(set(rules)-seen))
contextTarget=out/'EHRPortableJsonContext.cs';contextTarget.write_bytes((stage/'managed/EHRPortableJsonContext.cs').read_bytes())
group=ET.SubElement(root,'ItemGroup');ET.SubElement(group,'Compile',Include=str(contextTarget))
selfTest=out/'EHRPortableJsonSelfTest.cs';selfTest.write_bytes((stage/'managed/EHRPortableJsonSelfTest.cs').read_bytes());ET.SubElement(group,'Compile',Include=str(selfTest))
# Rebase any untouched relative paths so the fresh project preserves its inputs.
for item in root.iter():
 for name in ['Include','Project']:
  value=item.get(name)
  if value and not value.startswith('/') and '$(' not in value and '*' not in value and item.tag.split('}')[-1] in {'Compile','EmbeddedResource','Import'}:item.set(name,str((project.parent/value).resolve()))
tree.write(out/'EHR.csproj',encoding='unicode')
report={'schema':'ehr.aot-json-overlay.v1','upstreamRoot':str(a.upstream_root),'upstreamCommit':commit,'inputProject':str(project),'inputProjectSha256':hashlib.sha256(project.read_bytes()).hexdigest(),'jsonCallsLowered':sum(f['jsonCalls'] for f in files),'sourceFiles':files,'jsonContextRoots':14,'reflectionJSONFallbackUsed':False,'enumConverterAdded':False,'caseFoldingAdded':False,'fieldsIncluded':False,'indentedCallsites':4,'anonymousRequestReplacedByExactNamedDTOOnlyForIL2CPP':True}
(out/'json-overlay.json').write_text(json.dumps(report,indent=2)+'\n');print(out/'EHR.csproj')
