using System;
using System.Runtime.InteropServices;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
namespace EHR.Generated;
internal static unsafe class NativeParams
{
    internal static Il2CppReferenceArray<Il2CppSystem.Object>? Create(object?[]? values)
    {
        if(values is null)return null;
        var array=new Il2CppReferenceArray<Il2CppSystem.Object>(values.Length);
        try
        {
            for(int i=0;i<values.Length;++i)
            {
                object? value=values[i];
                using var boxed=value is null?new RuntimeObject(0):value is RuntimeObject reference?FacadeRuntime.Retain(reference):value is INativeValue native?FacadeRuntime.Retain(native.NativeBox):ElementCodecs.Get(value.GetType()).Box(value);
                LiveCollections.Set(array,i,boxed);
            }
            return array;
        }
        catch{array.Dispose();throw;}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_params_self_test")]
    internal static int SelfTest(int* output,nuint count)
    {
        if(output==null||count!=4)return 4;for(int i=0;i<4;++i)output[i]=0;
        try
        {
            using var values=Create([17,"A\0\U0001F680"]);
            using var format=FacadeRuntime.String("{0}|{1}");
            NativeArgument* arguments=stackalloc NativeArgument[2];arguments[0]=FacadeRuntime.Reference(format);arguments[1]=FacadeRuntime.Reference(values);
            using var result=FacadeRuntime.Invoke(new("mscorlib.dll","System","String","Format",true,false,"System.String",["System.String","System.Object[]"]),0,arguments,2);
            output[2]=FacadeRuntime.ReadString(result)=="17|A\0\U0001F680"?1:0;
            using var empty=Create([null,true,2.5f]);
            using var first=LiveCollections.Get(empty!,0);using var second=LiveCollections.Get(empty!,1);using var third=LiveCollections.Get(empty!,2);
            output[3]=first.Token==0&&FacadeRuntime.ReadValue<bool>(second)&&FacadeRuntime.ReadValue<float>(third)==2.5f?1:0;
            output[0]=output[2]==1&&output[3]==1?1:0;return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
    }
}
