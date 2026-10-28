using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;

namespace EHR.Generated;

[StructLayout(LayoutKind.Sequential)]
internal struct OriginalProof
{
    internal uint AbiVersion, ByteSize, RequestAccepted, RuntimeEntered, PermitConsumed, HookConsumptions;
}
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct OriginalTable
{
    internal uint AbiVersion, ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong, ulong*, int> TargetMethod;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, ulong*, int> Begin;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, ulong, ulong, NativeArgument*, nuint,
        ulong*, ulong*, OriginalProof*, nuint, int> Invoke;
    internal delegate* unmanaged[Cdecl]<ulong, int> End;
}
[StructLayout(LayoutKind.Sequential)]
internal struct OriginalSelfTestResult
{
    internal uint AbiVersion, ByteSize;
    internal int Pass, Status, RawOriginalValue, RepeatStatus, ScopeClosed, WrongTargetStatus;
    internal OriginalProof Proof;
    internal ulong EscapedNativeException;
}

// The native pool owns Invoke's borrowed outputs until End. Managed objects
// always retain independent roots before they can escape this using scope.
internal sealed unsafe class OriginalInvocation : IDisposable
{
    internal const ulong BroadcastVersionTarget = 1;
    private ulong invocation;
    private readonly ulong target, method;
    internal OriginalProof Proof { get; private set; }
    internal bool Closed => invocation == 0;

    internal OriginalInvocation(ulong targetId)
    {
        OriginalRuntime.Ready(); target = targetId;
        ulong resolved = 0, opened = 0;
        FacadeRuntime.Require(OriginalRuntime.Table.TargetMethod(target, &resolved), "original target metadata");
        FacadeRuntime.Require(OriginalRuntime.Table.Begin(target, resolved, &opened), "original invocation begin");
        if (opened == 0) throw new RuntimeGatewayException(5, "empty original invocation capability");
        method = resolved; invocation = opened;
    }

    internal int InvokeInt32()
    {
        if (Closed) throw new ObjectDisposedException(nameof(OriginalInvocation));
        ulong returned = 0, exception = 0;
        OriginalProof proof = default;
        int status = OriginalRuntime.Table.Invoke(invocation, target, method, 0, null, 0,
            &returned, &exception, &proof, (nuint)sizeof(OriginalProof));
        Proof = proof;
        if (exception != 0) throw NativeGameException.FromBorrowed(exception, "caught original invocation");
        FacadeRuntime.Require(status, "caught original invocation");
        if (returned == 0 || proof.AbiVersion != 1 || proof.ByteSize != sizeof(OriginalProof) ||
            proof.RequestAccepted != 1 || proof.RuntimeEntered != 1 || proof.PermitConsumed != 1 || proof.HookConsumptions != 1)
            throw new RuntimeGatewayException(5, "unproved original invocation");
        using RuntimeObject owned = FacadeRuntime.RetainToken(returned);
        return FacadeRuntime.ReadValue<int>(owned);
    }

    // Exact bad-target and repeated-request checks exercise the native API,
    // rather than short-circuiting in this managed wrapper.
    internal int TryInvokeForTest(ulong targetId, out OriginalProof proof)
    {
        ulong returned = 0, exception = 0;
        OriginalProof nativeProof = default;
        int status = OriginalRuntime.Table.Invoke(invocation, targetId, method, 0, null, 0,
            &returned, &exception, &nativeProof, (nuint)sizeof(OriginalProof));
        proof = nativeProof;
        if (returned != 0 || exception != 0) throw new RuntimeGatewayException(5, "rejected original returned an object");
        return status;
    }

    public void Dispose()
    {
        if (Closed) return;
        FacadeRuntime.Require(OriginalRuntime.Table.End(invocation), "original invocation end");
        invocation = 0;
    }
}

internal static unsafe class OriginalRuntime
{
    internal static OriginalTable Table;
    private static int bound;
    internal static void Ready()
    {
        if (Volatile.Read(ref bound) == 0) throw new RuntimeGatewayException(1, "original table not bound");
    }
    [UnmanagedCallersOnly(EntryPoint = "ehr_original_bind_gateway")]
    internal static int Bind(OriginalTable* source, nuint bytes)
    {
        try
        {
            if (source == null || bytes != (nuint)sizeof(OriginalTable) || sizeof(OriginalTable) != 40 ||
                source->AbiVersion != 1 || source->ByteSize != sizeof(OriginalTable) || source->TargetMethod == null ||
                source->Begin == null || source->Invoke == null || source->End == null) return 4;
            if (Volatile.Read(ref bound) != 0)
            {
                // Require the same native entry addresses on rebind, not a
                // managed function-pointer semantic-equivalence comparison.
                if ((void*)source->TargetMethod != (void*)Table.TargetMethod || (void*)source->Begin != (void*)Table.Begin ||
                    (void*)source->Invoke != (void*)Table.Invoke || (void*)source->End != (void*)Table.End) return 4;
                return 0;
            }
            Table = *source;
            Volatile.Write(ref bound, 1);
            return 0;
        }
        catch { return 7; }
    }

    [UnmanagedCallersOnly(EntryPoint = "ehr_original_self_test")]
    internal static int SelfTest(OriginalSelfTestResult* result, nuint bytes)
    {
        if (result == null || bytes != (nuint)sizeof(OriginalSelfTestResult)) return 4;
        *result = new OriginalSelfTestResult { AbiVersion = 1, ByteSize = (uint)sizeof(OriginalSelfTestResult) };
        try
        {
            using var invocation = new OriginalInvocation(OriginalInvocation.BroadcastVersionTarget);
            try
            {
                result->WrongTargetStatus = invocation.TryInvokeForTest(ulong.MaxValue, out OriginalProof rejected);
                if (result->WrongTargetStatus != 5 || rejected.RequestAccepted != 0 || rejected.RuntimeEntered != 0)
                    throw new RuntimeGatewayException(5, "foreign original target accepted");
                try { result->RawOriginalValue = invocation.InvokeInt32(); }
                finally { result->Proof = invocation.Proof; }
                result->RepeatStatus = invocation.TryInvokeForTest(OriginalInvocation.BroadcastVersionTarget, out rejected);
                if (result->RepeatStatus != 4 || rejected.RequestAccepted != 0 || rejected.RuntimeEntered != 0)
                    throw new RuntimeGatewayException(5, "repeated original entered runtime");
            }
            finally
            {
                invocation.Dispose();
                result->ScopeClosed = invocation.Closed ? 1 : 0;
            }
            result->Pass = result->ScopeClosed == 1 && result->RawOriginalValue >= 0 ? 1 : 0;
            return result->Status = result->Pass == 1 ? 0 : 5;
        }
        catch (NativeGameException exception)
        {
            // Return a separate owned native root; no exception crosses this C
            // export. The native caller may release it or rethrow after return.
            try
            {
                using (exception)
                using (RuntimeObject native = exception.RetainNativeException())
                    result->EscapedNativeException = native.Detach();
            }
            catch (RuntimeGatewayException failure) { return result->Status = failure.Status; }
            catch { return result->Status = 7; }
            return result->Status = 6;
        }
        catch (RuntimeGatewayException exception) { return result->Status = exception.Status; }
        catch { return result->Status = 7; }
    }
}
