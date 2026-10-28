using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated
{
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct TypedActionHostV1
    {
        internal uint AbiVersion,ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong,ulong,uint,ulong*,ulong*,ulong*,int> Create;
        internal delegate* unmanaged[Cdecl]<ulong,int> Close;
        internal delegate* unmanaged[Cdecl]<ulong,int*,int> CallbackStatus;
        internal delegate* unmanaged[Cdecl]<int> IsMainThread;
    }
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct TypedActionCallbacksV1
    {
        internal uint AbiVersion,ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong,int,int> InvokeI32;
        internal delegate* unmanaged[Cdecl]<ulong,byte,int> InvokeU8;
        internal delegate* unmanaged[Cdecl]<ulong,float,int> InvokeF32;
        internal delegate* unmanaged[Cdecl]<ulong,ulong,int> InvokeReference;
        internal delegate* unmanaged[Cdecl]<ulong,int> Forget;
    }
    internal static unsafe class TypedActionRuntime
    {
        private abstract class Entry
        {
            internal abstract Delegate Identity{get;}
            internal abstract void I32(int value);
            internal abstract void U8(byte value);
            internal abstract void F32(float value);
            internal abstract void Reference(ulong borrowed);
        }
        private sealed class Entry<T>(System.Action<T> source,IElementCodec codec):Entry
        {
            internal override Delegate Identity=>source;
            internal override void I32(int value)=>((System.Action<int>)(object)source)(value);
            internal override void U8(byte value)=>((System.Action<byte>)(object)source)(value);
            internal override void F32(float value)=>((System.Action<float>)(object)source)(value);
            internal override void Reference(ulong borrowed)
            {
                // The original native argument root remains borrowed. The
                // independent retained root can escape in an owning facade.
                using var owned=borrowed==0?new RuntimeObject(0):FacadeRuntime.RetainToken(borrowed);
                source((T)codec.Read(owned)!);
            }
        }
        private static TypedActionHostV1 host;
        private static bool bound;
        private static ulong next=0x5459504500000001;
        private static readonly Dictionary<ulong,Entry> sources=new();
        private static readonly Dictionary<Delegate,ulong> identities=new();
        private static readonly Dictionary<Type,ulong> classes=new();
        internal static void RequireMain()
        {
            if(!bound)throw new RuntimeGatewayException(1,"typed Action bridge unavailable");
            if(host.IsMainThread()!=1)throw new RuntimeGatewayException(2,"typed Action requires Unity main thread");
        }
        internal static uint ArgumentABI<T>()=>typeof(T)==typeof(int)?1u:typeof(T)==typeof(byte)?2u:typeof(T)==typeof(float)?3u:
            typeof(T)==typeof(string)||typeof(RuntimeObject).IsAssignableFrom(typeof(T))?4u:throw new RuntimeGatewayException(7,"typed Action argument ABI not implemented");
        internal static ulong NativeClass<T>()
        {
            RequireMain();ArgumentABI<T>();
            if(!classes.TryGetValue(typeof(T),out ulong klass))
            {klass=LiveReflection.MakeGenericClass(FacadeRuntime.Class("mscorlib.dll","System","Action`1"),[ElementCodecs.Get<T>().NativeClass()]);classes.Add(typeof(T),klass);}
            return klass;
        }
        internal static ActionCreation Create<T>(System.Action<T> source)
        {
            ArgumentNullException.ThrowIfNull(source);RequireMain();uint abi=ArgumentABI<T>();
            IElementCodec codec=ElementCodecs.Get<T>();ulong argumentClass=codec.NativeClass();
            bool reused=identities.TryGetValue(source,out ulong id);
            if(!reused)
            {
                if(sources.Count>=256||next==ulong.MaxValue)throw new RuntimeGatewayException(8,"typed Action registry limit");
                id=next++;sources.Add(id,new Entry<T>(source,codec));identities.Add(source,id);
            }
            ulong root=0,registration=0,exception=0;
            int status=host.Create(id,argumentClass,abi,&root,&registration,&exception);
            if(status!=0||exception!=0||root==0||registration==0)
            {if(!reused)ForgetIdentity(id);FacadeRuntime.Release(root);FacadeRuntime.CheckManaged(status==0?4:status,exception,"create real typed Action");}
            sources[id]=new Entry<T>(source,codec);identities[source]=id;
            return new(root,registration);
        }
        internal static void Close(ulong registration){RequireMain();FacadeRuntime.Require(host.Close(registration),"close typed Action");}
        internal static int Status(ulong registration){RequireMain();int status=0;FacadeRuntime.Require(host.CallbackStatus(registration,&status),"typed callback status");return status;}
        internal static int SourceCount{get{RequireMain();return sources.Count;}}
        internal static void Invoke<T>(ulong borrowed,T value)
        {
            RequireMain();uint abi=ArgumentABI<T>();IElementCodec codec=ElementCodecs.Get<T>();
            ulong method=NativeMethods.Lookup(NativeClass<T>(),"Invoke",[codec.NativeClass()],FacadeRuntime.Class("mscorlib.dll","System","Void"),false);
            using var boxed=codec.Box(value);
            NativeArgument argument=abi==4?FacadeRuntime.Reference(boxed):new(){Kind=3,Token=boxed.Token};
            using var result=FacadeRuntime.InvokeResolved(method,borrowed,&argument,1);
        }
        internal static RuntimeObject Combine(RuntimeObject? left,RuntimeObject? right,bool remove)
        {
            NativeArgument* arguments=stackalloc NativeArgument[2];arguments[0]=FacadeRuntime.Reference(left);arguments[1]=FacadeRuntime.Reference(right);
            return FacadeRuntime.Invoke(new("mscorlib.dll","System","Delegate",remove?"Remove":"Combine",true,false,"System.Delegate",["System.Delegate","System.Delegate"]),0,arguments,2);
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_typed_action_bind_gateway",CallConvs=[typeof(CallConvCdecl)])]
        internal static int Bind(TypedActionHostV1* table,nuint bytes,TypedActionCallbacksV1* callbacks,nuint callbackBytes)
        {
            if(table==null||callbacks==null||bytes!=(nuint)sizeof(TypedActionHostV1)||callbackBytes!=(nuint)sizeof(TypedActionCallbacksV1)||table->AbiVersion!=1||table->ByteSize!=sizeof(TypedActionHostV1)||table->Create==null||table->Close==null||table->CallbackStatus==null||table->IsMainThread==null)return 4;
            if(table->IsMainThread()!=1)return 2;
            if(bound&&((nuint)host.Create!=(nuint)table->Create||(nuint)host.Close!=(nuint)table->Close||(nuint)host.CallbackStatus!=(nuint)table->CallbackStatus||(nuint)host.IsMainThread!=(nuint)table->IsMainThread))return 4;
            host=*table;bound=true;
            *callbacks=new(){AbiVersion=1,ByteSize=(uint)sizeof(TypedActionCallbacksV1),InvokeI32=&I32,InvokeU8=&U8,InvokeF32=&F32,InvokeReference=&Reference,Forget=&Forget};return 0;
        }
        private static int Preflight(ulong id,out Entry? entry)
        {
            entry=null;if(!bound)return 1;if(host.IsMainThread()!=1)return 2;
            return sources.TryGetValue(id,out entry)?0:9;
        }
        private static int Failure(Exception error)
        {
            if(error is NativeGameException native){try{native.Dispose();}catch{}return 6;}
            return error is RuntimeGatewayException gateway?gateway.Status:6;
        }
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int I32(ulong id,int value){int status=Preflight(id,out var entry);if(status!=0)return status;try{entry!.I32(value);return 0;}catch(Exception error){return Failure(error);}}
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int U8(ulong id,byte value){int status=Preflight(id,out var entry);if(status!=0)return status;try{entry!.U8(value);return 0;}catch(Exception error){return Failure(error);}}
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int F32(ulong id,float value){int status=Preflight(id,out var entry);if(status!=0)return status;try{entry!.F32(value);return 0;}catch(Exception error){return Failure(error);}}
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int Reference(ulong id,ulong value){int status=Preflight(id,out var entry);if(status!=0)return status;try{entry!.Reference(value);return 0;}catch(Exception error){return Failure(error);}}
        private static void ForgetIdentity(ulong id)
        {
            if(sources.Remove(id,out Entry? entry)&&identities.TryGetValue(entry.Identity,out ulong current)&&current==id)identities.Remove(entry.Identity);
        }
        [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])]
        private static int Forget(ulong id){if(!bound)return 1;if(host.IsMainThread()!=1)return 2;try{ForgetIdentity(id);return 0;}catch{return 4;}}
    }
}
namespace Il2CppSystem
{
    public sealed class Action<T>:Object
    {
        internal ulong Registration{get;}
        private bool closed;
        public Action(System.Action<T> source):this(EHR.Generated.TypedActionRuntime.Create(source)){}
        internal Action(ulong ownedToken):base(ownedToken){}
        private Action(EHR.Generated.ActionCreation value):base(value.Root){Registration=value.Registration;}
        public void Invoke(T value)=>EHR.Generated.TypedActionRuntime.Invoke(Token,value);
        public void Close(){if(closed||Registration==0)return;EHR.Generated.TypedActionRuntime.Close(Registration);closed=true;}
        public static implicit operator Action<T>(System.Action<T> source)=>new(source);
        public static Action<T>? operator +(Action<T>? left,Action<T>? right)
        {using var result=EHR.Generated.TypedActionRuntime.Combine(left,right,false);return result.Token==0?null:new(result.Detach());}
        public static Action<T>? operator -(Action<T>? left,Action<T>? right)
        {using var result=EHR.Generated.TypedActionRuntime.Combine(left,right,true);return result.Token==0?null:new(result.Detach());}
        // Proxy Dispose remains inherited and independent of source Close.
    }
}
