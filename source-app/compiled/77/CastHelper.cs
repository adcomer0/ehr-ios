#if IL2CPP
using Il2CppInterop.Runtime.InteropTypes;
namespace EHR;
public static class Il2CppCastHelper
{
    public static T CastFast<T>(this Il2CppObjectBase obj) where T:Il2CppObjectBase
        =>obj.Cast<T>();
    public static bool TryCastFast<T>(this Il2CppObjectBase obj,out T casted) where T:Il2CppObjectBase
    {
        casted=obj is null?null!:obj.TryCast<T>()!;
        return casted is not null;
    }
}
#endif
