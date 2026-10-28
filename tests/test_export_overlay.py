from __future__ import annotations
import hashlib,importlib.util,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('overlay',ROOT/'tools/prepare_export_overlay.py');overlay=importlib.util.module_from_spec(spec);spec.loader.exec_module(overlay)
class ExportOverlayTests(unittest.TestCase):
    def test_reviewed_status_merge_preserves44_button_and_existing_messages(self):
        source=(ROOT/'tests/fixture_status_overlay.mm').read_bytes();result=overlay.transform(source,hashlib.sha256(source).hexdigest())
        self.assertIn(b'self.button.frame=CGRectMake(right-132,safe.top+10,132,44);',result)
        self.assertIn(b'self.exportsButton.frame=CGRectMake(14,self.panel.bounds.size.height-56,self.panel.bounds.size.width-28,44);',result)
        self.assertIn(b'@selector(shareExports)',result)
        self.assertEqual(result.count(b'presentViewController:EHRExportSharingController()'),1)
        for text in [b'EHR options are initialized.',b'Independent port; not endorsed by Innersloth.',b'Account linking, progress preservation and online play have not been verified.']:self.assertIn(text,result)
        self.assertIn(b'self.statusScroll.contentSize=self.label.bounds.size',result)
        self.assertEqual(source[source.index(b'__attribute__((constructor))'):],result[result.index(b'__attribute__((constructor))'):])
    def test_source_pin_and_anchor_mismatch_reject(self):
        source=(ROOT/'tests/fixture_status_overlay.mm').read_bytes()
        with self.assertRaisesRegex(ValueError,'hash mismatch'):overlay.transform(source,'0'*64)
        changed=source.replace(b'132,44);',b'132,40);')
        with self.assertRaisesRegex(ValueError,'44pt'):overlay.transform(changed,hashlib.sha256(changed).hexdigest())
        changed=source.replace(b'MIN(280,',b'MIN(290,')
        with self.assertRaisesRegex(ValueError,'anchor'):overlay.transform(changed,hashlib.sha256(changed).hexdigest())
    def test_sharing_has_no_autostart_export_or_network_calls(self):
        source=(ROOT/'native/EHRExportSharing.mm').read_text()
        for forbidden in ['__attribute__((constructor))','DumpLog(', 'ExportCustomTranslation(', 'NSURLSession','NSURLConnection','openURL:']:self.assertNotIn(forbidden,source)
        self.assertIn('UIActivityViewController',source);self.assertIn('popover.sourceView=tableView',source);self.assertIn('popover.sourceRect=',source)
        self.assertIn('NSApplicationSupportDirectory',source);self.assertIn('@"EHRSource"',source)
if __name__=='__main__':unittest.main()
