#!/usr/bin/env python3
"""Build a LOCAL-ONLY native EHR port candidate using an original Unity launcher.

The installed source app is read-only. Its executable is neither copied nor
decrypted. Only unencrypted frameworks/resources are used through public Unity
entry points. The resulting app includes game content and MUST NOT be published.
"""
from __future__ import annotations
import argparse
import ctypes
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import uuid

from inspect_ios import inspect_path, Entry, Limits, parse_image
from signing_config import validate_identity
from iterator_hook_inputs import ITERATOR_METHODS, OWNER as ITERATOR_OWNER, merge_iterator_inputs
from platform_capabilities import platform_signin_capabilities
from full_hook_inputs import merge_full_inputs
from eos_login_hook_inputs import merge_eos_login_inputs, binding_header as eos_binding_header
from auth_retry_hook_inputs import merge_auth_retry_inputs, binding_header as auth_retry_binding_header

ROOT = Path(__file__).resolve().parents[1]


def game_runtime_version(source_info):
    """Unity reads the main bundle version; retain the actual game version."""
    version = source_info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2,3}", version) or not any(int(p) for p in version.split(".")):
        raise ValueError("Original game runtime version is missing or invalid")
    return version


def run(*command):
    subprocess.run(command, check=True)


def copy_file(source, destination):
    """Use APFS copy-on-write for immutable inputs, with normal-copy fallback."""
    try:
        clone = ctypes.CDLL(None, use_errno=True).clonefile
        clone.argtypes, clone.restype = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int], ctypes.c_int
        if clone(os.fsencode(source), os.fsencode(destination), 0) == 0:
            return destination
    except (AttributeError, OSError):
        pass
    return shutil.copy2(source, destination)


def build(args):
    team, bundle, team_name = validate_identity(args.team_id, args.bundle_id, args.team_name)
    source = args.game_app.resolve()
    output = args.output.resolve()
    full=bool(args.full_native_catalog)
    guard_map=getattr(args,"auth_retry_guard_map",None)
    guard_requested=bool(getattr(args,"enable_auth_retry_guard",False))
    if guard_requested and not guard_map:
        raise ValueError("--enable-auth-retry-guard requires --auth-retry-guard-map")
    if guard_map and not args.eos_login_map:
        raise ValueError("Auth retry guard metadata candidate requires --eos-login-map; activation is default disabled")
    if full != bool(args.full_native_target_map) or full != bool(args.full_thunk_inputs):
        raise ValueError("Full source requires its native catalog, pinned target map and compiled thunk inputs together")
    if full and not (args.managed_dylib and args.iterator_hook_map and args.static_class_hooks):
        raise ValueError("Full source requires the production source image, iterator and static component entry maps")
    if args.full_source_autoload and not full:
        raise ValueError("Full source auto startup requires the full source profile")
    if args.eos_login_map and not full:
        raise ValueError("EOS diagnostics require the full source profile")
    if output.exists():
        raise ValueError("Output exists; choose a new staging directory")
    report = inspect_path(source)
    if report["readiness"] == "invalid":
        raise ValueError("Source bundle did not pass structural inspection")
    source_info = plistlib.loads((source / "Info.plist").read_bytes())
    original_main = source_info["CFBundleExecutable"]
    if source_info.get("CFBundleIdentifier") != "com.innersloth.amongus":
        raise ValueError("Expected the installed official Among Us bundle")
    unsupported = [i for i in report["issues"] if not
        (i["code"] == "encrypted_image" and i.get("path") == original_main)]
    if unsupported:
        raise ValueError("Required framework/resource analysis gate failed")
    for image in report["images"]:
        if image["path"] != original_main and any(e["cryptid"] for s in image["slices"] for e in s["encryption"]):
            raise ValueError("A required game image is encrypted; no decryption is supported")
    profile_bytes = args.profile.read_bytes()
    profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(args.profile)]))
    if team not in profile.get("TeamIdentifier", []):
        raise ValueError("A provisioning profile for the explicit development team is required")
    if team_name is not None and profile.get("TeamName", "").casefold() != team_name.casefold():
        raise ValueError("Provisioning profile name does not match the explicit team name")
    if profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("Provisioning profile expired")
    app_id = team + "." + bundle
    if not fnmatch.fnmatchcase(app_id, profile["Entitlements"].get("application-identifier", "")):
        raise ValueError("Provisioning profile does not cover the probe bundle")
    destination = args.destination_id_file.read_text().strip()
    if destination not in profile.get("ProvisionedDevices", []):
        raise ValueError("Profile does not cover the exact test destination")
    certificates = {hashlib.sha1(bytes(c)).hexdigest().upper() for c in profile.get("DeveloperCertificates", [])}
    if len(args.identity) == 40 and all(c in "0123456789abcdefABCDEF" for c in args.identity) and args.identity.upper() not in certificates:
        raise ValueError("Selected signing certificate is not covered by the paid-team profile")
    output.mkdir(parents=True)
    app = output / "EHRNativeGame.app"

    def ignored(directory, names):
        excluded = {"_CodeSignature"} & set(names)
        if Path(directory) == source:
            excluded.add(original_main)
        return excluded

    shutil.copytree(source, app, symlinks=True, ignore=ignored, copy_function=copy_file)
    info = dict(source_info)
    info.update({"CFBundleIdentifier": bundle, "CFBundleExecutable": "EHRNativeGame",
                 "CFBundleName": "EHRNativeGame", "CFBundleDisplayName": "EHR Native Preview",
                 # Application.version is used by the original game and EHR's
                 # compatibility check. A preview version here falsely marks
                 # the packaged, current game as unsupported.
                 "CFBundleShortVersionString": game_runtime_version(source_info),
                 "EHRPortVersion": (ROOT / "VERSION").read_text().strip(),
                 "CFBundleVersion": str(args.build), "MinimumOSVersion": "17.0",
                 "EHRReferenceGameVersion": source_info["CFBundleShortVersionString"],
                 "EHRReferenceGameBuild": source_info["CFBundleVersion"],
                 "EHRProbeScope": "Native EHR source-port prototype; full role integration and multiplayer pending",
                 "NSHumanReadableCopyright": "Independent personal mod research. Not endorsed by Innersloth or EHR developers."})
    # The candidate must not take ownership of the official game's URL handler.
    info.pop("CFBundleURLTypes", None)
    # The reference is an App Store distribution thinned for iPad/Mac. Our own
    # development launcher declares the actual iPhone/iPad family above; an
    # inherited distribution device allowlist would reject the signed iPhone.
    info.pop("UISupportedDevices", None)
    info["EHRFullSourceAutoLoad"]=bool(full and args.full_source_autoload)
    info["EHREOSLoginDiagnosticsEnabled"]=bool(args.eos_login_map)
    info["EHRAuthRetryGuardCompiled"]=bool(guard_map)
    # Initial native state; only the explicit request may enable after Prepare.
    info["EHRAuthRetryGuardEnabled"]=False
    info["EHRAuthRetryGuardActivationRequested"]=guard_requested
    if full:
        info["EHRSourceVersion"]="8.0.3"
        info["EHRSourceCommit"]="ce23f0d050f617a59507e5bb0fbfff751d4b5134"
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    (app / "embedded.mobileprovision").write_bytes(profile_bytes)
    entitlements = {"application-identifier": app_id,
                    "com.apple.developer.team-identifier": team,
                    "get-task-allow": bool(profile["Entitlements"].get("get-task-allow"))}
    entitlements.update(platform_signin_capabilities(profile["Entitlements"],args.platform_sign_in))
    entitlement_path = output / "probe-entitlements.plist"
    entitlement_path.write_bytes(plistlib.dumps(entitlements))
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    managed_framework = None
    if args.managed_dylib:
        binary = args.managed_dylib.resolve()
        image = parse_image(Entry(binary.name, binary.stat().st_size, lambda: binary.open("rb")), Limits())
        if len(image["slices"]) != 1 or image["slices"][0]["architecture"] != "arm64" or image["slices"][0]["platform"] != "iOS":
            raise ValueError("Managed rules must be a real iOS ARM64 image")
        if image["slices"][0]["file_type"] != 6:
            raise ValueError("Managed rules must be a dynamic library")
        if any(e["cryptid"] for s in image["slices"] for e in s["encryption"]):
            raise ValueError("Encrypted managed rules are unsupported")
        managed_framework = app / "Frameworks/NativeSourceReuse.framework"
        managed_framework.mkdir()
        managed_binary = managed_framework / "NativeSourceReuse"
        shutil.copy2(binary, managed_binary)
        run("xcrun", "install_name_tool", "-id", "@rpath/NativeSourceReuse.framework/NativeSourceReuse", str(managed_binary))
        (managed_framework / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle + ".managedrules", "CFBundleName": "NativeSourceReuse",
            "CFBundleExecutable": "NativeSourceReuse", "CFBundlePackageType": "FMWK",
            "CFBundleShortVersionString": "0.0.0", "CFBundleVersion": str(args.build),
            "MinimumOSVersion": "17.0", "CFBundleSupportedPlatforms": ["iPhoneOS"]}))
    original_framework = source / "Frameworks/UnityFramework.framework/UnityFramework"
    hook_map = json.loads(args.hook_map.read_text())
    selected_hooks = ["PlayerControl.MurderPlayer", "Constants.GetBroadcastVersion", "Constants.IsVersionModded"]
    map_path, contracts_path = args.hook_map.resolve(), ROOT / "native/extra-hook-contracts.json"
    hook_aliases={name:name for name in selected_hooks}
    if full:
        full_catalog=json.loads(args.full_native_catalog.read_text())
        if full_catalog.get("targetInputSha256")!=hashlib.sha256(args.full_native_target_map.read_bytes()).hexdigest():
            raise ValueError("Full native target map differs from the generated source catalog input")
        hook_map,contracts,selected_hooks,hook_aliases=merge_full_inputs(hook_map,
            json.loads(args.full_native_target_map.read_text()),full_catalog,
            json.loads((args.full_thunk_inputs/"native-thunk-contracts.local.json").read_text()))
        map_path,contracts_path=output/"full-hook-map.local.json",output/"full-hook-contracts.local.json"
        map_path.write_text(json.dumps(hook_map,indent=2)+"\n");contracts_path.write_text(json.dumps(contracts,indent=2)+"\n")
    if args.iterator_hook_map:
        if not managed_framework:
            raise ValueError("Iterator carrier hooks require the compiled managed source runtime")
        hook_map, contracts, iterator_hooks = merge_iterator_inputs(hook_map,
            json.loads(args.iterator_hook_map.read_text()), json.loads(contracts_path.read_text()))
        map_path, contracts_path = output / "combined-hook-map.local.json", output / "combined-hook-contracts.json"
        map_path.write_text(json.dumps(hook_map, indent=2) + "\n")
        contracts_path.write_text(json.dumps(contracts, indent=2) + "\n")
        selected_hooks.extend(iterator_hooks)
    if args.eos_login_map:
        hook_map, contracts, eos_hooks = merge_eos_login_inputs(hook_map,
            json.loads(args.eos_login_map.read_text()), json.loads(contracts_path.read_text()))
        map_path, contracts_path = output / "eos-hook-map.local.json", output / "eos-hook-contracts.local.json"
        map_path.write_text(json.dumps(hook_map, indent=2)+"\n")
        contracts_path.write_text(json.dumps(contracts, indent=2)+"\n")
        selected_hooks.extend(eos_hooks)
    if guard_map:
        hook_map, contracts, guard_hooks = merge_auth_retry_inputs(hook_map,
            json.loads(guard_map.read_text()), json.loads(contracts_path.read_text()))
        map_path, contracts_path = output / "auth-retry-hook-map.local.json", output / "auth-retry-hook-contracts.local.json"
        map_path.write_text(json.dumps(hook_map, indent=2)+"\n")
        contracts_path.write_text(json.dumps(contracts, indent=2)+"\n")
        selected_hooks.extend(guard_hooks)
    metadata_file = source / "Data/Managed/Metadata/global-metadata.dat"
    metadata_pin = hook_map["input_pins"]["metadata"]
    if metadata_file.stat().st_size != metadata_pin["size"] or hashlib.sha256(metadata_file.read_bytes()).hexdigest() != metadata_pin["sha256"]:
        raise ValueError("Game metadata does not match the pinned hook map")
    patched_framework = output / "PatchedUnityFramework"
    class_plan = None
    if args.static_class_hooks:
        class_plan = json.loads(args.static_class_hooks.read_text())
        if class_plan.get("generated_flag") != "EHR_HAS_STATIC_CLASS_HOOKS" or class_plan.get("generated_flag_value") != 1:
            raise ValueError("Unsupported static class hook binding flag")
        for entry in class_plan.get("hooks",[]):
            for key in ("method_rva_constant","trampoline_rva_constant"):
                value=entry.get(key)
                if not isinstance(value,str) or not re.fullmatch(r"EHRClassFrom[A-Za-z]+(?:Method|Trampoline)RVA",value):
                    raise ValueError("Invalid static class generated binding name")
    run("python3", str(ROOT / "tools/patch_native_entries.py"),
        "--input", str(original_framework), "--map", str(map_path),
        "--output", str(patched_framework),
        *[argument for name in selected_hooks for argument in ("--hook", name)],
        "--contracts", str(contracts_path),
        *(["--private-hooks",str(args.static_class_hooks.resolve())] if class_plan else []))
    hook_manifest_path = patched_framework.with_name(patched_framework.name + ".manifest.json")
    hook_manifest = json.loads(hook_manifest_path.read_text())
    if args.eos_login_map:
        (output/"EHREOSLoginBinding.generated.h").write_text(eos_binding_header(hook_manifest))
    if guard_map:
        (output/"EHRAuthRetryBinding.generated.h").write_text(auth_retry_binding_header(hook_manifest))
    hooks = {h["method"]: h for h in hook_manifest["hooks"]}
    # Existing native original-call adapters retain their exact version/murder
    # trampoline names while the full profile replaces those three entry sites.
    for legacy,selected in hook_aliases.items():hooks[legacy]=hooks[selected]
    pinned_uuid = uuid.UUID(hook_manifest["framework_uuid"])
    header = output / "EHRHookBinding.generated.h"
    header.write_text("#pragma once\n#include <stdint.h>\n" +
        "static const uint8_t EHRHookImageUUID[16] = {" + ",".join(str(b) for b in pinned_uuid.bytes) + "};\n" +
        "static const uintptr_t EHRMurderTrampolineRVA = " + hooks["PlayerControl.MurderPlayer"]["trampoline_rva"] + ";\n" +
        "#define EHR_HAS_VERSION_HOOK 1\n" +
        "static const uintptr_t EHRVersionMethodRVA = " + hooks["Constants.GetBroadcastVersion"]["original_rva"] + ";\n" +
        "static const uintptr_t EHRVersionTrampolineRVA = " + hooks["Constants.GetBroadcastVersion"]["trampoline_rva"] + ";\n" +
        "#define EHR_HAS_IS_MODDED_HOOK 1\n" +
        "static const uintptr_t EHRIsModdedMethodRVA = " + hooks["Constants.IsVersionModded"]["original_rva"] + ";\n" +
        "static const uintptr_t EHRIsModdedTrampolineRVA = " + hooks["Constants.IsVersionModded"]["trampoline_rva"] + ";\n")
    if args.iterator_hook_map:
        with header.open("a") as stream:
            stream.write("#define EHR_HAS_ITERATOR_HOOKS 1\n")
            for name, _, _, _, constant in ITERATOR_METHODS:
                stream.write("static const uintptr_t " + constant + " = " + hooks[ITERATOR_OWNER + "." + name]["trampoline_rva"] + ";\n")
    if class_plan:
        with header.open("a") as stream:
            stream.write("#define EHR_HAS_STATIC_CLASS_HOOKS 1\n")
            for entry in class_plan["hooks"]:
                hook=hooks[entry["target"]]
                stream.write("static const uintptr_t "+entry["method_rva_constant"]+" = "+hook["original_rva"]+";\n")
                stream.write("static const uintptr_t "+entry["trampoline_rva_constant"]+" = "+hook["trampoline_rva"]+";\n")
    if full:
        for name in ("EHRNativeTypedThunks.generated.inc","EHRNativeThunkTypes.generated.h"):
            shutil.copy2(args.full_thunk_inputs/name,output/name)
        run("python3",str(ROOT/"tools/generate_native_typed_thunks.py"),"sites",
            "--catalog",str(args.full_native_catalog.resolve()),"--patch-manifest",str(hook_manifest_path),
            "--patched-framework",str(patched_framework),"--output",str(output/"NativeInstalledSites"))
        shutil.copy2(output/"NativeInstalledSites/EHRNativeThunkSites.generated.h",output/"EHRNativeThunkSites.generated.h")
        (output/"EHRNativeTypedThunks.generated.mm").write_text('#include "EHRNativeTypedThunks.generated.inc"\n')
        startup=[]
        for owner,name in (("SplashManager","Start"),("TranslationController","Initialize"),("VersionShower","Start")):
            matching=[r for r in full_catalog["candidates"] if r["nativeNamespace"]=="" and r["nativeType"]==owner and r["nativeMethod"]==name and not r["isStatic"] and r["nativeReturn"]=="System.Void" and r["nativeParameters"]==[]]
            if len(matching)!=1:raise ValueError("Full source startup requires exact unique Unity entry: "+owner+"."+name)
            startup.append(matching[0]["targetId"])
        (output/"EHRFullSourceStartup.generated.h").write_text('#pragma once\n#include <stdint.h>\nstatic const uint64_t EHRFullSourceStartupTargets[]={'+','.join(str(value)+'ULL' for value in startup)+'};\n')
    shutil.copy2(patched_framework, app / "Frameworks/UnityFramework.framework/UnityFramework")
    # The association adapter pins the FINAL nested framework bytes. Sign these
    # inputs before compiling that adapter; signing the parent later records its
    # nested signatures without rewriting the already signed dependencies.
    frameworks = sorted((app / "Frameworks").glob("*.framework"), key=lambda p: len(p.parts), reverse=True)
    for framework in frameworks:
        run("codesign", "--force", "--sign", args.identity, "--timestamp=none", str(framework))
    signed_framework = app / "Frameworks/UnityFramework.framework/UnityFramework"
    signed_framework_hash = hashlib.sha256(signed_framework.read_bytes()).hexdigest()
    association_header = output / "EHRNativeAssociation.generated.h"
    association_header.write_text("#pragma once\n#include <stdint.h>\n" +
        "static const uint8_t EHRAssociationFrameworkUUID[16] = {" + ",".join(str(b) for b in pinned_uuid.bytes) + "};\n" +
        "static const char EHRAssociationSourceSHA256Hex[] = \"" + hook_manifest["source_sha256"] + "\";\n" +
        "static const char EHRAssociationCandidateSHA256Hex[] = \"" + signed_framework_hash + "\";\n")
    compiler = ["xcrun", "--sdk", "iphoneos", "clang++", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
                "-std=c++17", "-fobjc-arc", "-fobjc-arc-exceptions", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                "-I", str(ROOT / "native"), "-I", str(ROOT / "native/include"), "-I", str(output)]
    frameworks_flags = ["-framework", "Foundation", "-framework", "UIKit", "-framework", "QuartzCore", "-framework", "CoreGraphics"]
    helper = app / "Frameworks/EHRNativeHooks.dylib"
    managed_flags = (["-DEHR_HAS_MANAGED_RULES="+("0" if full else "1"), "-F", str(app / "Frameworks"),
                      "-framework", "NativeSourceReuse"] if managed_framework else ["-DEHR_HAS_MANAGED_RULES=0"])
    managed_flags += ["-DEHR_HAS_FULL_SOURCE="+("1" if full else "0")]
    managed_flags += ["-DEHR_HAS_EOS_LOGIN_DIAGNOSTICS="+("1" if args.eos_login_map else "0")]
    managed_flags += ["-DEHR_HAS_AUTH_RETRY_GUARD="+("1" if guard_map else "0")]
    iterator_sources = ([str(ROOT / "native/EHRManagedIteratorAdapter.mm"), str(ROOT / "native/EHRManagedIteratorProduction.mm"), str(ROOT / "native/EHRManagedIteratorProbe.mm"),
                         str(ROOT / "native/EHRManagedIteratorSchedulingProbe.mm")]
                        if args.iterator_hook_map else [])
    native_sources=[
        str(ROOT / "native/EHRNativeHooks.mm"), str(ROOT / "native/EHRLiveBridge.mm"),
        str(ROOT / "native/EHRRuntimeGateway.mm"),
        str(ROOT / "native/EHRManagedFacadeTables.mm"),
        str(ROOT / "native/EHRRuntimeCollections.mm"),
        str(ROOT / "native/EHRRuntimeReflection.mm"),
        str(ROOT / "native/EHRRuntimeOriginalProbe.mm"),
        str(ROOT / "native/EHRManagedOriginalAdapter.mm"),
        str(ROOT / "native/EHRManagedOriginalProbe.mm"),
        *iterator_sources,
        str(ROOT / "native/EHRRuntimePinnedAssociation.mm"),
        str(ROOT / "native/EHRManagedActionAdapter.mm"), str(ROOT / "native/EHRManagedActionProbe.mm"),
        str(ROOT / "native/EHRManagedUnityActionProbe.mm"),
        str(ROOT / "native/EHRManagedPatchAdapter.mm"),str(ROOT / "native/EHRManagedPatchProbe.mm"),
        str(ROOT / "native/EHRManagedTypedActionAdapter.mm"), str(ROOT / "native/EHRManagedTypedActionProbe.mm"),
        str(ROOT / "native/EHRManagedComplexDelegateAdapter.mm"), str(ROOT / "native/EHRManagedComplexDelegateProbe.mm"),
        str(ROOT / "native/EHRSourceComponents.mm"), str(ROOT / "native/EHRManagedSourceComponentProbe.mm"),
        str(ROOT / "native/EHRSourcePluginOwnerProbe.mm"),
        str(ROOT / "native/EHRTouchUI.mm"),
        str(ROOT / "native/EHRManagedActionIdentityProbe.mm"),
        *([str(ROOT / "native/EHRStaticComponents.mm")] if class_plan else []),
        str(ROOT / "native/EHRManagedRuntime.mm"),
        str(ROOT / "native/EHRNativeOverlay.mm"), str(ROOT / "native/EHRNativeProbe.mm"),
        str(ROOT / "native/EHRHostCore.cpp")]
    if full:
        native_sources=[name for name in native_sources if not Path(name).name.endswith("Probe.mm") and
            Path(name).name not in ("EHRManagedRuntime.mm","EHRNativeOverlay.mm")]
        native_sources += [str(ROOT/"native/EHRNativePatchThunks.mm"),str(output/"EHRNativeTypedThunks.generated.mm"),
            str(ROOT/"native/EHRFullSourceRuntime.mm"),str(ROOT/"native/EHRFullSourceOverlay.mm"),
            str(ROOT/"native/EHRExportSharing.mm"),str(ROOT/"native/EHRRuntimeDiagnostics.mm"),
            str(ROOT/"native/EHRAppleAuthDiagnostics.mm")]
        if args.eos_login_map:native_sources.append(str(ROOT/"native/EHREOSLoginDiagnostics.mm"))
        if guard_map:native_sources.append(str(ROOT/"native/EHRAuthRetryGuard.mm"))
    run(*compiler, "-dynamiclib", "-DEHR_LIVE_BRIDGE_AUTOSTART=0",*managed_flags,
        "-Wl,-install_name,@rpath/EHRNativeHooks.dylib",*frameworks_flags,*native_sources,"-o",str(helper))
    run(*compiler, "-I", str(ROOT / "native/launcher"), *frameworks_flags,
        "-Wl,-rpath,@executable_path/Frameworks", "-Wl,-rpath,/usr/lib/swift",
        str(ROOT / "native/launcher/main.mm"), "-o", str(app / "EHRNativeGame"))
    run("codesign", "--force", "--sign", args.identity, "--timestamp=none", str(helper))
    run("codesign", "--force", "--sign", args.identity, "--timestamp=none", "--entitlements", str(entitlement_path), str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    if hashlib.sha256(signed_framework.read_bytes()).hexdigest() != signed_framework_hash:
        raise ValueError("Nested framework changed after its native-association pin was compiled")
    run("xcrun", "dyld_info", "-validate_only", str(app / "EHRNativeGame"), str(helper),
        str(app / "Frameworks/UnityFramework.framework/UnityFramework"))
    bindings = subprocess.check_output(["xcrun", "llvm-objdump", "--macho", "--bind",
        str(app / "Frameworks/UnityFramework.framework/UnityFramework")], text=True, timeout=30)
    if not all(h["symbol"] in bindings for h in hook_manifest["hooks"]):
        raise ValueError("Apple's binding-table inspection did not resolve every native hook symbol")
    (output / "dyld-bindings.local.txt").write_text(bindings)
    run("python3", str(ROOT / "tools/verify_signing.py"), str(app),
        "--device-id-file", str(args.destination_id_file), "--team-id", team, "--bundle-id", bundle,
        *(["--team-name", team_name] if team_name is not None else []), "--output", str(output / "signing.json"))
    manifest = {"local_only_game_content": True, "must_not_publish_or_redistribute": True,
                "source_bundle": report["bundle"], "source_images": [{"path": i["path"], "sha256": i["sha256"]} for i in report["images"]],
                "source_launcher_copied": False, "decryption_performed": False,
                "original_app_modified": False, "app": str(app), "build": args.build,
                "native_executable_sha256": hashlib.sha256((app / "EHRNativeGame").read_bytes()).hexdigest(),
                "native_helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
                "hook_manifest": hook_manifest_path.name,
                "scope": "Native EHR source port: live runtime facades, original-method route and upstream option/version rules; full integration pending",
                "full_ehr_available": False, "runtime_validation": "pending"}
    manifest["native_method_association_pins"] = {
        "original_source_sha256": hook_manifest["source_sha256"],
        "signed_candidate_framework_sha256": signed_framework_hash,
        "framework_uuid": str(pinned_uuid),
        "runtime_association_verified_by_build": False}
    manifest["own_native_source_sha256"] = {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((ROOT / "native").rglob("*"))
        if p.is_file() and p.suffix in (".h", ".hpp", ".inc", ".mm", ".cpp")}
    manifest["generated_binding_headers_sha256"] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
        (header, association_header, *([output/"EHREOSLoginBinding.generated.h"] if args.eos_login_map else []),
         *([output/"EHRAuthRetryBinding.generated.h"] if guard_map else []))}
    manifest["managed_source_reuse"] = bool(managed_framework)
    manifest["iterator_carrier_hooks"] = bool(args.iterator_hook_map)
    manifest["own_platform_sign_in_capabilities"] = bool(args.platform_sign_in)
    manifest["publisher_backend_authentication_verified"] = False
    manifest["eos_login_diagnostics"] = bool(args.eos_login_map)
    manifest["auth_retry_guard_compiled"] = bool(guard_map)
    # Build-time initial state, not an assertion of runtime activation.
    manifest["auth_retry_guard_enabled"] = False
    manifest["auth_retry_guard_activation_requested"] = guard_requested
    if guard_map:manifest["auth_retry_guard_map_sha256"] = hashlib.sha256(guard_map.read_bytes()).hexdigest()
    if args.eos_login_map:manifest["eos_login_map_sha256"] = hashlib.sha256(args.eos_login_map.read_bytes()).hexdigest()
    manifest["full_source_profile"] = full
    manifest["source_target_handlers_compiled"] = len(full_catalog["candidates"]) if full else 0
    manifest["full_source_gameplay_verified"] = False
    if args.iterator_hook_map:
        manifest["iterator_hook_map_sha256"] = hashlib.sha256(args.iterator_hook_map.read_bytes()).hexdigest()
    manifest["managed_scope"] = "Unchanged EHR numeric/version sources and generated live API facades" if managed_framework else None
    (output / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.skip_ipa:
        print("LOCAL-ONLY signed app staged; IPA packaging skipped:", app)
        return
    # ditto preserves signatures, modes and bundle symlinks in a standard IPA.
    packaging = output / "Packaging/Payload"
    packaging.mkdir(parents=True)
    shutil.copytree(app, packaging / app.name, symlinks=True, copy_function=copy_file)
    ipa = output / ("EHRNativeGame-" + info["CFBundleShortVersionString"] + "-" + str(args.build) + "-local-only.ipa")
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(packaging), str(ipa))
    print("LOCAL-ONLY native EHR port candidate staged:", app)
    print("Runtime and multiplayer verification remain pending:", ipa)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--team-id", required=True, help="Your explicit Apple development team ID")
    p.add_argument("--bundle-id", required=True, help="Your own app identifier; the official game identifier is rejected")
    p.add_argument("--team-name", help="Optional exact provisioning team-name assertion")
    p.add_argument("--game-app", type=Path, required=True)
    p.add_argument("--profile", type=Path, required=True)
    p.add_argument("--destination-id-file", type=Path, required=True)
    p.add_argument("--identity", required=True)
    p.add_argument("--hook-map", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--build", type=int, required=True)
    p.add_argument("--skip-ipa", action="store_true", help="Stage the signed app only for direct device install or runtime checks")
    p.add_argument("--managed-dylib", type=Path, help="Own ahead-of-time-compiled iOS rules library; no desktop game DLLs")
    p.add_argument("--static-class-hooks",type=Path,help="Explicit pinned private class entry plan for native-only component test")
    p.add_argument("--platform-sign-in",action="store_true",help="Enable your own Apple sign-in/Game Center capabilities, only if explicitly covered by your profile")
    p.add_argument("--full-native-catalog",type=Path,help="Explicit full-source candidate declarations; requires matching pinned native map and independently compiled typed thunks")
    p.add_argument("--full-native-target-map",type=Path)
    p.add_argument("--full-thunk-inputs",type=Path,help="Reviewed generated typed thunks/types/contracts; installed-site evidence is regenerated after patching")
    p.add_argument("--full-source-autoload",action="store_true",help="Start full source at an exact Unity startup entry; requires the full source profile")
    p.add_argument("--eos-login-map",type=Path,help="Exact reviewed two-callback/getter map for passive numeric login diagnostics")
    p.add_argument("--auth-retry-guard-map",type=Path,help="Compile/install reviewed guard entry default-disabled for explicit metadata-only preparation tests; requires --eos-login-map")
    p.add_argument("--enable-auth-retry-guard",action="store_true",help="Opt-in development build: request startup activation only after successful metadata preparation; requires --auth-retry-guard-map")
    p.add_argument("--iterator-hook-map", type=Path, help="Optional exact pinned ArrayList iterator map; requires reviewed compiled carrier bridge")
    a = p.parse_args()
    if a.build < 2:
        p.error("Probe build numbers start at 2")
    try:
        build(a)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        p.exit(1, str(error) + "\n")
