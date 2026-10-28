#!/usr/bin/env python3
"""Execute the actual generated private helpers on an owned test universe."""
from pathlib import Path
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--dotnet',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);s=a.source.read_text();begin=s.index('    private static bool IOSNoClipStillEligible()');end=s.index('    private void DrawButtons(',begin);helpers=s[begin:end]
assert s.index('        ReconcileIOSNoClip();',s.index('private void OnGUI()'))<s.index('if (!HudManager.InstanceExists)',s.index('private void OnGUI()'))
assert 'canMove && Main.IntroDestroyed && (!AmongUsClient.Instance.IsGameStarted || !GameStates.IsOnlineGame) && (!GameStartManager.Instance || GameStartManager.Instance.startState == GameStartManager.StartingStates.NotStarting)' in s
program='''using System;
class UnityObject{public bool Alive=true;public static implicit operator bool(UnityObject? value)=>value is{Alive:true};public static bool operator !(UnityObject? value)=>value is not{Alive:true};}
record struct Vector2(float x,float y);
class Collider:UnityObject{public Vector2 offset;}
class PlayerControl:UnityObject{public static PlayerControl? LocalPlayer;public Collider Collider=new();}
class AmongUsClient:UnityObject{public static AmongUsClient? Instance;public bool IsGameStarted;}
class GameStartManager:UnityObject{public enum StartingStates{NotStarting,Countdown}public static GameStartManager? Instance;public StartingStates startState;}
static class Main{public static bool IntroDestroyed;}
static class GameStates{public static bool IsCanMove,IsOnlineGame;}
static class OperatingSystem{public static bool IOS=true;public static bool IsIOS()=>IOS;}
static class ControllerManagerUpdatePatch{public static bool NoClipEnabled;}
static class SourceHelpers{
'''+helpers+'''
internal static bool Eligible()=>IOSNoClipStillEligible();internal static void Reset()=>ResetIOSNoClip();internal static void Reconcile()=>ReconcileIOSNoClip();}
static class Program{
static int n;static void Check(bool value){++n;if(!value)throw new Exception("check "+n);}
static void Main(){
for(int bits=0;bits<64;++bits){bool move=(bits&1)!=0,intro=(bits&2)!=0,started=(bits&4)!=0,online=(bits&8)!=0,manager=(bits&16)!=0,counting=(bits&32)!=0;
PlayerControl.LocalPlayer=new();AmongUsClient.Instance=new(){IsGameStarted=started};GameStartManager.Instance=manager?new(){startState=counting?GameStartManager.StartingStates.Countdown:GameStartManager.StartingStates.NotStarting}:null;GameStates.IsCanMove=move;GameStates.IsOnlineGame=online;global::Main.IntroDestroyed=intro;
ControllerManagerUpdatePatch.NoClipEnabled=true;PlayerControl.LocalPlayer.Collider.offset=new(0,127);
// The independently partitioned exclusions are exactly the original source rule.
bool excluded=!move||!intro||(started&&online)||(manager&&counting);Check(SourceHelpers.Eligible()==!excluded);SourceHelpers.Reconcile();Check(ControllerManagerUpdatePatch.NoClipEnabled==!excluded);Check(PlayerControl.LocalPlayer.Collider.offset.y==(excluded?-0.3636f:127f));
ControllerManagerUpdatePatch.NoClipEnabled=false;SourceHelpers.Reconcile();Check(!ControllerManagerUpdatePatch.NoClipEnabled);
}
OperatingSystem.IOS=false;ControllerManagerUpdatePatch.NoClipEnabled=true;PlayerControl.LocalPlayer=new();PlayerControl.LocalPlayer.Collider.offset=new(0,127);GameStates.IsCanMove=false;SourceHelpers.Reconcile();SourceHelpers.Reset();Check(ControllerManagerUpdatePatch.NoClipEnabled&&PlayerControl.LocalPlayer.Collider.offset.y==127);
OperatingSystem.IOS=true;SourceHelpers.Reset();Check(!ControllerManagerUpdatePatch.NoClipEnabled&&PlayerControl.LocalPlayer.Collider.offset.y==-0.3636f);
ControllerManagerUpdatePatch.NoClipEnabled=true;PlayerControl.LocalPlayer=null;SourceHelpers.Reconcile();Check(!ControllerManagerUpdatePatch.NoClipEnabled);
PlayerControl.LocalPlayer=new();PlayerControl.LocalPlayer.Collider.Alive=false;ControllerManagerUpdatePatch.NoClipEnabled=true;SourceHelpers.Reset();Check(!ControllerManagerUpdatePatch.NoClipEnabled);
PlayerControl.LocalPlayer=new();AmongUsClient.Instance=null;ControllerManagerUpdatePatch.NoClipEnabled=true;SourceHelpers.Reconcile();Check(!ControllerManagerUpdatePatch.NoClipEnabled&&PlayerControl.LocalPlayer.Collider.offset.y==-0.3636f);
Console.WriteLine("PASS "+n+" actual-source iOS NoClip guard/restoration checks; no game executed");}}
'''
(out/'Program.cs').write_text(program);(out/'Fixture.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
r=subprocess.run([str(a.dotnet),'run','--project',str(out/'Fixture.csproj'),'-c','Release'],text=True,capture_output=True);(out/'test.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr,end='');raise SystemExit(r.returncode)
