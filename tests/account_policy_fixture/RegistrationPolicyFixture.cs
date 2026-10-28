namespace EHR;

// Own callbacks/resolver exercise the actual dispatcher and account policy.
// Every original/callback effect below is a counter; there is no game API.
internal static class RegistrationPolicyFixture
{
    internal sealed record Proof(bool Pass, bool SixExcludedBeforePrepare,
        bool SameTargetAllowedCallbackPreserved, bool PolicyReasonsSeparateFromUnavailable,
        bool DisabledBindingStopsCallbacks, bool RebindKeepsProtection,
        bool SharedClassAllowedCallbackPreserved, int ExcludedPrepareCalls,
        int ExcludedInvokeCalls, int OriginalCalls);

    sealed class Resolver : IEHRStaticTargetResolver
    {
        internal readonly List<string> Calls = new();
        public bool TryResolve(EHRStaticTargetSpec spec, out string key, out string reason)
        {
            Calls.Add(spec.MemberName);
            key = spec.MemberName == "Missing" ? "" : "own.shared.target";
            reason = spec.MemberName == "Missing" ? "own_fixture_missing_target" : "";
            return key.Length != 0;
        }
    }

    static EHRStaticTargetSpec Target(string name) => new("Own.Target", name, "Normal", [], true);
    static EHRStaticPatchDescriptor Descriptor(string id, string classId, string owner, int index,
        EHRStaticTargetSpec[] targets, Action<EHRStaticPatchFrame> invoke, Func<bool>? prepare = null)
        => new(id, classId, owner, EHRStaticPatchKind.Prefix, 400, index, true, true,
            [], [], targets, invoke, prepare);
    static EHRStaticPatchFrame Frame() => new(null, [], []);

    internal static Proof Run(string[] excluded)
    {
        int sensitivePrepare = 0, sensitiveInvoke = 0, allowedPrepare = 0;
        int allowedInvoke = 0, original = 0;
        var protectedDescriptors = excluded.Select((id, index) => Descriptor(id,
            id.Split("::", StringSplitOptions.None)[0], "own.protected", index,
            [Target("Sensitive" + index)],
            frame => { sensitiveInvoke++; frame.RunOriginal = false; },
            () => { sensitivePrepare++; throw new InvalidOperationException("Excluded Prepare ran."); })).ToArray();
        var safe = Descriptor("Own.Safe::Prefix#1000", "Own.Safe", "own.safe", 1000,
            [Target("Allowed")], _ => allowedInvoke++, () => { allowedPrepare++; return true; });
        var missing = Descriptor("Own.Missing::Prefix#1001", "Own.Missing", "own.other", 1001,
            [Target("Missing")], _ => throw new InvalidOperationException("Unavailable callback ran."));
        var noPrepare = Descriptor("Own.False::Prefix#1002", "Own.False", "own.other", 1002,
            [Target("MustNotResolve")], _ => throw new InvalidOperationException("Prepare-false callback ran."), () => false);
        var noTemplate = Descriptor("Own.Empty::Prefix#1003", "Own.Empty", "own.other", 1003,
            [], _ => throw new InvalidOperationException("Unresolved-template callback ran."));
        var registration = new EHRStaticRegistration([.. protectedDescriptors, safe, missing, noPrepare, noTemplate]);
        var resolver = new Resolver();
        bool unrequestedInactive = registration.BindRequested(resolver).Count == 0
            && registration.PolicyExcluded.Count == 0 && resolver.Calls.Count == 0;
        registration.RequestAssembly();
        var bindings = registration.BindRequested(resolver);
        bool excludedFirst = unrequestedInactive && sensitivePrepare == 0 && sensitiveInvoke == 0
            && registration.PolicyExcluded.Count == 6
            && excluded.All(id => registration.PolicyExcluded.TryGetValue(id, out string? reason) && reason.Length != 0)
            && resolver.Calls.SequenceEqual(new[] { "Allowed", "Missing" });
        bool shared = bindings.Count == 1 && bindings["own.shared.target"].Prefixes.Length == 1
            && bindings["own.shared.target"].Prefixes[0].Id == safe.Id && allowedPrepare == 2;
        bindings["own.shared.target"].Execute(Frame(), _ => original++);
        shared &= allowedInvoke == 1 && original == 1 && sensitiveInvoke == 0;
        bool separate = registration.Unavailable.Count == 3
            && registration.Unavailable[missing.Id + "@Own.Target.Missing"] == "own_fixture_missing_target"
            && registration.Unavailable[noPrepare.Id] == "class_Prepare_returned_false"
            && registration.Unavailable[noTemplate.Id] == "target_template_unresolved_by_generator"
            && excluded.All(id => !registration.Unavailable.ContainsKey(id))
            && !registration.PolicyExcluded.ContainsKey(missing.Id);

        registration.DisableOwner("own.safe");
        // Existing bindings must consult the enabled guard after owner removal.
        bindings["own.shared.target"].Execute(Frame(), _ => original++);
        bool disabled = allowedInvoke == 1 && original == 2;
        registration.PolicyExcluded["Own.Stale"] = "stale";
        registration.Unavailable["Own.Stale"] = "stale";
        var disabledBindings = registration.BindRequested(resolver);
        disabled &= disabledBindings.Count == 0 && registration.PolicyExcluded.Count == 6
            && !registration.PolicyExcluded.ContainsKey("Own.Stale") && !registration.Unavailable.ContainsKey("Own.Stale");

        registration.RequestClass("Own.Safe");
        var rebound = registration.BindRequested(resolver);
        rebound["own.shared.target"].Execute(Frame(), _ => original++);
        bool rebind = allowedInvoke == 2 && original == 3 && allowedPrepare == 4
            && sensitivePrepare == 0 && sensitiveInvoke == 0 && registration.PolicyExcluded.Count == 6;
        registration.DisableOwner("own.protected");
        registration.BindRequested(resolver);
        rebind &= registration.PolicyExcluded.Count == 0;
        registration.RequestAssembly();
        registration.BindRequested(resolver);
        rebind &= registration.PolicyExcluded.Count == 6 && sensitivePrepare == 0 && sensitiveInvoke == 0;

        // An allowed descriptor sharing an excluded descriptor's class still prepares.
        int sharedClassPrepare = 0, sharedClassInvoke = 0;
        var sameClassSafe = Descriptor("Own.SharedClassSafe::Prefix#2000", protectedDescriptors[0].ClassId,
            "own.sameclass", 2000, [Target("SharedClassAllowed")], _ => sharedClassInvoke++,
            () => { sharedClassPrepare++; return true; });
        var sameClass = new EHRStaticRegistration([protectedDescriptors[0], sameClassSafe]);
        sameClass.RequestAssembly();
        var classBindings = sameClass.BindRequested(new Resolver());
        classBindings["own.shared.target"].Execute(Frame(), _ => original++);
        bool classSafe = sharedClassPrepare == 2 && sharedClassInvoke == 1
            && classBindings["own.shared.target"].Prefixes.Length == 1
            && sameClass.PolicyExcluded.Count == 1 && sensitivePrepare == 0 && sensitiveInvoke == 0;
        bool pass = excludedFirst && shared && separate && disabled && rebind && classSafe;
        return new(pass, excludedFirst, shared, separate, disabled, rebind, classSafe,
            sensitivePrepare, sensitiveInvoke, original);
    }
}
