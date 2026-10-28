using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace EHR.Generated;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeArgument
{
    internal uint Kind, Reserved;
    internal ulong Token;
    internal void* Bytes;
    internal nuint ByteCount;
}
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeGatewayTable
{
    internal uint AbiVersion, ByteSize;
    internal delegate* unmanaged[Cdecl]<uint> RuntimeAbiVersion;
    internal delegate* unmanaged[Cdecl]<int> Initialize;
    internal delegate* unmanaged[Cdecl]<byte*, byte*, byte*, ulong*, int> FindClass;
    internal delegate* unmanaged[Cdecl]<ulong, ulong*, int> ObjectClass;
    internal delegate* unmanaged[Cdecl]<ulong, byte*, byte**, nuint, byte*, int, ulong*, int> FindMethod;
    internal delegate* unmanaged[Cdecl]<ulong, byte*, byte*, int, ulong*, int> FindField;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, NativeArgument*, nuint, ulong*, ulong*, int> Invoke;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, ulong*, int> ReadField;
    internal delegate* unmanaged[Cdecl]<ulong, ulong, NativeArgument*, int> WriteField;
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

public class RuntimeGatewayException(int status, string operation) : Exception(operation + " failed: " + status)
{
    public int Status { get; } = status;
}

// Keeps the actual managed-game exception alive across source dispatcher
// finalizers. A native adapter may retain a separate root for rethrow only after
// returning from NativeAOT; native exceptions never unwind through .NET frames.
public sealed class NativeGameException : RuntimeGatewayException, IDisposable
{
    private readonly RuntimeObject exception;
    internal NativeGameException(ulong ownedException,string operation):base(6,operation) { exception=new(ownedException); }
    internal RuntimeObject RetainNativeException()=>FacadeRuntime.Retain(exception);
    internal static NativeGameException FromBorrowed(ulong borrowedException,string operation)
    {
        using var owned=FacadeRuntime.RetainToken(borrowedException);
        return new NativeGameException(owned.Detach(),operation);
    }
    public void Dispose()=>exception.Dispose();
}

// Every instance owns exactly one strong native gateway root. Worker/finalizer
// release only enqueues to the native lifetime API; IL2CPP GC frees run on main.
public class RuntimeObject : IDisposable
{
    private long tokenBits;
    private int disposed;
    private int unitySourceProxy;
    internal RuntimeObject(ulong ownedToken) { tokenBits = unchecked((long)ownedToken); }
    internal void MarkUnitySourceProxy() { if(Volatile.Read(ref disposed)!=0||Interlocked.Read(ref tokenBits)==0)throw new ObjectDisposedException(GetType().Name);Volatile.Write(ref unitySourceProxy,1); }
    internal ulong Token
    {
        get
        {
            ulong token=unchecked((ulong)Interlocked.Read(ref tokenBits));
            return Volatile.Read(ref disposed)==0?token:Volatile.Read(ref unitySourceProxy)!=0?0UL:throw new ObjectDisposedException(GetType().Name);
        }
    }
    internal ulong Detach()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0)throw new ObjectDisposedException(GetType().Name);
        ulong result=unchecked((ulong)Interlocked.Exchange(ref tokenBits,0));GC.SuppressFinalize(this);return result;
    }
    public void Dispose()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0)return;
        ulong token=unchecked((ulong)Interlocked.Exchange(ref tokenBits,0));
        GC.SuppressFinalize(this);
        try{FacadeRuntime.Release(token);}
        catch(RuntimeGatewayException exception) when(exception.Status==1||exception.Status==2){NativeLifetime.Enqueue(token);}
    }
    ~RuntimeObject()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0)return;
        NativeLifetime.Enqueue(unchecked((ulong)Interlocked.Exchange(ref tokenBits,0)));
    }
    public override bool Equals(object? other)=>ReferenceEquals(this,other)||(other is RuntimeObject value&&NativeLifetime.Same(this,value));
    public override int GetHashCode()=>NativeLifetime.Hash(this);
}

internal sealed record BindingSpec(string Image, string Namespace, string Type, string Member,
    bool IsStatic, bool IsField, string ResultType, string[] Parameters);

internal static unsafe class FacadeRuntime
{
    private static NativeGatewayTable table;
    private static bool bound;
    internal static void Require(int status, string operation)
    {
        if (status != 0) throw new RuntimeGatewayException(status, operation);
    }
    internal static void CheckManaged(int status,ulong exception,string operation)
    {
        if(exception!=0)throw new NativeGameException(exception,operation);
        Require(status,operation);
    }
    internal static void Release(ulong token)
    {
        if (token != 0) Require(table.Release(token), "release");
    }
    internal static RuntimeObject Retain(RuntimeObject value)
    {
        return RetainToken(value.Token);
    }
    internal static RuntimeObject RetainToken(ulong borrowedToken)
    {
        Ready();ulong result=0;
        if(borrowedToken==0)return new(0);
        if(table.Retain==null)throw new RuntimeGatewayException(7,"retain unavailable");
        Require(table.Retain(borrowedToken,&result),"retain borrowed token");return new(result);
    }
    internal static int ReadCollectionVersion(RuntimeObject value)
    {
        Ready();ulong klass=0,field=0,result=0;
        Require(table.ObjectClass(value.Token,&klass),"collection class");
        byte* name=Utf8("_version"),type=Utf8("System.Int32");
        try{Require(table.FindField(klass,name,type,0,&field),"collection version field");}
        finally{NativeMemory.Free(name);NativeMemory.Free(type);}
        Require(table.ReadField(field,value.Token,&result),"collection version read");
        using var boxed=new RuntimeObject(result);return ReadValue<int>(boxed);
    }
    internal static ulong ObjectClass(RuntimeObject value)
    {Ready();ulong klass=0;Require(table.ObjectClass(value.Token,&klass),"object class");return klass;}
    internal static bool TokenIsValid(ulong token)
    {
        ulong klass=0;return table.ObjectClass(token,&klass)==0;
    }
    internal static RuntimeObject BoxValue<T>(string image, string space, string name, T value) where T : unmanaged
    {
        ulong result = 0;
        Require(table.Box(Class(image, space, name), &value, (nuint)sizeof(T), &result), "box array element");
        return new(result);
    }
    internal static int RawValueSize(ulong klass)
    {
        Ready();nuint size=0;Require(table.ValueSize(klass,&size),"reference-free value size");
        if(size==0||size>4096)throw new RuntimeGatewayException(9,"bounded raw value payload");return checked((int)size);
    }
    internal static void CopyRawValue(RuntimeObject value,Span<byte> destination)
    {
        Ready();nuint copied=0;
        fixed(byte* data=destination)Require(table.CopyValue(value.Token,data,(nuint)destination.Length,&copied),"copy reference-free boxed value");
        if(copied!=(nuint)destination.Length)throw new RuntimeGatewayException(5,"raw value size mismatch");
    }
    internal static RuntimeObject BoxRawValue(ulong klass,ReadOnlySpan<byte> bytes)
    {
        Ready();ulong token=0;
        fixed(byte* data=bytes)Require(table.Box(klass,data,(nuint)bytes.Length,&token),"box reference-free value payload");return new(token);
    }
    private static void Ready()
    {
        if (!bound) throw new RuntimeGatewayException(1, "gateway not bound");
        Require(table.Initialize(), "main-thread runtime readiness");
        NativeLifetime.FlushPending();
    }
    internal static void RequireReady()=>Ready();
    private static byte* Utf8(string text)
    {
        int count = Encoding.UTF8.GetByteCount(text);
        byte* result = (byte*)NativeMemory.Alloc((nuint)count + 1);
        Encoding.UTF8.GetBytes(text, new Span<byte>(result, count)); result[count] = 0;
        return result;
    }
    internal static ulong Class(string image, string space, string name)
    {
        Ready(); ulong result = 0;
        byte* i = Utf8(image), s = Utf8(space), n = Utf8(name);
        try { Require(table.FindClass(i, s, n, &result), "find class " + name); return result; }
        finally { NativeMemory.Free(i); NativeMemory.Free(s); NativeMemory.Free(n); }
    }
    internal static ulong ValueClass(string exactType)
    {
        int split = exactType.LastIndexOf('.');
        string space = split < 0 ? "" : exactType[..split];
        string name = split < 0 ? exactType : exactType[(split + 1)..];
        return Class(space == "System" ? "mscorlib.dll" : "Assembly-CSharp.dll", space, name);
    }
    internal static ulong Resolve(BindingSpec spec)
    {
        ulong klass = Class(spec.Image, spec.Namespace, spec.Type), result = 0;
        byte* name = Utf8(spec.Member), resultType = Utf8(NativeTypeNames.RuntimeName(spec.ResultType));
        int count = spec.Parameters.Length;
        byte** parameters = count == 0 ? null : (byte**)NativeMemory.AllocZeroed((nuint)count, (nuint)sizeof(byte*));
        try
        {
            if (spec.IsField) Require(table.FindField(klass, name, resultType, spec.IsStatic ? 1 : 0, &result), "find field " + spec.Member);
            else
            {
                for (int i = 0; i < count; ++i) parameters[i] = Utf8(NativeTypeNames.RuntimeName(spec.Parameters[i]));
                Require(table.FindMethod(klass, name, parameters, (nuint)count, resultType, spec.IsStatic ? 1 : 0, &result), "find method " + spec.Member);
            }
            return result;
        }
        finally
        {
            for (int i = 0; i < count; ++i) NativeMemory.Free(parameters[i]);
            NativeMemory.Free(parameters); NativeMemory.Free(name); NativeMemory.Free(resultType);
        }
    }
    internal static RuntimeObject InvokeOnClass(ulong klass,string member,string resultType,ulong instance)
    {
        Ready();ulong method=0,result=0,exception=0;
        byte* name=Utf8(member),type=Utf8(NativeTypeNames.RuntimeName(resultType));
        try{Require(table.FindMethod(klass,name,null,0,type,0,&method),"find closed-class method "+member);}
        finally{NativeMemory.Free(name);NativeMemory.Free(type);}
        int status=table.Invoke(method,instance,null,0,&result,&exception);
        if(status!=0||exception!=0){Release(result);CheckManaged(status,exception,"invoke closed-class method "+member);}
        return new(result);
    }
    internal static NativeArgument Value<T>(T* bytes, string exactType) where T : unmanaged
        => new() { Kind = 2, Token = ElementCodecs.Get<T>().NativeClass(), Bytes = bytes, ByteCount = (nuint)sizeof(T) };
    internal static NativeArgument Reference(RuntimeObject? value)
        => new() { Kind = 1, Token = value?.Token ?? 0 };
    internal static RuntimeObject String(string? value)
    {
        Ready(); if (value is null) return new(0);
        if (table.StringCreate == null) throw new RuntimeGatewayException(7, "string create unavailable");
        ulong token = 0;
        fixed (char* units = value) Require(table.StringCreate((ushort*)units, (nuint)value.Length, &token), "create string");
        return new(token);
    }
    internal static string? ReadString(RuntimeObject value)
    {
        if (value.Token == 0) return null;
        if (table.StringCopy == null) throw new RuntimeGatewayException(7, "string copy unavailable");
        nuint count = 0;
        int status = table.StringCopy(value.Token, null, 0, &count);
        if (status != 0 && status != 8) Require(status, "string length");
        if (count > 524288) throw new RuntimeGatewayException(8, "string length limit");
        char[] chars = new char[(int)count];
        fixed (char* units = chars) Require(table.StringCopy(value.Token, (ushort*)units, count, &count), "copy string");
        return new string(chars);
    }
    internal static T ReadValue<T>(RuntimeObject value) where T : unmanaged
    {
        T result = default; nuint count = 0;
        Require(table.CopyValue(value.Token, &result, (nuint)sizeof(T), &count), "copy boxed value");
        if (count != (nuint)sizeof(T)) throw new RuntimeGatewayException(5, "value size");
        return result;
    }
    internal static RuntimeObject ReadField(BindingSpec spec, ulong instance)
    {
        ulong result = 0;
        if(spec.IsStatic)LiveReflection.InitializeClass(Class(spec.Image,spec.Namespace,spec.Type));
        Require(table.ReadField(Resolve(spec), instance, &result), "read field " + spec.Member);
        return new(result);
    }
    internal static ulong ResolveField(ulong klass,string member,string canonicalType,bool isStatic=false)
    {
        Ready();ulong field=0;byte* name=Utf8(member),type=Utf8(NativeTypeNames.RuntimeName(canonicalType));
        try{Require(table.FindField(klass,name,type,isStatic?1:0,&field),"resolve exact runtime field "+member);return field;}
        finally{NativeMemory.Free(name);NativeMemory.Free(type);}
    }
    internal static RuntimeObject ReadResolvedField(ulong field,RuntimeObject instance)
    {
        Ready();ulong result=0;Require(table.ReadField(field,instance.Token,&result),"read resolved runtime field");return new(result);
    }
    internal static void WriteResolvedField(ulong field,RuntimeObject instance,NativeArgument argument)
    {
        Ready();Require(table.WriteField(field,instance.Token,&argument),"write resolved runtime field");
    }
    internal static void WriteField(BindingSpec spec, ulong instance, NativeArgument value)
    {
        if(spec.IsStatic)LiveReflection.InitializeClass(Class(spec.Image,spec.Namespace,spec.Type));
        Require(table.WriteField(Resolve(spec), instance, &value), "write field " + spec.Member);
    }
    internal static RuntimeObject InvokeResolved(ulong method,ulong instance,NativeArgument* arguments,int count)
    {
        Ready();ulong result=0,exception=0;int status=table.Invoke(method,instance,arguments,(nuint)count,&result,&exception);
        if(status!=0||exception!=0){Release(result);CheckManaged(status,exception,"invoke resolved method");}
        return new(result);
    }
    internal static RuntimeObject Invoke(BindingSpec spec, ulong instance, NativeArgument* arguments, int count)
    {
        ulong result = 0, exception = 0;
        int status = table.Invoke(Resolve(spec), instance, arguments, (nuint)count, &result, &exception);
        if (status != 0 || exception != 0)
        {
            Release(result);
            CheckManaged(status,exception,"invoke "+spec.Member);
        }
        return new(result);
    }
    [UnmanagedCallersOnly(EntryPoint = "ehr_generated_bind_gateway")]
    internal static int Bind(NativeGatewayTable* source, nuint bytes)
    {
        if (source == null || bytes != (nuint)sizeof(NativeGatewayTable) || source->AbiVersion != 1 || source->ByteSize != sizeof(NativeGatewayTable)) return 4;
        if (source->RuntimeAbiVersion == null || source->Initialize == null || source->FindClass == null || source->FindMethod == null ||
            source->FindField == null || source->Invoke == null || source->ReadField == null || source->WriteField == null ||
            source->CopyValue == null || source->Release == null) return 4;
        if (source->RuntimeAbiVersion() != 1) return 7;
        int status = source->Initialize(); if (status != 0) return status;
        table = *source; bound = true; return 0;
    }
    [UnmanagedCallersOnly(EntryPoint = "ehr_generated_binding_count")]
    internal static uint BindingCount() => (uint)GeneratedBindings.All.Length;
    [UnmanagedCallersOnly(EntryPoint = "ehr_generated_get_broadcast_version")]
    internal static int ReadGeneratedGetter(int* result)
    {
        if (result == null) return 4;
        try { *result = Constants.GetBroadcastVersion(); return 0; }
        catch (RuntimeGatewayException exception) { return exception.Status; }
        catch { return 6; }
    }
    // Metadata resolution only. No methods/field getters or mutating operations
    // are invoked by this validation export. Return exact gateway status.
    [UnmanagedCallersOnly(EntryPoint = "ehr_generated_validate_binding")]
    internal static int Validate(uint index)
    {
        if (index >= GeneratedBindings.All.Length) return 4;
        try { Resolve(GeneratedBindings.All[index]); return 0; }
        catch (RuntimeGatewayException exception) { return exception.Status; }
        catch { return 6; }
    }
}
