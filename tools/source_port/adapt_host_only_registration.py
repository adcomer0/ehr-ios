#!/usr/bin/env python3
"""Use official host-only +25 registration without all-client GUID filtering.

Only the pinned EHR AmciRegistration.Apply body is adapted. The game's normal
hosting/matchmaking code and all account/player protections remain in place.
"""
import argparse
import hashlib
import json
from pathlib import Path

BEFORE='''        CurrentModRegistration.ModRegistrationGuidString = ModGuidString;
        Logger.Info($"AMCI mod GUID registered: {ModGuidString}", nameof(AmciRegistration));'''
AFTER='''        CurrentModRegistration.ModRegistrationGuidString = string.Empty;
        Logger.Info("iOS host-only registration: +25 protocol, no all-client GUID", nameof(AmciRegistration));'''

def transform(data,expected_sha256):
    if hashlib.sha256(data).hexdigest()!=expected_sha256:raise ValueError('Selected registration source hash mismatch')
    text=data.decode('utf-8-sig');newline='\r\n' if '\r\n' in text else '\n';text=text.replace('\r\n','\n')
    if text.count(BEFORE)!=1 or text.count('public static void Apply()')!=1:
        raise ValueError('Reviewed all-client registration body changed')
    start=text.index('public static void Apply()');end=text.index('\n    }',start)
    if BEFORE not in text[start:end]:raise ValueError('Registration write is not in the reviewed Apply body')
    output=text.replace(BEFORE,AFTER,1).replace('\n',newline).encode('utf-8')
    if data.startswith(b'\xef\xbb\xbf'):output=b'\xef\xbb\xbf'+output
    return output,dict(schema='ehr.ios-host-only-registration.v1',inputSha256=expected_sha256,
        outputSha256=hashlib.sha256(output).hexdigest(),allClientGuidEnabled=False,
        hostOnlyPlus25SourceUnchanged=True,originalHostingAndAccountChecksUnchanged=True,
        vanillaJoinVerified=False,officialReference='https://github.com/Innersloth-LLC/AmongUsModdingInformation')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['input','output']:parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--input-sha256',required=True);args=parser.parse_args()
    if args.input.resolve()==args.output.resolve() or args.output.exists():parser.error('Choose a fresh separate output')
    output,report=transform(args.input.read_bytes(),args.input_sha256);args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(output);args.output.with_suffix('.registration.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))

if __name__=='__main__':main()
