#!/usr/bin/env python3
"""Compose the reviewed sandboxed iOS sound route after actual native audio proof.

No base-game DLLs, account state, runtime code writes, or arbitrary audio playback
are performed by this source tool. Generated upstream derivatives stay external.
"""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
import xml.etree.ElementTree as E

SOUND_SHA='8a03cd79cb9f20c40d79cb17a55c368889d5d4a9e422314c6506dd5426682308'
DATA_WORDS=[1,0,8,1,1,1,1,1,1,1,1,1,1,18,0,0]
MUTED_WORDS=[1,0,7,1,1,1,1,1,1,1,1,0,8,1,0,0]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def proof_gate(path):
    proof=json.loads(path.read_text())
    if proof.get('schema')!='ehr.full-source-audio-proof.v1':raise ValueError('Actual full-source audio proof schema required')
    for name,words in [('ehr_source_audio_data_probe_v1',DATA_WORDS),('ehr_source_muted_sound_probe_v1',MUTED_WORDS)]:
        result=proof.get(name,{})
        if result.get('status')!=0 or result.get('words')!=words:raise ValueError('Native audio data and muted route must both pass exactly')
    if proof.get('accountActionsPerformed') is not False or proof.get('playbackVolume')!=0:raise ValueError('The prerequisite is an account-free zero-volume proof')
def transform(data,expected):
    if hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Pinned CustomSounds source hash mismatch')
    text=data.decode('utf-8-sig');eol='\r\n' if '\r\n' in text else '\n'
    path='    private static readonly string SoundsPath = $"{Environment.CurrentDirectory.Replace(@"\\", "/")}/BepInEx/resources/";'
    guard='            if (!Constants.ShouldPlaySfx() || !Main.EnableCustomSoundEffect.Value || !OperatingSystem.IsWindows()) return;'
    if text.count(path)!=1 or text.count(guard)!=1:raise ValueError('Exact pinned sound anchors required')
    # Conditional evaluation prevents the original cwd expression from running
    # on iOS. The full Windows initializer/path/loader remains byte-identical.
    text=text.replace(path,path.replace('= $"','= OperatingSystem.IsIOS() ? "" : $"'),1)
    replacement=eol.join([
        '            if (!Constants.ShouldPlaySfx() || !Main.EnableCustomSoundEffect.Value) return;',
        '            if (OperatingSystem.IsIOS())',
        '            {',
        '                global::EHR.SourceAudio.SourceAudioPlayback.Play(sound, volume, pitch);',
        '                return;',
        '            }',
        '            if (!OperatingSystem.IsWindows()) return;'])
    text=text.replace(guard,replacement,1)
    result=text.encode('utf-8')
    if data.startswith(b'\xef\xbb\xbf'):result=b'\xef\xbb\xbf'+result
    return result
def prepare(project,output,pcm,proof=None,helpers=None):
    project=project.resolve();output=output.resolve();pcm=pcm.resolve()
    if output.exists():raise ValueError('Fresh output directory required')
    if not pcm.is_file():raise ValueError('Reviewed PCM decoder source required')
    own=helpers.resolve() if helpers else Path(__file__).resolve().parents[1]/'managed'
    selected_helpers={p.name:p for p in [pcm,own/'OwnedSoundFiles.cs',own/'SourceAudioPlayback.cs',own/'SourceAudioNames.cs']}
    if not all(p.is_file() for p in selected_helpers.values()):raise ValueError('All four current audio helpers, including SourceAudioNames, are required')
    if proof is not None:proof_gate(proof)
    tree=E.parse(project);root=tree.getroot();selected=None;existing_helpers={}
    for item in root.iter('Compile'):
        value=item.get('Include','')
        if any(c in value for c in '$*?'):raise ValueError('Explicit source paths required')
        path=Path(value);path=(project.parent/path).resolve() if not path.is_absolute() else path.resolve()
        item.set('Include',str(path))
        if path.name in selected_helpers:
            if path.name in existing_helpers:raise ValueError('Duplicate audio helper basename: '+path.name)
            current=selected_helpers[path.name]
            if path.name=='SourceAudioNames.cs' and sha(path)!=sha(current):raise ValueError('Conflicting SourceAudioNames implementation')
            existing_helpers[path.name]={'path':str(path),'sha256':sha(path)}
            item.set('Include',str(current))
        if path.name=='CustomSounds.cs':
            if selected is not None:raise ValueError('Single pinned CustomSounds source required')
            selected=(item,path)
    if selected is None or sha(selected[1])!=SOUND_SHA:raise ValueError('Pinned upstream CustomSounds source required')
    for item in root.iter('EmbeddedResource'):
        value=item.get('Include','');path=Path(value)
        if '$' in value:raise ValueError('Explicit resource paths required')
        item.set('Include',str((project.parent/path).resolve() if not path.is_absolute() else path.resolve()))
    output.mkdir(parents=True);group=E.SubElement(root,'ItemGroup')
    for name,path in selected_helpers.items():
        if name not in existing_helpers:E.SubElement(group,'Compile',Include=str(path))
    if proof is not None:
        target=output/'CustomSounds.cs';target.write_bytes(transform(selected[1].read_bytes(),SOUND_SHA));selected[0].set('Include',str(target))
    E.indent(root);tree.write(output/'EHR.csproj',encoding='unicode')
    report={'schema':1,'sourceSha256':SOUND_SHA,'upstreamSoundGuardsPreserved':True,'rpcBodiesUnchanged':True,'windowsBodyUnchanged':True,'iosProductionRouteEnabled':proof is not None,'runtimeProofPath':str(proof.resolve()) if proof else None,'runtimeProofSha256':sha(proof) if proof else None,'pcmDecoderSha256':sha(pcm),'outputSourceSha256':sha(output/'CustomSounds.cs') if proof else SOUND_SHA,'namesSelected':True,'selectedHelpers':{name:{'path':str(path),'sha256':sha(path)} for name,path in selected_helpers.items()},'replacedInputHelpers':existing_helpers}
    (output/'audio-overlay.json').write_text(json.dumps(report,indent=2)+'\n');return output/'EHR.csproj'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--pcm-source',type=Path,required=True);p.add_argument('--runtime-proof',type=Path,help='Omit to compile the helper with original Windows-only production guard')
    a=p.parse_args()
    try:print(prepare(a.project,a.output,a.pcm_source,a.runtime_proof))
    except (OSError,ValueError,E.ParseError) as error:p.exit(2,str(error)+'\n')
if __name__=='__main__':main()
