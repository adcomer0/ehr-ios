#!/usr/bin/env python3
"""Own deterministic fixtures plus iOS syntax; never starts game/account/UI."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--current-native',action='store_true',default=True);p.add_argument('--generated-headers',type=Path);a=p.parse_args()
stage=Path(__file__).resolve().parents[1];root=a.source_root.resolve();out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);checks=[]
def run(name,command,env=None):
    result=subprocess.run(command,capture_output=True,text=True,env=env)
    (out/(name+'.log')).write_text(result.stdout+result.stderr)
    checks.append({'name':name,'command':command,'exitCode':result.returncode,'output':(result.stdout+result.stderr).strip()})
    if result.returncode:raise RuntimeError(name+' failed; see output log')
# Canonical source already contains the integrated implementation.
native=root/'native'
base=['xcrun','clang++','-std=c++17','-fobjc-arc','-fobjc-arc-exceptions','-Wall','-Wextra','-Werror','-iquote',str(native),'-iquote',str(root/'native'),'-iquote',str(root/'native/include'),'-DEHR_PRODUCTION_SOURCE="'+str(native/'EHRManagedIteratorProduction.mm')+'"','-DEHR_FAILURE_CLEANUP_SOURCE="'+str(native/'EHRSourceFailureCleanup.inc')+'"']
fixture=str(stage/'tests/production_iterator_fixture.mm');binary=str(out/'iterator')
run('compile-iterator',base+['-framework','Foundation',fixture,'-o',binary])
for reset in [False,True]:
    for throws in [False,True]:
        env=os.environ.copy()
        if reset:env['EHR_FAILURE_RESET']='1'
        if throws:env['EHR_FAILURE_THROW_STOP']='1'
        run('iterator-'+str(int(reset))+str(int(throws)),[binary],env)
coordinator=str(out/'coordinator')
run('compile-coordinator',base+['-framework','Foundation',str(stage/'tests/failure_cleanup_fixture.mm'),'-o',coordinator]);run('coordinator',[coordinator])
run('compile-no-hooks',base+['-DEHR_TEST_PRODUCTION_NO_HOOKS=1','-framework','Foundation',fixture,'-o',str(out/'no-hooks')]);run('no-hooks',[str(out/'no-hooks')])
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
for name in ['EHRManagedIteratorProduction.mm','EHRSourceFailureCleanup.inc']:
    run('ios-'+name,base+['-target','arm64-apple-ios17.0','-isysroot',sdk,'-DEHR_HAS_FULL_SOURCE=1','-x','objective-c++','-c',str(native/name),'-o',str(out/(name+'.o'))])
run('ios-cleanup-default-profile',base+['-target','arm64-apple-ios17.0','-isysroot',sdk,'-DEHR_HAS_FULL_SOURCE=0','-x','objective-c++','-c',str(native/'EHRSourceFailureCleanup.inc'),'-o',str(out/'cleanup-default.o')])
if a.generated_headers:
    runtime=native/'EHRFullSourceRuntime.mm'
    run('ios-full-runtime',base+['-target','arm64-apple-ios17.0','-isysroot',sdk,'-DEHR_HAS_FULL_SOURCE=1','-iquote',str(native),'-iquote',str(a.generated_headers.resolve()),'-c',str(runtime),'-o',str(out/'EHRFullSourceRuntime.o')])
    run('ios-full-runtime-default-profile',base+['-target','arm64-apple-ios17.0','-isysroot',sdk,'-DEHR_HAS_FULL_SOURCE=0','-iquote',str(native),'-iquote',str(a.generated_headers.resolve()),'-c',str(runtime),'-o',str(out/'EHRFullSourceRuntime-default.o')])
proof={'schema':'ehr.startup-failure-owned-proof.v1','currentNative':a.current_native,'gameExecuted':False,'accountOperations':False,'dynamicCode':False,'productionHostBytes':72,'productionStatusBytes':104,'checks':checks,'files':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for directory in ['native','tests','tools'] for f in sorted((stage/directory).iterdir()) if f.is_file() and f.suffix in ['.h','.inc','.mm','.py']}}
(out/'proof.json').write_text(json.dumps(proof,indent=2)+'\n');print(out/'proof.json')
