#!/usr/bin/env python3
from pathlib import Path
import argparse,json,re,subprocess
p=argparse.ArgumentParser();p.add_argument('--overlay',type=Path,required=True);p.add_argument('--dotnet',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();report=json.loads((a.overlay/'storage-overlay.json').read_text())
for item in report['files']:
 before=Path(item['input']).read_text();after=Path(item['output']).read_text()
 if Path(item['output']).name=='AddSteamID.cs':assert after.replace('IsAndroid() || OperatingSystem.IsIOS()','IsAndroid()')==before
 else:assert after.replace('(OperatingSystem.IsAndroid() || OperatingSystem.IsIOS())','OperatingSystem.IsAndroid()')==before
cleanup=(a.overlay/'source/PlayerJoinAndLeftPatch.cs').read_text()
for guard in ['CleanOldItems(bool dryRun = true, int days = 7)','if (OperatingSystem.IsAndroid()) return (0, 0);','if (!Path.IsPathRooted(path))','if (!string.Equals(folderName, "EHR_Logs", StringComparison.OrdinalIgnoreCase))']:
 assert guard in cleanup,guard
utils=(a.overlay/'source/Utils.cs').read_text();condition=re.search(r'var basePath = (.*);',utils).group(1)
steam=(a.overlay/'source/AddSteamID.cs').read_text();steamGuard=re.search(r'if \((.*)\) return;',steam).group(1)
out=a.output
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True)
(out/'Fixture.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>')
(out/'Program.cs').write_text('''using System;static class OperatingSystem{public static bool IOS,Android;public static bool IsIOS()=>IOS;public static bool IsAndroid()=>Android;}
static class Main{public const string DataPath="/sandbox/host-owned-source-root";}static class Environment{public enum SpecialFolder{DesktopDirectory}public static string GetFolderPath(SpecialFolder unused)=>"/desktop-sentinel";}
static class Policy{public static string Path()=>'''+condition+''';public static bool SkipSteam()=>'''+steamGuard+''';}
static class Program{static void Main(){int n=0;for(int i=0;i<4;++i){OperatingSystem.IOS=(i&1)!=0;OperatingSystem.Android=(i&2)!=0;bool mobile=i!=0;if(Policy.Path()!=(mobile?global::Main.DataPath:"/desktop-sentinel")||Policy.SkipSteam()!=mobile)throw new Exception("policy "+i);n+=2;}Console.WriteLine("PASS "+n+" actual-source sandbox/Steam platform checks; no file operations");}}
''')
r=subprocess.run([str(a.dotnet),'run','--project',str(out/'Fixture.csproj'),'-c','Release'],text=True,capture_output=True);(out/'test.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr,end='');raise SystemExit(r.returncode)
