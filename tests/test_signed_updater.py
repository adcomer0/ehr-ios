import hashlib
import importlib.util
import unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('updater',Path(__file__).resolve().parents[1]/'tools'/'adapt_signed_updater.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
GUARD='''            if (string.IsNullOrWhiteSpace(DownloadUrl))
            {
                Logger.Error("No EHR.dll download URL found in release assets", "CheckRelease");
                IsBroken = true;
                yield break;
            }

'''
FIXTURE=('''class ModUpdater {
    const string SavePath = "BepInEx/plugins/EHR.dll.temp";
    public static void Prefix() {
            NewVersionCheck();
            DeleteOldFiles();
        Popup(GetString("updateButton"), onClickOnFirstButton: () => StartUpdate(DownloadUrl));
    }
    private static IEnumerator CheckReleaseFromGithub(bool beta = false)
    {
        // Original legitimate request and comparison are preserved.
        yield return request.SendWebRequest();
        DownloadUrl = FindDllAssetUrl(data);
        LatestVersion = new Version(versionString);
        HasUpdate = LatestVersion.CompareTo(Main.Version) > 0;
'''+GUARD+'''        IsBroken = false;
    }
#if IL2CPP
    private static string FindDllAssetUrl(JsonDocument data) { return null; }
#endif
    public static void StartUpdate(string url) { DownloadDLL(url); }
    private static void DeleteOldFiles() { File.Delete(SavePath); }
    private static IEnumerator DownloadDLL(string url) { File.Move(Assembly.Location,SavePath); }
    public static void UpdateFailed() { File.Delete(SavePath); }
    public static void ShowPopup(string message, bool button) { RenderPopup(message); }
}
''').encode()
class AdapterTests(unittest.TestCase):
    def render(self,data=FIXTURE):return module.transform(data,hashlib.sha256(data).hexdigest())
    def test_removes_file_mutations_and_desktop_installer(self):
        output,report=self.render()
        for forbidden in [b'File.Delete(',b'File.Move(',b'DownloadDLL(',b'Assembly.Location',b'DownloadHandler.data']:
            self.assertNotIn(forbidden,output)
        self.assertFalse(report['downloadsOrInstalls']);self.assertFalse(report['accountOrSaveDataOperations'])
    def test_keeps_real_version_check_and_popup(self):
        output,report=self.render();self.assertIn(b'HasUpdate = LatestVersion.CompareTo(Main.Version) > 0;',output)
        self.assertIn(b'yield return request.SendWebRequest();',output);self.assertIn(b'RenderPopup(message);',output)
        self.assertTrue(report['releaseCheckingPreserved'])
    def test_only_host_config_selects_instruction_url(self):
        output,_=self.render();self.assertIn(b'DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;',output)
        self.assertIn(b'SourceSignedUpdates.OpenInstructions();',output)
        self.assertNotIn(b'DownloadUrl = FindDllAssetUrl(data)',output)
    def test_changed_input_and_missing_anchor_reject(self):
        with self.assertRaises(ValueError):module.transform(FIXTURE,'0'*64)
        with self.assertRaises(ValueError):self.render(FIXTURE.replace(GUARD.encode(),b''))
    def test_retains_input_and_line_endings(self):
        data=FIXTURE.replace(b'\n',b'\r\n');saved=bytes(data);output,_=self.render(data)
        self.assertEqual(data,saved);self.assertNotIn(b'\n',output.replace(b'\r\n',b''))
if __name__=='__main__':unittest.main()
