import shutil
from pathlib import Path
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('account_adaptation',ROOT/'tools/source_port/adapt_account_protection.py');MODULE=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(MODULE)
POLICY=json.loads((ROOT/'tools/source_port/account_protection_policy.json').read_text())


def source_fixture(eol=b'\n'):
 files={
 'Modules/LobbySharingAPI.cs':'''// Own source canary before.
public static class LobbySharingAPI
{
    public static long LastRequestTimeStamp;
    public static string LastRoomCode = string.Empty;
    private static object OwnProducer() => EOSManager.Instance.UserIDToken;
}

[SuppressMessage("Own", "Canary")]
public class ExitGamePatch { public static void Postfix() { OwnKeptEffect(); } }
''',
 'Modules/OptionHolder.cs':'''PostLobbyCodeToEHRWebsite = new BooleanOptionItem(19422, "PostLobbyCodeToEHRDiscordServer", true, TabGroup.SystemSettings)
            .SetHeader(true);
        LobbyUpdateInterval = new IntegerOptionItem(19502, "LobbyUpdateInterval", new(10, 30, 5), 30, TabGroup.SystemSettings)
            .SetParent(PostLobbyCodeToEHRWebsite)
            .SetValueFormat(OptionFormat.Seconds);
// Unrelated role options canary preserved.
''',
 'Modules/OptionItem/OptionItem.cs':'''    public string GetName(bool disableColor = false, bool console = false)
    {
        return Name;
    }
''',
 'Patches/ChatCommandPatch.cs':'''// Unrelated chat canary before.
OwnCommandRegistration("Level", LevelCommand);
    private static void LevelCommand(PlayerControl player, string text, string[] args)
    {
        player.RpcSetLevel(123);
    }

    private static void HideNameCommand(PlayerControl player, string text, string[] args)
    { OwnKeptNameCommand(); }

    private static void ConfirmAuthCommand(PlayerControl player, string text, string[] args)
    {
        OwnExternalDirectoryVerification();
    }

    public static void RetributeCommand(PlayerControl player, string text, string[] args)
    { OwnKeptRoleCommand(); }
'''}
 return {k:v.replace('\n',eol.decode()).encode()for k,v in files.items()}


class AccountPolicyTests(unittest.TestCase):
 def test_generated_exact_six_policy_source_is_frozen(self):
  self.assertEqual(len(POLICY['excluded_callbacks']),6)
  self.assertEqual(MODULE.policy_source(POLICY),(ROOT/'managed/SourcePort/EHRSourceAccountPolicy.cs').read_text())
 def test_only_exact_descriptors_and_selectors(self):
  rows=[];selectors=[]
  for r in POLICY['excluded_callbacks']:
   class_id,member=r['callback_id'].split('::');method,index=member.split('#')
   rows.append({'id':r['callback_id'],'classId':class_id,'method':method,'index':int(index),'sourceFile':r['source_file']});selectors.append({'selectorId':r['selector_id'],'callbackIds':[r['callback_id'],'Own.UnrelatedSafeCallback']})
  audit={'upstreamCommit':POLICY['upstream_commit'],'compileProfile':'IL2CPP','rows':rows};targets={'upstreamCommit':POLICY['upstream_commit'],'compileProfile':'IL2CPP','selectors':selectors}
  decisions=MODULE.validate_descriptors(POLICY,audit,targets);self.assertTrue(all(d['allowed_callbacks']==['Own.UnrelatedSafeCallback']for d in decisions))
  rows[0]['index']+=1
  with self.assertRaisesRegex(ValueError,'declaration identity'):MODULE.validate_descriptors(POLICY,audit,targets)
 def test_source_pin_profile_and_target_change_fail(self):
  with self.assertRaisesRegex(ValueError,'pin/profile'):MODULE.validate_descriptors(POLICY,{'upstreamCommit':'wrong'},{})
 def test_directory_producer_removed_public_surface_and_broad_callback_preserved(self):
  base=source_fixture();result=MODULE.adapt_files(base,base);directory=result['Modules/LobbySharingAPI.cs']
  self.assertNotIn(b'EOSManager',directory);self.assertNotIn(b'UserIDToken',directory);self.assertNotIn(b'UnityWebRequest',directory)
  for member in (b'public static long LastRequestTimeStamp;',b'public static string LastRoomCode = string.Empty;',b'public static void NotifyLobbyStatusChanged(LobbyStatus status) { }'):self.assertIn(member,directory)
  self.assertIn(b'public class ExitGamePatch { public static void Postfix() { OwnKeptEffect(); } }',directory)
  self.assertIn(b'OwnKeptRoleCommand();',result['Patches/ChatCommandPatch.cs']);self.assertNotIn(b'OwnExternalDirectoryVerification',result['Patches/ChatCommandPatch.cs'])
 def test_level_registration_and_unrelated_commands_survive_without_level_write(self):
  base=source_fixture();chat=MODULE.adapt_files(base,base)['Patches/ChatCommandPatch.cs']
  self.assertIn(b'OwnCommandRegistration("Level", LevelCommand);',chat)
  self.assertIn(b'OwnKeptNameCommand();',chat);self.assertIn(b'OwnKeptRoleCommand();',chat)
  self.assertIn(MODULE.LEVEL_MESSAGE.encode(),chat);self.assertNotIn(b'RpcSetLevel',chat)
 def test_unavailable_row_false_default_and_interval_hidden(self):
  original=source_fixture();result=MODULE.adapt_files(original,original)
  self.assertIn(b': base(id, name, tab, 0, true)',result['EHRProtectedLobbyDirectoryOption.cs']);self.assertIn(b'GetValue() => 0',result['EHRProtectedLobbyDirectoryOption.cs'])
  self.assertIn(b'.SetHidden(true)',result['Modules/OptionHolder.cs']);self.assertIn(b'EHRProtectedLobbyDirectoryOption.Label',result['Modules/OptionItem/OptionItem.cs'])
 def test_crlf_and_composed_canaries_preserved(self):
  original=source_fixture(b'\r\n');base={k:b'// Composed callback canary.\r\n'+v for k,v in original.items()};result=MODULE.adapt_files(original,base)
  for name in original:self.assertTrue(result[name].startswith(b'// Composed callback canary.\r\n'))
  self.assertIn(b'\r\n',result['Modules/LobbySharingAPI.cs'])
 def test_composed_line_endings_and_callback_tail_are_preserved(self):
  for pinned_eol,composed_eol in ((b'\r\n',b'\n'),(b'\n',b'\r\n')):
   with self.subTest(pinned_eol=pinned_eol,composed_eol=composed_eol):
    original=source_fixture(pinned_eol);tail=b'// Generated source callback tail.'+composed_eol
    base={k:MODULE.with_newline(v,composed_eol)+tail for k,v in original.items()}
    result=MODULE.adapt_files(original,base)
    expected=MODULE.adapt_files(source_fixture(composed_eol),base)
    self.assertEqual(result,expected)
    for name in original:
     self.assertTrue(result[name].endswith(tail));self.assertEqual(result[name].count(tail),1)
     if composed_eol==b'\n':self.assertNotIn(b'\r\n',result[name])
 def test_modified_or_duplicate_source_spans_rejected(self):
  original=source_fixture();base=dict(original);base['Modules/LobbySharingAPI.cs']=base['Modules/LobbySharingAPI.cs'].replace(b'OwnProducer',b'ChangedProducer')
  with self.assertRaises(ValueError):MODULE.adapt_files(original,base)
  base=dict(original);base['Modules/OptionItem/OptionItem.cs']*=2
  with self.assertRaises(ValueError):MODULE.adapt_files(original,base)
 def test_actual_own_csharp_policy_and_legacy_option_fixture(self):
  sdk=Path(os.environ.get('EHR_DOTNET') or shutil.which('dotnet') or 'dotnet')
  if not sdk.exists():self.skipTest('Bundled own .NET SDK unavailable')
  source=source_fixture();adapted=MODULE.adapt_files(source,source);option=adapted['EHRProtectedLobbyDirectoryOption.cs'];chat=adapted['Patches/ChatCommandPatch.cs']
  with tempfile.TemporaryDirectory(prefix='ehr-own-policy-')as temporary:
   output=Path(temporary);generated=output/'DirectoryOption.cs';generated.write_bytes(option)
   level=MODULE.span(chat,b'    private static void LevelCommand(',b'    private static void HideNameCommand(')
   confirm=MODULE.span(chat,b'    private static void ConfirmAuthCommand(',b'    public static void RetributeCommand(')
   commands=output/'ProtectedCommands.cs';commands.write_bytes(b'namespace EHR;\ninternal static class OwnProtectedCommands\n{\n'+level+confirm+b'public static void Exercise(PlayerControl player) { LevelCommand(player,"/level 999",[]); ConfirmAuthCommand(player,"/ConfirmAuth nonce",[]); }\n}\n')
   project=ROOT/'tests/account_policy_fixture/AccountPolicyFixture.csproj'
   environment={**os.environ,'DOTNET_CLI_TELEMETRY_OPTOUT':'1','DOTNET_GENERATE_ASPNET_CERTIFICATE':'false','DOTNET_NOLOGO':'1'}
   args=[str(sdk),'run','--project',str(project),'-c','Release','-p:DirectoryOptionSource='+str(generated),'-p:ProtectedCommandsSource='+str(commands),'-p:BaseIntermediateOutputPath='+str(output/'obj')+'/','-p:OutputPath='+str(output/'bin')+'/']
   result=subprocess.run(args,capture_output=True,text=True,check=True,env=environment,timeout=60)
   proof=json.loads(next(line for line in result.stdout.splitlines()if line.startswith('{')));self.assertTrue(proof['pass']);self.assertTrue(proof['legacyPresetCannotEnable']);self.assertTrue(proof['protectedCommandResponses']);self.assertEqual(proof['gameApiCalls'],0)
   registration=proof['registration']
   for check in ('SixExcludedBeforePrepare','SameTargetAllowedCallbackPreserved','PolicyReasonsSeparateFromUnavailable','DisabledBindingStopsCallbacks','RebindKeepsProtection','SharedClassAllowedCallbackPreserved'):self.assertTrue(registration[check],check)
   self.assertEqual(registration['ExcludedPrepareCalls'],0);self.assertEqual(registration['ExcludedInvokeCalls'],0);self.assertEqual(registration['OriginalCalls'],4)


if __name__=='__main__':unittest.main()
