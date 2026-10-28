// Original managed dispatcher support for generated direct EHR callback calls.
// This file never discovers/patches executable methods or invokes reflection.
#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.ExceptionServices;

namespace EHR;

internal enum EHRStaticPatchKind { Prefix, Postfix, Finalizer }

internal sealed class EHRStaticPatchFrame
{
    internal object? Instance;
    internal object? Result;
    internal object?[] Arguments;
    internal readonly Dictionary<string, int> ArgumentNames;
    internal readonly Dictionary<string, object?> InstanceFields = new(StringComparer.Ordinal);
    internal readonly Dictionary<string, object?> State = new(StringComparer.Ordinal);
    internal bool RunOriginal = true;
    internal bool OriginalEntered;
    internal Exception? Exception;
    internal bool Consumed;

    internal EHRStaticPatchFrame(object? instance, object?[] arguments, string[] names)
    {
        if (arguments.Length != names.Length) throw new ArgumentException("Argument metadata count mismatch.");
        Instance = instance;
        Arguments = arguments;
        ArgumentNames = new Dictionary<string, int>(StringComparer.Ordinal);
        for (int i = 0; i < names.Length; i++)
            if (!ArgumentNames.TryAdd(names[i], i)) throw new ArgumentException("Duplicate original argument name.");
    }

    static T Cast<T>(object? value, bool allowDefault)
    {
        if (value is T typed) return typed;
        if (value is null && (allowDefault || !typeof(T).IsValueType)) return default!;
        throw new InvalidCastException("Bound value is not the generated callback's requested type " + typeof(T).FullName);
    }
    int Index(string name) => ArgumentNames.TryGetValue(name, out int index) ? index
        : throw new NotSupportedException("Original argument name is unbound: " + name);
    internal T GetInstance<T>() => Cast<T>(Instance, false);
    internal T GetArgument<T>(int index) => Cast<T>(Arguments[index], false);
    internal T GetArgument<T>(string name) => GetArgument<T>(Index(name));
    internal void SetArgument<T>(int index, T value) => Arguments[index] = value;
    internal void SetArgument<T>(string name, T value) => SetArgument(Index(name), value);
    internal T GetResult<T>() => Cast<T>(Result, true);
    internal T GetState<T>(string patchClass) => State.TryGetValue(patchClass, out object? value) ? Cast<T>(value, true) : default!;
    internal void SetState<T>(string patchClass, T value) => State[patchClass] = value;
    internal T GetField<T>(string name) => InstanceFields.TryGetValue(name, out object? value) ? Cast<T>(value, false)
        : throw new NotSupportedException("Original field is unbound: " + name);
    internal void SetField<T>(string name, T value)
    {
        if (!InstanceFields.ContainsKey(name)) throw new NotSupportedException("Original field is unbound: " + name);
        InstanceFields[name] = value;
    }
}

internal sealed class EHRStaticTargetSpec
{
    internal readonly string TypeName, MemberName, MethodKind;
    internal readonly string[] ArgumentTypeNames;
    internal readonly bool ExactArgumentTypes;
    internal readonly string? Image, ReturnType;
    internal readonly string ResolutionStatus;
    internal readonly string[] ParameterNames;
    internal readonly bool? IsStatic;
    internal EHRStaticTargetSpec(string typeName, string memberName, string methodKind, string[] argumentTypeNames, bool exactArgumentTypes,
        string? image = null, string? returnType = null, bool? isStatic = null, string[]? parameterNames = null, string resolutionStatus = "unresolved")
    { TypeName = typeName; MemberName = memberName; MethodKind = methodKind; ArgumentTypeNames = argumentTypeNames; ExactArgumentTypes = exactArgumentTypes;
      Image = image; ReturnType = returnType; IsStatic = isStatic; ParameterNames = parameterNames ?? Array.Empty<string>(); ResolutionStatus = resolutionStatus; }
}

internal sealed class EHRStaticPatchDescriptor
{
    internal readonly string Id, ClassId, Owner;
    internal readonly EHRStaticPatchKind Kind;
    internal readonly int Priority, Index;
    internal readonly bool AffectsOriginal, AssemblyScan;
    internal readonly string[] Before, After;
    internal readonly EHRStaticTargetSpec[] Targets;
    internal readonly Action<EHRStaticPatchFrame> Invoke;
    internal readonly Func<bool>? Prepare;
    internal EHRStaticPatchDescriptor(string id, string classId, string owner, EHRStaticPatchKind kind,
        int priority, int index, bool affectsOriginal, bool assemblyScan, string[] before, string[] after,
        EHRStaticTargetSpec[] targets, Action<EHRStaticPatchFrame> invoke, Func<bool>? prepare)
    { Id = id; ClassId = classId; Owner = owner; Kind = kind; Priority = priority; Index = index;
      AffectsOriginal = affectsOriginal; AssemblyScan = assemblyScan; Before = before; After = after;
      Targets = targets; Invoke = invoke; Prepare = prepare; }
}

internal sealed class EHRStaticPatchBinding
{
    internal readonly string TargetKey;
    internal readonly EHRStaticPatchDescriptor[] Prefixes, Postfixes, Finalizers;
    readonly Func<EHRStaticPatchDescriptor, bool> isEnabled;
    internal EHRStaticPatchBinding(string targetKey, IEnumerable<EHRStaticPatchDescriptor> callbacks, Func<EHRStaticPatchDescriptor, bool>? isEnabled = null)
    {
        TargetKey = targetKey;
        this.isEnabled = isEnabled ?? (_ => true);
        EHRStaticPatchDescriptor[] all = callbacks.ToArray();
        if (all.Select(c => c.Id).Distinct(StringComparer.Ordinal).Count() != all.Length) throw new ArgumentException("Duplicate callback registration.");
        Prefixes = Order(all.Where(c => c.Kind == EHRStaticPatchKind.Prefix));
        Postfixes = Order(all.Where(c => c.Kind == EHRStaticPatchKind.Postfix));
        Finalizers = Order(all.Where(c => c.Kind == EHRStaticPatchKind.Finalizer));
    }

    static EHRStaticPatchDescriptor[] Order(IEnumerable<EHRStaticPatchDescriptor> values)
    {
        var pending = values.OrderByDescending(c => c.Priority).ThenBy(c => c.Index).ToList();
        var result = new List<EHRStaticPatchDescriptor>();
        while (pending.Count > 0)
        {
            int next = pending.FindIndex(c => !pending.Any(other => !ReferenceEquals(c, other)
                && (c.After.Contains(other.Owner, StringComparer.Ordinal) || other.Before.Contains(c.Owner, StringComparer.Ordinal))));
            // EHR's pinned source has no Before/After cycles. Unsupported future
            // cyclic dependencies fail explicitly rather than silently breaking one.
            if (next < 0) throw new NotSupportedException("Cyclic static patch ordering dependencies.");
            result.Add(pending[next]); pending.RemoveAt(next);
        }
        return result.ToArray();
    }

    internal void Execute(EHRStaticPatchFrame frame, Action<EHRStaticPatchFrame> original)
    {
        if (frame.Consumed) throw new InvalidOperationException("A patch frame belongs to exactly one original invocation.");
        frame.Consumed = true;
        // Capture enabled callbacks for this invocation. Disabling the owner
        // affects subsequent invocations, as replacing a Harmony method does.
        var enabled = new HashSet<EHRStaticPatchDescriptor>(Prefixes.Concat(Postfixes).Concat(Finalizers).Where(isEnabled));
        bool failed = false;
        try
        {
            // HarmonyX 2.10.2 deliberately executes every prefix, including
            // mutating prefixes after a bool prefix has skipped the original.
            foreach (EHRStaticPatchDescriptor prefix in Prefixes) if (enabled.Contains(prefix)) prefix.Invoke(frame);
            if (frame.RunOriginal) { frame.OriginalEntered = true; original(frame); }
            foreach (EHRStaticPatchDescriptor postfix in Postfixes) if (enabled.Contains(postfix)) postfix.Invoke(frame);
        }
        catch (Exception error) { frame.Exception = error; failed = true; }
        if (!failed)
        {
            try { foreach (EHRStaticPatchDescriptor finalizer in Finalizers) if (enabled.Contains(finalizer)) finalizer.Invoke(frame); }
            catch (Exception error) { frame.Exception = error; failed = true; }
        }
        // HarmonyX retries the finalizer sequence on the exception path. Errors
        // from that sequence are suppressed, preserving the current exception.
        if (failed)
        {
            foreach (EHRStaticPatchDescriptor finalizer in Finalizers)
                try { if (enabled.Contains(finalizer)) finalizer.Invoke(frame); } catch (Exception) { }
        }
        if (frame.Exception != null) ExceptionDispatchInfo.Capture(frame.Exception).Throw();
    }
}

// Resolver success means an external binder has actually validated a target.
// The source generator supplies no resolver and cannot claim native availability.
internal interface IEHRStaticTargetResolver
{
    bool TryResolve(EHRStaticTargetSpec sourceSpec, out string targetKey, out string unavailableReason);
}

internal sealed class EHRStaticRegistration
{
    readonly EHRStaticPatchDescriptor[] descriptors;
    readonly HashSet<string> requestedClasses = new(StringComparer.Ordinal);
    readonly Dictionary<string, bool> preparedClasses = new(StringComparer.Ordinal);
    internal readonly Dictionary<string, string> Unavailable = new(StringComparer.Ordinal);
    internal readonly Dictionary<string, string> PolicyExcluded = new(StringComparer.Ordinal);
    internal EHRStaticRegistration(EHRStaticPatchDescriptor[] descriptors) { this.descriptors = descriptors; }

    internal void RequestAssembly()
    { foreach (EHRStaticPatchDescriptor callback in descriptors.Where(c => c.AssemblyScan)) requestedClasses.Add(callback.ClassId); }
    internal void RequestClass(string classId)
    {
        if (!descriptors.Any(c => c.ClassId == classId)) throw new NotSupportedException("Unregistered patch class: " + classId);
        requestedClasses.Add(classId);
    }
    internal void DisableOwner(string owner)
    {
        foreach (EHRStaticPatchDescriptor callback in descriptors.Where(c => c.Owner == owner))
        { requestedClasses.Remove(callback.ClassId); preparedClasses.Remove(callback.ClassId); }
    }

    internal Dictionary<string, EHRStaticPatchBinding> BindRequested(IEHRStaticTargetResolver resolver)
    {
        var targets = new Dictionary<string, List<EHRStaticPatchDescriptor>>(StringComparer.Ordinal);
        var preparedTargets = new Dictionary<string, bool>(StringComparer.Ordinal);
        Unavailable.Clear();
        PolicyExcluded.Clear();
        foreach (EHRStaticPatchDescriptor callback in descriptors.OrderBy(c => c.Index))
        {
            if (!requestedClasses.Contains(callback.ClassId)) continue;
            // Account protection is applied per callback before Prepare can
            // execute source side effects; unrelated callbacks stay available.
            if (EHRSourceAccountPolicy.TryExclude(callback.Id, out string policyReason))
            { PolicyExcluded[callback.Id] = policyReason; continue; }
            if (!preparedClasses.TryGetValue(callback.ClassId, out bool prepared))
            { prepared = callback.Prepare?.Invoke() ?? true; preparedClasses[callback.ClassId] = prepared; }
            if (!prepared) { Unavailable[callback.Id] = "class_Prepare_returned_false"; continue; }
            if (callback.Targets.Length == 0) { Unavailable[callback.Id] = "target_template_unresolved_by_generator"; continue; }
            foreach (EHRStaticTargetSpec spec in callback.Targets)
            {
                if (!resolver.TryResolve(spec, out string key, out string reason))
                { Unavailable[callback.Id + "@" + spec.TypeName + "." + spec.MemberName] = reason; continue; }
                if (string.IsNullOrEmpty(key)) throw new InvalidOperationException("Resolver returned an empty target identity.");
                string classTarget = callback.ClassId + "@" + key;
                if (!preparedTargets.TryGetValue(classTarget, out bool targetPrepared))
                { targetPrepared = callback.Prepare?.Invoke() ?? true; preparedTargets[classTarget] = targetPrepared; }
                if (!targetPrepared) { Unavailable[callback.Id + "@" + key] = "target_Prepare_returned_false"; continue; }
                if (!targets.TryGetValue(key, out List<EHRStaticPatchDescriptor>? list)) targets[key] = list = new();
                if (!list.Any(c => c.Id == callback.Id)) list.Add(callback);
            }
        }
        return targets.ToDictionary(pair => pair.Key, pair => new EHRStaticPatchBinding(pair.Key, pair.Value,
            callback => !EHRSourceAccountPolicy.TryExclude(callback.Id, out _)
                && requestedClasses.Contains(callback.ClassId) && preparedClasses.TryGetValue(callback.ClassId, out bool active) && active), StringComparer.Ordinal);
    }
}
