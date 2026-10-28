#!/usr/bin/env python3
"""Verify a staged app's signature/profile without exposing profile device lists."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import fnmatch
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from platform_capabilities import verify_platform_capabilities
from signing_config import validate_identity



def command(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def verify(app: Path, device_id: str | None = None, *, team_id: str, bundle_id: str, team_name: str | None = None):
    team, bundle, expected_name = validate_identity(team_id, bundle_id, team_name)
    command("codesign", "--verify", "--deep", "--strict", str(app))
    details = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], check=True,
                             capture_output=True).stderr.decode()
    match = re.search(r"^TeamIdentifier=(.+)$", details, re.M)
    if not match or match.group(1) != team:
        raise ValueError("Signed app does not identify the required paid team")
    profile = plistlib.loads(command("security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")))
    info = plistlib.loads((app / "Info.plist").read_bytes())
    entitlements = plistlib.loads(command("codesign", "-d", "--entitlements", ":-", str(app)))
    if team not in profile.get("TeamIdentifier", []):
        raise ValueError("Provisioning profile team does not match")
    if expected_name is not None and profile.get("TeamName", "").casefold() != expected_name.casefold():
        raise ValueError("Profile team name does not match the explicit expected name")
    expiry = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    if expiry <= datetime.now(timezone.utc):
        raise ValueError("Provisioning profile has expired")
    if info.get("CFBundleIdentifier") != bundle:
        raise ValueError("Signed app bundle identifier does not match the explicit expected identifier")
    app_id = team + "." + bundle
    if entitlements.get("application-identifier") != app_id:
        raise ValueError("Signed application identifier does not match the app")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise ValueError("Signed team entitlement does not match")
    profile_entitlements = profile.get("Entitlements", {})
    if not fnmatch.fnmatchcase(app_id, profile_entitlements.get("application-identifier", "")):
        raise ValueError("Profile does not cover this application identifier")
    if bool(entitlements.get("get-task-allow")) != bool(profile_entitlements.get("get-task-allow")):
        raise ValueError("Debug entitlement does not match the profile")
    platform_signin=verify_platform_capabilities(entitlements,profile_entitlements)
    with tempfile.TemporaryDirectory(prefix="ehr-signing-check-") as temp:
        prefix = str(Path(temp) / "certificate")
        command("codesign", "-d", "--extract-certificates=" + prefix, str(app))
        actual_certificate = Path(prefix + "0").read_bytes()
    if actual_certificate not in profile.get("DeveloperCertificates", []):
        raise ValueError("Signing certificate is not included in the provisioning profile")
    devices = profile.get("ProvisionedDevices", [])
    coverage = None if device_id is None else device_id in devices
    if device_id is not None and not coverage:
        raise ValueError("Profile does not cover the requested destination device")
    return {
        "signature_verified": True, "team_id": team, "team_name": profile.get("TeamName", ""),
        "bundle_id": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
        "profile_expires_utc": expiry.isoformat(),
        "profile_device_count": len(devices),
        "own_platform_sign_in_capabilities_verified": platform_signin,
        "publisher_backend_authentication_verified": False,
        "requested_device_covered": coverage, "installed": False,
        "playable_ehr": False,
        "scope": info.get("EHRProbeScope", "Native Bait rule harness; Among Us adapter is unavailable"),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--team-name", help="Optional exact provisioning team-name assertion")
    parser.add_argument("--device-id-file", type=Path,
                        help="Optional local file with exact target UDID; never included in output")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.app, args.device_id_file.read_text().strip() if args.device_id_file else None,
                        team_id=args.team_id, bundle_id=args.bundle_id, team_name=args.team_name)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Signing verification failed: {error}\n")
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(text)
    print(text, end="")
