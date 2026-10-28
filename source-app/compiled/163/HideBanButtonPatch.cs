using HarmonyLib;

namespace EHR;

[HarmonyPatch(typeof(ChatController), "Toggle")]
internal class CancelBanMenuStuckPatch
{
    public static void Prefix(ChatController __instance)
    {
        if (__instance.IsOpenOrOpening && !__instance.IsAnimating) __instance.banButton.SetVisible(false);
    }

    internal static void __EHRStaticCallback_146(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        ChatController __ehrp0 = __ehrFrame.GetInstance<ChatController>();
        try
        {
            Prefix(__ehrp0);
        }
        finally
        {
        }
    }

}