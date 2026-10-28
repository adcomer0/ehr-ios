using System;

namespace EHR.Generated
{
    internal static unsafe class NativeObjectCasts
    {
        private static readonly BindingSpec isInstance=new("mscorlib.dll","System","Type","IsInstanceOfType",false,false,"System.Boolean",["System.Object"]);
        internal static object? TryCast(RuntimeObject instance,Type target)
        {
            if(instance.Token==0)return null;
            var codec=ElementCodecs.Get(target);
            using var type=LiveCollections.TypeObject(codec.NativeClass());
            NativeArgument argument=FacadeRuntime.Reference(instance);
            using var matched=FacadeRuntime.Invoke(isInstance,type.Token,&argument,1);
            return FacadeRuntime.ReadValue<bool>(matched)?codec.Read(FacadeRuntime.Retain(instance)):null;
        }
    }
}
namespace Il2CppInterop.Runtime.InteropTypes
{
    public class Il2CppObjectBase:EHR.Generated.RuntimeObject
    {
        internal Il2CppObjectBase(ulong ownedToken):base(ownedToken){}
        public T? TryCast<T>() where T:Il2CppObjectBase => (T?)EHR.Generated.NativeObjectCasts.TryCast(this,typeof(T));
        public T Cast<T>() where T:Il2CppObjectBase => TryCast<T>()??throw new InvalidCastException(typeof(T).FullName);
        public object? TryCast(Type target)=>EHR.Generated.NativeObjectCasts.TryCast(this,target);
        // Raw native managed pointers are intentionally unavailable. Reused
        // Pointer/CastFast source must be rewritten to the validated Cast API.
        public IntPtr Pointer=>throw new EHR.Generated.RuntimeGatewayException(7,"raw managed pointers unavailable; use token cast");
    }
}
namespace Il2CppSystem
{
    public unsafe class Object:Il2CppInterop.Runtime.InteropTypes.Il2CppObjectBase
    {
        internal Object(ulong ownedToken):base(ownedToken){}
        public static implicit operator Object?(string? value)=>value is null?null:
            new(EHR.Generated.FacadeRuntime.String(value).Detach());
        public override string? ToString()
        {
            using var result=EHR.Generated.FacadeRuntime.Invoke(new("mscorlib.dll","System","Object","ToString",false,false,"System.String",[]),Token,null,0);
            return EHR.Generated.FacadeRuntime.ReadString(result);
        }
    }
}
namespace Il2CppSystem.Collections
{
    // Dispose releases this facade's root. IEnumerator itself has no Dispose
    // contract; iterator-specific IDisposable is separate native behavior.
    public unsafe class IEnumerator:Il2CppSystem.Object
    {
        internal IEnumerator(ulong ownedToken):base(ownedToken){}
        private static EHR.Generated.BindingSpec Spec(string member,string result)
            =>new("mscorlib.dll","System.Collections","IEnumerator",member,false,false,result,[]);
        public bool MoveNext()
        {
            using var result=EHR.Generated.FacadeRuntime.Invoke(Spec("MoveNext","System.Boolean"),Token,null,0);
            return EHR.Generated.FacadeRuntime.ReadValue<bool>(result);
        }
        public Il2CppSystem.Object? Current
        {
            get
            {
                using var result=EHR.Generated.FacadeRuntime.Invoke(Spec("get_Current","System.Object"),Token,null,0);
                return result.Token==0?null:new Il2CppSystem.Object(result.Detach());
            }
        }
        public void Reset(){using var result=EHR.Generated.FacadeRuntime.Invoke(Spec("Reset","System.Void"),Token,null,0);}
    }
}
