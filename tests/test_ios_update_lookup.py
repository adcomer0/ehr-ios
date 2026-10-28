from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('update_lookup', ROOT / 'tools/prepare_ios_update_lookup.py')
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)
FIXTURE = '''// Own source canaries: native permission/version gates are not adapted.
class ModUpdater {
    private static IEnumerator CheckReleaseFromGithub(bool beta = false)
    {
NETWORK_FAILURE
        try {
            DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;
            HasUpdate = LatestVersion.CompareTo(Main.Version) > 0;
            IsBroken = false;
        }
PARSE_FAILURE
    }
#if IL2CPP
    private static string FindDllAssetUrl() { return null; }
#endif
}
'''.replace('NETWORK_FAILURE', M.NETWORK_FAILURE).replace('PARSE_FAILURE', M.PARSE_FAILURE)


class OptionalLookupTests(unittest.TestCase):
    def adapt(self, data):
        return M.adapt_source(data, hashlib.sha256(data).hexdigest())

    def test_only_reviewed_error_assignments_change_with_bom_and_line_format(self):
        for eol, bom in [('\n', False), ('\r\n', True)]:
            before = FIXTURE.replace('\n', eol).encode()
            if bom:
                before = b'\xef\xbb\xbf' + before
            after = self.adapt(before)
            self.assertEqual(after.replace(M.GUARDED_FAILURE.encode(), b'IsBroken = true;'), before)
            self.assertEqual(after.count(M.GUARDED_FAILURE.encode()), 2)
            self.assertIn(b'HasUpdate = LatestVersion.CompareTo(Main.Version) > 0;', after)

    def test_changed_hash_failure_owner_or_additional_producer_is_rejected(self):
        before = FIXTURE.encode()
        with self.assertRaisesRegex(ValueError, 'hash'):
            M.adapt_source(before, '0' * 64)
        for bad in [before.replace(b'request.result !=', b'criticalRuntimeState !='),
                    before.replace(b'Error while checking release from GitHub:', b'Runtime bridge failed:'),
                    before + b'\nIsBroken = true;', self.adapt(before),
                    before.replace(b'global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl', b'FindDllAssetUrl(data)')]:
            with self.assertRaises(ValueError):
                self.adapt(bad)

    def test_project_replaces_only_updater_and_keeps_other_compile_resources_imports(self):
        with tempfile.TemporaryDirectory(prefix='ehr-own-updater-project-') as temp:
            base = Path(temp).resolve()
            (base / 'ModUpdater.cs').write_text(FIXTURE)
            (base / 'Untouched.cs').write_text('// Native checks and source critical state canary.')
            (base / 'Own.csproj').write_text('<Project><ItemGroup><Compile Include="ModUpdater.cs"/><Compile Include="Untouched.cs"/><EmbeddedResource Include="asset.bin"/></ItemGroup><Import Project="Original.props"/></Project>')
            project = M.prepare(base / 'Own.csproj', base / 'out', M.sha((base / 'ModUpdater.cs').read_bytes()))
            tree = ET.parse(project)
            includes = [r.get('Include') for r in tree.iter('Compile')]
            self.assertEqual(includes, [str(base / 'out/source/ModUpdater.cs'), str(base / 'Untouched.cs')])
            self.assertEqual(next(tree.iter('EmbeddedResource')).get('Include'), str(base / 'asset.bin'))
            self.assertEqual(next(tree.iter('Import')).get('Project'), str(base / 'Original.props'))
            self.assertEqual((base / 'ModUpdater.cs').read_text(), FIXTURE)

    def test_actual_reviewed_source_has_only_two_optional_failure_changes(self):
        value = os.environ.get('EHR_SIGNED_UPDATER_TEST_INPUT')
        if not value:
            self.skipTest('Set EHR_SIGNED_UPDATER_TEST_INPUT to the reviewed signed updater')
        source = Path(value)
        before = source.read_bytes()
        self.assertEqual(M.sha(before), M.REVIEWED_SIGNED_UPDATER_SHA256)
        after = M.adapt_source(before, M.REVIEWED_SIGNED_UPDATER_SHA256)
        self.assertEqual(after.replace(M.GUARDED_FAILURE.encode(), b'IsBroken = true;'), before)

    def test_actual_coroutine_caller_initializes_platform_cache_before_start(self):
        source_value = os.environ.get('EHR_SIGNED_UPDATER_TEST_INPUT')
        platform_value = os.environ.get('EHR_PLATFORM_TEST_INPUT')
        if not source_value or not platform_value:
            self.skipTest('Set EHR_SIGNED_UPDATER_TEST_INPUT and EHR_PLATFORM_TEST_INPUT to reviewed source inputs')
        source, platform = Path(source_value), Path(platform_value)
        text = source.read_text()
        prefix = text[text.index('    public static void Start_Prefix()'):text.index('    public static void ShowAvailableUpdate()')]
        self.assertLess(prefix.index('OperatingSystem.IsAndroid()'), prefix.index('StartCoroutine(CheckReleaseFromGithub('))
        self.assertEqual(text.count('CheckReleaseFromGithub('), 2)  # Caller and private declaration only.
        cache = platform.read_text()
        self.assertIn('private static readonly bool Android = Application.platform', cache)
        self.assertIn('private static readonly bool IOS = Application.platform', cache)
        self.assertIn('public static bool IsIOS() => IOS;', cache)

    def test_compiled_error_branches_preserve_critical_and_public_room_flags(self):
        transformed = self.adapt(FIXTURE.encode()).decode()
        guards = [line.strip() for line in transformed.splitlines() if M.GUARDED_FAILURE in line]
        self.assertEqual(len(guards), 2)
        code = '''using System.Text.Json;
static class OperatingSystem { internal static bool IOS; internal static bool IsIOS()=>IOS; }
static class Program {
 static bool IsBroken;
 static void NetworkFailure(){ NETWORK_GUARD }
 static void ParseFailure(){ PARSE_GUARD }
 static bool HideFinder(bool hasUpdate,bool force)=>hasUpdate&&force||IsBroken;
 static bool ForcePrivate(bool host,bool lobby,bool isPublic,bool hasUpdate,bool force,bool allow)=>host&&lobby&&(hasUpdate&&force||IsBroken||!allow)&&isPublic;
 static void Main(){ bool pass=true;int checks=0; foreach(int platform in new[]{0,1,2})foreach(bool broken in new[]{false,true})foreach(bool parse in new[]{false,true})foreach(bool update in new[]{false,true})foreach(bool force in new[]{false,true})foreach(bool allow in new[]{false,true}){
 OperatingSystem.IOS=platform==0;IsBroken=broken;if(parse)ParseFailure();else NetworkFailure();bool expectedBroken=broken||platform!=0;pass&=IsBroken==expectedBroken;pass&=HideFinder(update,force)==(update&&force||expectedBroken);
 foreach(bool host in new[]{false,true})foreach(bool lobby in new[]{false,true})foreach(bool pub in new[]{false,true}){pass&=ForcePrivate(host,lobby,pub,update,force,allow)==(host&&lobby&&(update&&force||expectedBroken||!allow)&&pub);checks++;}}
 Console.WriteLine(JsonSerializer.Serialize(new{pass,checks,gameCalls=0,networkRequests=0}));if(!pass)Environment.Exit(1); }
}'''.replace('NETWORK_GUARD', guards[0]).replace('PARSE_GUARD', guards[1])
        with tempfile.TemporaryDirectory(prefix='ehr-own-update-errors-') as temp:
            base = Path(temp)
            (base / 'Program.cs').write_text(code)
            (base / 'Own.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>')
            (base / 'NuGet.Config').write_text('<configuration><packageSources><clear/></packageSources></configuration>')
            env = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false', 'DOTNET_NOLOGO': '1'}
            result = subprocess.run([os.environ.get('EHR_DOTNET','dotnet'), 'run', '--project', str(base / 'Own.csproj'), '-c', 'Release'], env=env, text=True, capture_output=True, timeout=60, check=True)
            proof = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{')))
            self.assertTrue(proof['pass'])
            self.assertEqual(proof['checks'], 768)
            self.assertEqual(proof['gameCalls'], 0)
            self.assertEqual(proof['networkRequests'], 0)


if __name__ == '__main__':
    unittest.main()
