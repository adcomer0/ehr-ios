#!/usr/bin/env python3
"""Compile exact transformed presentation methods against own numeric inputs."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--overlay',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--dotnet',type=Path,default=Path(os.environ.get('DOTNET', 'dotnet')));a=p.parse_args()
stage=Path(__file__).resolve().parents[1];out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);s=(a.overlay/'ClientControlGUI.cs').read_text()
def method(signature):
 start=s.index(signature);brace=s.index('{',start);level=1;end=brace+1
 while level:
  level+=(s[end]=='{')-(s[end]=='}');end+=1
 return s[start:end]
metrics=s[s.index('    private static float PlatformScale'):s.index('    // Credits: Xtracube')].replace('    private Camera _cam;','')
methods=[method('    private void RebuildStyles()'),method('    private static GUIStyle MakeBtn('),method('    private void InitWindowRect()'),method('    private void RefreshTouchLayout()'),method('    private void HandleDrag()'),method('    private void DrawWindow()')]
for signature in ['    private static Color Lift(','    private static Texture2D RoundedTexture(']:
 start=s.index(signature);methods.append(s[start:s.index(';',start)+1])
toggle=method('    private void DrawToggle()');toggle=toggle[:toggle.index('        // 90% transparent')]+'''        GUI.Button(ToggleRect, "Own geometry toggle", _sToggle);
    }''';methods.append(toggle)
slider=method('        float Slider(ref float sy,');methods.append(slider.replace('        float Slider(','    private float Slider(',1))
source='''using System;
using EHR.Generated;
using GUI=EHR.Generated.TouchGUI;
using GUIStyle=EHR.Generated.TouchGUIStyle;
using Texture2D=EHR.Generated.TouchTexture;
using Color=EHR.Generated.UnityEngine_Color;
using Rect=EHR.Generated.UnityEngine_Rect;
using Vector2=EHR.Generated.UnityEngine_Vector2;
using FontStyle=EHR.Generated.UnityEngine_FontStyle;
using TextAnchor=EHR.Generated.UnityEngine_TextAnchor;
using Mathf=GeometryMath;
using OperatingSystem=GeometryPlatform;
using Screen=GeometryViewport;
// Extracted actual source presentation only. No gameplay action body is run.
internal sealed class SourceGeometry {
 private bool IsOpen,_windowInitialized; private Rect _windowRect;private Vector2 _scroll;private float _contentH;
 private static Rect ToggleRect;
 internal int Rebuilds;
 internal Rect Rect=>_windowRect;
 internal void DragTo(float x,float y)=>_windowRect=new(x,y,_windowRect.width,_windowRect.height);
 internal void Run(bool open){IsOpen=open;var style=_sAction;RefreshTouchLayout();if(!ReferenceEquals(style,_sAction))Rebuilds++;HandleDrag();DrawToggle();if(open)DrawWindow();}
'''+metrics+'\n'+'\n'.join(methods)+'''
 private void DrawButtons(ref float y,float w){GUI.Button(new Rect(0,y,w,ButtonHeight),"Own action row",_sAction);y+=ButtonHeight+Padding*0.7f;Slider(ref y,"Own slider label",3,3,18,w);}
}
'''
(out/'SourceGeometry.cs').write_text(source)
(out/'Program.cs').write_bytes((stage/'tests/GeometryFixture.cs').read_bytes())
(out/'NativeTouchGUI.cs').write_bytes((a.overlay/'NativeTouchGUI.cs').read_bytes())
(out/'Geometry.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><AllowUnsafeBlocks>true</AllowUnsafeBlocks><Nullable>disable</Nullable><EnableDefaultCompileItems>true</EnableDefaultCompileItems><NoWarn>CS8632;CS0169;CS0414</NoWarn></PropertyGroup></Project>')
env=os.environ.copy()
r=subprocess.run([str(a.dotnet),'run','--project',str(out/'Geometry.csproj'),'-c','Release'],env=env,text=True,capture_output=True)
(out/'geometry.log').write_text(r.stdout+r.stderr)
if r.returncode:raise RuntimeError('geometry compile/run failed: '+r.stdout+r.stderr)
line=next(line for line in r.stdout.splitlines() if line.startswith('{'));proof=json.loads(line);proof['sourceGuiSha256']=hashlib.sha256((a.overlay/'ClientControlGUI.cs').read_bytes()).hexdigest();proof['sourceTouchSha256']=hashlib.sha256((a.overlay/'NativeTouchGUI.cs').read_bytes()).hexdigest();proof['extractedGeometrySha256']=hashlib.sha256(source.encode()).hexdigest();proof['methodExtractionOnly']=True;proof['gameInvoked']=False
(out/'proof.json').write_text(json.dumps(proof,indent=2)+'\n');print(out/'proof.json')
