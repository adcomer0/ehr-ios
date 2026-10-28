using AmongUs.GameOptions;
using EHR.Modules;
using HarmonyLib;

namespace EHR.Patches;

[HarmonyPatch(typeof(GameOptionsManager), "SwitchGameMode")]
internal static class SwitchGameModePatch
{
    private static bool Warned;

    public static bool Prefix(GameModes gameMode)
    {
        if (!Options.IsLoaded || AmongUsClient.Instance != null && !AmongUsClient.Instance.AmHost && PlayerControl.LocalPlayer != null || gameMode != GameModes.HideNSeek || Warned || !HudManager.Instance) return true;

        ModUpdater.ShowPopup(Translator.GetString("HnSUnloadWarning"), StringNames.OkayDontShow, true, false);
        return false;
    }

    public static void Postfix(GameModes gameMode)
    {
        if (!Options.IsLoaded || !AmongUsClient.Instance.AmHost && PlayerControl.LocalPlayer != null || gameMode != GameModes.HideNSeek) return;

        if (!Warned)
        {
            Warned = true;
            return;
        }

        if (ErrorText.Instance != null)
        {
            ErrorText.Instance.HnSFlag = true;
            ErrorText.Instance.AddError(ErrorCode.HnsUnload);
        }

        Zoom.SetZoomSize(reset: true);
        AmciRegistration.Revert();
        EHRStaticPatchCatalog.Registration.DisableOwner("com.gurge44.endlesshostroles");
#if IL2CPP
        Main.Instance.Unload();
#else
        Object.Destroy(Main.Instance.gameObject);
#endif
    }

    internal static void __EHRStaticCallback_128(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameModes __ehrp0 = __ehrFrame.GetArgument<GameModes>("gameMode");
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


    internal static void __EHRStaticCallback_129(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameModes __ehrp0 = __ehrFrame.GetArgument<GameModes>("gameMode");
        try
        {
            Postfix(__ehrp0);
        }
        finally
        {
        }
    }

}