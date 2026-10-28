using System;
using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Text;
using System.Text.RegularExpressions;
using HarmonyLib;
using InnerNet;
using UnityEngine;
using UnityEngine.Networking;

#if IL2CPP
using System.Text.Json;
#else
using Newtonsoft.Json.Linq;
#endif

namespace EHR.Modules;

// The optional EHR directory is unavailable in the account-protected profile.
// Keep this original public surface for unrelated lifecycle callers. There is
// no credential read, HTTP request, token, queue or external response parser.
public static class LobbySharingAPI
{
    public static long LastRequestTimeStamp;
    public static string LastRoomCode = string.Empty;
    public static void NotifyLobbyStatusChanged(LobbyStatus status) { }
}


[SuppressMessage("ReSharper", "InconsistentNaming")]
public enum LobbyStatus
{
    In_Lobby,
    In_Game,
    Ended,
    Closed
}

[HarmonyPatch(typeof(InnerNetClient), "DisconnectInternal")]
internal static class ExitGamePatch
{
    public static void Prefix(InnerNetClient __instance, DisconnectReasons reason)
    {
        if (__instance is not AmongUsClient) return;

        Logger.Msg($"Exiting game - reason: {reason}", "ExitGamePatch.Prefix");

        GameStates.InGame = false;
        GameEndChecker.LoadingEndScreen = false;
        DataFlagRateLimiter.DropQueue();

        if (SetUpRoleTextPatch.IsInIntro)
        {
            SetUpRoleTextPatch.IsInIntro = false;
            Utils.NotifyRoles(ForceLoop: true);
        }

        if (GameSettingMenu.Instance)
            GameSettingMenuPatch.Close_Prefix();
    }

    public static void Postfix(InnerNetClient __instance)
    {
        if (__instance is not AmongUsClient) return;

        LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.Closed);

        GameEndChecker.LoadingEndScreen = false;
    }

    internal static void __EHRStaticCallback_12(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        InnerNetClient __ehrp0 = __ehrFrame.GetInstance<InnerNetClient>();
        DisconnectReasons __ehrp1 = __ehrFrame.GetArgument<DisconnectReasons>("reason");
        try
        {
            Prefix(__ehrp0, __ehrp1);
        }
        finally
        {
        }
    }


    internal static void __EHRStaticCallback_13(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        InnerNetClient __ehrp0 = __ehrFrame.GetInstance<InnerNetClient>();
        try
        {
            Postfix(__ehrp0);
        }
        finally
        {
        }
    }

}
