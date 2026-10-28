using EHR;
using System;
using System.Collections.Generic;
using System.Linq;

int checks = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception("FAIL: " + name); checks++; }
EHRStaticPatchFrame Frame(int input = 2) => new(new Arithmetic(), new object?[] { input }, new[] { "input" });
EHRStaticPatchDescriptor Descriptor(string id, EHRStaticPatchKind kind, Action<EHRStaticPatchFrame> action,
    int priority = 400, int index = 0, string owner = "fixture", string[]? before = null, string[]? after = null)
    => new(id, id, owner, kind, priority, index, true, true, before ?? [], after ?? [], [], action, null);

var registration = EHRStaticPatchCatalog.Registration;
registration.RequestAssembly();
var bindings = registration.BindRequested(new Resolver());
Check(ArithmeticPatch.PrepareCount == 2, "Prepare once per class and once per target");
var frame = Frame(); frame.InstanceFields["Value"] = 10;
bindings["Calculate"].Execute(frame, _ => throw new Exception("original must be skipped"));
Check((int)frame.Arguments[0]! == 10 && (int)frame.Result! == 46, "generated ref arg/result/state and all prefixes after false");
Check(((Arithmetic)frame.Instance!).Value == 9 && (int)frame.InstanceFields["Value"]! == 15, "generated instance and field writeback");
Check(!frame.OriginalEntered && ArithmeticPatch.PrefixCount == 1 && ArithmeticPatch.PostfixCount == 1, "original skipped and postfix called");
bool reused = false; try { bindings["Calculate"].Execute(frame, _ => { }); } catch (InvalidOperationException) { reused = true; }
Check(reused, "single invocation frame");
var throwing = Frame(); bindings["Throw"].Execute(throwing, _ => throw new Exception("unreachable"));
Check((int)throwing.Arguments[0]! == 77 && throwing.Exception == null, "ref writeback on exception and finalizer suppression");
var control = Frame(); bindings["Control"].Execute(control, _ => throw new Exception("false must dominate ref runOriginal"));
Check(!control.OriginalEntered && !control.RunOriginal, "bool return AND follows ref runOriginal mutation");
var structFrame = new EHRStaticPatchFrame(new Arithmetic(), new object?[] { new Number { Value = 8 } }, new[] { "payload" });
bindings["Struct"].Execute(structFrame, f => f.Result = f.GetArgument<Number>(0).Value);
Check(((Number)structFrame.Arguments[0]!).Value == 12 && (int)structFrame.Result! == 24, "boxed value struct and out state propagation");
var exceptionRef = Frame(); bindings["ExceptionReference"].Execute(exceptionRef, _ => throw new InvalidOperationException());
Check(exceptionRef.Exception == null, "returned finalizer exception supersedes ref exception mutation");
var multi = EHRStaticPatchCatalog.Descriptors.Single(c => c.ClassId.EndsWith("MultiplePatch"));
Check(multi.Targets.Select(t => t.MemberName).SequenceEqual(new[] { "Second", "Third" }) && multi.Priority == 200,
    "HarmonyX multiple complete targets and method overrides class priority");
registration.DisableOwner("com.gurge44.endlesshostroles");
Check(registration.BindRequested(new Resolver()).Count == 0, "owner disabled");
var disabledFrame = Frame(); bindings["Calculate"].Execute(disabledFrame, f => f.Result = 13);
Check(disabledFrame.OriginalEntered && (int)disabledFrame.Result! == 13, "already-bound native thunk becomes pass-through after owner disabled");
registration.RequestAssembly(); registration.BindRequested(new Resolver());
Check(ArithmeticPatch.PrepareCount == 4, "class Prepare reruns after disable and reregister");
var unavailable = new EHRStaticRegistration(EHRStaticPatchCatalog.Descriptors); unavailable.RequestAssembly();
Check(unavailable.BindRequested(new Resolver(false)).Count == 0 && unavailable.Unavailable.Count > 0, "unbound never available");

var order = new List<string>();
var ordered = new EHRStaticPatchBinding("order", new[] {
    Descriptor("low", EHRStaticPatchKind.Prefix, _ => order.Add("low"), 100, 0, "low", before: new[] { "high" }),
    Descriptor("high", EHRStaticPatchKind.Prefix, _ => order.Add("high"), 800, 1, "high"),
    Descriptor("middle", EHRStaticPatchKind.Prefix, _ => order.Add("middle"), 400, 2) });
ordered.Execute(Frame(), _ => order.Add("original"));
Check(string.Join(",", order) == "middle,low,high,original", "priority and acyclic owner constraints");
bool cycled = false; try { _ = new EHRStaticPatchBinding("cycle", new[] {
    Descriptor("a", EHRStaticPatchKind.Prefix, _ => { }, owner:"a", after:new[]{"b"}),
    Descriptor("b", EHRStaticPatchKind.Prefix, _ => { }, owner:"b", after:new[]{"a"}) }); } catch (NotSupportedException) { cycled = true; }
Check(cycled, "cycle rejected explicitly");
int finalized = 0;
var finalizing = new EHRStaticPatchBinding("retry", new[] {
    Descriptor("retry", EHRStaticPatchKind.Finalizer, f => { finalized++; if (finalized == 1) throw new ApplicationException("finalizer"); f.Exception = null; }) });
finalizing.Execute(Frame(), _ => { });
Check(finalized == 2, "HarmonyX throwing normal finalizer retried on exception path");
var failure = new InvalidOperationException("original"); bool retained = false;
var failing = new EHRStaticPatchBinding("preserve", new[] {
    Descriptor("bad", EHRStaticPatchKind.Finalizer, _ => throw new ApplicationException("suppressed")) });
try { failing.Execute(Frame(), _ => throw failure); } catch (InvalidOperationException e) { retained = ReferenceEquals(e, failure); }
Check(retained, "exception-path finalizer errors do not replace original failure");
var recursive = new EHRStaticPatchBinding("nested", new[] {
    Descriptor("state", EHRStaticPatchKind.Prefix, f => f.SetState("state", f.GetArgument<int>(0))),
    Descriptor("statepost", EHRStaticPatchKind.Postfix, f => f.Result = f.GetState<int>("state")) });
var outer = Frame(11); var inner = Frame(22);
recursive.Execute(outer, _ => recursive.Execute(inner, _ => { }));
Check((int)outer.Result! == 11 && (int)inner.Result! == 22, "per-invocation nested state isolation");
Console.WriteLine($"PASS: {checks} original arithmetic/static dispatcher checks; no game assembly executed.");

sealed class Resolver(bool available = true) : IEHRStaticTargetResolver
{
    public bool TryResolve(EHRStaticTargetSpec spec, out string key, out string reason)
    { key = available ? spec.MemberName : ""; reason = available ? "" : "fixture_unbound"; return available; }
}
