using System;
namespace EHR.Generated;
// Reflection's actual Object[] performs managed byref transport, including
// structs containing references. No native payload layout enters this process.
internal sealed unsafe class NativeReflectedCall : IDisposable
{
    private readonly RuntimeObject arguments,result;
    private NativeReflectedCall(RuntimeObject arguments,RuntimeObject result){this.arguments=arguments;this.result=result;}
    internal RuntimeObject Argument(int index)=>LiveCollections.Get(arguments,index);
    internal RuntimeObject TakeResult()=>new(result.Detach());
    public void Dispose(){result.Dispose();arguments.Dispose();}
    internal static NativeReflectedCall Invoke(BindingSpec spec,ulong instance,RuntimeObject[] values)
        =>InvokeResolved(FacadeRuntime.Resolve(spec),instance,values);
    internal static NativeReflectedCall InvokeResolved(ulong methodToken,ulong instance,RuntimeObject[] values)
    {
        using var method=NativeMethods.ToObject(methodToken);
        var array=new RuntimeObject(LiveCollections.Create(FacadeRuntime.Class("mscorlib.dll","System","Object"),values.Length));
        try
        {
            for(int i=0;i<values.Length;++i)LiveCollections.Set(array,i,values[i]);
            using var target=instance==0?new RuntimeObject(0):FacadeRuntime.RetainToken(instance);
            NativeArgument* invokeArguments=stackalloc NativeArgument[2];invokeArguments[0]=FacadeRuntime.Reference(target);invokeArguments[1]=FacadeRuntime.Reference(array);
            var result=FacadeRuntime.Invoke(new("mscorlib.dll","System.Reflection","MethodBase","Invoke",false,false,"System.Object",["System.Object","System.Object[]"]),method.Token,invokeArguments,2);
            return new(array,result);
        }
        catch(NativeGameException exception)
        {
            array.Dispose();
            using var caught=exception.RetainNativeException();
            if(FacadeRuntime.ObjectClass(caught)==FacadeRuntime.Class("mscorlib.dll","System.Reflection","TargetInvocationException"))
            {
                using var inner=FacadeRuntime.Invoke(new("mscorlib.dll","System","Exception","get_InnerException",false,false,"System.Exception",[]),caught.Token,null,0);
                if(inner.Token!=0){exception.Dispose();throw new NativeGameException(inner.Detach(),"reflected native target");}
            }
            throw;
        }
        catch{array.Dispose();throw;}
    }
}
