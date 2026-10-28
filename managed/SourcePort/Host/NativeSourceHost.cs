using System;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using BepInEx;
using BepInEx.Logging;

namespace EHR.SourceHost;

[StructLayout(LayoutKind.Sequential)]
public unsafe struct SourceHostTableV1
{
    public uint Version, Size;
    public delegate* unmanaged[Cdecl]<int> IsMainThread;
    public delegate* unmanaged[Cdecl]<int, byte*, nuint, void> Log;
}

public static unsafe class NativeSourceHost
{
    private static SourceHostTableV1 table;
    private static bool bound;
    public static bool IsMainThread => bound && table.IsMainThread() != 0;

    [UnmanagedCallersOnly(EntryPoint="ehr_source_host_bind_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    public static int Bind(SourceHostTableV1* value, nuint size)
    {
        if (value == null || size != (nuint)sizeof(SourceHostTableV1) ||
            value->Version != 1 || value->Size != sizeof(SourceHostTableV1) ||
            value->IsMainThread == null || value->Log == null) return 4;
        if (bound) return 4;
        if (value->IsMainThread() == 0) return 5;
        table = *value; bound = true;
        return 0;
    }

    public static SourceHostOptions Options(string dataRoot, string nativeModulePath) => new()
    {
        DataRoot = dataRoot,
        NativeModulePath = nativeModulePath,
        IsMainThread = () => IsMainThread,
        LogSink = WriteLog
    };

    private static void WriteLog(LogLevel level, string message)
    {
        if (!bound) throw new InvalidOperationException("Bind native source host first");
        byte[] utf8 = Encoding.UTF8.GetBytes(message);
        fixed (byte* bytes = utf8) table.Log((int)level, bytes, (nuint)utf8.Length);
    }

    [UnmanagedCallersOnly(EntryPoint="ehr_source_host_self_test",CallConvs=new[]{typeof(CallConvCdecl)})]
    public static int SelfTest(byte* root, nuint rootLength, byte* module, nuint moduleLength,
        int* proof, nuint proofCount)
    {
        if (proof == null || proofCount != 16) return 4;
        for (int i=0;i<16;++i) proof[i]=0;
        if (!IsMainThread) { proof[1]=5; return 5; }
        if (root == null || module == null || rootLength == 0 || moduleLength == 0 ||
            rootLength > 4096 || moduleLength > 4096) { proof[1]=4; return 4; }
        try
        {
            UTF8Encoding strict = new(false,true);
            string dataRoot = strict.GetString(new ReadOnlySpan<byte>(root,(int)rootLength));
            string modulePath = strict.GetString(new ReadOnlySpan<byte>(module,(int)moduleLength));
            if (dataRoot.Contains('\0') || modulePath.Contains('\0')) { proof[1]=4; return 4; }
            SourceHostSelfTest.Run(Options(dataRoot,modulePath),new Span<int>(proof,16));
            return proof[0] == 1 ? 0 : 1;
        }
        catch (Exception error)
        {
            proof[1]=1;
            // Do not expose filesystem paths or native arguments in the proof.
            WriteLog(LogLevel.Error,"SourceHost self-test failed: " + error.GetType().Name);
            return 1;
        }
    }
}
