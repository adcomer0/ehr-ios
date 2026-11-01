using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace EHR.OwnSettingsLoading;

// Owned identities, handles and injected actions, not a Unity/game emulator.
internal enum TabGroup { Other, Roles }
internal sealed record Row(int Index, TabGroup Tab, bool Continues = false);
internal sealed class OwnedMenu
{
    internal bool Live = true, Active = true;
    internal int Stops;
    internal Action? OnStop;
    internal void Stop(OwnedHandle handle) { Stops++; OnStop?.Invoke(); handle.Dispose(); }
}
internal sealed class OwnedHandle(IEnumerator routine) : IDisposable
{
    internal bool Live = true;
    internal readonly IEnumerator Routine = routine;
    public void Dispose() { if (!Live) return; Live = false; ((IDisposable)Routine).Dispose(); }
}
internal static unsafe partial class SettingsBuildControl
{
    private static readonly Dictionary<OwnedMenu, OwnedHandle> BuildCoroutines = new();
    private static readonly Dictionary<OwnedMenu, int> BuildGenerations = new();
    private static readonly List<OwnedMenu> Menus = [];
    private static readonly List<Row> Options = [];
    private static readonly List<int> Effects = [];
    private static bool OwnMain = true;
    private static int OwnTab = 4, checks, bounds, finishes, reports;
    private static Action<Row>? OnStep;
    private static Action? OnBounds, OnFinish;
    private static void OwnBounds() { bounds++; OnBounds?.Invoke(); }
    private static void OwnFinish() { finishes++; OnFinish?.Invoke(); }
    private static void OwnStep(Row row) { Effects.Add(row.Index); OnStep?.Invoke(row); }
    private static void OwnReport(Exception error) { reports++; }
    private static void Check(bool value, string label) { checks++; if (!value) throw new InvalidOperationException(label); }
    private static void Reset(int count, bool continues = false)
    {
        foreach (var handle in BuildCoroutines.Values.ToArray()) handle.Dispose();
        BuildCoroutines.Clear(); BuildGenerations.Clear(); SettingsBuilds.Clear(); Menus.Clear(); Options.Clear(); Effects.Clear();
        OwnMain = true; OwnTab = 4; bounds = finishes = reports = 0; OnStep = null; OnBounds = OnFinish = null;
        for (int i = 0; i < count; i++) Options.Add(new(i, TabGroup.Roles, continues));
    }
    private static uint[] Read(int expected = 0)
    {
        uint* words = stackalloc uint[8]; for (int i = 0; i < 8; i++) words[i] = 0xdeadbeef;
        delegate* unmanaged[Cdecl]<uint*, nuint, int> read = &CopySettingsLoading;
        Check(read(words, 8) == expected, "reader status");
        var result = new ReadOnlySpan<uint>(words, 8).ToArray();
        if (expected == 0) Check(result[0] == 1 && result[1] == 8 && result[7] == 0, "exact8word ABI");
        else Check(result.All(v => v == 0xdeadbeef), "rejected read untouched");
        return result;
    }
    private static void Drain(OwnedHandle handle)
    {
        int before = Effects.Count;
        while (handle.Routine.MoveNext())
        {
            Check(handle.Routine.Current is null, "null yield");
            Check(Effects.Count - before <= 8, "at most8 actual rows per slice"); before = Effects.Count;
        }
        Check(Effects.Count - before <= 8, "bounded final slice");
    }
    private static void NormalAndContinues()
    {
        foreach (bool continues in new[] { false, true })
        foreach (int count in new[] { 0, 1, 7, 8, 9, 100, 101, 1003 })
        {
            Reset(count, continues); var menu = new OwnedMenu(); Menus.Add(menu); var handle = Begin(menu);
            Check(Effects.Count == 0 && bounds == 0, "first actual yield precedes all work");
            var word = Read(); Check(word[2] == 1 && word[3] == 1 && word[4] == 0 && word[5] == count && word[6] == 5, "busy before work");
            Drain(handle);
            Check(Effects.SequenceEqual(Enumerable.Range(0, count)), "every selected row once and original order");
            Check(finishes == 1 && bounds == 1 && BuildCoroutines.Count == 0, "normal completion retires handle");
            Check(SettingsBuilds[menu].Complete && !SettingsBuilds[menu].Busy && !NeedsSettingsBuild(menu), "complete only after finish");
            Check(Read()[2] == 0, "normal label clears"); handle.Dispose();
        }
        Reset(19, true); Options.InsertRange(0, Enumerable.Range(0, 999).Select(i => new Row(-i - 1, TabGroup.Other)));
        var m = new OwnedMenu(); var h = Begin(m); Drain(h); Check(Effects.Count == 19, "foreign-tab scans do not change row accounting");
    }
    private static void CancellationAndReplacement()
    {
        Reset(33, true); var menu = new OwnedMenu(); Menus.Add(menu); var old = Begin(menu);
        Check(old.Routine.MoveNext() && Effects.Count == 8, "old suspended after8 rows");
        CancelSettingsBuild(menu);
        Check(menu.Stops == 1 && BuildCoroutines.Count == 0 && NeedsSettingsBuild(menu) && !SettingsBuilds[menu].Busy, "cancel marks incomplete and clears loading");
        Check(Read()[2] == 0 && finishes == 0, "cancel no fake completion");
        var replacement = Begin(menu); old.Dispose();
        Check(ReferenceEquals(BuildCoroutines[menu], replacement), "retired Dispose cannot remove replacement");
        Drain(replacement); Check(SettingsBuilds[menu].Complete, "partial menu can rebuild to completion");
        Reset(20); menu = new(); old = Begin(menu); menu.Active = false;
        Check(!old.Routine.MoveNext() && Effects.Count == 0 && !SettingsBuilds[menu].Busy && NeedsSettingsBuild(menu), "inactive before first work retires incomplete");
        Reset(20); menu = new(); old = Begin(menu); Check(old.Routine.MoveNext(), "first slice before inactive"); menu.Active = false;
        Check(!old.Routine.MoveNext() && Effects.Count == 8 && finishes == 0 && !SettingsBuilds[menu].Busy, "inactive next slice stops before more work");
        Reset(20); menu = new(); Menus.Add(menu); old = Begin(menu); var second = new OwnedMenu(); Menus.Add(second); var other = Begin(second);
        CancelAllSettingsBuilds(); Check(menu.Stops == 1 && second.Stops == 1 && BuildCoroutines.Count == 0 && Read()[3] == 0, "close retires all owned builds");
        Reset(20); menu = new() { OnStop = () => throw new InvalidOperationException("owned stop fault") }; Menus.Add(menu);
        old = Begin(menu); second = new(); Menus.Add(second); other = Begin(second);
        CancelAllSettingsBuilds();
        Check(reports == 1 && second.Stops == 1 && BuildCoroutines.Count == 0 && Read()[3] == 0, "one failed stop does not block remaining close cleanup");
        Check(!old.Routine.MoveNext() && Effects.Count == 0, "generation fence retires next step even if native stop failed");
    }
    private static void FaultsAndReader()
    {
        foreach (bool finish in new[] { false, true })
        {
            Reset(10); var fault = new InvalidOperationException("owned injected fault");
            if (finish) OnFinish = () => throw fault; else OnBounds = () => throw fault;
            var menu = new OwnedMenu(); var handle = Begin(menu); Exception? seen = null;
            try { Drain(handle); } catch (Exception error) { seen = error; }
            Check(ReferenceEquals(seen, fault), "original outer fault preserved");
            Check(!SettingsBuilds[menu].Busy && !SettingsBuilds[menu].Complete && BuildCoroutines.Count == 0 && Read()[2] == 0, "fault clears label without completion");
        }
        Reset(21, true); OnStep = row => { if (row.Index % 3 == 0) throw new ArgumentException("owned per-row fault"); };
        var own = new OwnedMenu(); var h = Begin(own); Drain(h); Check(reports == 7 && Effects.Count == 21 && finishes == 1, "existing per-row catch/continue preserved");
        Reset(20); own = new(); h = Begin(own); OwnTab = 3; Check(Read()[2] == 0 && Read()[3] == 1, "only selected tab shows loading");
        OwnMain = false; Read(2); OwnMain = true;
        SettingsBuilds[own] = new(9, TabGroup.Roles, 20001); Read(8);
        SettingsBuilds[own] = new(9, TabGroup.Roles, 1) { Processed = 2 }; Read(8);
        SettingsBuilds[own] = new(9, TabGroup.Roles, 1); OwnTab = 4;
        delegate* unmanaged[Cdecl]<uint*, nuint, int> read = &CopySettingsLoading;
        uint* words = stackalloc uint[8]; Check(read(null, 8) == 4 && read(words, 7) == 4, "invalid ABI rejected");
        SettingsBuilds[new()] = new(10, TabGroup.Roles, 1); Read(4);
        SettingsBuilds.Clear(); OwnTab = 1;
        for (int i = 0; i < 33; i++) SettingsBuilds[new()] = new(i, (TabGroup)i, 1);
        Read(8);
    }
    public static void Main()
    {
        NormalAndContinues(); CancellationAndReplacement(); FaultsAndReader();
        checks += SettingsCacheControl.CheckRepeatedOpen();
        Console.WriteLine(JsonSerializer.Serialize(new { schema = "ehr.settings-loading-owned-proof.v1", pass = true, checks,
            maxSelectedRowsPerSlice = 8, initialYieldBeforeWork = true, exactWordCount = 8,
            originalOuterFaultPropagated = true, currentGenerationOnlyCleanup = true,
            actualGameCalls = 0, nativeCalls = 0, accountActions = 0 }));
    }
}

internal enum OwnedMode { A, B, C, D, E }
internal sealed class OwnedButton
{
    internal bool Live = true, Active;
    internal int Configured, Reparents;
    internal void SetActive(bool value) => Active = value;
    internal void Reparent() => Reparents++;
    public static implicit operator bool(OwnedButton? value) => value is not null && value.Live;
}
internal static partial class SettingsCacheControl
{
    private static readonly Dictionary<OwnedMode, OwnedButton> GMButtons = new();
    private static int created;
    private static OwnedButton OwnCreate() { created++; return new() { Active = true }; }
    private static void Configure(OwnedButton value, OwnedMode mode) => value.Configured++;
    internal static int CheckRepeatedOpen()
    {
        int checks = 0;
        void Check(bool okay, string label) { checks++; if (!okay) throw new InvalidOperationException(label); }
        var modes = Enum.GetValues<OwnedMode>().ToList(); Open(modes);
        var original = GMButtons.ToDictionary();
        for (int i = 0; i < 100; i++)
        {
            Open(modes);
            Check(created == 5 && GMButtons.Count == 5, "reopen reuses exact cached set");
            Check(modes.All(mode => ReferenceEquals(original[mode], GMButtons[mode]) && GMButtons[mode].Active), "live identity and visibility retained");
        }
        Open(modes.Take(3).ToList());
        Check(GMButtons.Where(pair => (int)pair.Key >= 3).All(pair => !pair.Value.Active), "obsolete modes hidden");
        Open(modes); Check(created == 5 && GMButtons.Values.All(value => value.Active), "returning modes reuse old identities");
        original[OwnedMode.B].Live = false; Open(modes);
        Check(created == 6 && !ReferenceEquals(original[OwnedMode.B], GMButtons[OwnedMode.B]), "dead cache entry replaced");
        Check(GMButtons.Count == 5 && GMButtons.Values.All(value => value.Live), "one live cached button per mode");
        return checks;
    }
}
