using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class PredicateSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_predicate_self_test")]
    internal static int Run(int* output,nuint count)
    {
        if(output==null||count!=5)return 4;for(int i=0;i<5;++i)output[i]=0;
        try
        {
            using var list=new Il2CppSystem.Collections.Generic.List<int>();list.Add(1);list.Add(2);list.Add(3);
            output[2]=list.Find(x=>x==2)==2&&list.Exists(x=>x>2)&&list.TrueForAll(x=>x>0)&&!list.Exists(x=>x<0)?1:0;
            using var selected=list.FindAll(x=>x%2==1);
            using var selectedArray=selected.ToArray();
            output[3]=selected.Count==2&&selectedArray[0]==1&&selectedArray[1]==3?1:0;
            int sum=0;list.ForEach(x=>sum+=x);
            try{list.ForEach(x=>{if(x==1)list.Add(4);});}
            catch(InvalidOperationException){output[4]=sum==6&&list.Count==4?1:0;}
            output[0]=output[2]==1&&output[3]==1&&output[4]==1?1:0;return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
    }
}
