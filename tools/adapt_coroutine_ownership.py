#!/usr/bin/env python3
"""Add explicit post-success ownership bookkeeping to real coroutine facades."""
from __future__ import annotations
import argparse,hashlib,json,re
from pathlib import Path
def sha(data):return hashlib.sha256(data).hexdigest()
def surface(data,expected):
    if sha(data)!=expected:raise ValueError('Generated facade hash mismatch')
    text=data.decode();pattern=re.compile(r'(    public (?P<result>[^\n]+) @(?P<name>StartCoroutine|StopCoroutine|StopAllCoroutines)\((?P<args>[^\n]*)\)\n    \{\n)(?P<body>.*?)(    \}\n)',re.S)
    if 'ProductionCoroutines.Started(' in text or 'ProductionCoroutines.Stopped' in text:raise ValueError('Coroutine ownership already adapted')
    count=0
    def replace(match):
        nonlocal count
        body=match['body'];name=match['name'];args=match['args']
        if 'FacadeRuntime.Invoke(' not in body:raise ValueError('Coroutine facade no longer calls actual gateway')
        if name=='StartCoroutine':
            if 'IEnumerator' not in args:raise ValueError('Unreviewed coroutine start overload')
            anchor='        return result.Token == 0 ? null : '
            if body.count(anchor)!=1:raise ValueError('Coroutine start return changed')
            body=body.replace(anchor,'        ProductionCoroutines.Started(this, @routine, result);\n'+anchor)
        elif name=='StopAllCoroutines':
            body+='        ProductionCoroutines.StoppedOwner(this);\n'
        elif 'IEnumerator' in args:body+='        ProductionCoroutines.StoppedCarrier(@routine);\n'
        elif 'Coroutine' in args:body+='        ProductionCoroutines.StoppedHandle(@routine);\n'
        else:raise ValueError('Unreviewed coroutine stop overload')
        count+=1;return match[1]+body+match[6]
    output=pattern.sub(replace,text)
    if count!=4:raise ValueError('Expected exactly four real coroutine facade overloads')
    return output.encode(),{'inputSha256':sha(data),'outputSha256':sha(output.encode()),'realGatewayCallsPreserved':True,'patchedOverloads':count,'onlyAfterNativeSuccess':True}
def main_source(data,expected):
    if sha(data)!=expected:raise ValueError('Main source hash mismatch')
    text=data.decode();before='        coroutines.StopCoroutine(coroutine.WrapToIl2Cpp());';after='        global::EHR.Generated.ProductionCoroutines.StopSource(coroutines, coroutine);'
    if text.count(before)!=1:raise ValueError('Main IEnumerator stop anchor mismatch')
    output=text.replace(before,after).encode();return output,{'inputSha256':sha(data),'outputSha256':sha(output),'scope':'exact CLR-source identity reuse for Main.StopCoroutine(IEnumerator)','nativeStopBeforeClose':True}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kind',choices=['surface','main'],required=True);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--expected-sha256',required=True);a=p.parse_args()
    try:
        if a.input.resolve()==a.output.resolve():raise ValueError('Never overwrite the input')
        data,proof=(surface if a.kind=='surface' else main_source)(a.input.read_bytes(),a.expected_sha256);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes(data);a.output.with_suffix(a.output.suffix+'.provenance.json').write_text(json.dumps(proof,indent=2)+'\n')
    except (OSError,ValueError,UnicodeError) as e:p.exit(2,str(e)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
