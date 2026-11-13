#!/usr/bin/env python3
"""Run the owned UIKit scene fixture in an explicitly selected iOS simulator.

Contains no Unity/game code. Never accesses a physical device, signing account,
credentials or another app's container. Newly created simulators are retained,
then shut down; none are reset or deleted. Keep all output outside this repo.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
BUNDLE='org.ehr.owned.scene-fixture'

def run(command,timeout=120):
    return subprocess.run(command,capture_output=True,text=True,timeout=timeout,check=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    selected=parser.add_mutually_exclusive_group(required=True)
    selected.add_argument('--simulator-id-file',type=Path,help='Explicit own simulator UUID file; never a physical device')
    selected.add_argument('--create-simulator',action='store_true',help='Create and retain a fresh owned simulator, never download a runtime')
    parser.add_argument('--hidden-window',action='store_true',help='Own fixture starts with a hidden window and lazy root')
    parser.add_argument('--runtime',default='com.apple.CoreSimulator.SimRuntime.iOS-27-0')
    parser.add_argument('--device-type',default='com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max')
    args=parser.parse_args();out=args.output.resolve()
    if out==ROOT or ROOT in out.parents:parser.error('Output must be outside the source repository')
    if out.exists():parser.error('Choose a new output directory')
    out.mkdir(parents=True)
    inputs=['tests/UnitySceneUIKitFixture.mm','native/launcher/EHRUnitySceneDelegate.h','native/launcher/EHRUnitySceneDelegate.mm','native/launcher/EHRUnityFrameworkAPI.h']
    hashes={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in inputs}
    sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path']).stdout.strip();app=out/'EHRSceneOwned.app';app.mkdir()
    info={'CFBundleExecutable':'EHRSceneOwned','CFBundleIdentifier':BUNDLE,'CFBundleName':'Owned scene fixture','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','MinimumOSVersion':'17.0','LSRequiresIPhoneOS':True,'OwnedHiddenWindow':args.hidden_window,'UIDeviceFamily':[1,2],'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Owned Unity scene','UISceneDelegateClassName':'EHRUnitySceneDelegate'}]}}}
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    command=['xcrun','clang++','-target','arm64-apple-ios17.0-simulator','-isysroot',sdk,'-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror',str(ROOT/inputs[0]),str(ROOT/inputs[2]),'-framework','UIKit','-framework','Foundation','-o',str(app/'EHRSceneOwned')]
    compiled=subprocess.run(command,capture_output=True,text=True);(out/'compile.log').write_text(compiled.stdout+compiled.stderr)
    if compiled.returncode:raise RuntimeError('Owned fixture compilation failed; see compile.log')
    run(['codesign','--force','--sign','-',str(app)])
    if args.create_simulator:
        runtimes=json.loads(run(['xcrun','simctl','list','runtimes','-j']).stdout)['runtimes']
        if not any(x.get('identifier')==args.runtime and x.get('isAvailable') for x in runtimes):raise RuntimeError('Requested installed simulator runtime is unavailable; nothing downloaded')
        simulator=run(['xcrun','simctl','create','EHR Owned Scene Fixture',args.device_type,args.runtime]).stdout.strip();was_booted=False
    else:
        simulator=args.simulator_id_file.read_text().strip()
        devices=json.loads(run(['xcrun','simctl','list','devices','-j']).stdout)['devices']
        match=[d for group in devices.values() for d in group if d.get('udid')==simulator]
        if len(match)!=1:raise RuntimeError('Explicit simulator identifier not found')
        was_booted=match[0].get('state')=='Booted'
    (out/'simulator.local.json').write_text(json.dumps({'udid':simulator,'wasBooted':was_booted,'createdForThisProof':args.create_simulator},indent=2)+'\n')
    try:
        run(['xcrun','simctl','bootstatus',simulator,'-b']);run(['xcrun','simctl','install',simulator,str(app)])
        launched=run(['xcrun','simctl','launch','--console',simulator,BUNDLE],timeout=45);(out/'launch.local.log').write_text(launched.stdout+launched.stderr)
        container=Path(run(['xcrun','simctl','get_app_container',simulator,BUNDLE,'data']).stdout.strip())
        proof=json.loads((container/'Documents/proof.json').read_text());(out/'proof.json').write_text(json.dumps(proof,indent=2)+'\n')
        if hashes!={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in inputs}:raise RuntimeError('Source changed while proof was running')
        provenance={'schema':'ehr.unity-scene-fixture-provenance.v1','sourceHashes':hashes,'binarySHA256':hashlib.sha256((app/'EHRSceneOwned').read_bytes()).hexdigest(),'newSimulator':args.create_simulator,'requestedRuntime':args.runtime,'physicalDeviceActions':0,'gameFilesUsed':False,'networkRequests':0,'credentialsRead':0}
        (out/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n');print(json.dumps(proof,indent=2))
        return 0 if proof.get('success') else 1
    finally:
        if not was_booted:
            shutdown=subprocess.run(['xcrun','simctl','shutdown',simulator],capture_output=True,text=True,timeout=30)
            (out/'shutdown.local.log').write_text(shutdown.stdout+shutdown.stderr)

if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as error:
        print('Owned scene fixture failed:',type(error).__name__,file=sys.stderr);raise SystemExit(1)
