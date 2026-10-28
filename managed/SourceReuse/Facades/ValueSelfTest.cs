using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class ValueSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_value_self_test")]
    internal static int Run(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;
        for(int i=0;i<6;++i)output[i]=0;
        try
        {
            var original=new UnityEngine_Vector2(3,4);
            var copy=original;
            copy.x=8;
            output[2]=original.x==3&&original.y==4&&copy.x==8&&copy.y==4?1:0;
            var normalized=original;
            normalized.Normalize();
            output[3]=original.x==3&&original.y==4&&Math.Abs(normalized.magnitude-1)<0.00001f?1:0;
            var zero=default(UnityEngine_Vector2);
            var anotherZero=new UnityEngine_Vector2(0,0);
            output[4]=zero==anotherZero&&zero.Equals(anotherZero)&&zero.GetHashCode()==anotherZero.GetHashCode()?1:0;
            output[5]=UnityEngine_Vector2.Distance(original,anotherZero)==5?1:0;
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;
            return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}
        catch{return output[1]=6;}
    }
}
