using System;
using System.Runtime.InteropServices;
namespace EHR.Generated
{
    internal sealed class ClosedBoxedReferenceCodec<T>(Func<ulong> nativeClass,Func<ulong,T> factory):IElementCodec where T:RuntimeObject
    {
        public ulong NativeClass()=>nativeClass();
        public object Read(RuntimeObject owned){if(owned.Token==0){owned.Dispose();throw new RuntimeGatewayException(5,"null boxed value proxy");}return factory(owned.Detach());}
        public RuntimeObject Box(object? value)=>value is null?throw new ArgumentNullException(nameof(value)):FacadeRuntime.Retain((RuntimeObject)value);
    }
    internal static unsafe class NativeAsyncHandles
    {
        internal static ulong Class<T>()=>LiveReflection.MakeGenericClass(FacadeRuntime.Class("Unity.ResourceManager.dll","UnityEngine.ResourceManagement.AsyncOperations","AsyncOperationHandle`1"),[ElementCodecs.Get<T>().NativeClass()]);
        internal static RuntimeObject Read<T>(RuntimeObject value,string name,ulong resultClass)
        {
            ulong method=NativeMethods.Lookup(Class<T>(),name,[],resultClass,false);
            return FacadeRuntime.InvokeResolved(method,value.Token,null,0);
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_async_handle_self_test")]
        internal static int SelfTest(int* output,nuint count)
        {
            if(output==null||count!=5)return 4;for(int i=0;i<5;++i)output[i]=0;
            try
            {
                using var handle=new UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<UnityEngine_GameObject>();
                output[2]=!handle.IsValid()?1:0;
                ulong owner=Class<UnityEngine_GameObject>();
                output[3]=FacadeRuntime.ObjectClass(handle)==owner&&NativeMethods.Lookup(owner,"get_IsDone",[],ElementCodecs.Get<bool>().NativeClass(),false)!=0&&NativeMethods.Lookup(owner,"get_PercentComplete",[],ElementCodecs.Get<float>().NativeClass(),false)!=0&&NativeMethods.Lookup(owner,"get_Result",[],ElementCodecs.Get<UnityEngine_GameObject>().NativeClass(),false)!=0?1:0;
                using var clone=new UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<UnityEngine_GameObject>(NativeValues.Clone(handle).Detach(),true);
                output[4]=!clone.IsValid()&&FacadeRuntime.ObjectClass(clone)==owner?1:0;
                output[0]=output[2]==1&&output[3]==1&&output[4]==1?1:0;return output[1]=output[0]==1?0:5;
            }
            catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
        }
    }
}
namespace UnityEngine.ResourceManagement.AsyncOperations
{
    // Source IL2CPP interop exposes this native struct as a boxed value proxy.
    // Dispose releases the facade root; it does not release an addressable asset.
    public sealed class AsyncOperationHandle<T>:Il2CppSystem.Object
    {
        internal static ulong NativeClass=>EHR.Generated.NativeAsyncHandles.Class<T>();
        public AsyncOperationHandle():base(EHR.Generated.LiveReflection.Construct(NativeClass,[]).Detach()){}
        internal AsyncOperationHandle(ulong owned,bool takeOwnership):base(owned){}
        public bool IsValid(){using var result=EHR.Generated.NativeAsyncHandles.Read<T>(this,"IsValid",EHR.Generated.ElementCodecs.Get<bool>().NativeClass());return EHR.Generated.FacadeRuntime.ReadValue<bool>(result);}
        public bool IsDone{get{using var result=EHR.Generated.NativeAsyncHandles.Read<T>(this,"get_IsDone",EHR.Generated.ElementCodecs.Get<bool>().NativeClass());return EHR.Generated.FacadeRuntime.ReadValue<bool>(result);}}
        public float PercentComplete{get{using var result=EHR.Generated.NativeAsyncHandles.Read<T>(this,"get_PercentComplete",EHR.Generated.ElementCodecs.Get<float>().NativeClass());return EHR.Generated.FacadeRuntime.ReadValue<float>(result);}}
        public T? Result{get{return (T?)EHR.Generated.ElementCodecs.Get<T>().Read(EHR.Generated.NativeAsyncHandles.Read<T>(this,"get_Result",EHR.Generated.ElementCodecs.Get<T>().NativeClass()));}}
    }
}
