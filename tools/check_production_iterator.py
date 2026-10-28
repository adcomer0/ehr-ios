#!/usr/bin/env python3
"""Compile actual new and old routing code; run owned fixtures, never the game."""
from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();stage=Path(__file__).resolve().parents[1];out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True)
native=a.source_root.resolve()/'native'
if 'EHRProductionIteratorMoveNext(identity, result)' not in (native/'EHRManagedIteratorAdapter.mm').read_text():raise ValueError('actual integrated production routing required')
includes=['-iquote',str(stage/'native'),'-iquote',str(stage/'native/include'),'-iquote',str(a.source_root/'native'),'-iquote',str(a.source_root/'native/include')]
base=['xcrun','clang++','-std=c++17','-fobjc-arc','-fobjc-arc-exceptions','-Wall','-Wextra','-Werror']+includes
commands=[]
def run(name,command):
 r=subprocess.run(command,text=True,capture_output=True);(out/(name+'.log')).write_text(r.stdout+r.stderr);commands.append({'name':name,'command':command,'exitCode':r.returncode,'output':(r.stdout+r.stderr).strip()});
 if r.returncode:raise RuntimeError(name+' failed; see '+str(out/(name+'.log')))
fixture=str(stage/'tests/production_iterator_fixture.mm')
run('compile-own',base+['-framework','Foundation',fixture,'-o',str(out/'own')]);run('own',[str(out/'own')])
run('compile-no-hooks',base+['-DEHR_TEST_PRODUCTION_NO_HOOKS=1','-framework','Foundation',fixture,'-o',str(out/'no-hooks')]);run('no-hooks',[str(out/'no-hooks')])
run('compile-combined',base+['-DEHR_COMBINED_ADAPTER="'+str(native/'EHRManagedIteratorAdapter.mm')+'"','-framework','Foundation',fixture,'-o',str(out/'combined')]);run('combined',[str(out/'combined')])
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
for name in ['EHRManagedIteratorProduction','EHRManagedIteratorAdapter']:
 run('ios-'+name,base+['-target','arm64-apple-ios17.0','-isysroot',sdk,'-c',str(native/(name+'.mm')),'-o',str(out/(name+'.o'))])
report={'schema':'ehr.production-iterator-owned-checks.v1','sourceRoot':str(a.source_root),'nativeSourceSha256':{name:hashlib.sha256((native/name).read_bytes()).hexdigest() for name in ['EHRManagedIteratorProduction.mm','EHRManagedIteratorAdapter.mm']},'actualGameExecuted':False,'oldStrongHostBytes':40,'oldCallbackBytes':32,'productionHostBytes':72,'productionStatusBytes':104,'checks':commands}
(out/'proof.json').write_text(json.dumps(report,indent=2)+'\n');print(out/'proof.json')
