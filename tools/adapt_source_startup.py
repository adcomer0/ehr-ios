#!/usr/bin/env python3
"""Pinned iOS initialization observations, Steam policy, and AOT enum calls."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
def transform(data,expected,kind):
    if hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Reviewed source hash mismatch')
    text=data.decode('utf-8');changes=[]
    def once(before,after):
        nonlocal text
        if text.count(before)!=1:raise ValueError('Source initialization anchor mismatch: '+before[:60])
        text=text.replace(before,after)
    newline='\r\n' if '\r\n' in text else '\n'
    if kind=='options':
        once('        AddSteamID.AddSteamAppIdFile();','        // iOS uses its signed application identity; no desktop Steam app-id file.')
        once('        IsLoaded = true;','        IsLoaded = true;'+newline+'        global::EHR.EHRSourceApplication.ObserveOptionsLoaded(OptionItem.AllOptions.Count);')
        once('        PostLoadTasks();','        PostLoadTasks();'+newline+'        global::EHR.EHRSourceApplication.ObserveOptionsPostLoad();')
        changes=['omit desktop Steam app-id file creation','observe original actual IsLoaded=true and completed PostLoadTasks; no status-triggered type initialization']
    elif kind=='enum-helper':
        once('public static T[] GetValues<T>() => (T[])Enum.GetValues(typeof(T));','public static T[] GetValues<T>() where T : struct, Enum => Enum.GetValues<T>();')
        once('public static string[] GetNames<T>() => Enum.GetNames(typeof(T));','public static string[] GetNames<T>() where T : struct, Enum => Enum.GetNames<T>();')
        changes=['real statically closed generic Enum APIs; same enum order/values/names']
    elif kind=='role-enum':
        once('Enum.GetValues(typeof(Mode)).Length','Enum.GetValues<Mode>().Length')
        changes=['real statically closed nested Mode enum API']
    else:raise ValueError('Unknown source adaptation')
    output=text.encode('utf-8');return output,{'inputSha256':expected,'outputSha256':hashlib.sha256(output).hexdigest(),'kind':kind,'changes':changes}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kind',choices=['options','enum-helper','role-enum'],required=True);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--expected-sha256',required=True);a=p.parse_args()
    try:
        if a.input.resolve()==a.output.resolve():raise ValueError('Never overwrite source input')
        output,report=transform(a.input.read_bytes(),a.expected_sha256,a.kind);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes(output);a.output.with_suffix(a.output.suffix+'.provenance.json').write_text(json.dumps(report,indent=2)+'\n')
    except (OSError,ValueError,UnicodeError) as e:p.exit(2,str(e)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
