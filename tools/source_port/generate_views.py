#!/usr/bin/env python3
"""Emit three pinned source adaptations with no input mutation or fake native APIs."""
from __future__ import annotations
import argparse,hashlib,json,subprocess
from pathlib import Path
import xml.etree.ElementTree as E

COMMIT='ce23f0d050f617a59507e5bb0fbfff751d4b5134'
SELECTOR_SHA='d8d0237d405aa266f505ca4839aa14af4d396c3a8fba7db039c9f1f322b68ce5'
CONTEXT='''using System.Text.Json.Serialization;
namespace EHR.SourcePort;
[JsonSourceGenerationOptions(IncludeFields=true,PropertyNameCaseInsensitive=false)]
[JsonSerializable(typeof(global::EHR.Roles.Bard.Joke),TypeInfoPropertyName="BardJoke")]
internal partial class EHRSourceJsonContext:JsonSerializerContext { }
'''
RULES={
 'GameOptionsMenuPatch.cs':('Patches/GameOptionsMenuPatch.cs','foreach (KeyValuePair<OptionBehaviour, int> kvp in ModGameOptionsMenu.OptionList)',
   'foreach (global::System.Collections.Generic.KeyValuePair<OptionBehaviour, int> kvp in ModGameOptionsMenu.OptionList)',2,
   'Qualify the CLR dictionary entry view returned by the live facade cursor; keys/values are still read from actual native IDictionaryEnumerator with owning reference roots'),
 'ExilePatch.cs':('Patches/ExilePatch.cs','nameof(AirshipExileController.WrapUpAndSpawn)','"WrapUpAndSpawn"',1,
   'Preserve the exact pinned coroutine-factory name as a string; no phantom facade method or MoveNext binding is invented'),
 'Bard.cs':('Roles/Standard/Impostor/Killing/Bard.cs','JsonUtility.FromJson<Joke>(json)',
   'global::System.Text.Json.JsonSerializer.Deserialize(json,global::EHR.SourcePort.EHRSourceJsonContext.Default.BardJoke)',1,
   'Use a statically generated JSON contract for this CLR-owned joke DTO; it has no IL2CPP class to inflate into Unity JsonUtility<T>')}

def sha(data:bytes)->str:return hashlib.sha256(data).hexdigest()
def transform(name:str,data:bytes,pin:str)->tuple[str,dict]:
    if name not in RULES:raise ValueError('Unknown reviewed source rule')
    if sha(data)!=pin:raise ValueError('Selected source hash mismatch: '+name)
    relative,old,new,count,reason=RULES[name];text=data.decode('utf-8-sig').replace('\r\n','\n')
    if text.count(old)!=count:raise ValueError('Reviewed source pattern drift: '+name)
    return text.replace(old,new),dict(file=relative,adaptation=reason,selectedInputSha256=sha(data),replacementCount=count)
def verify_selector(data:bytes)->None:
    if sha(data)!=SELECTOR_SHA:raise ValueError('Authoritative selector bytes changed')
    values=json.loads(data)['selectors']
    matches=[x for x in values if x['declaringType']=='AirshipExileController' and x['methodName']=='WrapUpAndSpawn']
    if len(matches)!=1 or matches[0]['methodKind']!='CoroutineMoveNext' or matches[0]['parameterTypes']!=[]:
        raise ValueError('Exact coroutine factory selector unavailable')
def generate(project:Path,upstream:Path,pins:dict,selectors:Path,output:Path)->dict:
    observed=subprocess.check_output(['git','-C',str(upstream),'rev-parse','HEAD'],text=True).strip()
    if observed!=COMMIT:raise ValueError('Upstream commit pin mismatch')
    verify_selector(selectors.read_bytes())
    if project.resolve()==(output/'EHR.csproj').resolve():raise ValueError('Output cannot overwrite input project')
    tree=E.parse(project);root=tree.getroot();plans=[]
    for item in root.iter('Compile'):
        include=item.get('Include')
        if not include:continue
        path=(project.parent/include).resolve()
        if path.name in RULES:
            relative=RULES[path.name][0]
            if relative not in pins:raise ValueError('Missing reviewed selected-source pin: '+relative)
            text,report=transform(path.name,path.read_bytes(),pins[relative]);plans.append((item,path,text,report))
        else:item.set('Include',str(path))
    if len(plans)!=3 or len({p[1].name for p in plans})!=3:raise ValueError('Expected exactly the three reviewed source inputs')
    # Validate every input before any output source is written.
    output.mkdir(parents=True,exist_ok=True);(output/'source').mkdir(exist_ok=True)
    reports=[]
    for item,path,text,report in plans:
        target=output/'source'/path.name;target.write_text(text);item.set('Include',str(target.resolve()))
        report['outputSha256']=sha(target.read_bytes());reports.append(report)
    context=output/'EHRSourceJsonContext.cs';context.write_text(CONTEXT)
    E.SubElement(E.SubElement(root,'ItemGroup'),'Compile',Include=str(context.resolve()))
    for item in root.iter():
        if item.tag in ('EmbeddedResource','Reference') and item.get('Include'):
            path=Path(item.get('Include'))
            if not path.is_absolute() and (project.parent/path).exists():item.set('Include',str((project.parent/path).resolve()))
        if item.tag=='HintPath' and item.text and not Path(item.text).is_absolute():item.text=str((project.parent/item.text).resolve())
    E.indent(tree);tree.write(output/'EHR.csproj',encoding='unicode')
    result=dict(upstreamCommit=COMMIT,selectorsSha256=SELECTOR_SHA,scope='Three explicit source compatibility adaptations, not full feature or gameplay parity',adapters=reports,jsonContextSha256=sha(context.read_bytes()))
    (output/'source-view-adapters.json').write_text(json.dumps(result,indent=2)+'\n');return result
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['project','upstream-root','input-pins','selectors','output']:p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args();print(json.dumps(generate(args.project.resolve(),args.upstream_root.resolve(),json.loads(args.input_pins.read_text()),args.selectors.resolve(),args.output.resolve()),indent=2))
if __name__=='__main__':main()
