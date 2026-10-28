#!/usr/bin/env python3
"""Replace only Main's registration handle, after sandbox path adaptation."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
def transform(data,expected):
    if hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Reviewed Main input hash mismatch')
    text=data.decode('utf-8');before='    public Harmony Harmony { get; } = new(PluginGuid);';after='    public global::EHR.SourcePatchOwner Harmony { get; } = new(PluginGuid);'
    if text.count(before)!=1:raise ValueError('Expected one Main Harmony owner initializer')
    if 'SourcePlatformPaths.DataRoot' not in text:raise ValueError('Apply native-owned sandbox DataPath overlay first')
    output=text.replace(before,after).encode();return output,{'inputSha256':expected,'outputSha256':hashlib.sha256(output).hexdigest(),'scope':'Main registration owner only; no runtime Harmony engine constructed','loadBodyUnchanged':True,'dataPathStillNativeOwned':True}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--expected-sha256',required=True);a=p.parse_args()
    try:
        if a.input.resolve()==a.output.resolve():raise ValueError('Never overwrite source input')
        output,report=transform(a.input.read_bytes(),a.expected_sha256);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes(output);a.output.with_suffix(a.output.suffix+'.provenance.json').write_text(json.dumps(report,indent=2)+'\n')
    except (OSError,ValueError,UnicodeError) as e:p.exit(2,str(e)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
