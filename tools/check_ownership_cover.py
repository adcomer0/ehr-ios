#!/usr/bin/env python3
"""Run the actual owned UIKit license-cover fixture in a fresh simulator.

No game inputs, player keys, profiles, accounts or physical devices are used.
Output must be a new directory outside Git. The created simulator is removed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args();out=args.output_root.resolve()
    if out.exists() or any((p/'.git').exists() for p in (out,*out.parents)):
        parser.error('Output must be new and outside Git')
    out.mkdir(parents=True,mode=0o700)
    def run(label,command,timeout=90):
        result=subprocess.run(command,capture_output=True,text=True,timeout=timeout)
        log=out/(label+'.local.log');log.write_text(result.stdout+result.stderr);log.chmod(0o600)
        if result.returncode:raise RuntimeError(label+' failed; inspect local log')
        return result.stdout.strip()
    names=('native/EHROwnershipCover.h','native/EHROwnershipCover.mm','native/EHRFullSourceOverlay.mm',
           'native/EHRItchAuthProvider.h','tests/OwnershipCoverUIKitFixture.mm')
    pins={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in names}
    app=out/'OwnershipFixture.app';app.mkdir()
    sdk=run('sdk',['xcrun','--sdk','iphonesimulator','--show-sdk-path'])
    command=['xcrun','clang++','-target','arm64-apple-ios17.0-simulator','-isysroot',sdk,
        '-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror',
        str(ROOT/'tests/OwnershipCoverUIKitFixture.mm'),str(ROOT/'native/EHROwnershipCover.mm')]
    for framework in ('UIKit','Foundation','QuartzCore','CoreGraphics'):command+=['-framework',framework]
    run('compile',command+['-o',str(app/'EHRNativeGame')])
    info={'CFBundleIdentifier':'org.ehr.owned.cover','CFBundleExecutable':'EHRNativeGame',
        'CFBundleName':'OwnershipFixture','CFBundleDisplayName':'Owned EHR Cover',
        'CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL',
        'MinimumOSVersion':'17.0','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],
        'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},
        'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
        'UILaunchScreen':{}}
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2(ROOT/'app/Assets.xcassets/AppIcon.appiconset/AppIcon.png',app/'EHRBrandIcon.png')
    run('sign-own-fixture',['codesign','--force','--sign','-',str(app)])
    inventory=json.loads(run('simulator-inventory',['xcrun','simctl','list','--json']))
    kind=next(t for t in inventory['devicetypes'] if t['name']=='iPhone 17 Pro Max')
    runtime=sorted((t for t in inventory['runtimes'] if t.get('isAvailable') and t.get('name','').startswith('iOS')),
        key=lambda t:tuple(int(x) for x in t['version'].split('.')))[-1]
    device=run('create-own-simulator',['xcrun','simctl','create','Owned EHR Cover '+str(time.time_ns()),kind['identifier'],runtime['identifier']])
    process=None
    try:
        run('boot',['xcrun','simctl','boot',device])
        run('bootstatus',['xcrun','simctl','bootstatus',device,'-b'],120)
        run('install-own-fixture',['xcrun','simctl','install',device,str(app)])
        container=Path(run('own-container',['xcrun','simctl','get_app_container',device,'org.ehr.owned.cover','data']))
        allowed={'ownership-cover-portrait.png','ownership-cover-landscape.png'};captured=set();started=time.time()
        with (out/'launch.local.log').open('w') as log:
            process=subprocess.Popen(['xcrun','simctl','launch','--console',device,'org.ehr.owned.cover'],stdout=log,stderr=subprocess.STDOUT)
            while process.poll() is None and time.time()-started<70:
                try:
                    phase=container/'Documents/phase.json'
                    if phase.stat().st_mtime>=started:
                        name=json.loads(phase.read_text())['file']
                        if name in allowed and name not in captured:
                            run('screenshot-'+str(len(captured)),['xcrun','simctl','io',device,'screenshot','--type=png',str(out/name)],15)
                            captured.add(name)
                except (FileNotFoundError,KeyError,json.JSONDecodeError):pass
                time.sleep(.04)
            if process.poll() is None:raise RuntimeError('Owned fixture timed out')
        proof=json.loads((container/'Documents/proof.json').read_text())
        (out/'uikit-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
        if not proof['success']:raise RuntimeError('Owned checks failed: '+str(proof['failures']))
        if captured!=allowed:raise RuntimeError('Actual simulator screenshots missing')
        if pins!={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in names}:
            raise RuntimeError('Fixture source changed during verification')
        provenance={'schema':'ehr.ownership-cover-provenance.v1','sourceHashes':pins,
            'actualSimulatorScreenshots':sorted(captured),'actualCredentialsRead':0,
            'networkRequests':0,'physicalDeviceActions':0,'gameInputs':0}
        (out/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
        print(json.dumps({'success':True,'checks':proof['checks'],'screenshots':len(captured),'networkRequests':0}))
    finally:
        if process is not None and process.poll() is None:process.terminate()
        subprocess.run(['xcrun','simctl','shutdown',device],capture_output=True,timeout=30)
        subprocess.run(['xcrun','simctl','delete',device],capture_output=True,timeout=30)

if __name__=='__main__':main()
