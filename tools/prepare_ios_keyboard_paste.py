#!/usr/bin/env python3
"""Skip only the obsolete desktop caretPos paste block on iOS."""
from pathlib import Path
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET

OLD = '''if ((Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl)) &&
                            Input.GetKeyDown(KeyCode.V))'''
NEW = OLD.replace('if ((', 'if (!OperatingSystem.IsIOS() && (', 1)


def adapt_source(text):
    if text.count(OLD) != 1 or NEW in text:
        raise ValueError('Exact unadapted Ctrl+V predicate is absent or ambiguous')
    result = text.replace(OLD, NEW)
    if result.replace(NEW, OLD) != text:
        raise ValueError('Unexpected source mutation')
    return result


def sha(data): return hashlib.sha256(data).hexdigest()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--expected-control-sha256', required=True)
    a = p.parse_args(argv)
    project, output = a.project.resolve(), a.output.resolve()
    if output.exists() or any((root/'.git').exists() for root in (output, *output.parents)):
        raise ValueError('A new outside-Git output is required')
    tree = ET.parse(project)
    selected = []
    for item in tree.getroot().iter():
        include = item.get('Include')
        if item.tag.split('}')[-1] == 'Compile' and include and Path(include).name == 'ControlPatch.cs':
            path = Path(include); path = path if path.is_absolute() else project.parent/path
            selected.append((item,path.resolve()))
    if len(selected) != 1: raise ValueError('Exactly one selected ControlPatch is required')
    item, source = selected[0]
    before = source.read_bytes()
    if sha(before) != a.expected_control_sha256: raise ValueError('Selected control source hash differs')
    eol = b'\r\n' if b'\r\n' in before else b'\n'
    text = before.decode('utf-8').replace('\r\n','\n')
    after = adapt_source(text).replace('\n',eol.decode()).encode()
    if after.replace(NEW.replace('\n',eol.decode()).encode(), OLD.replace('\n',eol.decode()).encode()) != before:
        raise ValueError('Bytes outside the single predicate changed')
    (output/'source').mkdir(parents=True)
    target = output/'source/ControlPatch.cs'; target.write_bytes(after); item.set('Include',str(target))
    for node in tree.getroot().iter():
        if node.tag.split('}')[-1] not in ('Compile','EmbeddedResource','Import'): continue
        for key in ('Include','Project'):
            value=node.get(key)
            if value and not Path(value).is_absolute() and '$(' not in value and '*' not in value:
                node.set(key,str((project.parent/value).resolve()))
    tree.write(output/'EHR.csproj',encoding='unicode')
    report={'schema':'ehr.ios-native-keyboard-paste-guard.v1','input':str(source),
            'input_sha256':sha(before),'output_sha256':sha(after),
            'only_obsolete_desktop_ctrl_v_predicate_changed':True,'desktop_android_body_unchanged':True,
            'native_settext_and_filter_hooks_unchanged':True,'no_new_native_facades_or_calls':True,
            'physical_keyboard_paste_verified':False}
    (output/'keyboard-paste-overlay.json').write_text(json.dumps(report,indent=2)+'\n')
    print(output/'EHR.csproj')


if __name__=='__main__':main()
