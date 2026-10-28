import hashlib
import unittest
from adapt_host_only_registration import BEFORE,AFTER,transform

class HostOnlyRegistrationTests(unittest.TestCase):
    def fixture(self,newline='\n',bom=False):
        source=('// own fixture\npublic static class AmciRegistration {\n    public static void Apply()\n    {\n'+BEFORE+'\n    }\n    public static void Revert(){ OriginalRevert(); }\n    // Original source callback body\n}\n').replace('\n',newline).encode()
        return (b'\xef\xbb\xbf' if bom else b'')+source
    def test_only_registration_body_changes_and_line_format_preserved(self):
        for newline,bom in [('\n',False),('\r\n',True)]:
            source=self.fixture(newline,bom);output,report=transform(source,hashlib.sha256(source).hexdigest())
            self.assertEqual(output,source.replace(BEFORE.replace('\n',newline).encode(),AFTER.replace('\n',newline).encode()))
            self.assertFalse(report['allClientGuidEnabled']);self.assertTrue(report['originalHostingAndAccountChecksUnchanged'])
            self.assertFalse(report['vanillaJoinVerified'])
    def test_unreviewed_or_ambiguous_input_rejected(self):
        source=self.fixture()
        with self.assertRaisesRegex(ValueError,'hash'):transform(source,'0'*64)
        for bad in [source.replace(b'ModRegistrationGuidString',b'OtherField'),source+BEFORE.encode()]:
            with self.assertRaisesRegex(ValueError,'body changed'):transform(bad,hashlib.sha256(bad).hexdigest())

if __name__=='__main__':unittest.main()
