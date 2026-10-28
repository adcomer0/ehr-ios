using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class ReferenceOutSelfTest
{
    private static readonly BindingSpec parse=new("mscorlib.dll","System","Version","TryParse",true,false,"System.Boolean",["System.String","System.Version&"]);
    private static int Part(RuntimeObject version,string name)
    {using var result=FacadeRuntime.Invoke(new("mscorlib.dll","System","Version",name,false,false,"System.Int32",[]),version.Token,null,0);return FacadeRuntime.ReadValue<int>(result);}
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_reference_out_self_test")]
    internal static int SelfTest(int* output,nuint count)
    {
        if(output==null||count!=7)return 4;for(int i=0;i<7;++i)output[i]=0;
        try
        {
            using var text=FacadeRuntime.String("1.2.3");using var nullValue=new RuntimeObject(0);
            using(var invocation=NativeReflectedCall.Invoke(parse,0,[text,nullValue]))
            {
                using var parsed=invocation.TakeResult();using var version=invocation.Argument(1);
                output[2]=FacadeRuntime.ReadValue<bool>(parsed)&&version.Token!=0&&FacadeRuntime.ObjectClass(version)==FacadeRuntime.Class("mscorlib.dll","System","Version")?1:0;
                output[3]=Part(version,"get_Major");output[4]=Part(version,"get_Minor");output[5]=Part(version,"get_Build");
            }
            using var invalid=FacadeRuntime.String("not-a-version");
            using(var invocation=NativeReflectedCall.Invoke(parse,0,[invalid,nullValue]))
            {
                using var parsed=invocation.TakeResult();using var version=invocation.Argument(1);
                output[6]=!FacadeRuntime.ReadValue<bool>(parsed)&&version.Token==0?1:0;
            }
            output[0]=output[2]==1&&output[3]==1&&output[4]==2&&output[5]==3&&output[6]==1?1:0;
            return output[1]=output[0]==1?0:5;
        }
        catch(NativeGameException error){using(error){return output[1]=6;}}
        catch(RuntimeGatewayException error){return output[1]=error.Status;}catch{return output[1]=6;}
    }
}
