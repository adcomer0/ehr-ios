using HarmonyLib;

namespace EHR;

internal class GuardAngelPatch
{
    [HarmonyPatch(typeof(MeetingIntroAnimation), "Start")]
    public static class ProtectedRecentlyPatch
    {
        public static bool Prefix(MeetingIntroAnimation __instance)
        {
            __instance.ProtectedRecently.SetActive(false);
            __instance.ProtectedRecently.transform.localPosition = new(100f, 100f, 100f);
            __instance.ProtectedRecentlySound = new();
            return true;
        }
    
    internal static void __EHRStaticCallback_140(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        MeetingIntroAnimation __ehrp0 = __ehrFrame.GetInstance<MeetingIntroAnimation>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}
}