using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class ObjectSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_object_self_test")]
    internal static int Run(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;
        for(int i=0;i<6;++i)output[i]=0;
        try
        {
            using var list=new Il2CppSystem.Collections.Generic.List<int>();list.Add(41);
            using var iteratorObject=FacadeRuntime.Invoke(new("mscorlib.dll","System.Collections","IEnumerable","GetEnumerator",false,false,"System.Collections.IEnumerator",[]),list.Token,null,0);
            using var iterator=new Il2CppSystem.Collections.IEnumerator(iteratorObject.Detach());
            bool began=iterator.MoveNext();
            using(var current=iterator.Current)
                output[2]=began&&current is not null&&FacadeRuntime.ReadValue<int>(current)==41?1:0;
            bool ended=!iterator.MoveNext();iterator.Reset();
            output[3]=ended&&iterator.MoveNext()?1:0;
            ulong klass=FacadeRuntime.Class("Assembly-CSharp.dll","AmongUs.GameOptions","NormalGameOptionsV12");
            using var created=LiveReflection.Construct(klass,[null]);
            using var generic=new Il2CppSystem.Object(created.Detach());
            using var options=generic.TryCast<AmongUs_GameOptions_IGameOptions>();
            using var exact=generic.TryCast<AmongUs_GameOptions_NormalGameOptionsV12>();
            using var wrong=generic.TryCast<PlayerControl>();
            output[4]=options is not null&&exact is not null&&wrong is null&&NativeLifetime.Same(generic,exact)?1:0;
            // Native IList.get_Item invokes the managed getter and throws.
            // Array gateway bounds checks would stop earlier with BAD_ARGUMENT.
            try{_ = list[99];}
            catch(NativeGameException exception)
            {
                using(exception)
                using(var retained=exception.RetainNativeException())
                    output[5]=retained.Token!=0&&FacadeRuntime.TokenIsValid(retained.Token)?1:0;
            }
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;
            return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}
        catch{return output[1]=6;}
    }
}
