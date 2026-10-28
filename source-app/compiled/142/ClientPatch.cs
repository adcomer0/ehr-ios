using System;
using System.Collections;
using AmongUs.Data;
using EHR.Modules;
using HarmonyLib;
using Hazel;
using InnerNet;
using TMPro;
using UnityEngine;
using static EHR.Translator;

namespace EHR;

/*[HarmonyPatch(typeof(GameStartManager), nameof(GameStartManager.MakePublic))]
internal static class MakePublicPatch
{
    public static bool Prefix()
    {
        if (ModUpdater.IsBroken || (ModUpdater.HasUpdate && ModUpdater.ForceUpdate) || !VersionChecker.IsSupported)
        {
            var message = string.Empty;
            if (!VersionChecker.IsSupported) message = GetString("UnsupportedVersion");
            if (ModUpdater.IsBroken) message = GetString("ModBrokenMessage");
            if (ModUpdater.HasUpdate) message = GetString("CanNotJoinPublicRoomNoLatest");
            Logger.Info(message, "MakePublicPatch");
            Logger.SendInGame(message, Color.red);
            return false;
        }

        return true;
    }
}*/

[HarmonyPatch(typeof(InnerNetClient), "StartRpcImmediately")]
static class StartRpcImmediatelyPatch
{
    public static void Postfix(uint targetNetId, byte callId, SendOption option, int targetClientId = -1)
    {
        if (callId is 21 or 44 or 45 or 104) return;
        Logger.Info($"Starting RPC: {callId} ({RPC.GetRpcName(callId)}) as {Main.CachedAllPlayerControls().Find(x => x.NetId == targetNetId)?.GetRealName() ?? targetNetId.ToString()} with SendOption {option} to {Utils.GetClientById(targetClientId)?.Character?.GetRealName() ?? targetClientId.ToString()}", "StartRpcImmediately");
    }

    internal static void __EHRStaticCallback_51(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        uint __ehrp0 = __ehrFrame.GetArgument<uint>("targetNetId");
        byte __ehrp1 = __ehrFrame.GetArgument<byte>("callId");
        SendOption __ehrp2 = __ehrFrame.GetArgument<SendOption>("option");
        int __ehrp3 = __ehrFrame.GetArgument<int>("targetClientId");
        try
        {
            Postfix(__ehrp0, __ehrp1, __ehrp2, __ehrp3);
        }
        finally
        {
        }
    }

}

[HarmonyPatch(typeof(MMOnlineManager), "Start")]
// ReSharper disable once InconsistentNaming
internal static class MMOnlineManagerStartPatch
{
    public static void Postfix()
    {
        if (!(ModUpdater.HasUpdate && ModUpdater.ForceUpdate || ModUpdater.IsBroken)) return;

        GameObject obj = GameObject.Find("FindGameButton");

        if (obj)
        {
            obj.SetActive(false);
            TextMeshPro textObj = Object.Instantiate(obj.transform.Find("Text_TMP").GetComponent<TextMeshPro>());
            textObj.transform.position = new(1f, -0.3f, 0);
            textObj.name = "CanNotJoinPublic";

            string message = ModUpdater.IsBroken
                ? $"<size=2>{Utils.ColorString(Color.red, GetString("ModBrokenMessage"))}</size>"
                : $"<size=2>{Utils.ColorString(Color.red, GetString("CanNotJoinPublicRoomNoLatest"))}</size>";

            LateTask.New(() => { textObj.text = message; }, 0.01f, "CanNotJoinPublic");
        }
    }

    internal static void __EHRStaticCallback_52(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        try
        {
            Postfix();
        }
        finally
        {
        }
    }

}

[HarmonyPatch(typeof(SplashManager), "Start")]
internal static class SplashLogoAnimatorPatch
{
    public static SceneChanger SceneChanger;
    
    public static void Postfix(SplashManager __instance)
    {
        SceneChanger = __instance.sceneChanger;
        Main.Instance.StartCoroutine(Coroutine());
        return;

        IEnumerator Coroutine()
        {
            while (__instance && SceneChanger && SceneChanger.loadOp == null) yield return null;
                
            if (SceneChanger) SceneChanger.AllowFinishLoadingScene();
            if (__instance) __instance.startedSceneLoad = true;

            while (!ModManager.InstanceExists) yield return null;
            
            ModManager.Instance.ShowModStamp();
        }
    }

    internal static void __EHRStaticCallback_53(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        SplashManager __ehrp0 = __ehrFrame.GetInstance<SplashManager>();
        try
        {
            Postfix(__ehrp0);
        }
        finally
        {
        }
    }

}

[HarmonyPatch(typeof(EOSManager), "IsAllowedOnline")]
internal static class RunLoginPatch
{
    public const int ClickCount = 0;

    public static void Prefix(ref bool canOnline)
    {
        if (DebugModeManager.AmDebugger) canOnline = true;
        
        if (!Main.AckdConsentPopup.Value)
        {
            canOnline = true;
        }

        try { ModUpdater.ShowAvailableUpdate(); }
        catch (Exception error) { Logger.Error(error.ToString(), "ModUpdater.ShowAvailableUpdate"); }
    }

    internal static void __EHRStaticCallback_54(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrp0 = __ehrFrame.GetArgument<bool>("canOnline");
        try
        {
            Prefix(ref __ehrp0);
        }
        finally
        {
            __ehrFrame.SetArgument("canOnline", __ehrp0);
        }
    }

}

[HarmonyPatch(typeof(BanMenu), "SetVisible")]
internal static class BanMenuSetVisiblePatch
{
    public static bool Prefix(BanMenu __instance, bool show)
    {
        if (!AmongUsClient.Instance.AmHost) return true;

        show &= PlayerControl.LocalPlayer && PlayerControl.LocalPlayer.Data != null;
        __instance.BanButton.gameObject.SetActive(AmongUsClient.Instance.CanBan());
        __instance.KickButton.gameObject.SetActive(AmongUsClient.Instance.CanKick());
        __instance.MenuButton.gameObject.SetActive(show);
        return false;
    }

    internal static void __EHRStaticCallback_55(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        BanMenu __ehrp0 = __ehrFrame.GetInstance<BanMenu>();
        bool __ehrp1 = __ehrFrame.GetArgument<bool>("show");
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0, __ehrp1);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}

[HarmonyPatch(typeof(InnerNetClient), "CanBan")]
internal static class InnerNetClientCanBanPatch
{
    public static bool Prefix(InnerNetClient __instance, ref bool __result)
    {
        __result = __instance.AmHost;
        return false;
    }

    internal static void __EHRStaticCallback_56(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        InnerNetClient __ehrp0 = __ehrFrame.GetInstance<InnerNetClient>();
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

[HarmonyPatch(typeof(InnerNetClient), "KickPlayer")]
internal static class KickPlayerPatch
{
    public static bool Prefix( /*InnerNetClient __instance,*/ int clientId, bool ban)
    {
        if (!AmongUsClient.Instance.AmHost && !OnGameJoinedPatch.JoiningGame) return true;

        if (AmongUsClient.Instance.ClientId == clientId)
        {
            Logger.SendInGame($"Game Attempting to {(ban ? "Ban" : "Kick")} Host, Blocked the attempt.", Color.red);
            return false;
        }

        if (ban) BanManager.AddBanPlayer(AmongUsClient.Instance.GetRecentClient(clientId));

        return true;
    }

    internal static void __EHRStaticCallback_57(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetArgument<int>("clientId");
        bool __ehrp1 = __ehrFrame.GetArgument<bool>("ban");
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0, __ehrp1);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}

[HarmonyPatch(typeof(ResolutionManager), "SetResolution")]
internal static class SetResolutionManager
{
    public static void Postfix()
    {
        if (MainMenuManagerPatch.UpdateButton)
            MainMenuManagerPatch.UpdateButton.transform.localPosition = MainMenuManagerPatch.Template.transform.localPosition + new Vector3(0.25f, 0.75f);
    }

    internal static void __EHRStaticCallback_58(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        try
        {
            Postfix();
        }
        finally
        {
        }
    }

}

[HarmonyPatch(typeof(InnerNetClient), "SendAllStreamedObjects")]
internal static class InnerNetObjectSerializePatch
{
    public static void Prefix()
    {
        if (!AmongUsClient.Instance.AmHost || GameOptionsSender.ActiveCoroutine != null) return;
        GameOptionsSender.ActiveCoroutine = Main.Instance.StartCoroutine(GameOptionsSender.SendDirtyGameOptionsContinuously());
    }

    internal static void __EHRStaticCallback_59(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        try
        {
            Prefix();
        }
        finally
        {
        }
    }

}

// https://github.com/Rabek009/MoreGamemodes/blob/master/Patches/ClientPatch.cs
[HarmonyPatch(typeof(AmongUsClient), "CheckOnlinePermissions")]
static class CheckOnlinePermissionsPatch
{
    public static void Prefix()
    {
        DataManager.Player.Ban.banPoints = 0f;
    }

    internal static void __EHRStaticCallback_60(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        try
        {
            Prefix();
        }
        finally
        {
        }
    }

}