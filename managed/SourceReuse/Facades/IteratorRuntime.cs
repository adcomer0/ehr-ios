// Original source. This is a deliberately bounded native IEnumerator bridge,
// not ClassInjector, Unity coroutine scheduling, or a full EHR WrapToIl2Cpp.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct IteratorHostV1
{
    internal uint AbiVersion, ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, ulong*, int> Register;
    internal delegate* unmanaged[Cdecl]<ulong, int> Release;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, int*, int> Same;
    internal delegate* unmanaged[Cdecl]<ulong, ulong*, int> ObjectClass;
}
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct IteratorCallbacksV1
{
    internal uint AbiVersion, ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong, int*, ulong*, int> Step;
    internal delegate* unmanaged[Cdecl]<ulong, int> Reset;
    internal delegate* unmanaged[Cdecl]<ulong, int> Cancel;
}
[StructLayout(LayoutKind.Sequential)]
internal struct IteratorProofV1
{
    internal uint AbiVersion, ByteSize, Pass, Status;
    internal uint SideEffects, DisposedOnce, NullYield, StringYield;
    internal uint RepeatedCurrentIdentity, ResetException, BeforeCurrentException, AfterCurrentException;
    internal uint UnregisteredFallback, CompletedFalse, RegistrationsClosed, Reserved;
}
internal static unsafe class IteratorRuntime
{
    private sealed class Entry(IEnumerator source)
    {
        internal IEnumerator? Source = source;
        internal ulong Registration;
        internal bool Executing, Terminal, Disposed;
    }
    private static IteratorHostV1 host;
    private static bool bound;
    private static ulong next = 1;
    private static readonly Dictionary<ulong, Entry> entries = new();
    // Reference identity, even for iterators overriding Equals/GetHashCode.
    private static readonly ConditionalWeakTable<IEnumerator, Entry> sources = new();
    private static readonly BindingSpec Move = new("mscorlib.dll", "System.Collections", "IEnumerator", "MoveNext", false, false, "System.Boolean", []);
    private static readonly BindingSpec Current = new("mscorlib.dll", "System.Collections", "IEnumerator", "get_Current", false, false, "System.Object", []);
    private static readonly BindingSpec ResetMethod = new("mscorlib.dll", "System.Collections", "IEnumerator", "Reset", false, false, "System.Void", []);
    [UnmanagedCallersOnly(EntryPoint = "ehr_iterator_bind_gateway", CallConvs = [typeof(CallConvCdecl)])]
    internal static int Bind(IteratorHostV1* source, nuint bytes, IteratorCallbacksV1* callbacks, nuint callbackBytes)
    {
        if (source == null || callbacks == null || bytes != (nuint)sizeof(IteratorHostV1) || callbackBytes != (nuint)sizeof(IteratorCallbacksV1) ||
            source->AbiVersion != 1 || source->ByteSize != sizeof(IteratorHostV1) || source->Register == null || source->Release == null || source->Same == null || source->ObjectClass == null) return 4;
        if (bound && ((nuint)host.Register != (nuint)source->Register || (nuint)host.Release != (nuint)source->Release || (nuint)host.Same != (nuint)source->Same || (nuint)host.ObjectClass != (nuint)source->ObjectClass)) return 4;
        host = *source; bound = true;
        *callbacks = new() { AbiVersion = 1, ByteSize = (uint)sizeof(IteratorCallbacksV1), Step = &Step, Reset = &Reset, Cancel = &Cancel };
        return 0;
    }
    internal static ulong Register(IEnumerator source, ulong carrier)
    {
        if (!bound) throw new RuntimeGatewayException(1, "iterator table unavailable");
        if (sources.TryGetValue(source, out Entry? prior))
            throw new NotSupportedException(prior.Terminal ? "completed iterator is not restarted" : "source already registered");
        if (entries.Count >= 256 || next == ulong.MaxValue) throw new RuntimeGatewayException(8, "iterator limit");
        ulong id = next++, registration = 0;
        var entry = new Entry(source);
        entries.Add(id, entry); sources.Add(source, entry);
        int status = host.Register(carrier, id, &registration);
        if (status != 0) { entries.Remove(id); sources.Remove(source); throw new RuntimeGatewayException(status, "register native carrier"); }
        entry.Registration = registration; return id;
    }
    // Explicit source lifetime only. Caller stops Unity before closing an
    // engine-owned carrier. Existing main-thread native host performs cleanup.
    internal static int Close(ulong id)
    {
        if (!entries.TryGetValue(id, out Entry? entry)) return 9;
        return host.Release(entry.Registration);
    }
    private static void Finish(Entry entry)
    {
        if (entry.Disposed) return;
        entry.Disposed = entry.Terminal = true;
        IEnumerator? source = entry.Source; entry.Source = null;
        (source as IDisposable)?.Dispose();
    }
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static int Step(ulong id, int* nextValue, ulong* current)
    {
        if (nextValue == null || current == null) return 4;
        *nextValue = 0; *current = 0;
        if (!entries.TryGetValue(id, out Entry? entry)) return 9;
        if (entry.Executing) return 4;
        if (entry.Terminal) return 0;
        entry.Executing = true;
        int status = 0;
        try
        {
            if (!entry.Source!.MoveNext()) Finish(entry);
            else
            {
                object? yielded = entry.Source.Current; // Read once before true.
                if (yielded is RuntimeObject native)
                {
                    using var retained = FacadeRuntime.Retain(native);
                    *current = retained.Detach(); // Transfer ONE root to native.
                }
                else if (yielded is not null)
                    throw new NotSupportedException("yield has no real native-object conversion; nested source adapters are not enabled");
                *nextValue = 1;
            }
        }
        catch (NativeGameException exception) { exception.Dispose(); status = 6; }
        catch (NotSupportedException) { status = 7; }
        catch { status = 4; }
        finally { entry.Executing = false; }
        if (status != 0)
        {
            if (*current != 0) { using var owned = new RuntimeObject(*current); *current = 0; }
            *nextValue = 0;
            try { Finish(entry); } catch { /* Dispose once, never leak over ABI. */ }
        }
        return status;
    }
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static int Reset(ulong id)
    {
        if (!entries.TryGetValue(id, out Entry? entry)) return 9;
        if (entry.Executing) return 4;
        if (entry.Source is null) return 7;
        entry.Executing = true;
        try { entry.Source.Reset(); entry.Terminal = false; return 0; }
        catch (NativeGameException exception) { exception.Dispose(); return 6; }
        catch (NotSupportedException) { return 7; }
        catch { return 4; }
        finally { entry.Executing = false; }
    }
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static int Cancel(ulong id)
    {
        if (!entries.TryGetValue(id, out Entry? entry)) return 9;
        if (entry.Executing) return 4;
        entries.Remove(id);
        try { Finish(entry); return 0; }
        catch (NativeGameException exception) { exception.Dispose(); return 6; }
        catch { return 4; }
    }
    private sealed class Effects { internal uint Steps, Disposed; }
    private static IEnumerator ActualNativeString(Effects effects)
    {
        try
        {
            ++effects.Steps; yield return null;
            ++effects.Steps;
            using var value = FacadeRuntime.String("ehr-native-iterator");
            yield return value;
            ++effects.Steps;
        }
        finally { ++effects.Disposed; }
    }
    private static bool Next(ulong carrier)
    {
        using var result = FacadeRuntime.Invoke(Move, carrier, null, 0);
        return FacadeRuntime.ReadValue<byte>(result) == 1;
    }
    private static bool NativeException(ulong carrier, BindingSpec method, string expectedType)
    {
        try { using var _ = FacadeRuntime.Invoke(method, carrier, null, 0); return false; }
        catch (NativeGameException exception)
        {
            try
            {
                using var retained = exception.RetainNativeException();
                // Exact exception class is checked through the live gateway.
                return IteratorExceptionClass(retained.Token, expectedType);
            }
            finally { exception.Dispose(); }
        }
    }
    private static bool IteratorExceptionClass(ulong exception, string expectedType)
    {
        ulong actual = 0;
        return host.ObjectClass(exception, &actual) == 0 && actual == FacadeRuntime.Class("mscorlib.dll", "System", expectedType);
    }
    [UnmanagedCallersOnly(EntryPoint = "ehr_iterator_self_test", CallConvs = [typeof(CallConvCdecl)])]
    internal static int SelfTest(ulong carrier, ulong ordinary, IteratorProofV1* proof, nuint bytes)
    {
        if (proof == null || bytes != (nuint)sizeof(IteratorProofV1)) return 4;
        *proof = new() { AbiVersion = 1, ByteSize = (uint)sizeof(IteratorProofV1) };
        ulong id = 0;
        var effects = new Effects();
        try
        {
            if (carrier == 0 || ordinary == 0) throw new RuntimeGatewayException(4, "two real native enumerators required");
            id = Register(ActualNativeString(effects), carrier);
            proof->BeforeCurrentException = NativeException(carrier, Current, "InvalidOperationException") ? 1u : 0;
            proof->NullYield = Next(carrier) ? 1u : 0;
            using (var first = FacadeRuntime.Invoke(Current, carrier, null, 0))
                if (first.Token != 0) proof->NullYield = 0;
            proof->ResetException = NativeException(carrier, ResetMethod, "NotSupportedException") ? 1u : 0;
            bool advanced = Next(carrier);
            proof->ResetException = proof->ResetException == 1 && NativeException(carrier, ResetMethod, "NotSupportedException") ? 1u : 0;
            using (var value = FacadeRuntime.Invoke(Current, carrier, null, 0))
            using (var again = FacadeRuntime.Invoke(Current, carrier, null, 0))
            {
                proof->StringYield = advanced && FacadeRuntime.ReadString(value) == "ehr-native-iterator" ? 1u : 0;
                int same = 0;
                proof->RepeatedCurrentIdentity = value.Token != 0 && again.Token != 0 && value.Token != again.Token &&
                    host.Same(value.Token, again.Token, &same) == 0 && same == 1 ? 1u : 0;
            }
            proof->CompletedFalse = !Next(carrier) && !Next(carrier) ? 1u : 0;
            proof->AfterCurrentException = NativeException(carrier, Current, "InvalidOperationException") ? 1u : 0;
            proof->UnregisteredFallback = !Next(ordinary) ? 1u : 0;
            using (var reset = FacadeRuntime.Invoke(ResetMethod, ordinary, null, 0)) { }
            proof->SideEffects = effects.Steps; proof->DisposedOnce = effects.Disposed;
        }
        catch (NativeGameException exception) { exception.Dispose(); proof->Status = 6; }
        catch (RuntimeGatewayException exception) { proof->Status = (uint)exception.Status; }
        catch { proof->Status = 4; }
        finally
        {
            if (id != 0 && entries.TryGetValue(id, out Entry? entry))
            {
                int released = host.Release(entry.Registration);
                if (released == 0 && !entries.ContainsKey(id)) proof->RegistrationsClosed = 1;
                else if (proof->Status == 0) proof->Status = (uint)(released != 0 ? released : 4);
            }
        }
        proof->Pass = proof->Status == 0 && proof->SideEffects == 3 && proof->DisposedOnce == 1 && proof->NullYield == 1 && proof->StringYield == 1 &&
            proof->RepeatedCurrentIdentity == 1 && proof->ResetException == 1 && proof->BeforeCurrentException == 1 && proof->AfterCurrentException == 1 &&
            proof->UnregisteredFallback == 1 && proof->CompletedFalse == 1 && proof->RegistrationsClosed == 1 ? 1u : 0;
        return (int)proof->Status;
    }
}
