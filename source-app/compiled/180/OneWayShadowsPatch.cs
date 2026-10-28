using HarmonyLib;

namespace EHR;

[HarmonyPatch(typeof(OneWayShadows), "IsIgnored")]
public static class OneWayShadowsIsIgnoredPatch
{
    public static bool Prefix(OneWayShadows __instance, ref bool __result)
    {
        if (__instance.IgnoreImpostor && Main.ResetCamPlayerList.Contains(PlayerControl.LocalPlayer.PlayerId))
        {
            __result = true;
            return false;
        }

        return true;
    }

    internal static void __EHRStaticCallback_221(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        OneWayShadows __ehrp0 = __ehrFrame.GetInstance<OneWayShadows>();
        bool __ehrp1 = __ehrFrame.GetResult<bool>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0, ref __ehrp1);
        }
        finally
        {
            __ehrFrame.Result = __ehrp1;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}