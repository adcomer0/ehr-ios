using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated;

internal static unsafe class SettingsSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_settings_self_test")]
    internal static int Run(int* output,nuint count)
    {
        if(output==null||count!=4)return 4;
        for(int i=0;i<4;++i)output[i]=0;
        try
        {
            // A new, unregistered options object; the active game/lobby settings
            // are never retrieved or changed. ILogger constructor input is null.
            ulong klass=FacadeRuntime.Class("Assembly-CSharp.dll","AmongUs.GameOptions","NormalGameOptionsV12");
            using var created=LiveReflection.Construct(klass,[null]);
            using var options=new AmongUs_GameOptions_IGameOptions(created.Detach());
            options.SetInt(AmongUs_GameOptions_Int32OptionNames.NumImpostors,2);
            bool integer=options.TryGetInt(AmongUs_GameOptions_Int32OptionNames.NumImpostors,out int intValue)&&intValue==2;
            options.SetFloat(AmongUs_GameOptions_FloatOptionNames.PlayerSpeedMod,1.25f);
            bool floating=options.TryGetFloat(AmongUs_GameOptions_FloatOptionNames.PlayerSpeedMod,out float floatValue)&&floatValue==1.25f;
            options.SetByte(AmongUs_GameOptions_ByteOptionNames.MapId,1);
            bool bytes=options.TryGetByte(AmongUs_GameOptions_ByteOptionNames.MapId,out byte byteValue)&&byteValue==1;
            options.SetBool(AmongUs_GameOptions_BoolOptionNames.VisualTasks,true);
            bool booleans=options.TryGetBool(AmongUs_GameOptions_BoolOptionNames.VisualTasks,out bool boolValue)&&boolValue;
            options.SetBool(AmongUs_GameOptions_BoolOptionNames.VisualTasks,false);
            booleans=booleans&&options.TryGetBool(AmongUs_GameOptions_BoolOptionNames.VisualTasks,out boolValue)&&!boolValue;
            output[2]=integer&&floating&&bytes&&booleans?1:0;
            output[3]=5; // five typed out calls completed on that real test object
            output[0]=output[2];return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}
        catch{return output[1]=6;}
    }
}
