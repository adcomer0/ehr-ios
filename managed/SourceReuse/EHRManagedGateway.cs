using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct RuntimeArgument
{
    internal uint Kind, Reserved;
    internal ulong Token;
    internal void* Bytes;
    internal nuint ByteCount;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct GatewayTable
{
    internal uint AbiVersion, ByteSize;
    internal delegate* unmanaged[Cdecl]<uint> RuntimeAbiVersion;
    internal delegate* unmanaged[Cdecl]<int> Initialize;
    internal delegate* unmanaged[Cdecl]<byte*, byte*, byte*, ulong*, int> FindClass;
    internal delegate* unmanaged[Cdecl]<ulong, ulong*, int> ObjectClass;
    internal delegate* unmanaged[Cdecl]<ulong, byte*, byte**, nuint, byte*, int, ulong*, int> FindMethod;
    internal delegate* unmanaged[Cdecl]<ulong, byte*, byte*, int, ulong*, int> FindField;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, RuntimeArgument*, nuint, ulong*, ulong*, int> Invoke;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, ulong*, int> ReadField;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, RuntimeArgument*, int> WriteField;
    internal delegate* unmanaged[Cdecl]<ulong, nuint*, int> ValueSize;
    internal delegate* unmanaged[Cdecl]<ulong, void*, nuint, ulong*, int> Box;
    internal delegate* unmanaged[Cdecl]<ulong, void*, nuint, nuint*, int> CopyValue;
    internal delegate* unmanaged[Cdecl]<ushort*, nuint, ulong*, int> StringCreate;
    internal delegate* unmanaged[Cdecl]<ulong, ushort*, nuint, nuint*, int> StringCopy;
    internal delegate* unmanaged[Cdecl]<ulong, int> Release;
    internal delegate* unmanaged[Cdecl]<ulong, ulong*, int> Retain;
    internal delegate* unmanaged[Cdecl]<ulong> BroadcastCallbackCount;
    internal delegate* unmanaged[Cdecl]<int> PinnedImageObserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SelfTestResult
{
    internal uint AbiVersion, ByteSize;
    internal int Pass, Status, DynamicCodeFlags, ActualGetterValue;
    internal int OfflineValue, OnlineValue, ExpectedOnlineValue, PinnedImageObserved;
    internal ulong CallbacksBefore, CallbacksAfter, RootedResultsReleased;
}

internal sealed class GatewayException(int status) : Exception
{
    internal int Status { get; } = status;
}

// Fixed AOT facade for the first metadata-verified game API. This class does not
// cache native game pointers, load assemblies, emit IL, allocate runtime native
// thunks, or perform game method detours. The native gateway owns all GC roots.
internal static unsafe class EHRManagedGateway
{
    private static GatewayTable table;
    private static bool bound;
    private static ulong released;

    private static void Require(int status)
    {
        if (status != 0) throw new GatewayException(status);
    }

    private static void Release(ulong token)
    {
        if (token == 0) return;
        Require(table.Release(token));
        ++released;
    }

    internal static int GetBroadcastVersion()
    {
        if (!bound) throw new GatewayException(1);
        Require(table.Initialize());
        ulong klass = 0, method = 0;
        fixed (byte* image = "Assembly-CSharp.dll\0"u8)
        fixed (byte* space = "\0"u8)
        fixed (byte* name = "Constants\0"u8)
            Require(table.FindClass(image, space, name, &klass));
        fixed (byte* name = "GetBroadcastVersion\0"u8)
        fixed (byte* resultType = "System.Int32\0"u8)
            Require(table.FindMethod(klass, name, null, 0, resultType, 1, &method));

        ulong result = 0, exception = 0;
        int status = table.Invoke(method, 0, null, 0, &result, &exception);
        try
        {
            Require(status);
            if (exception != 0) throw new GatewayException(6);
            int value = 0;
            nuint copied = 0;
            Require(table.CopyValue(result, &value, sizeof(int), &copied));
            if (copied != sizeof(int)) throw new GatewayException(5);
            return value;
        }
        finally
        {
            Release(exception);
            Release(result);
        }
    }

    internal static int ApplySourceVersion(int original, bool online, bool local)
    {
        bool previousOnline = EHR.GameStates.Online;
        bool previousLocal = EHR.GameStates.Local;
        try
        {
            EHR.GameStates.Online = online;
            EHR.GameStates.Local = local;
            EHR.Patches.ServerUpdatePatch.Postfix(ref original);
            return original;
        }
        finally
        {
            EHR.GameStates.Online = previousOnline;
            EHR.GameStates.Local = previousLocal;
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "ehr_managed_bind_gateway")]
    internal static int Bind(GatewayTable* source, nuint byteCount)
    {
        if (source == null || byteCount != (nuint)sizeof(GatewayTable) ||
            source->ByteSize != sizeof(GatewayTable) || source->AbiVersion != 1)
            return 4;
        if (source->RuntimeAbiVersion == null || source->Initialize == null ||
            source->FindClass == null || source->FindMethod == null ||
            source->Invoke == null || source->CopyValue == null || source->Release == null)
            return 4;
        if (source->RuntimeAbiVersion() != 1) return 7;
        int status = source->Initialize();
        if (status != 0) return status;
        table = *source;
        bound = true;
        return 0;
    }

    [UnmanagedCallersOnly(EntryPoint = "ehr_managed_server_version_postfix")]
    internal static int VersionPostfix(int original, int online, int local, int* result)
    {
        if (result == null || (online != 0 && online != 1) || (local != 0 && local != 1)) return 4;
        try
        {
            *result = ApplySourceVersion(original, online != 0, local != 0);
            return 0;
        }
        catch { return 6; }
    }

    [UnmanagedCallersOnly(EntryPoint = "ehr_managed_gateway_self_test")]
    internal static int SelfTest(SelfTestResult* output, nuint byteCount)
    {
        if (output == null || byteCount != (nuint)sizeof(SelfTestResult)) return 4;
        *output = default;
        output->AbiVersion = 1;
        output->ByteSize = (uint)sizeof(SelfTestResult);
        output->DynamicCodeFlags = (RuntimeFeature.IsDynamicCodeSupported ? 1 : 0) |
                                   (RuntimeFeature.IsDynamicCodeCompiled ? 2 : 0);
        if (!bound) return output->Status = 1;
        if (table.BroadcastCallbackCount == null || table.PinnedImageObserved == null)
            return output->Status = 7;
        try
        {
            ulong initialReleased = released;
            output->CallbacksBefore = table.BroadcastCallbackCount();
            int actual = Constants.GetBroadcastVersion();
            output->ActualGetterValue = actual;
            output->CallbacksAfter = table.BroadcastCallbackCount();
            output->PinnedImageObserved = table.PinnedImageObserved();
            output->RootedResultsReleased = released - initialReleased;
            output->OfflineValue = ApplySourceVersion(actual, false, true);
            output->OnlineValue = ApplySourceVersion(actual, true, false);
            output->ExpectedOnlineValue = actual % 50 < 25 ? unchecked(actual + 25) : actual;
            bool valid = actual >= 0 && output->DynamicCodeFlags == 0 &&
                output->OfflineValue == actual && output->OnlineValue == output->ExpectedOnlineValue &&
                output->PinnedImageObserved == 1 && output->CallbacksAfter > output->CallbacksBefore &&
                output->RootedResultsReleased == 1;
            output->Pass = valid ? 1 : 0;
            return output->Status = valid ? 0 : 5;
        }
        catch (GatewayException exception) { return output->Status = exception.Status; }
        catch { return output->Status = 6; }
    }

    [UnmanagedCallersOnly(EntryPoint = "ehr_managed_is_version_modded_prefix")]
    internal static int IsVersionModdedPrefix(int* result, int* runOriginal)
    {
        if (result == null || runOriginal == null) return 4;
        try
        {
            bool value = false;
            bool run = EHR.Patches.IsVersionModdedPatch.Prefix(ref value);
            *result = value ? 1 : 0;
            *runOriginal = run ? 1 : 0;
            return 0;
        }
        catch { return 6; }
    }
}
