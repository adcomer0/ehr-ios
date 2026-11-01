#!/usr/bin/env python3
"""Pinned, reversible settings-build scheduling and owned-cache adaptation."""
import argparse
import hashlib
import json
from pathlib import Path

EXPECTED_SOURCE_SHA256 = "e831dcd6ffecbd7f496cf819e4193216fff55a2e7c979fdab7615f9f02025ee7"
STATE_ANCHOR = "    private static readonly Dictionary<GameOptionsMenu, int> BuildGenerations = new();\n"
STATE = r'''
    // Own CLR state: the exported reader never inspects a Unity object.
    private sealed class SettingsBuildState(int generation, TabGroup tab, int total)
    {
        internal readonly int Generation = generation, Total = total;
        internal readonly TabGroup Tab = tab;
        internal int Processed;
        internal bool Busy = true, Complete;
    }
    private static readonly System.Collections.Generic.Dictionary<GameOptionsMenu, SettingsBuildState> SettingsBuilds = new();
    private static bool NeedsSettingsBuild(GameOptionsMenu menu) =>
        SettingsBuilds.TryGetValue(menu, out var state) && !state.Complete;

    internal static void CancelSettingsBuild(GameOptionsMenu menu)
    {
        if (SettingsBuilds.TryGetValue(menu, out var state)) state.Busy = false;
        if (BuildGenerations.TryGetValue(menu, out int generation)) BuildGenerations[menu] = unchecked(generation + 1);
        if (!BuildCoroutines.TryGetValue(menu, out Coroutine running)) return;
        // Remove the retired handle before Stop can synchronously dispose/reenter.
        BuildCoroutines.Remove(menu);
        try { if (menu && running != null) menu.StopCoroutine(running); }
        catch (Exception error) { Utils.ThrowException(error); }
    }

    internal static void CancelAllSettingsBuilds()
    {
        foreach (GameOptionsMenu menu in GameSettingMenuPatch.ModSettingsTabs.Values)
            CancelSettingsBuild(menu);
    }

    private static bool IsCurrentSettingsBuild(GameOptionsMenu menu, SettingsBuildState state) =>
        BuildGenerations.TryGetValue(menu, out int generation) && generation == state.Generation &&
        SettingsBuilds.TryGetValue(menu, out var current) && ReferenceEquals(current, state) &&
        menu && menu.gameObject.activeInHierarchy;

    // v1, words8, selectedBusy, activeCount, processed, total, tabIndexPlus1, reserved0.
    // A diagnostic read cannot invoke game facades, finish a build or clear state.
    [System.Runtime.InteropServices.UnmanagedCallersOnly(EntryPoint = "ehr_source_settings_loading_v1",
        CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static unsafe int CopySettingsLoading(uint* words, nuint count)
    {
        if (words == null || count != 8) return 4;
        if (!SourceHost.NativeSourceHost.IsMainThread) return 2;
        try
        {
            uint active = 0, busy = 0, processed = 0, total = 0, tab = 0;
            foreach (var state in SettingsBuilds.Values)
            {
                if (!state.Busy) continue;
                if (++active > 32 || state.Processed < 0 || state.Total < state.Processed || state.Total > 20000) return 8;
                if ((int)state.Tab + 3 != ModGameOptionsMenu.TabIndex) continue;
                if (busy != 0 || ModGameOptionsMenu.TabIndex < 0 || ModGameOptionsMenu.TabIndex >= 64) return 4;
                busy = 1; processed = (uint)state.Processed; total = (uint)state.Total;
                tab = (uint)ModGameOptionsMenu.TabIndex + 1;
            }
            words[0] = 1; words[1] = 8; words[2] = busy; words[3] = active;
            words[4] = processed; words[5] = total; words[6] = tab; words[7] = 0;
            return 0;
        }
        catch (Exception) { return 6; }
    }
'''

REPLACEMENTS = [
    (STATE_ANCHOR, STATE_ANCHOR + STATE),
    ("        if (__instance.Children == null || __instance.Children.Count == 0)\n",
     "        if (__instance.Children == null || __instance.Children.Count == 0 || NeedsSettingsBuild(__instance))\n"),
    ('''        __instance.scrollBar.SetYBoundsMax(CalculateScrollBarYBoundsMax());

        // Cancel any in-progress build coroutine on this instance before starting a new one
        if (BuildCoroutines.TryGetValue(__instance, out Coroutine existing) && existing != null)
        {
            __instance.StopCoroutine(existing);
            BuildCoroutines.Remove(__instance);
        }
''', '''        CancelSettingsBuild(__instance);
        __instance.Children = new();
'''),
    ('''        BuildGenerations[__instance] = currentGen;

#if IL2CPP
''', '''        BuildGenerations[__instance] = currentGen;
        var buildState = new SettingsBuildState(currentGen, modTab, OptionItem.AllOptions.Count(option => option.Tab == modTab));
        SettingsBuilds[__instance] = buildState;

#if IL2CPP
'''),
    ('''            try
            {
                var num = 2.0f;
''', '''            try
            {
                // Let the real loading indicator render before any settings work.
                yield return null;
                if (!IsCurrentSettingsBuild(__instance, buildState)) yield break;
                __instance.scrollBar.SetYBoundsMax(CalculateScrollBarYBoundsMax());
                int batch = 0;
                var num = 2.0f;
'''),
    ('''                for (var index = 0; index < OptionItem.AllOptions.Count; index++)
                {
                    try
''', '''                for (var index = 0; index < OptionItem.AllOptions.Count; index++)
                {
                    // Count actual tab rows, including header/hidden/error paths.
                    if (batch >= 8)
                    {
                        batch = 0;
                        yield return null;
                        if (!IsCurrentSettingsBuild(__instance, buildState)) yield break;
                    }
                    try
'''),
    ('''                        if (option.Tab != modTab) continue;

                        bool enabledOrNotCollapsed''', '''                        if (option.Tab != modTab) continue;
                        batch++;
                        buildState.Processed++;

                        bool enabledOrNotCollapsed'''),
    ('''                            CategoryHeaderMasked categoryHeaderMasked = ModGameOptionsMenu.CategoryHeaderList.TryGetValue(index, out CategoryHeaderMasked cache) ? cache : ModGameOptionsMenu.Track(Object.Instantiate(__instance.categoryHeaderOrigin, Vector3.zero, Quaternion.identity, __instance.settingsContainer));''',
     '''                            CategoryHeaderMasked categoryHeaderMasked = ModGameOptionsMenu.CategoryHeaderList.TryGetValue(index, out CategoryHeaderMasked cache) && cache ? cache : ModGameOptionsMenu.Track(Object.Instantiate(__instance.categoryHeaderOrigin, Vector3.zero, Quaternion.identity, __instance.settingsContainer));'''),
    ('''                            var chmCollider = categoryHeaderMasked.gameObject.AddComponent<BoxCollider2D>();''', '''                            var chmCollider = categoryHeaderMasked.gameObject.GetComponent<BoxCollider2D>();
                            if (!chmCollider) chmCollider = categoryHeaderMasked.gameObject.AddComponent<BoxCollider2D>();'''),
    ('''                            var chmButton = categoryHeaderMasked.gameObject.AddComponent<PassiveButton>();''', '''                            var chmButton = categoryHeaderMasked.gameObject.GetComponent<PassiveButton>();
                            if (!chmButton) chmButton = categoryHeaderMasked.gameObject.AddComponent<PassiveButton>();'''),
    ('''                            chmButton.OnClick.AddListener(() =>''', '''                            chmButton.OnClick.RemoveAllListeners();
                            chmButton.OnClick.AddListener(() =>'''),
    ('''                        if (!ModGameOptionsMenu.BehaviourList.TryGetValue(index, out OptionBehaviour optionBehaviour))''', '''                        if (!ModGameOptionsMenu.BehaviourList.TryGetValue(index, out OptionBehaviour optionBehaviour) || !optionBehaviour)'''),
    ('''                    if (index % 100 == 0)
                    {
                        yield return null;
                    }
''', '''                    // The next loop iteration yields after at most eight tab rows.
'''),
    ('''                if (!BuildGenerations.TryGetValue(__instance, out int latestGen) || latestGen != gen)
''', '''                if (!IsCurrentSettingsBuild(__instance, buildState))
'''),
    ('''                Canvas.ForceUpdateCanvases();
            }
            finally''', '''                __instance.InitializeControllerNavigation();
                Canvas.ForceUpdateCanvases();
                if (IsCurrentSettingsBuild(__instance, buildState)) buildState.Complete = true;
            }
            finally'''),
    ('''                // A retired iterator must not remove a replacement generation.
                if (BuildGenerations.TryGetValue(__instance, out int completedGen) && completedGen == gen)
                    BuildCoroutines.Remove(__instance);''', '''                buildState.Busy = false;
                // A retired iterator must not remove a replacement generation.
                if (BuildGenerations.TryGetValue(__instance, out int completedGen) && completedGen == gen)
                    BuildCoroutines.Remove(__instance);'''),
    ('''        GMButtons.Clear();''', '''        // Retain/reuse owned cached buttons rather than abandoning a set on every open.
        foreach (GameObject previous in GMButtons.Values)
            if (previous) previous.SetActive(false);'''),
    ('''            cached = GMButtons.TryGetValue(gm, out cache);''', '''            cached = GMButtons.TryGetValue(gm, out cache) && cache;'''),
    ('''                if (ModSettingsTabs.TryGetValue(tab, out settingsTab) && settingsTab)
                    settingsTab.gameObject.SetActive(false);''', '''                if (ModSettingsTabs.TryGetValue(tab, out settingsTab) && settingsTab)
                {
                    GameOptionsMenuPatch.CancelSettingsBuild(settingsTab);
                    settingsTab.gameObject.SetActive(false);
                }'''),
    ('''    public static void Close_Prefix()
    {
''', '''    public static void Close_Prefix()
    {
        GameOptionsMenuPatch.CancelAllSettingsBuilds();
'''),
    ('''        foreach (var x in GMButtons.Values)
        {
            var pb = x.GetComponent<PassiveButton>();''', '''        foreach (var x in GMButtons.Values)
        {
            if (!x) continue;
            var pb = x.GetComponent<PassiveButton>();'''),
    ('''        foreach (var x in ModSettingsTabs.Values) SetTempParent(x.gameObject);
        foreach (var x in ModSettingsButtons.Values) SetTempParent(x.gameObject);''', '''        foreach (var x in ModSettingsTabs.Values) if (x) SetTempParent(x.gameObject);
        foreach (var x in ModSettingsButtons.Values) if (x) SetTempParent(x.gameObject);'''),
    ('''        SetTempParent(InputField.gameObject);''', '''        if (InputField) SetTempParent(InputField.gameObject);'''),
    ('''            __instance.cachedData = GameOptionsManager.Instance.CurrentGameOptions;
            __instance.InitializeControllerNavigation();''', '''            __instance.cachedData = GameOptionsManager.Instance.CurrentGameOptions;
            if (!SettingsBuilds.TryGetValue(__instance, out var initializingBuild) || !initializingBuild.Busy)
                __instance.InitializeControllerNavigation();'''),
    ('''        void SetTempParent(GameObject go)
        {
            go.gameObject.transform.SetParent(TempParent, false);''', '''        void SetTempParent(GameObject go)
        {
            if (!go) return;
            go.gameObject.transform.SetParent(TempParent, false);'''),
]


def adapt(source):
    for old, new in REPLACEMENTS:
        if source.count(old) != 1:
            raise ValueError("Settings loading anchor changed or ambiguous: " + old.splitlines()[0])
        source = source.replace(old, new, 1)
    return source


def reverse(source):
    for old, new in reversed(REPLACEMENTS):
        if source.count(new) != 1:
            raise ValueError("Settings loading reverse anchor changed or ambiguous: " + new.splitlines()[0])
        source = source.replace(new, old, 1)
    return source


def transform(data):
    if hashlib.sha256(data).hexdigest() != EXPECTED_SOURCE_SHA256:
        raise ValueError("Settings source pin changed")
    source = data.decode()
    output = adapt(source)
    if reverse(output) != source:
        raise ValueError("Settings source did not reverse exactly")
    return output.encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.input.resolve() == args.output.resolve():
        parser.error("Choose a fresh separate output")
    original = args.input.read_bytes()
    output = transform(original)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    print(json.dumps({"schema": "ehr.settings-loading-adaptation.v1", "inputSha256": hashlib.sha256(original).hexdigest(),
        "outputSha256": hashlib.sha256(output).hexdigest(), "rowsPerSlice": 8, "initialFrameYield": True,
        "ownedCacheReuse": True, "capacityChanges": False, "physicalFreezeCauseProven": False}))


if __name__ == "__main__":
    main()
