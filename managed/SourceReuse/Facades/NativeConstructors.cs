using System;
namespace EHR.Generated;
internal static unsafe class NativeConstructors
{
    private static RuntimeObject Property(RuntimeObject value,string owner,string name,string result)
        =>FacadeRuntime.Invoke(new("mscorlib.dll","System.Reflection",owner,name,false,false,result,[]),value.Token,null,0);
    internal static ulong Create(ulong klass,ReadOnlySpan<ulong> parameterClasses,RuntimeObject?[] arguments)
    {
        if(parameterClasses.Length!=arguments.Length||arguments.Length>128)throw new ArgumentException("constructor parameter descriptors");
        using var type=LiveCollections.TypeObject(klass);
        using var types=new RuntimeObject(LiveCollections.Create(FacadeRuntime.Class("mscorlib.dll","System","Type"),parameterClasses.Length));
        for(int i=0;i<parameterClasses.Length;++i){using var parameter=LiveCollections.TypeObject(parameterClasses[i]);LiveCollections.Set(types,i,parameter);}
        NativeArgument typeArray=FacadeRuntime.Reference(types);
        using var constructor=FacadeRuntime.Invoke(new("mscorlib.dll","System","Type","GetConstructor",false,false,"System.Reflection.ConstructorInfo",["System.Type[]"]),type.Token,&typeArray,1);
        if(constructor.Token==0)throw new RuntimeGatewayException(3,"exact native constructor");
        using var declaring=Property(constructor,"MemberInfo","get_DeclaringType","System.Type");
        if(LiveReflection.ClassFromTypeObject(declaring)!=klass)throw new RuntimeGatewayException(5,"constructor owner");
        using var staticValue=Property(constructor,"MethodBase","get_IsStatic","System.Boolean");
        if(FacadeRuntime.ReadValue<bool>(staticValue))throw new RuntimeGatewayException(5,"static constructor unavailable");
        using var parameters=Property(constructor,"MethodBase","GetParameters","System.Reflection.ParameterInfo[]");
        if(LiveCollections.Length(parameters)!=parameterClasses.Length)throw new RuntimeGatewayException(5,"constructor arity");
        for(int i=0;i<parameterClasses.Length;++i)
        {
            using var parameter=LiveCollections.Get(parameters,i);
            using var parameterType=Property(parameter,"ParameterInfo","get_ParameterType","System.Type");
            if(LiveReflection.ClassFromTypeObject(parameterType)!=parameterClasses[i])throw new RuntimeGatewayException(5,"constructor exact parameter class");
        }
        using var values=new RuntimeObject(LiveCollections.Create(FacadeRuntime.Class("mscorlib.dll","System","Object"),arguments.Length));
        for(int i=0;i<arguments.Length;++i){using var nullValue=arguments[i] is null?new RuntimeObject(0):null;LiveCollections.Set(values,i,arguments[i]??nullValue!);}
        NativeArgument valueArray=FacadeRuntime.Reference(values);
        try
        {
            using var created=FacadeRuntime.Invoke(new("mscorlib.dll","System.Reflection","ConstructorInfo","Invoke",false,false,"System.Object",["System.Object[]"]),constructor.Token,&valueArray,1);
            if(created.Token==0||FacadeRuntime.ObjectClass(created)!=klass)throw new RuntimeGatewayException(5,"constructor result exact class");
            return created.Detach();
        }
        catch(NativeGameException exception)
        {
            using var caught=exception.RetainNativeException();
            if(FacadeRuntime.ObjectClass(caught)==FacadeRuntime.Class("mscorlib.dll","System.Reflection","TargetInvocationException"))
            {
                using var inner=FacadeRuntime.Invoke(new("mscorlib.dll","System","Exception","get_InnerException",false,false,"System.Exception",[]),caught.Token,null,0);
                if(inner.Token!=0){exception.Dispose();throw new NativeGameException(inner.Detach(),"exact native constructor target");}
            }
            throw;
        }
    }
}
