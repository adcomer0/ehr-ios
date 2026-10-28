using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct MethodsTable
{
    internal uint AbiVersion,ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> MethodObject;
    internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> MethodFromObject;
    internal delegate* unmanaged[Cdecl]<ulong,ulong*,nuint,ulong*,ulong*,int> MakeGenericMethod;
}
internal static unsafe class NativeMethods
{
    private static MethodsTable table;
    private static bool bound;
    internal static int LastLookupStep { get; private set; }
    private static readonly Dictionary<string,ulong> cache=new(StringComparer.Ordinal);
    private static RuntimeObject Property(RuntimeObject instance,string owner,string name,string resultType)
        =>FacadeRuntime.Invoke(new("mscorlib.dll","System.Reflection",owner,name,false,false,resultType,[]),instance.Token,null,0);
    internal static ulong Lookup(ulong owner,string name,ReadOnlySpan<ulong> parameterClasses,ulong resultClass,bool isStatic)
    {
        LastLookupStep=1;
        if(!bound)throw new RuntimeGatewayException(1,"method reflection extensions not bound");
        string key=owner+"/"+name+"/"+resultClass+"/"+isStatic+"/"+string.Join(",",parameterClasses.ToArray());
        if(cache.TryGetValue(key,out ulong cached))return cached;
        using var type=LiveCollections.TypeObject(owner);
        using var nameObject=FacadeRuntime.String(name);
        using var parameters=new RuntimeObject(LiveCollections.Create(FacadeRuntime.Class("mscorlib.dll","System","Type"),parameterClasses.Length));
        for(int i=0;i<parameterClasses.Length;++i)
        {using var parameter=LiveCollections.TypeObject(parameterClasses[i]);LiveCollections.Set(parameters,i,parameter);}
        NativeArgument* arguments=stackalloc NativeArgument[2];arguments[0]=FacadeRuntime.Reference(nameObject);arguments[1]=FacadeRuntime.Reference(parameters);
        using var reflected=FacadeRuntime.Invoke(new("mscorlib.dll","System","Type","GetMethod",false,false,"System.Reflection.MethodInfo",["System.String","System.Type[]"]),type.Token,arguments,2);
        LastLookupStep=2;
        if(reflected.Token==0)throw new RuntimeGatewayException(3,"exact reflected method "+name);
        LastLookupStep=3;
        using var returnType=Property(reflected,"MethodInfo","get_ReturnType","System.Type");
        if(LiveReflection.ClassFromTypeObject(returnType)!=resultClass)throw new RuntimeGatewayException(5,"reflected method return class");
        LastLookupStep=4;
        using var declaringType=Property(reflected,"MemberInfo","get_DeclaringType","System.Type");
        if(LiveReflection.ClassFromTypeObject(declaringType)!=owner)throw new RuntimeGatewayException(5,"reflected method owning class");
        LastLookupStep=5;
        using var staticValue=Property(reflected,"MethodBase","get_IsStatic","System.Boolean");
        if(FacadeRuntime.ReadValue<bool>(staticValue)!=isStatic)throw new RuntimeGatewayException(5,"reflected method staticness");
        LastLookupStep=6;
        ulong method=0;FacadeRuntime.Require(table.MethodFromObject(reflected.Token,&method),"convert reflected exact method");
        cache.Add(key,method);return method;
    }
    internal static ulong MakeGeneric(ulong open,ReadOnlySpan<ulong> classes)
    {
        if(!bound)throw new RuntimeGatewayException(1,"method reflection extensions not bound");
        ulong result=0,exception=0;int status;
        fixed(ulong* arguments=classes)status=table.MakeGenericMethod(open,arguments,(nuint)classes.Length,&result,&exception);
        FacadeRuntime.CheckManaged(status,exception,"inflate real generic method");return result;
    }
    internal static ulong FromObject(RuntimeObject reflected)
    {
        if(!bound)throw new RuntimeGatewayException(1,"method reflection extensions not bound");
        ulong method=0;FacadeRuntime.Require(table.MethodFromObject(reflected.Token,&method),"convert validated reflected method");return method;
    }
    internal static RuntimeObject ToObject(ulong method)
    {
        if(!bound)throw new RuntimeGatewayException(1,"method reflection extensions not bound");
        ulong reflected=0;FacadeRuntime.Require(table.MethodObject(method,&reflected),"reflect actual method metadata");return new(reflected);
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_methods")]
    internal static int Bind(MethodsTable* source,nuint size)
    {
        if(source==null||size!=(nuint)sizeof(MethodsTable)||source->AbiVersion!=1||source->ByteSize!=sizeof(MethodsTable)||source->MethodObject==null||source->MethodFromObject==null||source->MakeGenericMethod==null)return 4;
        table=*source;cache.Clear();NativeGenericMethods.Reset();bound=true;return 0;
    }
}
internal static unsafe class NativeSingletons
{
    internal static ulong Class<T>()=>LiveReflection.MakeGenericClass(FacadeRuntime.Class("Assembly-CSharp.dll","","DestroyableSingleton`1"),[ElementCodecs.Get<T>().NativeClass()]);
    internal static T? Instance<T>() where T:RuntimeObject
    {
        ulong method=NativeMethods.Lookup(Class<T>(),"get_Instance",[],ElementCodecs.Get<T>().NativeClass(),true);
        return (T?)ElementCodecs.Get<T>().Read(FacadeRuntime.InvokeResolved(method,0,null,0));
    }
    internal static bool Exists<T>() where T:RuntimeObject
    {
        ulong method=NativeMethods.Lookup(Class<T>(),"get_InstanceExists",[],ElementCodecs.Get<bool>().NativeClass(),true);
        using var result=FacadeRuntime.InvokeResolved(method,0,null,0);return FacadeRuntime.ReadValue<bool>(result);
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_singleton_self_test")]
    internal static int SelfTest(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;for(int i=0;i<6;++i)output[i]=0;
        try
        {
            // Metadata-only validation of both real getters on the closed
            // singleton type. Instance is called only when it already exists.
            ulong klass=Class<ServerManager>();
            ulong method=NativeMethods.Lookup(klass,"get_Instance",[],ElementCodecs.Get<ServerManager>().NativeClass(),true);
            output[2]=method!=0?1:0;
            bool exists=DestroyableSingleton<ServerManager>.InstanceExists;
            output[3]=exists?1:0;output[4]=0;output[5]=2; // skipped if no existing singleton
            if(exists)
            {
                using var actual=DestroyableSingleton<ServerManager>.Instance;
                output[4]=1;output[5]=actual is not null&&FacadeRuntime.TokenIsValid(actual.Token)?1:0;
            }
            output[0]=output[2]==1&&(output[5]==1||output[5]==2)?1:0;return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){if(output[2]==0)output[2]=-NativeMethods.LastLookupStep;return output[1]=exception.Status;}catch{return output[1]=6;}
    }
}
