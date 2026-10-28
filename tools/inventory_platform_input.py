#!/usr/bin/env python3
"""Pinned source lexical inventory; comments/preprocessor are not executable proof."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
p=argparse.ArgumentParser();p.add_argument('--upstream-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
commit=subprocess.check_output(['git','-C',str(a.upstream_root),'rev-parse','HEAD'],text=True).strip()
if commit!='ce23f0d050f617a59507e5bb0fbfff751d4b5134':raise ValueError('pinned source required')
sites=[];hashes={};pattern=re.compile(r'OperatingSystem\.Is\w+\(|Application\.platform|RuntimePlatform\.|Input\.(?:GetKey\w*|GetMouse\w*|touch\w*|mouseScrollDelta)|KeyCode\.')
for path in sorted(a.upstream_root.rglob('*.cs')):
 if any(x in path.parts for x in ['obj','bin','.git','CTA']):continue
 s=path.read_text();matches=[];conditions=[]
 for lineNo,line in enumerate(s.splitlines(),1):
  stripped=line.strip()
  if stripped.startswith('#if '):conditions.append(stripped[4:])
  elif stripped.startswith('#else') and conditions:conditions[-1]='ELSE('+conditions[-1]+')'
  elif stripped.startswith('#elif ') and conditions:conditions[-1]=stripped[6:]
  elif stripped.startswith('#endif') and conditions:conditions.pop()
  if pattern.search(line):matches.append({'line':lineNo,'text':stripped,'preprocessorLexicalStack':list(conditions)})
 if matches:
  name=str(path.relative_to(a.upstream_root));hashes[name]=hashlib.sha256(path.read_bytes()).hexdigest();sites.extend({'file':name,**x}for x in matches)
report={'schema':'ehr.platform-input-lexical-inventory.v1','upstreamCommit':commit,'lexicalSites':sites,'inputSha256':hashes,'commentsMayBeIncluded':True,'runtimeAvailabilityProven':False,'activeFeatureCountInferred':False}
if a.output.exists():raise ValueError('fresh output required')
a.output.write_text(json.dumps(report,indent=2)+'\n');print(len(sites),'lexical sites')
