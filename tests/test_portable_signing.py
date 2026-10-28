"""Own profile/certificate fixtures; no installed identity or device operations."""
from datetime import datetime, timedelta, timezone
import importlib.util
from pathlib import Path
import plistlib
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from signing_config import validate_identity
spec = importlib.util.spec_from_file_location('portable_signing', ROOT / 'tools/verify_signing.py')
SIGNING = importlib.util.module_from_spec(spec)
spec.loader.exec_module(SIGNING)


class PortableSigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='ehr-own-signature-')
        self.app = Path(self.temporary.name) / 'Own.app'
        self.app.mkdir()
        self.team, self.bundle = 'ABCDEFGHIJ', 'org.example.ehrfixture'
        self.device, self.certificate = 'Own fixture device', b'Own fixture certificate'
        self.info = {'CFBundleIdentifier': self.bundle, 'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '7'}
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        self.entitlements = {'application-identifier': self.team + '.' + self.bundle,
                             'com.apple.developer.team-identifier': self.team, 'get-task-allow': True}
        self.profile = {'TeamIdentifier': [self.team], 'TeamName': 'Own Fixture Development',
                        'ExpirationDate': datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=1),
                        'Entitlements': dict(self.entitlements), 'DeveloperCertificates': [self.certificate],
                        'ProvisionedDevices': [self.device]}
        self.calls = []
        self.signed_team = self.team
        self.command_patch = patch.object(SIGNING, 'command', side_effect=self.command)
        self.process_patch = patch.object(SIGNING.subprocess, 'run', side_effect=self.process)
        self.command_patch.start()
        self.process_patch.start()

    def tearDown(self):
        self.command_patch.stop()
        self.process_patch.stop()
        self.temporary.cleanup()

    def command(self, *args):
        self.calls.append(args)
        if args[0] == 'security': return plistlib.dumps(self.profile)
        if '--entitlements' in args: return plistlib.dumps(self.entitlements)
        for value in args:
            if value.startswith('--extract-certificates='):
                Path(value.split('=', 1)[1] + '0').write_bytes(self.certificate)
        return b''

    def process(self, *args, **kwargs):
        return SimpleNamespace(stderr=('TeamIdentifier=' + self.signed_team + '\n').encode())

    def verify(self, **kwargs):
        return SIGNING.verify(self.app, self.device, team_id=self.team, bundle_id=self.bundle, **kwargs)

    def test_explicit_identity_and_matching_profile_are_required(self):
        result = self.verify(team_name='Own Fixture Development')
        self.assertTrue(result['signature_verified'])
        self.assertTrue(result['requested_device_covered'])
        self.assertEqual(result['team_id'], self.team)
        self.assertFalse(result['publisher_backend_authentication_verified'])
        self.assertNotIn(self.device, str(result))
        self.assertTrue(any('--strict' in args for args in self.calls))
        self.assertTrue(any(any(x.startswith('--extract-certificates=') for x in args) for args in self.calls))

    def test_second_developer_identity_has_no_personal_default(self):
        self.team, self.bundle = 'KLMNOPQRST', 'net.example.secondport'
        self.signed_team = self.team
        self.info['CFBundleIdentifier'] = self.bundle
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        self.entitlements['application-identifier'] = self.team + '.' + self.bundle
        self.entitlements['com.apple.developer.team-identifier'] = self.team
        self.profile['TeamIdentifier'] = [self.team]
        self.profile['Entitlements'] = dict(self.entitlements)
        self.assertTrue(self.verify()['signature_verified'])

    def test_invalid_or_official_identity_rejected_before_signing_tools(self):
        for team, bundle in [('', self.bundle), ('abc', self.bundle), (self.team, 'com.innersloth.amongus'),
                             (self.team, 'COM.INNERSLOTH.AMONGUS'), (self.team, '*'), (self.team, 'own;command')]:
            with self.subTest(team=team, bundle=bundle), self.assertRaises(ValueError):
                SIGNING.verify(self.app, team_id=team, bundle_id=bundle)
        self.assertEqual(self.calls, [])

    def test_mismatched_signed_team_or_bundle_fails(self):
        self.signed_team = 'KLMNOPQRST'
        with self.assertRaisesRegex(ValueError, 'paid team'): self.verify()
        self.signed_team = self.team
        self.info['CFBundleIdentifier'] = 'org.example.foreign'
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        with self.assertRaisesRegex(ValueError, 'bundle identifier'): self.verify()

    def test_team_name_assertion_and_profile_expiry_are_enforced(self):
        with self.assertRaisesRegex(ValueError, 'team name'): self.verify(team_name='Different Name')
        self.profile['ExpirationDate'] = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=1)
        with self.assertRaisesRegex(ValueError, 'expired'): self.verify()

    def test_profile_team_certificate_and_exact_device_are_enforced(self):
        self.profile['TeamIdentifier'] = ['KLMNOPQRST']
        with self.assertRaisesRegex(ValueError, 'profile team'): self.verify()
        self.profile['TeamIdentifier'] = [self.team]
        self.profile['DeveloperCertificates'] = [b'Foreign fixture certificate']
        with self.assertRaisesRegex(ValueError, 'certificate'): self.verify()
        self.profile['DeveloperCertificates'] = [self.certificate]
        self.profile['ProvisionedDevices'] = ['Different fixture device']
        with self.assertRaisesRegex(ValueError, 'destination device'): self.verify()

    def test_profile_capabilities_and_application_identifier_are_enforced(self):
        self.profile['Entitlements']['application-identifier'] = self.team + '.org.example.foreign'
        with self.assertRaisesRegex(ValueError, 'cover this application'): self.verify()
        self.profile['Entitlements'] = dict(self.entitlements)
        self.entitlements['com.apple.developer.applesignin'] = ['Default']
        with self.assertRaisesRegex(ValueError, 'capability'): self.verify()


if __name__ == '__main__': unittest.main()
