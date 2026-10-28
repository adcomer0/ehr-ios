using HarmonyLib;

namespace EHR.Patches;
// https://github.com/tukasa0001/TownOfHost/blob/main/Patches/ActionButtonPatch.cs

[HarmonyPatch(typeof(SabotageButton), "DoClick")]
public static class SabotageButtonDoClickPatch
{
    public static bool Prefix()
    {
        if (!PlayerControl.LocalPlayer.inVent && GameManager.Instance.SabotagesEnabled() && HudManager.InstanceExists)
        {
            HudManager.Instance.ToggleMapVisible(new()
            {
                Mode = MapOptions.Modes.Sabotage
            });
        }

        return false;
    }

    internal static void __EHRStaticCallback_274(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix();
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}