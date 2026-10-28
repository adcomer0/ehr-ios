using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class ConstructorSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_constructor_self_test")]
    internal static int SelfTest(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;for(int i=0;i<6;++i)output[i]=0;
        try
        {
            using var wait=new UnityEngine_WaitForSecondsRealtime(1.25f);
            using var duration=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine","WaitForSecondsRealtime","get_waitTime",false,false,"System.Single",[]),wait.Token,null,0);
            output[2]=FacadeRuntime.ReadValue<float>(duration)==1.25f?1:0;
            ulong waitClass=FacadeRuntime.Class("UnityEngine.CoreModule.dll","UnityEngine","WaitForSecondsRealtime");
            output[3]=FacadeRuntime.ObjectClass(wait)==waitClass?1:0;
            using var wrongArgument=ElementCodecs.Get<int>().Box(1);
            try { using var invalid=new RuntimeObject(NativeConstructors.Create(waitClass,[ElementCodecs.Get<int>().NativeClass()],[wrongArgument])); }
            catch(RuntimeGatewayException exception) when(exception.Status==3||exception.Status==5){output[4]=1;}
            // List's negative-capacity constructor throws inside the actual
            // runtime. Expose the original exception, not reflection's wrapper.
            using var negative=ElementCodecs.Get<int>().Box(-1);
            try { using var invalid=new RuntimeObject(NativeConstructors.Create(LiveReflection.ListClass<int>(),[ElementCodecs.Get<int>().NativeClass()],[negative])); }
            catch(NativeGameException exception)
            {
                using var actual=exception.RetainNativeException();
                output[5]=FacadeRuntime.ObjectClass(actual)==FacadeRuntime.Class("mscorlib.dll","System","ArgumentOutOfRangeException")?1:0;
                exception.Dispose();
            }
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
    }
}
