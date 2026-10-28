using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class GenericGameMethodsSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_generic_game_methods_self_test")]
    internal static int SelfTest(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;for(int i=0;i<6;++i)output[i]=0;
        try
        {
            ulong game=FacadeRuntime.Class("Assembly-CSharp.dll","","MatchMaker");
            output[2]=NativeGenericMethods.Lookup(game,"Connecting","System.Boolean",["!!0"],[ElementCodecs.Get<CreateGameOptions>().NativeClass()],false)!=0?1:0;
            output[3]=NativeGenericMethods.Lookup(FacadeRuntime.Class("Assembly-CSharp.dll","","PlayerTask"),"PlayerHasTaskOfType","System.Boolean",["PlayerControl"],[ElementCodecs.Get<HudOverrideTask>().NativeClass()],true)!=0?1:0;
            output[4]=NativeGenericMethods.Lookup(FacadeRuntime.Class("Assembly-CSharp.dll","","ObjectPoolBehavior"),"Get","!!0",[],[ElementCodecs.Get<ServerListButton>().NativeClass()],false)!=0?1:0;
            using Il2CppSystem.Object? native="host\0\U0001F680";
            Il2CppSystem.Object? nil=(string?)null;
            output[5]=native!=null&&FacadeRuntime.ObjectClass(native)==FacadeRuntime.Class("mscorlib.dll","System","String")&&native.ToString()=="host\0\U0001F680"&&nil==null?1:0;
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;
            return output[1]=output[0]==1?0:5;
        }
        catch(NativeGameException error){using(error){return output[1]=6;}}
        catch(RuntimeGatewayException error){return output[1]=error.Status;}catch{return output[1]=6;}
    }
}
