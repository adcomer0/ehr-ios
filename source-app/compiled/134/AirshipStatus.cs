using HarmonyLib;

namespace EHR;

// From: https://github.com/yukieiji/ExtremeRoles/blob/master/ExtremeRoles/Patches/AirshipStatusPatch.cs
[HarmonyPatch(typeof(AirshipStatus), "PrespawnStep")]
public static class AirshipStatusPrespawnStepPatch
{
    public static bool Prefix()
    {
        return !PlayerControl.LocalPlayer.Is(CustomRoles.GM);
    }

    internal static void __EHRStaticCallback_26(global::EHR.EHRStaticPatchFrame __ehrFrame)
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