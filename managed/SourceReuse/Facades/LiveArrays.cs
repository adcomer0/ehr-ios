using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated
{
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct ByRefOutput
    {
        internal uint ArgumentIndex, Reserved;
        internal ulong ValueClass;
        internal void* Bytes;
        internal nuint ByteCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct FacadeExtensions
    {
        internal uint AbiVersion, ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong, ulong, NativeArgument*, nuint, ByRefOutput*, nuint, ulong*, ulong*, int> InvokeWithRefs;
        internal delegate* unmanaged[Cdecl]<ulong, ulong*, int> ClassTypeObject;
        internal delegate* unmanaged[Cdecl]<ulong, int, ulong*, ulong*, int> ArrayCreate;
        internal delegate* unmanaged[Cdecl]<ulong, int*, ulong*, int> ArrayLength;
        internal delegate* unmanaged[Cdecl]<ulong, int, ulong*, ulong*, int> ArrayGet;
        internal delegate* unmanaged[Cdecl]<ulong, int, ulong, ulong*, int> ArraySet;
    }
    internal static unsafe class LiveCollections
    {
        private static FacadeExtensions extensions;
        private static bool bound;
        internal static RuntimeObject TypeObject(ulong klass)
        {
            if(!bound)throw new RuntimeGatewayException(1,"type object extensions not bound");
            ulong result=0;FacadeRuntime.Require(extensions.ClassTypeObject(klass,&result),"class type object");return new(result);
        }
        internal static RuntimeObject InvokeWithRefs(BindingSpec spec,ulong instance,NativeArgument* arguments,int count,ByRefOutput* outputs,int outputCount)
        {
            if(!bound)throw new RuntimeGatewayException(1,"byref extensions not bound");
            ulong result=0,exception=0;
            int status=extensions.InvokeWithRefs(FacadeRuntime.Resolve(spec),instance,arguments,(nuint)count,outputs,(nuint)outputCount,&result,&exception);
            if(status!=0||exception!=0){FacadeRuntime.Release(result);Check(status,exception,"invoke refs "+spec.Member);}
            return new(result);
        }
        private static void Check(int status, ulong exception, string operation)
        {
            FacadeRuntime.CheckManaged(status,exception,operation);
        }
        internal static ulong Create(ulong elementClass, long length)
        {
            if (!bound) throw new RuntimeGatewayException(1, "array extensions not bound");
            if (length < 0 || length > 65536) throw new ArgumentOutOfRangeException(nameof(length));
            ulong result=0, exception=0;
            int status=extensions.ArrayCreate(elementClass,(int)length,&result,&exception);
            if (status != 0 || exception != 0) { FacadeRuntime.Release(result); Check(status,exception,"array create"); }
            return result;
        }
        internal static int Length(RuntimeObject array)
        {
            if (!bound) throw new RuntimeGatewayException(1, "array extensions not bound");
            int result=0; ulong exception=0;
            int status=extensions.ArrayLength(array.Token,&result,&exception);
            Check(status,exception,"array length");return result;
        }
        internal static RuntimeObject Get(RuntimeObject array,int index)
        {
            if (!bound) throw new RuntimeGatewayException(1, "array extensions not bound");
            ulong result=0, exception=0;
            int status=extensions.ArrayGet(array.Token,index,&result,&exception);
            if (status != 0 || exception != 0) { FacadeRuntime.Release(result); Check(status,exception,"array get"); }
            return new(result);
        }
        internal static void Set(RuntimeObject array,int index,RuntimeObject value)
        {
            if (!bound) throw new RuntimeGatewayException(1, "array extensions not bound");
            ulong exception=0;
            int status=extensions.ArraySet(array.Token,index,value.Token,&exception);
            Check(status,exception,"array set");
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_extensions")]
        internal static int Bind(FacadeExtensions* source,nuint bytes)
        {
            if (source == null || bytes != (nuint)sizeof(FacadeExtensions) || source->ByteSize != sizeof(FacadeExtensions) || source->AbiVersion != 1) return 4;
            if (source->InvokeWithRefs == null || source->ClassTypeObject == null || source->ArrayCreate == null ||
                source->ArrayLength == null || source->ArrayGet == null || source->ArraySet == null) return 4;
            extensions=*source; bound=true;return 0;
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_array_self_test")]
        internal static int SelfTest(int* output,nuint count)
        {
            if (output == null || count != 4) return 4;
            for(int i=0;i<4;++i) output[i]=0;
            try
            {
                using var bytes=new Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppStructArray<byte>(2);
                bytes[0]=17;bytes[1]=42;
                byte[] explicitCopy=bytes;
                bytes[1]=43;
                output[2]=bytes.Length==2 && bytes[0]==17 && bytes[1]==43 && explicitCopy[1]==42 ? 1:0;
                using var strings=new Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppStringArray(2);
                strings[0]="A\0\U0001F680";strings[1]=null;
                output[3]=strings[0]=="A\0\U0001F680" && strings[1] is null ? 1:0;
                output[0]=output[2]==1 && output[3]==1 ? 1:0;
                return output[1]=output[0]==1 ? 0:5;
            }
            catch(RuntimeGatewayException exception){return output[1]=exception.Status;}
            catch{return output[1]=6;}
        }
    }
    internal interface IElementCodec
    {
        ulong NativeClass();
        object? Read(RuntimeObject owned);
        RuntimeObject Box(object? value);
    }
    internal sealed class PrimitiveCodec<T>(string image,string space,string name) : IElementCodec where T:unmanaged
    {
        public ulong NativeClass()=>FacadeRuntime.Class(image,space,name);
        public object Read(RuntimeObject owned){using(owned)return FacadeRuntime.ReadValue<T>(owned);}
        public RuntimeObject Box(object? value)=>FacadeRuntime.BoxValue(image,space,name,(T)value!);
    }
    internal sealed class StringCodec : IElementCodec
    {
        public ulong NativeClass()=>FacadeRuntime.Class("mscorlib.dll","System","String");
        public object? Read(RuntimeObject owned){using(owned)return FacadeRuntime.ReadString(owned);}
        public RuntimeObject Box(object? value)=>FacadeRuntime.String((string?)value);
    }
    internal sealed class ReferenceCodec<T>(string image,string space,string name,Func<ulong,T> factory):IElementCodec where T:RuntimeObject
    {
        public ulong NativeClass()=>FacadeRuntime.Class(image,space,name);
        public object? Read(RuntimeObject owned)
        {
            if(owned.Token==0){owned.Dispose();return null;}
            return factory(owned.Detach());
        }
        public RuntimeObject Box(object? value)=>value is null ? new(0):FacadeRuntime.Retain((RuntimeObject)value);
    }
    internal sealed class ClosedReferenceCodec<T>(Func<ulong> nativeClass,Func<ulong,T> factory):IElementCodec where T:RuntimeObject
    {
        public ulong NativeClass()=>nativeClass();
        public object? Read(RuntimeObject owned){if(owned.Token==0){owned.Dispose();return null;}return factory(owned.Detach());}
        public RuntimeObject Box(object? value)=>value is null?new(0):FacadeRuntime.Retain((RuntimeObject)value);
    }
    internal static class ElementCodecs
    {
        private static readonly Dictionary<Type,IElementCodec> codecs=new();
        static ElementCodecs()
        {
            Register<bool>(new PrimitiveCodec<bool>("mscorlib.dll","System","Boolean"));
            Register<byte>(new PrimitiveCodec<byte>("mscorlib.dll","System","Byte"));
            Register<sbyte>(new PrimitiveCodec<sbyte>("mscorlib.dll","System","SByte"));
            Register<char>(new PrimitiveCodec<char>("mscorlib.dll","System","Char"));
            Register<short>(new PrimitiveCodec<short>("mscorlib.dll","System","Int16"));
            Register<ushort>(new PrimitiveCodec<ushort>("mscorlib.dll","System","UInt16"));
            Register<int>(new PrimitiveCodec<int>("mscorlib.dll","System","Int32"));
            Register<uint>(new PrimitiveCodec<uint>("mscorlib.dll","System","UInt32"));
            Register<long>(new PrimitiveCodec<long>("mscorlib.dll","System","Int64"));
            Register<ulong>(new PrimitiveCodec<ulong>("mscorlib.dll","System","UInt64"));
            Register<float>(new PrimitiveCodec<float>("mscorlib.dll","System","Single"));
            Register<double>(new PrimitiveCodec<double>("mscorlib.dll","System","Double"));
            Register<string>(new StringCodec());
            Register<Il2CppSystem.Object>(new ReferenceCodec<Il2CppSystem.Object>("mscorlib.dll","System","Object",static token=>new(token)));
            Register<Il2CppSystem.Action>(new ReferenceCodec<Il2CppSystem.Action>("mscorlib.dll","System","Action",static token=>new(token)));
            Register<Il2CppSystem.Text.StringBuilder>(new ReferenceCodec<Il2CppSystem.Text.StringBuilder>("mscorlib.dll","System.Text","StringBuilder",static token=>new(token)));
            Register<Il2CppSystem.Collections.IEnumerator>(new ReferenceCodec<Il2CppSystem.Collections.IEnumerator>("mscorlib.dll","System.Collections","IEnumerator",static token=>new(token)));
            GeneratedElementCodecs.RegisterAll();
        }
        internal static void Register<T>(IElementCodec codec)=>codecs.Add(typeof(T),codec);
        internal static IElementCodec Get<T>()=>Get(typeof(T));
        internal static IElementCodec Get(Type type)=>codecs.TryGetValue(type,out var codec) ? codec:throw new RuntimeGatewayException(7,"No compiled element codec for "+type.FullName);
    }
}

namespace Il2CppInterop.Runtime.InteropTypes.Arrays
{
    public class Il2CppArrayBase<T>:Il2CppSystem.Object,IReadOnlyList<T>
    {
        protected internal Il2CppArrayBase(ulong ownedToken):base(ownedToken){}
        protected Il2CppArrayBase(long length):base(EHR.Generated.LiveCollections.Create(EHR.Generated.ElementCodecs.Get<T>().NativeClass(),length)){}
        public int Length=>EHR.Generated.LiveCollections.Length(this);
        public int Count=>Length;
        public T this[int index]
        {
            get=>(T)EHR.Generated.ElementCodecs.Get<T>().Read(EHR.Generated.LiveCollections.Get(this,index))!;
            set { using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(value);EHR.Generated.LiveCollections.Set(this,index,boxed); }
        }
        public IEnumerator<T> GetEnumerator(){for(int i=0;i<Length;++i)yield return this[i];}
        IEnumerator IEnumerable.GetEnumerator()=>GetEnumerator();
        // This operator is an explicit snapshot boundary inherited from the
        // original Il2CppInterop API. The array wrapper and its indexer stay live.
        public static implicit operator T[](Il2CppArrayBase<T> value)
        {
            var copy=new T[value.Length];for(int i=0;i<copy.Length;++i)copy[i]=value[i];return copy;
        }
    }
    public sealed class Il2CppStructArray<T>:Il2CppArrayBase<T> where T:struct
    {
        public Il2CppStructArray(long length):base(length){}
        internal Il2CppStructArray(ulong ownedToken,bool owned):base(ownedToken){}
        public static implicit operator Il2CppStructArray<T>(T[] values)
        {
            var result=new Il2CppStructArray<T>(values.LongLength);
            try{for(int i=0;i<values.Length;++i)result[i]=values[i];return result;}
            catch{result.Dispose();throw;}
        }
    }
    public sealed class Il2CppReferenceArray<T>:Il2CppArrayBase<T> where T:EHR.Generated.RuntimeObject
    {
        public Il2CppReferenceArray(long length):base(length){}
        internal Il2CppReferenceArray(ulong ownedToken,bool owned):base(ownedToken){}
        public static implicit operator Il2CppReferenceArray<T>(T[] values)
        {
            var result=new Il2CppReferenceArray<T>(values.LongLength);
            try{for(int i=0;i<values.Length;++i)result[i]=values[i];return result;}
            catch{result.Dispose();throw;}
        }
    }
    public sealed class Il2CppStringArray:Il2CppArrayBase<string?>
    {
        public Il2CppStringArray(long length):base(length){}
        internal Il2CppStringArray(ulong ownedToken,bool owned):base(ownedToken){}
        public static implicit operator Il2CppStringArray(string?[] values)
        {
            ArgumentNullException.ThrowIfNull(values);var result=new Il2CppStringArray(values.LongLength);
            try{for(int i=0;i<values.Length;++i)result[i]=values[i];return result;}catch{result.Dispose();throw;}
        }
    }
}
