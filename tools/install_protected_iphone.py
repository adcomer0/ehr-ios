#!/usr/bin/env python3
"""Upgrade the explicitly identified test app only after matching a passed Mac startup proof.

Never uninstalls, reads app containers, changes pairing/security, signs code,
accepts game terms, or operates accounts. All CoreDevice output stays private.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import sys
import traceback
from urllib.parse import unquote, urlparse
from signing_config import validate_identity



class Rejected(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise Rejected(code)


def outside_git(path):
    return not any((parent / ".git").exists() for parent in (path, *path.parents))


def private_write(path, value):
    path.write_text(value)
    path.chmod(0o600)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def helpers(source):
    # Reuse the canonical exact-device loader, four-binary pin validator, and
    # strict paid-team signature/profile verification. Importing runs no CLI.
    runtime = load_module("ehr_install_runtime_helpers", source / "tests/runtime/run_native_runtime_test.py")
    sys.path.insert(0, str(source / "tools"))
    try:
        signing = load_module("ehr_install_signing_helpers", source / "tools/verify_signing.py")
    finally:
        sys.path.pop(0)
    return runtime, signing.verify


def build_number(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,3}", value), "non_numeric_build")
    return tuple(int(part) for part in value.split(".")) + (0,) * (4 - len(value.split(".")))


def verify_candidate(candidate, udid, runtime, verifier, *, team_id, bundle_id, team_name=None):
    result = verifier(candidate, udid, team_id=team_id, bundle_id=bundle_id, team_name=team_name)
    for relative in runtime.RELATIVE_BINARIES:
        details = subprocess.run(["codesign", "-d", "--verbose=4", str(candidate / relative)],
                                 capture_output=True, check=True, text=True)
        match = re.search(r"^TeamIdentifier=(.+)$", details.stderr, re.M)
        require(match is not None and match.group(1) == team_id, "tested_binary_signing_team_differs")
    return result


def validate_game_start_iterator_proof(attachments):
    path = attachments / "EHRGameStartIteratorProof.json"
    require(path.is_file() and not path.is_symlink()
            and path.resolve().parent == attachments.resolve(), "game_start_iterator_self_test_missing")
    try:
        proof = json.loads(path.read_text())
    except (OSError, UnicodeError, ValueError) as error:
        raise Rejected("game_start_iterator_self_test_invalid") from error
    require(isinstance(proof, dict), "game_start_iterator_self_test_invalid")
    require(proof.get("schema") == "ehr.game-start-iterator-proof.v1"
            and proof.get("success") is True and type(proof.get("status")) is int
            and proof["status"] == 0 and type(proof.get("stage")) is int and proof["stage"] == 0
            and proof.get("rootAccountingBalanced") is True
            and proof.get("fixtureNullOwner") is True
            and all(proof.get(key) is False for key in (
                "realGameOwnerInvoked", "originalMoveNextInvoked", "realHostFactoryInvoked",
                "unityObjectCreated", "runtimeExecutableWrites")), "game_start_iterator_self_test_not_passed")
    counts = ("checks", "factorySeamCalls", "cancelCallsBefore", "cancelCallsAfter", "rootsBefore", "rootsAfter",
              "deferredReleasedBefore", "deferredReleasedAfter", "deferredEnqueuedBefore", "deferredEnqueuedAfter",
              "deferredDequeuedBefore", "deferredDequeuedAfter")
    require(all(type(proof.get(key)) is int and 0 <= proof[key] <= (1 << 64) - 1 for key in counts),
            "game_start_iterator_self_test_counts_invalid")
    require(46 <= proof["checks"] <= (1 << 32) - 1 and proof["factorySeamCalls"] == 6
            and proof["cancelCallsAfter"] == proof["cancelCallsBefore"] + 1,
            "game_start_iterator_self_test_counts_invalid")
    # Deferred finalizer releases can reduce the baseline while the own probe
    # runs. Match the native test's accounting rather than requiring raw totals
    # equal or trusting its success flag alone.
    require(all(proof["deferred" + name + "After"] >= proof["deferred" + name + "Before"]
                for name in ("Released", "Enqueued", "Dequeued"))
            and all(proof["deferredReleased" + side] <= proof["deferredDequeued" + side]
                    <= proof["deferredEnqueued" + side] for side in ("Before", "After"))
            and proof["rootsAfter"] + proof["deferredReleasedAfter"] - proof["deferredReleasedBefore"]
                    == proof["rootsBefore"], "game_start_iterator_self_test_root_accounting_invalid")


def validate_auth_handoff_proof(attachments):
    path = attachments / "EHRAuthHandoffProof.json"
    require(path.is_file() and not path.is_symlink()
            and path.resolve().parent == attachments.resolve(), "auth_handoff_self_test_missing")
    try:
        proof = json.loads(path.read_text())
    except (OSError, UnicodeError, ValueError) as error:
        raise Rejected("auth_handoff_self_test_invalid") from error
    require(isinstance(proof, dict), "auth_handoff_self_test_invalid")
    require(proof.get("schema") == "ehr.auth-handoff-proof.v1"
            and proof.get("success") is True and type(proof.get("status")) is int and proof["status"] == 0
            and type(proof.get("preparedStatus")) is int and proof["preparedStatus"] == 0
            and type(proof.get("failures")) is int and proof["failures"] == 0
            and type(proof.get("checks")) is int and 87 <= proof["checks"] <= (1 << 32) - 1
            and proof.get("isolatedRecorder") is True
            and proof.get("eventCapacity") == 32 and proof.get("eventRingBounded") is True
            and proof.get("middleAppleTypePreserved") is True and proof.get("unknownScalarRedacted") is True
            and all(proof.get(key) is False for key in (
                "realAuthenticationInvoked", "credentialsRead", "networkOperations", "runtimeExecutableWrites"))
            and all(type(proof.get(key)) is int and proof[key] == 0 for key in (
                "actualCredentialReads", "originalAuthCalls", "networkRequests", "accountActions")),
            "auth_handoff_self_test_not_passed")


def validate_mac_proof(candidate, summary_path, runtime, *, team_id, bundle_id):
    candidate, summary_path = candidate.resolve(), summary_path.resolve()
    require(outside_git(candidate) and outside_git(summary_path), "artifact_input_inside_git")
    summary = json.loads(summary_path.read_text())
    require(summary.get("destination") == {"platform": "macOS", "physical_device": False}
            and summary.get("xcodebuild_exit_code") == 0
            and summary.get("source_candidate_unchanged") is True
            and summary.get("terms_or_ui_actions_performed") is False, "mac_test_not_passed")
    require(summary.get("diagnostic_install_attempted") is False, "mac_summary_is_not_local_test")
    result_bundle = Path(summary.get("result_bundle", "")).resolve()
    attachments = Path(summary.get("attachments", "")).resolve()
    require(result_bundle.parent == summary_path.parent and result_bundle.suffix == ".xcresult"
            and result_bundle.is_dir() and attachments == summary_path.parent / "Attachments",
            "mac_result_evidence_missing")
    proof_path = attachments / "EHRNativeXCTestProof.json"
    proof = json.loads(proof_path.read_text())
    status = proof.get("status", {})
    application = status.get("application", {})
    require(proof.get("schema") == "ehr.full-source-startup-proof.v1"
            and proof.get("startupReachedTerminalObservation") is True
            and proof.get("termsAcceptedByTest") is False
            and proof.get("accountActionsPerformed") is False
            and status.get("status") == 0 and status.get("attempted") is True
            and status.get("fullMainLoadRequested") is True
            and status.get("productionCoroutinesReady") is True
            and status.get("bindingsReady") is True
            and status.get("stage") == "source_callbacks_active"
            and application.get("state") == 3 and application.get("status") == 0
            and application.get("dynamicCodeFlags") == 0
            and application.get("optionsLoaded") == 1
            and application.get("postLoadTasksComplete") == 1
            and application.get("activeBindings", 0) > 0
            and application.get("optionCount", 0) > 0
            and application.get("unavailableTargets") == 0, "full_startup_proof_not_passed")
    test_log = (summary_path.parent / "test.log").read_text()
    require("** TEST EXECUTE SUCCEEDED **" in test_log
            and "** TEST EXECUTE FAILED **" not in test_log, "mac_test_terminal_success_missing")
    pins = runtime.validate_candidate_pins(candidate, summary_path)
    profile_pin = runtime.hash_file(candidate / "embedded.mobileprovision")
    require(profile_pin == summary.get("candidate_profile_sha256"), "profile_differs_from_mac_test")
    info = plistlib.loads((candidate / "Info.plist").read_bytes())
    version_proof = proof.get("applicationVersion", {})
    if info.get("EHRNetworkDiagnosticsCompiled"):
        network = status.get("numericDiagnostics", {}).get("networkDisconnect", {})
        require(isinstance(network, dict) and network.get("schemaVersion") == 1
                and all(type(network.get(key)) is int and network[key] == 0 for key in (
                    "targetMatches", "count", "hasReason", "observerFaults")),
                "network_disconnect_startup_not_ready")
    if info.get("EHREOSLoginDiagnosticsEnabled"):
        require(status.get("eosLoginObserverStatus") == 0, "eos_login_observer_not_ready")
    if info.get("EHRAuthHandoffDiagnosticsCompiled"):
        handoff = status.get("authHandoff", {})
        require(isinstance(handoff, dict) and type(handoff.get("preparedStatus")) is int
                and handoff["preparedStatus"] == 0
                and handoff.get("schemaVersion") == 2 and handoff.get("eventCapacity") == 32
                and handoff.get("eventCount") == 0 and handoff.get("events") == []
                and all(type(handoff.get(key)) is int and handoff[key] == 0 for key in (
                    "appleSuccesses", "managedCredentialEntries", "loginEntries", "typeObservations",
                    "observerFaults")), "auth_handoff_startup_not_ready")
        validate_auth_handoff_proof(attachments)
    if info.get("EHRAuthRetryGuardActivationRequested"):
        guard = status.get("authRetryGuard", {})
        require(info.get("EHRAuthRetryGuardCompiled") is True and isinstance(guard, dict)
                and guard.get("startupRequested") is True and guard.get("preparedStatus") == 0
                and guard.get("startupPrepareStatus") == 0 and guard.get("startupEnableStatus") == 0
                and guard.get("enabled") is True, "auth_retry_guard_startup_not_ready")
    if info.get("EHRGameStartIteratorCompiled"):
        adapter = status.get("gameStartIterator", {})
        require(isinstance(adapter, dict) and adapter.get("preparedStatus") == 0
                and adapter.get("enabled") is True, "game_start_iterator_startup_not_ready")
        validate_game_start_iterator_proof(attachments)
    require(version_proof.get("success") is True and version_proof.get("status") == 0
            and version_proof.get("value") == info.get("EHRReferenceGameVersion")
            == info.get("CFBundleShortVersionString") == version_proof.get("expected")
            and info.get("CFBundleShortVersionString") not in (None, "", "0.0.0"),
            "actual_game_runtime_version_not_preserved")
    require((info.get("CFBundleIdentifier"), info.get("CFBundleExecutable")) == (bundle_id, "EHRNativeGame"), "wrong_bundle_contract")
    require(1 in info.get("UIDeviceFamily", []) and not info.get("UISupportedDevices"), "candidate_not_unthinned_iphone_app")
    build_number(info.get("CFBundleVersion"))
    signed_mac = json.loads((summary_path.parent / "signing-before.json").read_text())
    require(signed_mac.get("signature_verified") is True and signed_mac.get("team_id") == team_id
            and signed_mac.get("bundle_id") == bundle_id
            and signed_mac.get("build") == info["CFBundleVersion"]
            and signed_mac.get("version") == info.get("CFBundleShortVersionString"), "mac_signed_app_identity_differs")
    for relative in runtime.RELATIVE_BINARIES:
        require((candidate / relative).resolve().is_relative_to(candidate), "binary_escapes_candidate")
    return {"pins": pins, "profile_pin": profile_pin, "info_pin": runtime.hash_file(candidate / "Info.plist"),
            "build": info["CFBundleVersion"], "version": info["CFBundleShortVersionString"],
            "options": application["optionCount"], "active_targets": application["activeBindings"]}


def assert_unchanged(candidate, evidence, runtime):
    require(all(runtime.hash_file(candidate / path) == value for path, value in evidence["pins"].items())
            and runtime.hash_file(candidate / "embedded.mobileprovision") == evidence["profile_pin"]
            and runtime.hash_file(candidate / "Info.plist") == evidence["info_pin"], "local_candidate_changed")


def receipt_result(data, command, device=None):
    info, result = data.get("info", {}), data.get("result", {})
    require(info.get("outcome") == "success" and info.get("commandType") == "devicectl." + command
            and isinstance(result, dict), "device_receipt_not_success")
    if device is not None:
        require(result.get("deviceIdentifier") == device, "device_receipt_identity_differs")
    return result


def installed_app(data, device, *, bundle_id):
    result = receipt_result(data, "device.info.apps", device)
    require(result.get("matchingBundleIdentifier") == bundle_id, "installed_query_not_exact_bundle")
    apps = result.get("apps")
    require(isinstance(apps, list), "installed_apps_missing")
    require(len(apps) <= 1 and all(row.get("bundleIdentifier") == bundle_id for row in apps), "installed_bundle_ambiguous")
    return apps[0] if apps else None


def executable_path(value):
    require(isinstance(value, str), "invalid_executable_receipt")
    url = urlparse(value)
    require(url.scheme in ("", "file") and not url.netloc and not url.query and not url.fragment, "invalid_executable_receipt")
    return PurePosixPath(unquote(url.path))


def validate_launch(data, device, app):
    result = receipt_result(data, "device.process.launch", device)
    options, process = result.get("launchOptions", {}), result.get("process", {})
    environment = options.get("environmentVariables") or {}
    # CoreDevice itself propagates TERM on an ordinary foreground launch. No
    # launch environment flags are supplied by this tool; other overrides fail.
    environment_plain = isinstance(environment, dict) and set(environment) <= {"TERM"}
    require(options.get("activatedWhenStarted") is True and options.get("startStopped") is False
            and options.get("terminateExistingInstances") is False
            and not options.get("arguments") and environment_plain, "launch_was_not_plain_foreground")
    pid = process.get("processIdentifier")
    expected = executable_path(app.get("url")) / "EHRNativeGame"
    require(type(pid) is int and pid > 0 and executable_path(process.get("executable")) == expected, "launched_process_differs")
    return pid, expected


class DeviceCommandFailure(RuntimeError):
    pass


class DeviceRunner:
    def __init__(self, output):
        self.output = output

    def call(self, name, arguments, seconds=20):
        receipt = self.output / (name + ".local.json")
        log = self.output / (name + ".local.log")
        try:
            with log.open("w") as stream:
                log.chmod(0o600)
                result = subprocess.run(["xcrun", "devicectl", *arguments, "--timeout", str(seconds),
                                         "--json-output", str(receipt)], stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=seconds + 5)
            if result.returncode != 0:
                raise DeviceCommandFailure()
            return json.loads(receipt.read_text())
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
            raise DeviceCommandFailure() from error
        finally:
            if receipt.exists():
                receipt.chmod(0o600)


def execute(candidate, summary_path, private_file, output, runtime, verifier,
            runner, summary, preflight_only=False, launch=False, *, team_id, bundle_id):
    validate_identity(team_id, bundle_id)
    evidence = validate_mac_proof(candidate, summary_path, runtime, team_id=team_id, bundle_id=bundle_id)
    requested = runtime.load_physical_device_file(private_file)
    signing = verifier(candidate, requested["udid"])
    require(signing.get("signature_verified") is True and signing.get("team_id") == team_id
            and signing.get("bundle_id") == bundle_id and signing.get("requested_device_covered") is True,
            "exact_phone_paid_signature_not_verified")
    private_write(output / "signing.local.json", json.dumps(signing, indent=2) + "\n")
    summary.update(local_candidate_verified=True, passed_mac_startup=True,
                   same_four_tested_binaries=True, exact_phone_profile_coverage=True,
                   candidate_build=evidence["build"], option_count=evidence["options"],
                   active_patch_targets=evidence["active_targets"])
    try:
        inventory = runner.call("device-inventory", ["list", "devices"])
        receipt_result(inventory, "list.devices")
        try:
            device = runtime.select_physical_device(inventory, requested)
        except ValueError:
            summary["status"] = "exact_paired_iphone_unreachable_or_not_ready"
            return summary
        identifier = device["identifier"]
        details = runner.call("device-details", ["device", "info", "details", "--device", identifier])
        detail = receipt_result(details, "device.info.details")
        require(detail.get("identifier") == identifier
                and detail.get("hardwareProperties", {}).get("udid") == requested["udid"]
                and detail.get("hardwareProperties", {}).get("productType") == "iPhone18,2", "details_identity_differs")
        connection, properties = detail.get("connectionProperties", {}), detail.get("deviceProperties", {})
        require(connection.get("pairingState") == "paired"
                and connection.get("transportType") in ("wired", "localNetwork"), "details_pairing_or_transport_differs")
        if connection.get("tunnelState") != "connected":
            summary["status"] = "paired_iphone_tunnel_unavailable"
            return summary
        if (properties.get("bootState") != "booted" or properties.get("developerModeStatus") != "enabled"
                or properties.get("ddiServicesAvailable") is not True):
            summary["status"] = "iphone_development_services_not_ready"
            return summary
        summary.update(device_reachable=True, transport=connection.get("transportType"))
        before = installed_app(runner.call("installed-before", ["device", "info", "apps", "--device", identifier,
                                                                      "--bundle-id", bundle_id]), identifier, bundle_id=bundle_id)
    except DeviceCommandFailure:
        summary["status"] = "paired_iphone_services_unreachable"
        return summary
    if before is None:
        summary["status"] = "upgrade_requires_existing_exact_app"
        return summary
    summary["previous_build"] = before.get("bundleVersion")
    if build_number(evidence["build"]) <= build_number(before.get("bundleVersion")):
        summary["status"] = "candidate_build_not_newer"
        return summary
    summary["upgrade_ready"] = True
    if preflight_only:
        summary["status"] = "ready_for_upgrade"
        return summary
    assert_unchanged(candidate, evidence, runtime)
    summary["install_attempted"] = True
    data = runner.call("install", ["device", "install", "app", "--device", identifier, str(candidate)], 180)
    result = receipt_result(data, "device.install.app", identifier)
    apps = result.get("installedApplications")
    require(isinstance(apps, list) and len(apps) == 1 and apps[0].get("bundleID") == bundle_id, "install_receipt_bundle_differs")
    summary["installation_succeeded"] = True
    after = installed_app(runner.call("installed-after", ["device", "info", "apps", "--device", identifier,
                                                                  "--bundle-id", bundle_id]), identifier, bundle_id=bundle_id)
    require(after is not None and after.get("bundleVersion") == evidence["build"]
            and after.get("version") == evidence["version"], "installed_version_not_confirmed")
    assert_unchanged(candidate, evidence, runtime)
    summary.update(installed_version_confirmed=True, status="upgrade_installed")
    if launch:
        summary["launch_attempted"] = True
        data = runner.call("launch", ["device", "process", "launch", "--device", identifier, "--activate", bundle_id])
        pid, expected = validate_launch(data, identifier, after)
        summary["normal_foreground_launch_succeeded"] = True
        result = receipt_result(runner.call("processes", ["device", "info", "processes", "--device", identifier,
                                                               "--filter", "processIdentifier == " + str(pid)]),
                                "device.info.processes", identifier)
        summary["process_observed_running"] = any(row.get("processIdentifier") == pid
            and executable_path(row.get("executable")) == expected for row in result.get("runningProcesses", []))
        require(summary["process_observed_running"], "launched_process_not_observed")
        summary["status"] = "upgrade_installed_and_launched"
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source-root", "candidate-app", "mac-runtime-summary", "device-id-file", "output-root"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--team-name", help="Optional exact provisioning team-name assertion")
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--launch", action="store_true", help="Optional plain foreground launch; no game UI or account interaction")
    args = parser.parse_args(argv)
    validate_identity(args.team_id, args.bundle_id, args.team_name)
    if args.preflight_only and args.launch:
        parser.error("Preflight never launches an app")
    output = args.output_root.resolve()
    require(not output.exists() and outside_git(output), "output_must_be_new_outside_git")
    require(output != args.candidate_app.resolve() and args.candidate_app.resolve() not in output.parents,
            "output_must_not_be_inside_candidate")
    output.mkdir(parents=True, mode=0o700)
    output.chmod(0o700)
    summary = {"schema": "ehr.protected-iphone-upgrade.v1", "status": "not_started", "upgrade_ready": False,
               "install_attempted": False, "installation_succeeded": False, "installed_version_confirmed": False,
               "launch_attempted": False, "normal_foreground_launch_succeeded": False, "process_observed_running": False,
               "preflight_only": args.preflight_only, "uninstall_performed": False, "container_access_performed": False,
               "pairing_or_security_changes_performed": False, "account_or_game_ui_actions_performed": False,
               "publisher_backend_authentication_verified": False, "multiplayer_verified": False}
    exit_code = 0
    try:
        runtime, verifier = helpers(args.source_root.resolve())
        strict_verify = lambda app, udid: verify_candidate(app, udid, runtime, verifier, team_id=args.team_id, bundle_id=args.bundle_id, team_name=args.team_name)
        execute(args.candidate_app.resolve(), args.mac_runtime_summary.resolve(), args.device_id_file,
                output, runtime, strict_verify, DeviceRunner(output), summary, args.preflight_only, args.launch,
                team_id=args.team_id, bundle_id=args.bundle_id)
        if not args.preflight_only and not summary["installation_succeeded"]:
            exit_code = 3
    except Exception as error:
        private_write(output / "failure.local.log", traceback.format_exc())
        summary["status"] = str(error) if isinstance(error, Rejected) else "operation_failed_see_private_log"
        exit_code = 2
    private_write(output / "install-summary.json", json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return exit_code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Rejected as error:
        print(json.dumps({"status": str(error), "install_attempted": False}))
        sys.exit(2)
