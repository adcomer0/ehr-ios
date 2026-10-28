#!/usr/bin/env python3
"""Adapt only desktop DLL installation/cleanup to an explicit signed-iOS handoff."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

REVIEWED_INPUT_SHA256='ae3a51e3fc1d4925fcbeab89e7021942744da8551dc5356c979309cc29d72599'
def sha(data):return hashlib.sha256(data).hexdigest()
def section(text,start,end,replacement):
    if text.count(start)!=1 or text.count(end)!=1:raise ValueError("Pinned updater anchor mismatch")
    i=text.index(start);j=text.index(end,i)
    return text[:i]+replacement+text[j:]
def transform(data,expected_sha256=REVIEWED_INPUT_SHA256):
    if sha(data)!=expected_sha256:raise ValueError("Updater source hash does not match reviewed input")
    text=data.decode('utf-8');newline='\r\n' if '\r\n' in text else '\n';text=text.replace('\r\n','\n')
    original_check=text[text.index('    private static IEnumerator CheckReleaseFromGithub'):text.index('\n#if IL2CPP\n    private static string FindDllAssetUrl')]
    text=text.replace('    const string SavePath = "BepInEx/plugins/EHR.dll.temp";\n','')
    text=text.replace('            NewVersionCheck();\n            DeleteOldFiles();\n','')
    text=text.replace('GetString("updateButton"), onClickOnFirstButton:', 'global::EHR.SourceHost.SourceSignedUpdates.ActionTitle, onClickOnFirstButton:')
    text=text.replace('DownloadUrl = FindDllAssetUrl(data);','DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;')
    guard='''            if (string.IsNullOrWhiteSpace(DownloadUrl))
            {
                Logger.Error("No EHR.dll download URL found in release assets", "CheckRelease");
                IsBroken = true;
                yield break;
            }

'''
    if text.count(guard)!=1:raise ValueError('Desktop release-asset guard changed')
    text=text.replace(guard,'')
    start='    public static void StartUpdate(string url)'
    end='    public static void ShowPopup(string message,'
    replacement='''    public static void StartUpdate(string url)
    {
        // The upstream URL may name a desktop DLL. Only the immutable native
        // host configuration can select this build's iPhone update instructions.
        global::EHR.SourceHost.SourceSignedUpdates.OpenInstructions();
        ShowPopup(global::EHR.SourceHost.SourceSignedUpdates.StatusMessage, StringNames.Close, true, false);
    }

    public static void UpdateFailed()
    {
        ShowPopup(global::EHR.SourceHost.SourceSignedUpdates.StatusMessage, StringNames.Close, true, false);
    }

'''
    text=section(text,start,end,replacement)
    # Assert that the legitimate version/title comparison and release request
    # remain exactly unchanged except for the explicit asset-policy adaptation.
    expected=original_check.replace('DownloadUrl = FindDllAssetUrl(data);','DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;').replace(guard,'')
    actual=text[text.index('    private static IEnumerator CheckReleaseFromGithub'):text.index('\n#if IL2CPP\n    private static string FindDllAssetUrl')]
    if actual!=expected:raise ValueError('Release checking unexpectedly changed')
    output=text.replace('\n',newline).encode('utf-8')
    return output,{'inputSha256':sha(data),'outputSha256':sha(output),'releaseCheckingPreserved':True,'removedDesktopOperations':['DownloadDLL','Assembly.Location binary replacement','legacy folder migration deletion','DLL residue deletion'],'iOSBehavior':'configured HTTPS instructions opened only by explicit update action; otherwise explain rebuilt signed app required','downloadsOrInstalls':False,'accountOrSaveDataOperations':False}
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--expected-sha256',default=REVIEWED_INPUT_SHA256);args=parser.parse_args()
    try:
        if args.input.resolve()==args.output.resolve():raise ValueError('Never overwrite source input')
        output,report=transform(args.input.read_bytes(),args.expected_sha256);args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(output);args.output.with_suffix(args.output.suffix+'.provenance.json').write_text(json.dumps(report,indent=2)+'\n')
    except (OSError,ValueError,UnicodeError) as error:parser.exit(2,str(error)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
