import unittest
from platform_capabilities import SIGN_IN,platform_signin_capabilities,verify_platform_capabilities

class PlatformCapabilityTests(unittest.TestCase):
    def test_capabilities_are_explicit_and_never_inherit_publisher_identity(self):
        profile={**SIGN_IN,"com.apple.developer.associated-domains":["applinks:publisher.example"],"keychain-access-groups":["Publisher.Identity"]}
        self.assertEqual(platform_signin_capabilities(profile,False),{})
        own=platform_signin_capabilities(profile,True)
        self.assertEqual(own,SIGN_IN);own['com.apple.developer.applesignin'].append('changed')
        self.assertEqual(SIGN_IN['com.apple.developer.applesignin'],['Default'])
    def test_incomplete_or_wrong_profile_capabilities_rejected(self):
        for profile in [{},{'com.apple.developer.applesignin':['Default']},{**SIGN_IN,'com.apple.developer.game-center':False}]:
            with self.assertRaisesRegex(ValueError,'does not cover'):platform_signin_capabilities(profile,True)
    def test_signature_requires_own_profile_coverage(self):
        self.assertTrue(verify_platform_capabilities(SIGN_IN,SIGN_IN))
        self.assertFalse(verify_platform_capabilities({},SIGN_IN))
        with self.assertRaisesRegex(ValueError,'not covered'):verify_platform_capabilities(SIGN_IN,{})
        with self.assertRaisesRegex(ValueError,'not covered'):verify_platform_capabilities({**SIGN_IN,'com.apple.developer.applesignin':['Other']},SIGN_IN)

if __name__=='__main__':unittest.main()
