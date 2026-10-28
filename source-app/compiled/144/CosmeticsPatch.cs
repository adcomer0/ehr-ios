using HarmonyLib;

namespace EHR.Patches;

public static class CosmeticsPatch
{
    [HarmonyPatch(typeof(HatManager), "CheckLongModeValidCosmetic")]
    internal class CheckLongModeValidCosmeticPatch
    {
        public static bool Prefix(ref bool __result)
        {
            __result = true;
            return false;
        }
    
    internal static void __EHRStaticCallback_64(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrp0 = __ehrFrame.GetResult<bool>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(ref __ehrp0);
        }
        finally
        {
            __ehrFrame.Result = __ehrp0;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}
}