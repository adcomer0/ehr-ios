#!/usr/bin/env python3
"""Run extracted settings scheduling/state code against owned action collaborators."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("settings_loading", ROOT / "tools/source_port/prepare_settings_loading.py")
loading = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loading)


def extract(source):
    # Exact reversible mapping also verifies every work/cancel/cache anchor.
    baseline = loading.reverse(source)
    if loading.transform(baseline.encode()).decode() != source:
        raise ValueError("Selected settings source pin or adaptation changed")
    start = source.index("        IEnumerator CoRoutine(int gen)\n")
    end = source.index("\n        float CalculateScrollBarYBoundsMax()", start)
    routine = source[start:end]
    a = routine.index("                var num = 2.0f;")
    b = routine.index("                for (var index", a)
    routine = routine[:a] + routine[b:]
    a = routine.index("                        OptionItem option = OptionItem.AllOptions[index];")
    b = routine.index("                        if (enabledOrNotCollapsed) num -= 0.45f;", a) + len("                        if (enabledOrNotCollapsed) num -= 0.45f;")
    original = routine[a:b]
    # Counter placement precedes all four continue paths and all UI work.
    if original.index("buildState.Processed++;") > original.index("bool enabledOrNotCollapsed") or original.count("continue;") != 4:
        raise ValueError("Selected row accounting/continue paths changed")
    routine = routine[:a] + """                        var option = Options[index];
                        if (option.Tab != modTab) continue;
                        batch++;
                        buildState.Processed++;
                        OwnStep(option);
                        if (option.Continues) continue;""" + routine[b:]
    a = routine.index("                __instance.ControllerSelectable.Clear();")
    b = routine.index("                Canvas.ForceUpdateCanvases();", a) + len("                Canvas.ForceUpdateCanvases();")
    routine = routine[:a] + "                OwnFinish();" + routine[b:]
    routine = routine.replace("__instance.scrollBar.SetYBoundsMax(CalculateScrollBarYBoundsMax());", "OwnBounds();")
    routine = routine.replace("OptionItem.AllOptions.Count", "Options.Count")
    state = loading.STATE
    for old, new in [("GameOptionsMenu", "OwnedMenu"), ("Coroutine running", "OwnedHandle running"),
                     ("menu && running != null", "menu.Live && running != null"), ("menu.StopCoroutine(running)", "menu.Stop(running)"),
                     ("GameSettingMenuPatch.ModSettingsTabs.Values", "Menus"),
                     ("menu && menu.gameObject.activeInHierarchy", "menu.Live && menu.Active"),
                     ("SourceHost.NativeSourceHost.IsMainThread", "OwnMain"),
                     ("ModOwnedMenu.TabIndex", "OwnTab"), ("Utils.ThrowException(error)", "OwnReport(error)")]:
        state = state.replace(old, new)
    routine = routine.replace("Utils.ThrowException(e)", "OwnReport(e)")
    return state, routine


def extract_cache(source):
    start = source.index("        // Retain/reuse owned cached buttons")
    end = source.index("        if (!HudManager.InstanceExists) return;", start)
    cache = source[start:end]
    a = cache.index("            gmButton.transform.localPosition =")
    b = cache.index("            GMButtons[gm] = gmButton;", a)
    cache = cache[:a] + "            Configure(gmButton, gm);\n" + cache[b:]
    cache = cache.replace("GameObject", "OwnedButton").replace("CustomGameMode", "OwnedMode")
    cache = cache.replace("ModGameOptionsMenu.Track(Object.Instantiate(gMinus, gameSettingsLabel.transform, true))", "OwnCreate()")
    cache = cache.replace("gmButton.transform.SetParent(gameSettingsLabel.transform, false);", "gmButton.Reparent();")
    if "Instantiate" in cache or "transform" in cache or "UnityEngine" in cache:
        raise ValueError("Cache game-work extraction changed")
    return cache


def check(source, output, dotnet):
    source, output = source.resolve(), output.resolve()
    if output.exists():
        raise ValueError("Fresh fixture output required")
    state, routine = extract(source.read_text())
    output.mkdir(parents=True)
    generated = output / "ExtractedSettingsBuild.cs"
    generated.write_text("""using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
namespace EHR.OwnSettingsLoading;
internal static unsafe partial class SettingsBuildControl
{
""" + state + """
    internal static OwnedHandle Begin(OwnedMenu menu)
    {
        var __instance = menu;
        var modTab = (TabGroup)(OwnTab - 3);
        CancelSettingsBuild(menu);
        BuildGenerations.TryGetValue(menu, out int currentGen);
        currentGen++;
        BuildGenerations[menu] = currentGen;
        var buildState = new SettingsBuildState(currentGen, modTab, Options.Count(option => option.Tab == modTab));
        SettingsBuilds[menu] = buildState;
        var routine = CoRoutine(currentGen);
        var handle = new OwnedHandle(routine);
        if (!routine.MoveNext()) throw new InvalidOperationException("Expected actual initial frame yield");
        BuildCoroutines[menu] = handle;
        return handle;
""" + routine + "    }\n}\n" + """
internal static partial class SettingsCacheControl
{
    private static void Open(System.Collections.Generic.List<OwnedMode> gms)
    {
        bool cached; OwnedButton? cache;
""" + extract_cache(source.read_text()) + "    }\n}\n")
    project = ET.Element("Project", Sdk="Microsoft.NET.Sdk")
    group = ET.SubElement(project, "PropertyGroup")
    for k, v in {"TargetFramework": "net10.0", "OutputType": "Exe", "AllowUnsafeBlocks": "true", "Nullable": "enable", "EnableDefaultCompileItems": "false"}.items():
        ET.SubElement(group, k).text = v
    group = ET.SubElement(project, "ItemGroup")
    for p in (generated, ROOT / "tests/SettingsLoadingFixture.cs"):
        ET.SubElement(group, "Compile", Include=str(p))
    target = output / "Fixture.csproj"
    ET.ElementTree(project).write(target, encoding="unicode")
    run = subprocess.run([str(dotnet), "run", "--project", str(target), "-c", "Release", "--artifacts-path", str(output / "artifacts")],
                         text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90, env=os.environ.copy())
    (output / "fixture.log").write_text(run.stdout)
    if run.returncode:
        raise RuntimeError(run.stdout[-7000:])
    proof = json.loads(next(line for line in run.stdout.splitlines() if line.startswith('{"schema":"ehr.settings-loading-owned-proof.v1"')))
    proof.update(actualSelectedControlFlowExtracted=True, gameUiWorkReplacedByOwnedActions=True, physicalFreezeCauseProven=False)
    (output / "proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    return proof


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--dotnet", type=Path, required=True)
    a = p.parse_args()
    print(json.dumps(check(a.source, a.output, a.dotnet)))
