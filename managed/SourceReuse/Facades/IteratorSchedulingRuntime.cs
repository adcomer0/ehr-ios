// Original bounded source probe. Only Unity drives MoveNext in this proof.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)]
internal struct IteratorScheduleStateV1
{
    internal uint AbiVersion, ByteSize, Steps, FinallyCount;
}
internal static unsafe class IteratorSchedulingRuntime
{
    private sealed class State(RuntimeObject wait)
    {
        internal readonly RuntimeObject Wait = wait;
        internal uint Steps, FinallyCount;
    }
    private static readonly Dictionary<ulong, State> states = new();
    private static IEnumerator Source(State state)
    {
        try
        {
            ++state.Steps; yield return null;
            ++state.Steps; yield return state.Wait;
            ++state.Steps;
        }
        finally { ++state.FinallyCount; state.Wait.Dispose(); }
    }
    [UnmanagedCallersOnly(EntryPoint = "ehr_iterator_schedule_create", CallConvs = [typeof(CallConvCdecl)])]
    internal static int Create(ulong carrier, ulong wait, ulong* sourceId)
    {
        if (sourceId == null) return 4;
        *sourceId = 0;
        if (carrier == 0 || wait == 0) return 4;
        State? state = null; ulong id = 0;
        try
        {
            if (states.Count >= 2) return 8;
            state = new(FacadeRuntime.RetainToken(wait));
            id = IteratorRuntime.Register(Source(state), carrier);
            states.Add(id, state); *sourceId = id; return 0;
        }
        catch (NativeGameException exception) { exception.Dispose(); return 6; }
        catch (RuntimeGatewayException exception) { return exception.Status; }
        catch { return 4; }
        finally
        {
            if (*sourceId == 0)
            {
                try
                {
                    if (id != 0) IteratorRuntime.Close(id);
                    state?.Wait.Dispose();
                }
                catch { /* No managed exception may unwind across this ABI. */ }
            }
        }
    }
    private static void Fill(State state, IteratorScheduleStateV1* output)
        => *output = new() { AbiVersion = 1, ByteSize = (uint)sizeof(IteratorScheduleStateV1), Steps = state.Steps, FinallyCount = state.FinallyCount };
    [UnmanagedCallersOnly(EntryPoint = "ehr_iterator_schedule_snapshot", CallConvs = [typeof(CallConvCdecl)])]
    internal static int Snapshot(ulong id, IteratorScheduleStateV1* output, nuint bytes)
    {
        if (output == null || bytes != (nuint)sizeof(IteratorScheduleStateV1)) return 4;
        *output = default;
        if (!states.TryGetValue(id, out State? state)) return 9;
        Fill(state, output); return 0;
    }
    [UnmanagedCallersOnly(EntryPoint = "ehr_iterator_schedule_close", CallConvs = [typeof(CallConvCdecl)])]
    internal static int Close(ulong id, IteratorScheduleStateV1* output, nuint bytes)
    {
        if (output == null || bytes != (nuint)sizeof(IteratorScheduleStateV1)) return 4;
        *output = default;
        if (!states.TryGetValue(id, out State? state)) return 9;
        int status;
        try
        {
            status = IteratorRuntime.Close(id);
            // If native close refuses while executing, preserve both owners.
            if (status != 0) return status;
            state.Wait.Dispose(); Fill(state, output); states.Remove(id); return 0;
        }
        catch (NativeGameException exception) { exception.Dispose(); return 6; }
        catch (RuntimeGatewayException exception) { return exception.Status; }
        catch { return 4; }
    }
}
