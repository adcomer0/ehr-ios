#!/usr/bin/env python3
"""Generate the small Xcode project without a third-party project generator."""
from pathlib import Path
import argparse
import re
from signing_config import validate_identity

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--team-id", required=True)
parser.add_argument("--bundle-id", required=True)
args = parser.parse_args()
team, bundle, _ = validate_identity(args.team_id, args.bundle_id)

ROOT = Path(__file__).resolve().parents[1]
version = (ROOT / "VERSION").read_text().strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("VERSION must contain MAJOR.FEATURE.MINOR")
project = ROOT / "EHRPortLab.xcodeproj"
project.mkdir(exist_ok=True)
text = r'''// !$*UTF8*$!
{
 archiveVersion = 1;
 classes = {};
 objectVersion = 56;
 objects = {
  A00000000000000000000001 = {isa = PBXBuildFile; fileRef = B00000000000000000000001; };
  A00000000000000000000002 = {isa = PBXBuildFile; fileRef = B00000000000000000000002; };
  A00000000000000000000003 = {isa = PBXBuildFile; fileRef = B00000000000000000000006; };
  B00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EHRPortLabApp.swift; sourceTree = "<group>"; };
  B00000000000000000000002 = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = EHRHostCore.cpp; sourceTree = "<group>"; };
  B00000000000000000000003 = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = include/EHRHostCore.h; sourceTree = "<group>"; };
  B00000000000000000000004 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = EHRPortLab.app; sourceTree = BUILT_PRODUCTS_DIR; };
  B00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
  B00000000000000000000006 = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
  C00000000000000000000001 = {isa = PBXGroup; children = (C00000000000000000000002,C00000000000000000000003,C00000000000000000000004); sourceTree = "<group>"; };
  C00000000000000000000002 = {isa = PBXGroup; children = (B00000000000000000000001,B00000000000000000000005,B00000000000000000000006); path = app; sourceTree = "<group>"; };
  C00000000000000000000003 = {isa = PBXGroup; children = (B00000000000000000000002,B00000000000000000000003); path = native; sourceTree = "<group>"; };
  C00000000000000000000004 = {isa = PBXGroup; children = (B00000000000000000000004); name = Products; sourceTree = "<group>"; };
  D00000000000000000000001 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000001,A00000000000000000000002); runOnlyForDeploymentPostprocessing = 0; };
  D00000000000000000000002 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
  D00000000000000000000003 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000003); runOnlyForDeploymentPostprocessing = 0; };
  E00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000002; buildPhases = (D00000000000000000000001,D00000000000000000000002,D00000000000000000000003); buildRules = (); dependencies = (); name = EHRPortLab; productName = EHRPortLab; productReference = B00000000000000000000004; productType = "com.apple.product-type.application"; };
  E00000000000000000000002 = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700; TargetAttributes = {E00000000000000000000001 = {CreatedOnToolsVersion = 27.0; DevelopmentTeam = __TEAM_ID__; }; }; }; buildConfigurationList = F00000000000000000000001; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = C00000000000000000000001; productRefGroup = C00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (E00000000000000000000001); };
  F00000000000000000000001 = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000003,F00000000000000000000004); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
  F00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000005,F00000000000000000000006); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
  F00000000000000000000003 = {isa = XCBuildConfiguration; buildSettings = {CLANG_CXX_LANGUAGE_STANDARD = "c++17"; CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; }; name = Debug; };
  F00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {CLANG_CXX_LANGUAGE_STANDARD = "c++17"; CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; }; name = Release; };
  F00000000000000000000005 = {isa = XCBuildConfiguration; buildSettings = {__SETTINGS__ SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; }; name = Debug; };
  F00000000000000000000006 = {isa = XCBuildConfiguration; buildSettings = {__SETTINGS__ SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; }; name = Release; };
 };
 rootObject = E00000000000000000000002;
}
'''
settings = f'''ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
 CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = __TEAM_ID__;
 CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = {version};
 GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = app/Info.plist;
 PRODUCT_BUNDLE_IDENTIFIER = __APP_BUNDLE_ID__; PRODUCT_NAME = "$(TARGET_NAME)";
 SWIFT_VERSION = 5.0; SWIFT_OBJC_BRIDGING_HEADER = "app/EHRPortLab-Bridging-Header.h";
 HEADER_SEARCH_PATHS = "$(SRCROOT)/native/include";
 TARGETED_DEVICE_FAMILY = "1,2"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
 ENABLE_USER_SCRIPT_SANDBOXING = YES; SUPPORTS_MACCATALYST = NO;
'''
(project / "project.pbxproj").write_text(text.replace("__SETTINGS__", settings).replace("__TEAM_ID__", team).replace("__APP_BUNDLE_ID__", bundle))
schemes = project / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "EHRPortLab.xcscheme").write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="E00000000000000000000001" BuildableName="EHRPortLab.app" BlueprintName="EHRPortLab" ReferencedContainer="container:EHRPortLab.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="E00000000000000000000001" BuildableName="EHRPortLab.app" BlueprintName="EHRPortLab" ReferencedContainer="container:EHRPortLab.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
