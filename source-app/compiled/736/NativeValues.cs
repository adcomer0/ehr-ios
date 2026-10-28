using System;

namespace EHR.Generated;

// A facade struct contains a shared immutable native boxed value. C# struct
// copies may share that owner; a field write or instance call first clones it.
// No reference-containing IL2CPP payload enters NativeAOT-owned byte storage.
public interface INativeValue
{
    RuntimeObject NativeBox { get; }
}
internal static unsafe class NativeValues
{
    private static readonly BindingSpec clone=new("mscorlib.dll","System","Object","MemberwiseClone",false,false,"System.Object",[]);
    private static readonly BindingSpec equals=new("mscorlib.dll","System","Object","Equals",false,false,"System.Boolean",["System.Object"]);
    private static readonly BindingSpec hash=new("mscorlib.dll","System","Object","GetHashCode",false,false,"System.Int32",[]);
    internal static RuntimeObject Default(string image,string space,string name)
        =>LiveReflection.Construct(FacadeRuntime.Class(image,space,name),[]);
    internal static RuntimeObject Clone(RuntimeObject value)=>FacadeRuntime.Invoke(clone,value.Token,null,0);
    internal static RuntimeObject Box<T>(T value) where T:INativeValue=>FacadeRuntime.Retain(value.NativeBox);
    internal static NativeArgument Argument(RuntimeObject box)=>new(){Kind=3,Token=box.Token};
    internal static bool Equal(RuntimeObject left,RuntimeObject right)
    {
        NativeArgument argument=FacadeRuntime.Reference(right);
        using var result=FacadeRuntime.Invoke(equals,left.Token,&argument,1);
        return FacadeRuntime.ReadValue<bool>(result);
    }
    internal static int Hash(RuntimeObject value)
    {
        using var result=FacadeRuntime.Invoke(hash,value.Token,null,0);
        return FacadeRuntime.ReadValue<int>(result);
    }
}
internal sealed class NativeValueCodec<T>(string image,string space,string name,Func<RuntimeObject,T> factory):IElementCodec where T:struct,INativeValue
{
    public ulong NativeClass()=>FacadeRuntime.Class(image,space,name);
    public object Read(RuntimeObject owned)=>factory(owned);
    public RuntimeObject Box(object? value)=>NativeValues.Box((T)value!);
}
