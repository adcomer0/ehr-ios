using System;
using System.Collections;
using System.Collections.Generic;
using System.Text.Json;

namespace EHR.OwnBuildFixture;

// These are own state/action collaborators for the extracted source iterator.
// No Unity classes, native facades, settings model or game UI are emulated.
internal sealed class OwnedHandles : Dictionary<object, object>
{
    internal int RemoveCalls;
    public new bool Remove(object key) { RemoveCalls++; return base.Remove(key); }
}
internal sealed class OwnCount(Func<int> read)
{
    internal OwnCount AllOptions => this;
    internal int Count => read();
}
internal sealed class OwnReporter(Action<Exception> report)
{
    internal void ThrowException(Exception error) => report(error);
}
internal abstract class BuildState
{
    internal readonly object __instance = new();
    internal readonly OwnedHandles BuildCoroutines = new();
    internal readonly Dictionary<object, int> BuildGenerations = new();
    internal readonly List<string> Effects = new();
    internal readonly OwnCount OptionItem;
    internal readonly OwnReporter Utils;
    internal int Count = 3, FinishCalls, Logged;
    internal Func<int>? ReadCount;
    internal Action<int>? OnStep;
    internal Action? OnFinish;
    internal Action<Exception>? OnReport;
    protected BuildState()
    {
        OptionItem = new(() => ReadCount?.Invoke() ?? Count);
        Utils = new(error => { Logged++; OnReport?.Invoke(error); });
    }
    internal void Step(int index) { Effects.Add("step:" + index); OnStep?.Invoke(index); }
    internal void FinishUi() { Effects.Add("finish"); FinishCalls++; OnFinish?.Invoke(); }
    internal abstract IEnumerator Routine(int gen);
    internal IEnumerator Begin(int gen, object handle)
    {
        BuildGenerations[__instance] = gen;
        BuildCoroutines[__instance] = handle;
        return Routine(gen);
    }
}
internal static class Program
{
    private static int checks;
    private static readonly List<string> scenarios = new();
    private static void Check(bool value, string label)
    {
        checks++;
        if (!value) throw new InvalidOperationException(label);
    }
    private static void Dispose(IEnumerator value) => ((IDisposable)value).Dispose();
    private static int Drain(IEnumerator value)
    {
        int yields = 0;
        while (value.MoveNext()) { Check(value.Current is null, "original null yield"); yields++; }
        return yields;
    }
    private static void SameException(Action action, Exception expected, string label)
    {
        Exception? caught = null;
        try { action(); } catch (Exception error) { caught = error; }
        Check(ReferenceEquals(caught, expected), label);
    }
    private static void NormalAndOrdering()
    {
        var actual = new ActualSettingsBuild { Count = 101 };
        var baseline = new BaselineSettingsBuild { Count = 101 };
        var a = actual.Begin(1, new()); var b = baseline.Begin(1, new());
        Check(Drain(a) == 2 && Drain(b) == 2, "yield sites at indices0 and100");
        Check(string.Join(",", actual.Effects) == string.Join(",", baseline.Effects), "original action order");
        Check(actual.Effects.Count == 102 && actual.FinishCalls == 1, "all steps and final actions once");
        Check(actual.BuildCoroutines.Count == 0 && actual.BuildCoroutines.RemoveCalls == 1, "normal cleanup once");
        Check(actual.BuildGenerations[actual.__instance] == 1, "generation preserved");
        Dispose(a); Dispose(a);
        Check(actual.BuildCoroutines.RemoveCalls == 1, "normal subsequent disposal is idempotent");
        scenarios.Add("normal completion and original effect/yield order");
    }
    private static void Cancel()
    {
        var actual = new ActualSettingsBuild(); var a = actual.Begin(7, new());
        Check(a.MoveNext(), "cancel fixture starts through actual first yield");
        Check(actual.BuildCoroutines.Count == 1, "suspended build retained");
        Dispose(a);
        Check(actual.BuildCoroutines.Count == 0 && actual.BuildCoroutines.RemoveCalls == 1, "dispose retires started build");
        Check(actual.FinishCalls == 0 && actual.Effects.Count == 1, "cancel performs no remaining UI actions");
        Dispose(a); Check(actual.BuildCoroutines.RemoveCalls == 1, "repeated cancellation once");
        scenarios.Add("started iterator cancellation and repeated Dispose");
    }
    private static void Faults()
    {
        var fault = new InvalidOperationException("own finish action failure");
        var baseline = new BaselineSettingsBuild { OnFinish = () => throw fault };
        var b = baseline.Begin(1, new());
        SameException(() => Drain(b), fault, "baseline propagates UI failure");
        Check(baseline.BuildCoroutines.Count == 1, "baseline fault leaves stale handle");
        var actual = new ActualSettingsBuild { OnFinish = () => throw fault };
        var a = actual.Begin(1, new());
        SameException(() => Drain(a), fault, "adapted propagates same UI failure");
        Check(actual.BuildCoroutines.Count == 0 && actual.BuildCoroutines.RemoveCalls == 1, "fault final cleanup once");
        Dispose(a); Check(actual.BuildCoroutines.RemoveCalls == 1, "fault disposal once");
        var readFault = new InvalidOperationException("own count read failure");
        var count = new ActualSettingsBuild(); int reads = 0;
        count.ReadCount = () => ++reads == 2 ? throw readFault : 3;
        var c = count.Begin(2, new()); Check(c.MoveNext(), "count fault starts suspended");
        SameException(() => c.MoveNext(), readFault, "loop-condition fault propagated");
        Check(count.BuildCoroutines.Count == 0 && count.FinishCalls == 0, "loop-condition fault retires without finish");
        var first = new ActualSettingsBuild { ReadCount = () => throw readFault };
        var f = first.Begin(3, new());
        SameException(() => f.MoveNext(), readFault, "failure before first yield propagated");
        Check(first.BuildCoroutines.Count == 0 && first.BuildCoroutines.RemoveCalls == 1, "entered try cleanup before first yield");
        scenarios.Add("final UI failure and loop-condition failure before/after yield");
    }
    private static void PerOptionCatch()
    {
        var fault = new InvalidOperationException("own option action failure");
        var actual = new ActualSettingsBuild { OnStep = i => { if (i == 1) throw fault; } };
        var baseline = new BaselineSettingsBuild { OnStep = i => { if (i == 1) throw fault; } };
        Drain(actual.Begin(1, new())); Drain(baseline.Begin(1, new()));
        Check(actual.Logged == 1 && baseline.Logged == 1, "existing per-option catch runs");
        Check(string.Join(",", actual.Effects) == string.Join(",", baseline.Effects), "caught-option effects unchanged");
        Check(actual.FinishCalls == 1 && actual.BuildCoroutines.Count == 0, "caught option permits normal finish");
        var reportFault = new InvalidOperationException("own logger failure");
        var report = new ActualSettingsBuild { OnStep = _ => throw fault, OnReport = _ => throw reportFault };
        var r = report.Begin(2, new());
        SameException(() => r.MoveNext(), reportFault, "existing catch reporter failure propagated");
        Check(report.BuildCoroutines.Count == 0 && report.FinishCalls == 0, "reporter failure retires current build");
        scenarios.Add("existing per-option catch behavior and reporter failure");
    }
    private static void Replacement()
    {
        var replacement = new object();
        var actual = new ActualSettingsBuild(); var a = actual.Begin(1, new()); Check(a.MoveNext(), "old build suspends");
        actual.BuildGenerations[actual.__instance] = 2; actual.BuildCoroutines[actual.__instance] = replacement;
        Dispose(a);
        Check(ReferenceEquals(actual.BuildCoroutines[actual.__instance], replacement), "old Dispose preserves replacement");
        Check(actual.BuildCoroutines.RemoveCalls == 0 && actual.FinishCalls == 0, "old Dispose does not remove or finish");
        var stale = new ActualSettingsBuild(); var s = stale.Begin(1, new()); Check(s.MoveNext(), "stale build starts");
        stale.BuildGenerations[stale.__instance] = 2; stale.BuildCoroutines[stale.__instance] = replacement;
        Drain(s);
        Check(ReferenceEquals(stale.BuildCoroutines[stale.__instance], replacement), "stale yield-break preserves replacement");
        Check(stale.FinishCalls == 0 && stale.BuildCoroutines.RemoveCalls == 0, "stale branch skips finish and remove");
        var baseline = new BaselineSettingsBuild(); var b = baseline.Begin(1, new()); Check(b.MoveNext(), "baseline stale starts");
        baseline.BuildGenerations[baseline.__instance] = 2; baseline.BuildCoroutines[baseline.__instance] = replacement;
        Drain(b); Check(baseline.BuildCoroutines.Count == 0, "baseline stale branch removes replacement");
        var reentrant = new ActualSettingsBuild(); var r = reentrant.Begin(1, new());
        reentrant.OnFinish = () => { reentrant.BuildGenerations[reentrant.__instance] = 2; reentrant.BuildCoroutines[reentrant.__instance] = replacement; };
        Drain(r);
        Check(ReferenceEquals(reentrant.BuildCoroutines[reentrant.__instance], replacement), "replacement during final UI action preserved");
        Check(reentrant.FinishCalls == 1 && reentrant.BuildCoroutines.RemoveCalls == 0, "final action completes before guarded cleanup");
        scenarios.Add("replacement during suspension, stale completion, and reentrant final UI action");
    }
    private static void OtherOwnershipCases()
    {
        var actual = new ActualSettingsBuild(); object unrelated = new(), unrelatedHandle = new();
        actual.BuildCoroutines[unrelated] = unrelatedHandle;
        Drain(actual.Begin(1, new()));
        Check(actual.BuildCoroutines.Count == 1 && ReferenceEquals(actual.BuildCoroutines[unrelated], unrelatedHandle), "other menu untouched");
        var unknown = new ActualSettingsBuild(); object handle = new(); var u = unknown.Begin(1, handle);
        Check(u.MoveNext(), "missing generation case starts"); unknown.BuildGenerations.Remove(unknown.__instance); Dispose(u);
        Check(ReferenceEquals(unknown.BuildCoroutines[unknown.__instance], handle) && unknown.BuildCoroutines.RemoveCalls == 0, "no generation proof does not remove");
        var never = new ActualSettingsBuild(); var n = never.Begin(1, new()); Dispose(n);
        Check(never.BuildCoroutines.Count == 1 && never.Effects.Count == 0, "unstarted CLR iterator preserves lazy Dispose semantics");
        scenarios.Add("other menu, absent generation proof, and unstarted CLR iterator");
    }
    public static void Main()
    {
        NormalAndOrdering(); Cancel(); Faults(); PerOptionCatch(); Replacement(); OtherOwnershipCases();
        Console.WriteLine(JsonSerializer.Serialize(new { schema = "ehr.settings-build-cleanup-fixture.v1", checks, scenarios,
            baselineFaultRetainsStaleHandle = true, baselineStaleBranchRemovesReplacement = true,
            actualFaultAndCancelRetireCurrentGeneration = true, actualOlderGenerationPreservesReplacement = true,
            normalActionsAndYieldsUnchanged = true, gameCalls = 0, nativeCalls = 0 }));
    }
}
