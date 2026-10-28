from pathlib import Path
import importlib.util,json,os,subprocess,tempfile,unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('paste',ROOT/'tools/prepare_ios_keyboard_paste.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)


class PasteGuardTests(unittest.TestCase):
 def test_only_predicate_changes_and_duplicate_or_changed_anchor_fails(self):
  text='// Existing chat/name/phase/char-filter canary.\n'+M.OLD+'\n{ OriginalDesktopPasteBody(); }\n// Existing native touch input canary.\n'
  changed=M.adapt_source(text)
  self.assertEqual(changed.replace(M.NEW,M.OLD),text)
  self.assertIn('{ OriginalDesktopPasteBody(); }',changed)
  for invalid in (changed,text+text,text.replace('KeyCode.V','KeyCode.X')):
   with self.assertRaises(ValueError):M.adapt_source(invalid)
 def test_actual_selected_full_source_diff_is_exact(self):
  value=os.environ.get('EHR_CONTROL_PATCH_TEST_INPUT')
  if not value:self.skipTest('Set EHR_CONTROL_PATCH_TEST_INPUT to the selected unadapted ControlPatch.cs')
  path=Path(value)
  text=path.read_text();changed=M.adapt_source(text)
  self.assertEqual(changed.count('caretPos'),text.count('caretPos'))
  self.assertEqual(changed.replace(M.NEW,M.OLD),text)
 def test_compiled_predicate_keeps_ios_out_and_desktop_android_behavior(self):
  with tempfile.TemporaryDirectory(prefix='ehr-own-paste-')as temp:
   out=Path(temp)
   predicate=M.adapt_source(M.OLD)
   code='''using System.Text.Json;
enum KeyCode { LeftControl,RightControl,V }
static class Input { internal static bool Left,Right,Pressed; internal static bool GetKey(KeyCode key)=>key==KeyCode.LeftControl?Left:Right; internal static bool GetKeyDown(KeyCode key)=>Pressed; }
static class OperatingSystem { internal static bool IOS; internal static bool IsIOS()=>IOS; }
static class Program {
 static int MissingFieldReads;
 static void Run(bool chat,bool focus) { if(chat&&focus) { PREDICATE { MissingFieldReads++; } } }
 static void Main() { int checks=0;bool pass=true;foreach(int platform in new[]{0,1,2})foreach(bool left in new[]{false,true})foreach(bool right in new[]{false,true})foreach(bool press in new[]{false,true})foreach(bool chat in new[]{false,true})foreach(bool focus in new[]{false,true}){
 OperatingSystem.IOS=platform==0;Input.Left=left;Input.Right=right;Input.Pressed=press;MissingFieldReads=0;Run(chat,focus);
 pass&=MissingFieldReads==((platform!=0&&chat&&focus&&(left||right)&&press)?1:0);checks++;}
 Console.WriteLine(JsonSerializer.Serialize(new{pass,checks,gameCalls=0,nativeKeyboardInvoked=false}));if(!pass)Environment.Exit(1); }
}'''.replace('PREDICATE',predicate)
   (out/'Program.cs').write_text(code)
   (out/'Own.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>')
   (out/'NuGet.Config').write_text('<configuration><packageSources><clear/></packageSources></configuration>')
   env={**os.environ,'DOTNET_CLI_TELEMETRY_OPTOUT':'1','DOTNET_GENERATE_ASPNET_CERTIFICATE':'false','DOTNET_NOLOGO':'1'}
   r=subprocess.run([os.environ.get('EHR_DOTNET','dotnet'),'run','--project',str(out/'Own.csproj'),'-c','Release'],capture_output=True,text=True,check=True,env=env,timeout=60)
   proof=json.loads(next(line for line in r.stdout.splitlines()if line.startswith('{')))
   self.assertTrue(proof['pass']);self.assertEqual(proof['checks'],96);self.assertEqual(proof['gameCalls'],0)


if __name__=='__main__':unittest.main()
