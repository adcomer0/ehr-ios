using HarmonyLib;

namespace EHR;

[HarmonyPatch(typeof(LogicGameFlowNormal), "IsGameOverDueToDeath")]
internal class DontBlackoutPatch
{
    public static void Postfix(ref bool __result)
    {
        __result = false;
    }

    internal static void __EHRStaticCallback_215(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrp0 = __ehrFrame.GetResult<bool>();
        try
        {
            Postfix(ref __ehrp0);
        }
        finally
        {
            __ehrFrame.Result = __ehrp0;
        }
    }

}