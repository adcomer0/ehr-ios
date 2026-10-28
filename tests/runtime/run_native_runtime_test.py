#!/usr/bin/env python3
"""Normal signed iOS-on-Mac or explicit physical-iOS XCTest using a NEW app copy.

No UI control, game agreements, authentication, network games, security-setting
changes, decryption or runtime executable writes. Requires an Apple Silicon
Mac with Xcode, normal development signing, and a profile covering the exact destination.
Physical iOS is diagnostic XCTest installation, separate from final playable delivery.
The original app and source project are never modified. All game bytes stay
in the explicitly selected non-Git artifact directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
RELATIVE_BINARIES = ("EHRNativeGame", "Frameworks/UnityFramework.framework/UnityFramework",
                     "Frameworks/EHRNativeHooks.dylib", "Frameworks/NativeSourceReuse.framework/NativeSourceReuse")
SOURCE_FILES = ("app/EHRPortLabApp.swift", "app/Info.plist",
                "app/EHRPortLab-Bridging-Header.h", "native/EHRHostCore.cpp",
                "native/include/EHRHostCore.h", "native/EHRRuntimeGateway.h", "native/EHRRuntimeCollections.h",
                "native/EHRRuntimeReflection.h")


def hash_file(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def run(arguments, log=None, cwd=None, timeout=180):
    if log:
        with log.open("w") as stream:
            log.chmod(0o600)
            subprocess.run([str(x) for x in arguments], cwd=cwd, stdout=stream,
                           stderr=subprocess.STDOUT, timeout=timeout, check=True)
        return ""
    result = subprocess.run([str(x) for x in arguments], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout, check=True)
    return result.stdout


def private_write(path, text):
    path.write_text(text)
    path.chmod(0o600)


def load_physical_device_file(path):
    """Read exact IDs without ever rendering them into a public summary."""
    path = path.resolve()
    if not path.is_file() or any((parent / ".git").exists() for parent in (path.parent, *path.parents)):
        raise ValueError("Physical device input must be a local file outside Git")
    text = path.read_text().strip()
    if text.startswith("{"):
        value = json.loads(text)
        if not isinstance(value, dict):
            raise ValueError("Physical device JSON must be an object")
        udid = value.get("udid")
        identifier = value.get("deviceIdentifier")
    else:
        udid, identifier = text, None
    if not isinstance(udid, str) or not re.fullmatch(r"[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}", udid):
        raise ValueError("An exact physical iPhone UDID is required in the private input")
    if identifier is not None and (not isinstance(identifier, str) or not re.fullmatch(r"[A-Fa-f0-9-]{36}", identifier)):
        raise ValueError("Invalid CoreDevice identifier in private device input")
    return {"udid": udid, "identifier": identifier}


def validate_candidate_pins(candidate, path):
    """Accept the previous Mac run summary or an exact relative-path mapping."""
    supplied = json.loads(path.read_text())
    if not isinstance(supplied, dict):
        raise ValueError("Candidate hash preflight input must be a JSON object")
    supplied = supplied.get("candidate_binary_sha256", supplied)
    if not isinstance(supplied, dict) or set(supplied) != set(RELATIVE_BINARIES):
        raise ValueError("Candidate pins must contain exactly the four tested relative binary paths")
    for relative, expected in supplied.items():
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("Candidate pin must be lowercase SHA256")
        if hash_file(candidate / relative) != expected:
            raise ValueError("Candidate hash differs from the preflight pins")
    return supplied


def select_physical_device(inventory, requested):
    devices = inventory.get("result", {}).get("devices", [])
    matches = [d for d in devices if d.get("hardwareProperties", {}).get("udid") == requested["udid"]]
    if len(matches) != 1:
        raise ValueError("Exact physical iPhone is not uniquely visible to CoreDevice")
    device = matches[0]
    hardware, connection = device.get("hardwareProperties", {}), device.get("connectionProperties", {})
    if hardware.get("productType") != "iPhone18,2" or hardware.get("platform") != "iOS":
        raise ValueError("Destination is not the requested physical iPhone 17 Pro Max")
    if connection.get("transportType") not in ("wired", "localNetwork") or connection.get("pairingState") != "paired":
        raise ValueError("Physical iPhone must already be paired and reachable by USB or network")
    identifier = device.get("identifier")
    if not isinstance(identifier, str) or requested["identifier"] not in (None, identifier):
        raise ValueError("CoreDevice identity differs from the private device input")
    return device


def physical_preflight(candidate, private_file, hash_file_path, output):
    requested = load_physical_device_file(private_file)
    pins = validate_candidate_pins(candidate, hash_file_path)
    inventory_path = output / "device-inventory.local.json"
    run(["xcrun", "devicectl", "list", "devices", "--json-output", inventory_path], output / "device-inventory.local.log")
    inventory_path.chmod(0o600)
    device = select_physical_device(json.loads(inventory_path.read_text()), requested)
    details_path = output / "device-details.local.json"
    run(["xcrun", "devicectl", "device", "info", "details", "--device", device["identifier"], "--json-output", details_path], output / "device-details.local.log")
    details_path.chmod(0o600)
    properties = json.loads(details_path.read_text()).get("result", {}).get("deviceProperties", {})
    if properties.get("bootState") != "booted" or properties.get("developerModeStatus") != "enabled" or properties.get("ddiServicesAvailable") is not True:
        raise ValueError("Physical iPhone is not ready for normal development XCTest; no settings were changed")
    xcode = json.loads(run(["xcrun", "xcdevice", "list"]))
    private_write(output / "xcode-devices.local.json", json.dumps(xcode, indent=2) + "\n")
    matches = [d for d in xcode if d.get("identifier") == requested["udid"] and d.get("simulator") is False]
    if len(matches) != 1 or matches[0].get("available") is not True or matches[0].get("modelCode") != "iPhone18,2" or matches[0].get("platform") != "com.apple.platform.iphoneos":
        raise ValueError("Exact physical iPhone is not available to Xcode")
    entitlements = plistlib.loads(run(["codesign", "-d", "--entitlements", ":-", candidate]).encode())
    if entitlements.get("get-task-allow") is not True:
        raise ValueError("Physical diagnostic XCTest requires the existing development debug entitlement")
    destination = output / "physical-destination.local.txt"
    private_write(destination, requested["udid"] + "\n")
    summary = {"physical_model": "iPhone 17 Pro Max", "product_type": "iPhone18,2",
               "os_version": properties.get("osVersionNumber"), "xcode_available": True,
               "developer_mode_already_enabled": True, "transport": device["connectionProperties"]["transportType"],
               "candidate_hashes_match_preflight": True, "security_or_pairing_changes_performed": False}
    return destination, "platform=iOS,id=" + requested["udid"], pins, summary


def verify_test_bundle_team(bundle, team, app_bundle_id):
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != app_bundle_id + ".nativeruntimetests":
        raise ValueError("Generated XCTest bundle has an unexpected identifier")
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(bundle)], check=True,
                            text=True, capture_output=True)
    match = re.search(r"^TeamIdentifier=(.+)$", result.stderr, re.M)
    if not match or match.group(1) != team:
        raise ValueError("Generated XCTest bundle does not use the required paid team")


def prepare_project(source_root, test_source, output, team, bundle_id):
    project = output / "Project"
    project.mkdir()
    template = HERE / "EHRRuntimeProbe.xcodeproj"
    shutil.copytree(template, project / template.name)
    pbx = project / template.name / "project.pbxproj"
    text = pbx.read_text()
    if "__TEAM_ID__" not in text or "__APP_BUNDLE_ID__" not in text or "CLANG_ENABLE_OBJC_ARC = YES" not in text:
        raise ValueError("Project template is missing its team placeholder or ARC setting")
    pbx.write_text(text.replace("__TEAM_ID__", team).replace("__APP_BUNDLE_ID__", bundle_id))
    for relative in SOURCE_FILES:
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_root / relative, target)
    shutil.copytree(source_root / "app/Assets.xcassets", project / "app/Assets.xcassets")
    (project / "NativeRuntimeTests.mm").write_text(test_source.read_text().replace("__EHR_TEST_APP_BUNDLE_ID__", bundle_id))
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True,
                        help="Own EHR project source containing app/ and native/")
    parser.add_argument("--candidate-app", type=Path, required=True,
                        help="Existing correctly signed personal EHRNativeGame.app")
    parser.add_argument("--test-source", type=Path, default=HERE / "NativeRuntimeTests.mm")
    parser.add_argument("--output-root", type=Path, required=True,
                        help="NEW artifact directory outside every Git checkout")
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--team-name", help="Optional exact provisioning team-name assertion")
    parser.add_argument("--sign-identity", required=True,
                        help="Normal installed development signing identity name or SHA1")
    parser.add_argument("--destination", choices=("mac", "ios"), default="mac",
                        help="Default Mac; ios explicitly installs/runs a diagnostic XCTest host on the private-file device")
    parser.add_argument("--device-id-file", type=Path,
                        help="Physical iOS only: private outside-Git JSON {udid,deviceIdentifier} or exact UDID text")
    parser.add_argument("--candidate-hashes-file", type=Path,
                        help="Required for physical iOS: exact candidate pins or previous Mac runtime-test-summary.json")
    parser.add_argument("--allow-provisioning-updates", action="store_true")
    parser.add_argument("--preflight-only", action="store_true",
                        help="Check exact destination, candidate pins and paid signing only; no build/install/launch")
    parser.add_argument("--prepare-only", action="store_true",
                        help="Generate own source project only; no game copy/build/launch")
    args = parser.parse_args()
    physical = args.destination == "ios"
    if args.preflight_only and args.prepare_only:
        parser.error("Choose either prepare-only or preflight-only")
    if physical and (not args.device_id_file or not args.candidate_hashes_file):
        parser.error("Physical iOS requires private --device-id-file and --candidate-hashes-file")
    if not physical and (args.device_id_file or args.candidate_hashes_file):
        parser.error("Physical destination inputs require explicit --destination ios")
    if physical and args.allow_provisioning_updates:
        parser.error("Physical diagnostic tests do not change provisioning or device registration")
    source, candidate = args.source_root.resolve(), args.candidate_app.resolve()
    output = args.output_root.resolve()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("A native Apple Silicon Mac is required")
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("Team ID must contain ten uppercase alphanumeric characters")
    if (not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id)
            or args.bundle_id.casefold() == "com.innersloth.amongus" or len(args.bundle_id) > 230):
        parser.error("An explicit own bundle identifier is required; the official game identifier is rejected")
    if output.exists() or output.is_symlink():
        parser.error("Output directory already exists; refusing to replace anything")
    if source in output.parents or candidate in output.parents:
        parser.error("Output must be outside both input trees")
    if any((parent / ".git").exists() for parent in (output, *output.parents)):
        parser.error("Game output must be outside Git checkouts")
    info = plistlib.loads((candidate / "Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier"), info.get("CFBundleExecutable")) != (
            args.bundle_id, "EHRNativeGame"):
        parser.error("Candidate does not match this runtime test's bundle contract")
    output.mkdir(parents=True)
    project = None if args.preflight_only else prepare_project(source, args.test_source.resolve(), output, args.team_id, args.bundle_id)
    if args.prepare_only:
        print(json.dumps({"prepared_project": str(project), "game_copied": False,
                          "game_launched": False}, indent=2))
        return
    destination_summary = {"platform": "macOS", "physical_device": False}
    if physical:
        destination_file, destination, pins_before, destination_summary = physical_preflight(
            candidate, args.device_id_file, args.candidate_hashes_file, output)
        destination_summary.update({"platform": "iOS", "physical_device": True})
    else:
        hardware = json.loads(run(["system_profiler", "SPHardwareDataType", "-json"]))
        mac_id = hardware["SPHardwareDataType"][0].get("provisioning_UDID")
        if not mac_id:
            raise ValueError("The exact Mac provisioning UDID could not be determined")
        destination_file = output / "mac-destination.local.txt"
        private_write(destination_file, mac_id + "\n")
        destination = "platform=macOS,arch=arm64"
        pins_before = {relative: hash_file(candidate / relative) for relative in RELATIVE_BINARIES}
    profile_pin = hash_file(candidate / "embedded.mobileprovision")
    verifier = source / "tools/verify_signing.py"
    run(["python3", verifier, candidate, "--device-id-file", destination_file,
         "--team-id", args.team_id, "--bundle-id", args.bundle_id,
         *(["--team-name", args.team_name] if args.team_name is not None else []),
         "--output", output / "signing-before.json"], output / "signing-before.log")
    if args.preflight_only:
        summary = {"destination": destination_summary, "candidate_binary_sha256": pins_before,
                   "paid_profile_verified": True, "exact_destination_covered": True,
                   "candidate_profile_sha256": profile_pin,
                   "diagnostic_install_attempted": False, "game_launched": False,
                   "security_or_pairing_changes_performed": False}
        (output / "runtime-preflight-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, indent=2))
        return
    derived = output / "DerivedData"
    result_bundle = output / "RuntimeResults.xcresult"
    common = ["xcodebuild", "-project", "EHRRuntimeProbe.xcodeproj", "-scheme", "EHRRuntimeProbe",
              "-configuration", "Debug", "-destination", destination,
              "-derivedDataPath", derived, "ENABLE_DEBUG_DYLIB=NO",
              "GCC_PREPROCESSOR_DEFINITIONS=$(inherited) EHR_XCTEST_WRAPPER_HOLD_SECONDS=" + ("0" if physical else "5")]
    provisioning = ["-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration"] if args.allow_provisioning_updates else []
    run([*common, *provisioning, "build-for-testing"], output / ("build.local.log" if physical else "build.log"), project)
    host = derived / "Build/Products/Debug-iphoneos/EHRNativeGame.app"
    generated = output / "OriginalGeneratedHost.app"
    host.rename(generated)
    run(["cp", "-cR", candidate, host])
    (host / "PlugIns").mkdir(exist_ok=True)
    shutil.copytree(generated / "PlugIns/NativeRuntimeTests.xctest",
                    host / "PlugIns/NativeRuntimeTests.xctest")
    run(["codesign", "--force", "--sign", args.sign_identity,
         "--preserve-metadata=entitlements,requirements,flags", "--timestamp=none",
         "--generate-entitlement-der", host])
    run(["codesign", "--verify", "--deep", "--strict", host])
    if physical:
        verify_test_bundle_team(host / "PlugIns/NativeRuntimeTests.xctest", args.team_id, args.bundle_id)
    run(["python3", verifier, host, "--device-id-file", destination_file,
         "--team-id", args.team_id, "--bundle-id", args.bundle_id,
         *(["--team-name", args.team_name] if args.team_name is not None else []),
         "--output", output / "signing-test-host.json"], output / "signing-test-host.log")
    # Resealing the copied host changes its own CodeDirectory, while nested
    # framework/helper/AOT binaries must remain exactly the preflight candidate.
    if physical and (hash_file(candidate / "embedded.mobileprovision") != profile_pin or
                     hash_file(host / "embedded.mobileprovision") != profile_pin):
        raise ValueError("Exact candidate provisioning profile changed before diagnostic launch")
    if physical and any(hash_file(host / relative) != pins_before[relative] for relative in RELATIVE_BINARIES[1:]):
        raise ValueError("A nested candidate binary changed before physical diagnostic launch")
    if any(hash_file(candidate / relative) != pins_before[relative] for relative in RELATIVE_BINARIES):
        raise ValueError("Source candidate changed before diagnostic launch")
    test_arguments = [*common, "-resultBundlePath", result_bundle,
                      "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                      "-default-test-execution-time-allowance", "60",
                      "-maximum-test-execution-time-allowance", "65", "test-without-building"]
    # Keep project/scheme constraints. A standalone .xctestrun with only a Mac
    # destination can accidentally select ordinary macOS rather than iOSMac.
    log_path = output / ("test.local.log" if physical else "test.log")
    wrapper = output / "PreservedXcodeTemporaryWrapper"
    copied = False
    with log_path.open("w") as stream:
        log_path.chmod(0o600)
        process = subprocess.Popen([str(x) for x in test_arguments], cwd=project,
                                   stdout=stream, stderr=subprocess.STDOUT)
        started = time.monotonic()
        try:
            while process.poll() is None:
                text = log_path.read_text(errors="replace")
                match = re.search(r"EHR_XCTEST_WRAPPER_READY (/.+?/Wrapper/EHRNativeGame\.app)", text)
                if match and not copied and not physical:
                    original_wrapper = Path(match.group(1)).parent.parent
                    run(["cp", "-cRp", original_wrapper, wrapper], timeout=30)
                    copied = True
                if time.monotonic() - started > 150:
                    raise TimeoutError("Normal XCTest exceeded150seconds")
                time.sleep(0.1)
        except BaseException:
            process.terminate()
            process.wait(timeout=15)
            raise
    unchanged = (all(hash_file(candidate / relative) == pin for relative, pin in pins_before.items()) and
                 hash_file(candidate / "embedded.mobileprovision") == profile_pin)
    attachments = output / "Attachments"
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", result_bundle,
         "--output-path", attachments])
    for attachment in attachments.glob("*.json"):
        value = json.loads(attachment.read_text())
        if not isinstance(value, dict):
            continue
        friendly = ("EHRNativeXCTestSnapshot.json" if value.get("schema") == "ehr.live-runtime.v1"
                    else "EHRFullSourceFailureCleanupProof.json" if value.get("schema") == "ehr.full-source-failure-cleanup-proof.v1"
                    else "EHRSourceAudioProof.json" if value.get("schema") == "ehr.full-source-audio-proof.v1"
                    else "EHRSourceAudioLoaderProof.json" if value.get("schema") == "ehr.full-source-audio-loader-proof.v1"
                    else "EHRSourceActionOwnershipProof.json" if value.get("schema") == "ehr.full-source-action-ownership-proof.v1"
                    else "EHRSourceTouchShortcutsProof.json" if value.get("schema") == "ehr.full-source-touch-shortcuts-proof.v1"
                    else "EHRNativeXCTestProof.json" if "versionGetter" in value or value.get("schema") in
                    ("ehr.full-source-runtime-proof.v1", "ehr.full-source-startup-proof.v1") else None)
        if friendly and attachment.name != friendly:
            target = attachments / friendly
            if not target.exists():
                shutil.copy2(attachment, target)
    summary = {"destination": destination_summary,
               "diagnostic_install_attempted": physical, "final_playable_app_delivered": False,
               "xcodebuild_exit_code": process.returncode, "source_candidate_unchanged": unchanged,
               "candidate_binary_sha256": pins_before, "candidate_profile_sha256": profile_pin,
               "wrapper_preserved": copied,
               "preserved_inner_executable": str(wrapper / "Wrapper/EHRNativeGame.app/EHRNativeGame") if copied else None,
               "test_source_sha256": hash_file(args.test_source), "result_bundle": str(result_bundle),
               "attachments": str(attachments), "terms_or_ui_actions_performed": False,
               "multiplayer_verified": False,
               "limitations": (["Physical installation is a diagnostic XCTest host, separate from final playable delivery.",
                                 "No terms, login, game UI or lobby was operated."] if physical else
                                ["The preserved Xcode temporary wrapper is evidence, not a standalone app installation.",
                                 "Direct standalone execution may still be rejected by normal macOS launch policy."]) +
                               ["Murder/report behavior requires a later valid lobby test."]}
    (output / "runtime-test-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    if process.returncode or not unchanged:
        raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit("Runtime test subprocess failed (" + type(error).__name__ + "); inspect local artifact logs") from None
