"""Synthetic provider selection/configuration tests; no real key or signing.

The copy fixture ends before the SDK lookup and never reads a game image,
performs an authentication request, signs, installs, or modifies its source.
"""
from datetime import datetime
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("ehr_itch_auth_builder", ROOT / "tools/build_game_probe.py")
builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)


class StopBeforeInputRead(Exception): pass
class StopBeforeSDKCall(Exception): pass


class ItchAuthBuilderTests(unittest.TestCase):
    def options(self, root, *, full=False, **overrides):
        values = dict(team_id="ABCDEFGHIJ", bundle_id="org.example.ehrfixture", team_name=None,
            game_app=root / "OwnSource.app", output=root / "Output", profile=root / "OwnProfile",
            destination_id_file=root / "own-destination.local.txt", identity="Own Fixture Identity", build=55,
            full_native_catalog=None, full_native_target_map=None, full_thunk_inputs=None,
            managed_dylib=None, iterator_hook_map=None, static_class_hooks=None,
            full_source_autoload=False, eos_login_map=None, platform_sign_in=False,
            auth_retry_guard_map=None, enable_auth_retry_guard=False, game_start_iterator_map=None,
            auth_handoff_map=None, itch_auth_map=None, itch_oauth_client_id=None, itch_oauth_redirect_uri=None)
        if full:
            values.update(full_native_catalog=root / "own-catalog.json",
                full_native_target_map=root / "own-targets.json", full_thunk_inputs=root / "own-thunks",
                managed_dylib=root / "own.dylib", iterator_hook_map=root / "own-iterators.json",
                static_class_hooks=root / "own-classes.json")
        values.update(overrides)
        return SimpleNamespace(**values)

    def reject_before_inputs(self, overrides, reason):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); args = self.options(root, full=True, **overrides)
            with patch.object(builder, "inspect_path") as inspect, \
                 patch.object(builder.subprocess, "check_output") as external, \
                 patch.object(builder, "run") as run, self.assertRaisesRegex(ValueError, reason):
                builder.build(args)
            inspect.assert_not_called(); external.assert_not_called(); run.assert_not_called()
            self.assertFalse(args.output.exists())

    def test_itch_provider_requires_complete_full_source_before_source_inspection(self):
        self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"), "full_native_catalog": None},
                                 "requires the full source profile")
        for missing in ("full_native_target_map", "full_thunk_inputs"):
            self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"), missing: None},
                                     "catalog, pinned target map and compiled thunk inputs")
        for missing in ("managed_dylib", "iterator_hook_map", "static_class_hooks"):
            self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"), missing: None},
                                     "production source image, iterator and static component")

    def test_website_directory_requires_ownership_checked_provider_before_inputs(self):
        self.reject_before_inputs({"ehr_directory": True}, "requires the ownership-checked itch.io provider")

    def test_itch_and_activated_apple_retry_guard_cannot_compete(self):
        self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"), "enable_auth_retry_guard": True},
                                 "do not enable the Apple retry guard")

    def test_public_oauth_configuration_cannot_select_a_provider_implicitly(self):
        for configuration in ({"itch_oauth_client_id": "own-fixture-public-client"},
                              {"itch_oauth_redirect_uri": "org.example.ehrfixture.itch://oauth/callback"}):
            self.reject_before_inputs(configuration, "configuration requires --itch-auth-map")
        self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"),
            "itch_oauth_redirect_uri": "org.example.ehrfixture.itch://oauth/callback"},
            "redirect requires a public OAuth client identifier")

    def test_public_client_identifier_matches_runtime_policy(self):
        # These are invented format fixtures, never credentials or client secrets.
        for value in (True, 42, "own.invalid.period", "own client", "own\nclient", "a" * 257,
                      "https://example.invalid/client"):
            with self.subTest(value=value):
                self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"), "itch_oauth_client_id": value},
                                          "public itch.io OAuth client identifier")

    def test_redirect_must_be_bounded_raw_valid_uri_in_this_apps_own_scheme(self):
        own = "org.example.ehrfixture.itch://oauth/callback"
        invalid = ["amongus://oauth/callback", "org.example.other.itch://oauth/callback",
            "https://oauth/callback", "org.example.ehrfixture.itch://other/callback",
            "org.example.ehrfixture.itch://oauth/other", own + "?code=own-fixture",
            own + "#own-fixture", "org.example.ehrfixture.itch://user@oauth/callback",
            "org.example.ehrfixture.itch://oauth:443/callback", "\n" + own, own + "\r",
            "org.example.ehrfixture." + "a" * 1024 + "://oauth/callback"]
        for value in invalid:
            with self.subTest(redirect=value):
                self.reject_before_inputs({"itch_auth_map": Path("own-itch.json"),
                    "itch_oauth_client_id": "own-fixture-public-client", "itch_oauth_redirect_uri": value},
                    "itch.io OAuth")

    def test_absent_provider_option_keeps_default_profile_independent(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.options(Path(temp))
            del args.itch_auth_map; del args.itch_oauth_client_id; del args.itch_oauth_redirect_uri
            with patch.object(builder, "inspect_path", side_effect=StopBeforeInputRead) as inspect, \
                 patch.object(builder, "run") as run, self.assertRaises(StopBeforeInputRead):
                builder.build(args)
            inspect.assert_called_once_with(args.game_app.resolve()); run.assert_not_called()
            self.assertFalse(args.output.exists())

    def test_invalid_display_names_fail_before_input_read_or_output_creation(self):
        for name in (None, True, 42, "", " ", "a" * 65, "Own\nName", "Own\rName",
                     "Own\x00Name", "Own\x7fName", "Own\x85Name"):
            with self.subTest(display_name=name):
                self.reject_before_inputs({"display_name": name}, "Display name")

    def copied_info(self, root, *, selected, oauth=False, redirect=None, display_name=None, prepared_icon=None):
        source = root / "OwnSource.app"; source.mkdir()
        # Invented source fixture includes stale custom entries. The builder must
        # replace the selected provider and own only the explicitly supplied URL.
        info = {"CFBundleIdentifier": "com.innersloth.amongus", "CFBundleExecutable": "OwnMain",
            "CFBundleVersion": "3", "CFBundleShortVersionString": "1.2.3",
            "CFBundleURLTypes": [{"CFBundleURLSchemes": ["amongus"]}],
            "EHRAuthProvider": "inherited-provider", "EHRItchAuthCompiled": True,
            "EHRItchOAuthClientID": "inherited-public-fixture",
            "EHRItchOAuthRedirectURI": "amongus://oauth/callback",
            "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconName": "OwnInheritedIcon"},
                              "CFBundleAlternateIcons": {"OwnOldAlternate": {"CFBundleIconFiles": ["OwnOld"]}}}}
        source_plist = source / "Info.plist"; source_plist.write_bytes(plistlib.dumps(info))
        (source / "OwnMain").write_bytes(b"own synthetic launcher")
        before = hashlib.sha256(source_plist.read_bytes()).hexdigest()
        (root / "own-destination.local.txt").write_text("own-fixture-destination")
        (root / "OwnProfile").write_bytes(b"own synthetic profile")
        profile = {"TeamIdentifier": ["ABCDEFGHIJ"], "ExpirationDate": datetime(2100, 1, 1),
            "ProvisionedDevices": ["own-fixture-destination"], "DeveloperCertificates": [],
            "Entitlements": {"application-identifier": "ABCDEFGHIJ.org.example.ehrfixture", "get-task-allow": True}}
        overrides = {"itch_auth_map": root / "own-itch.json"} if selected else {}
        if display_name is not None:
            overrides["display_name"] = display_name
        if prepared_icon is not None:
            overrides["app_icon"] = root / "own-input-icon.png"
        if oauth:
            overrides.update(itch_oauth_client_id="own-fixture-public-client")
            if redirect: overrides["itch_oauth_redirect_uri"] = redirect
        args = self.options(root, full=selected, **overrides)
        def external(arguments, **unused):
            if arguments[:3] == ["security", "cms", "-D"]: return plistlib.dumps(profile)
            if arguments[:3] == ["xcrun", "--sdk", "iphoneos"]: raise StopBeforeSDKCall
            self.fail("Unexpected external operation in the synthetic builder fixture")
        with patch.object(builder, "inspect_path", return_value={"readiness": "ready", "issues": [], "images": []}), \
             patch.object(builder.subprocess, "check_output", side_effect=external), \
             patch.object(builder, "prepare_app_icon", return_value=prepared_icon) as icon_prepare, \
             patch.object(builder, "run") as run, self.assertRaises(StopBeforeSDKCall):
            builder.build(args)
        if prepared_icon is not None:
            icon_prepare.assert_called_once_with(root / "own-input-icon.png")
            for name, data in prepared_icon.files.items():
                self.assertEqual((args.output / "EHRNativeGame.app" / name).read_bytes(), data)
        else:
            icon_prepare.assert_not_called()
        run.assert_not_called()
        self.assertEqual(hashlib.sha256(source_plist.read_bytes()).hexdigest(), before)
        self.assertEqual((source / "OwnMain").read_bytes(), b"own synthetic launcher")
        self.assertFalse((args.output / "EHRNativeGame.app/OwnMain").exists())
        return plistlib.loads((args.output / "EHRNativeGame.app/Info.plist").read_bytes())

    def test_display_name_default_and_custom_name_only_change_visible_label(self):
        for name in (None, "EHR Sign-in Test", "X", "x" * 64, "Owned \u2606 Fixture"):
            with self.subTest(display_name=name), tempfile.TemporaryDirectory() as temp:
                info = self.copied_info(Path(temp), selected=False, display_name=name)
                self.assertEqual(info["CFBundleDisplayName"], name or "EHR Native Preview")
                self.assertEqual(info["CFBundleName"], "EHRNativeGame")
                self.assertEqual(info["CFBundleExecutable"], "EHRNativeGame")
                self.assertEqual(info["CFBundleIdentifier"], "org.example.ehrfixture")
                self.assertEqual(info["CFBundleShortVersionString"], "1.2.3")

    def test_prepared_custom_icon_overrides_source_selection_without_identity_or_version_changes(self):
        from app_icon import PreparedAppIcon, VARIANTS, BRAND_FILE
        # Pixel decoding and real variant sizes are separately exercised against
        # Apple ImageIO. Here the prepared boundary uses owned fixture bytes.
        icon = PreparedAppIcon("0" * 64, {name: b"OWN_PREPARED_ICON_" + name.encode() for name in VARIANTS})
        with tempfile.TemporaryDirectory() as temporary:
            info = self.copied_info(Path(temporary), selected=True, prepared_icon=icon,
                                    display_name="EHR Among Us")
            self.assertNotIn("OwnInheritedIcon", str(info))
            self.assertNotIn("CFBundleAlternateIcons", info["CFBundleIcons"])
            self.assertEqual(info["CFBundleDisplayName"], "EHR Among Us")
            self.assertEqual(info["CFBundleIdentifier"], "org.example.ehrfixture")
            self.assertEqual(info["CFBundleShortVersionString"], "1.2.3")
            self.assertTrue(info["EHRItchAuthCompiled"])
            self.assertIn(BRAND_FILE, icon.files)

    def test_invalid_icon_is_rejected_before_game_inputs_or_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "own.png"; source.write_bytes(b"OWN_NOT_A_PNG")
            args = self.options(root, app_icon=source)
            with patch.object(builder, "inspect_path") as inspect, \
                 patch.object(builder.subprocess, "check_output") as external, \
                 self.assertRaisesRegex(ValueError, "App icon"):
                builder.build(args)
            inspect.assert_not_called(); external.assert_not_called()
            self.assertFalse(args.output.exists())

    def test_signed_selection_overwrites_inherited_provider_without_importing_oauth_config(self):
        for selected in (False, True):
            with self.subTest(selected=selected), tempfile.TemporaryDirectory() as temp:
                info = self.copied_info(Path(temp), selected=selected)
                self.assertIs(info["EHRItchAuthCompiled"], selected)
                self.assertIs(info["EHRItchOwnershipRequired"], selected)
                self.assertIs(info["EHRDirectoryCompiled"], False)
                self.assertEqual(info["EHRAuthProvider"], "itchio" if selected else "apple")
                self.assertNotIn("CFBundleURLTypes", info)
                self.assertNotIn("EHRItchOAuthClientID", info)
                self.assertNotIn("EHRItchOAuthRedirectURI", info)
                self.assertEqual(info["CFBundleShortVersionString"], "1.2.3")
                self.assertIs(info["EHRAuthRetryGuardActivationRequested"], False)

    def test_configured_browser_owns_only_its_explicit_app_callback_scheme(self):
        for redirect in (None, "org.example.ehrfixture.callback://oauth/callback"):
            with self.subTest(redirect=redirect), tempfile.TemporaryDirectory() as temp:
                info = self.copied_info(Path(temp), selected=True, oauth=True, redirect=redirect)
                wanted = redirect or "org.example.ehrfixture.itch://oauth/callback"
                self.assertEqual(info["EHRItchOAuthRedirectURI"], wanted)
                self.assertEqual(info["EHRItchOAuthClientID"], "own-fixture-public-client")
                self.assertEqual(info["CFBundleURLTypes"], [{
                    "CFBundleURLName": "org.example.ehrfixture.itch-oauth",
                    "CFBundleURLSchemes": [wanted.split(":", 1)[0]]}])
                self.assertIs(info["EHRItchAuthCompiled"], True)
                self.assertEqual(info["EHRAuthProvider"], "itchio")

    def test_cli_labels_public_configuration_and_explicit_selection(self):
        env = dict(os.environ); env["PYTHONPATH"] = str(ROOT / "tools")
        text = subprocess.check_output([sys.executable, str(ROOT / "tools/build_game_probe.py"), "--help"],
                                       env=env, text=True, timeout=10)
        for option in ("--itch-auth-map", "--itch-oauth-client-id", "--itch-oauth-redirect-uri", "--display-name", "--app-icon"):
            self.assertIn(option, text)
        self.assertIn("public itch.io OAuth", text); self.assertIn("never a player token", text)
        self.assertIn("default: EHR Native Preview", text)


if __name__ == "__main__": unittest.main()
