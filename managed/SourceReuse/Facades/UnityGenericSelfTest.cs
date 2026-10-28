using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class UnityGenericSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_unity_generic_self_test")]
    internal static int Run(int* output,nuint count)
    {
        if(output==null||count!=8)return 4;for(int i=0;i<8;++i)output[i]=0;
        UnityEngine_GameObject? source=null,clone=null;int status=0;
        try
        {
            output[2]=1;source=new UnityEngine_GameObject("EHRLiveFacadeIndependentProbe");
            using var transform=source.transform;
            if(transform is null)throw new RuntimeGatewayException(5,"independent object Transform");
            output[2]=2;using var found=source.GetComponent<UnityEngine_Transform>();
            output[3]=found is not null&&found.Equals(transform)?1:0;
            output[2]=3;using var componentFound=transform.GetComponent<UnityEngine_Transform>();
            output[4]=componentFound is not null&&componentFound.Equals(transform)?1:0;
            output[2]=4;using var children=source.GetComponentsInChildren<UnityEngine_Transform>(true);
            if(children is not null&&children.Length==1)
            {
                using var first=children[0];
                output[5]=first is not null&&first.Equals(transform)&&FacadeRuntime.ObjectClass(children)==NativeTypeNames.VectorClass(ElementCodecs.Get<UnityEngine_Transform>().NativeClass())?1:0;
            }
            output[2]=5;clone=UnityEngine_Object.Instantiate<UnityEngine_GameObject>(source);
            output[6]=clone is not null&&!clone.Equals(source)&&FacadeRuntime.ObjectClass(clone)==ElementCodecs.Get<UnityEngine_GameObject>().NativeClass()?1:0;
            output[2]=6;
            if(clone is not null){using var cloneTransform=clone.GetComponent<UnityEngine_Transform>();output[7]=cloneTransform is not null&&!cloneTransform.Equals(transform)?1:0;}
        }
        catch(RuntimeGatewayException exception){status=exception.Status;}
        catch{status=6;}
        finally
        {
            // Request normal engine destruction only for these two independent
            // objects; facade disposal releases roots, not Unity ownership.
            try {if(clone is not null)UnityEngine_Object.Destroy(clone);}
            catch(RuntimeGatewayException exception){status=exception.Status;}catch{status=6;}
            finally{clone?.Dispose();}
            try {if(source is not null)UnityEngine_Object.Destroy(source);}
            catch(RuntimeGatewayException exception){status=exception.Status;}catch{status=6;}
            finally{source?.Dispose();}
        }
        output[0]=status==0&&output[3]==1&&output[4]==1&&output[5]==1&&output[6]==1&&output[7]==1?1:0;
        return output[1]=status!=0?status:output[0]==1?0:5;
    }
}
