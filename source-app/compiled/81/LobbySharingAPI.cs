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

// Opt-in directory: native sign-in/ownership gate defaults to deny.
public static class LobbySharingAPI
{
    public static long LastRequestTimeStamp;
    public static string LastRoomCode = string.Empty;
    private static Session? current;
    private static ulong nextGeneration;
    private static bool verifying;
    private static long nextRequestAt;
    private const long MinimumSpacing = 5000, RetrySpacing = 30000;

    private sealed record Snapshot(int GameId, int ClientId, uint NetId, byte PlayerId,
        string Room, string Region, string Language, string Host, string Map, string Mode, int Players, int Maximum);
    private sealed class Session(ulong generation, Snapshot snapshot, LobbyStatus status)
    {
        internal readonly ulong Generation = generation;
        internal readonly Snapshot Identity = snapshot;
        internal LobbyStatus Desired = status, Sent;
        internal Snapshot Latest = snapshot;
        internal string? Token;
        internal bool Running, Dirty = true;
    }

    private static bool Enabled => EHRDirectoryGate.Allowed && Options.PostLobbyCodeToEHRWebsite.GetBool();
    private static string Number(int value) => value.ToString(System.Globalization.CultureInfo.InvariantCulture);
    private static bool Same(Snapshot a, Snapshot b) => a.GameId == b.GameId && a.ClientId == b.ClientId && a.NetId == b.NetId && a.PlayerId == b.PlayerId && a.Room == b.Room && a.Region == b.Region;
    private static bool SameListing(Snapshot a, Snapshot b) => a.Players == b.Players && a.Maximum == b.Maximum && a.Map == b.Map && a.Mode == b.Mode;
    private static void Reset()
    {
        if (current != null) current.Token = null;
        current = null; LastRoomCode = string.Empty;
    }
    private static Snapshot? Capture()
    {
        if (!Enabled || GameStates.CurrentServerType != GameStates.ServerType.Vanilla) return null;
        var client = AmongUsClient.Instance; var local = PlayerControl.LocalPlayer;
        if (client == null || local == null || local.Data == null || !client.AmHost || local.OwnerId != client.ClientId ||
            client.NetworkMode != NetworkModes.OnlineGame || client.GameState == InnerNetClient.GameStates.NotJoined ||
            client.GameId == 0 || client.GameId == 32 || client.ClientId < 0 || Main.NormalOptions == null) return null;
        string room = GameCode.IntToGameName(client.GameId);
        if (room.Length is < 4 or > 8) return null;
        foreach (char unit in room) if (unit is < 'A' or > 'Z') return null;
        int language = Options.ModLanguage.GetValue();
        string lang = language == 0 ? Translator.GetUserTrueLang().ToString() : ((Options.ModLanguages)language).ToString();
        string host = Main.AllPlayerNames.TryGetValue(local.PlayerId, out string? name) ? name.RemoveHtmlTags() : "Host";
        string map = Options.RandomMapsMode.GetBool() ? "Random" : SubmergedCompatibility.Loaded && Main.NormalOptions.MapId == 6 ? "Submerged" : Main.CurrentMap.ToString();
        string mode = Options.EnableAutoGMRotation.GetBool() ? "Rotating" : Options.CurrentGameMode.ToString();
        string region = Utils.GetRegionName();
        if (host.Length > 128 || region.Length > 128 || lang.Length > 64 || map.Length > 64 || mode.Length > 64 || Main.NormalOptions.MaxPlayers is < 1 or > 127) return null;
        return new(client.GameId, client.ClientId, local.NetId, local.PlayerId, room, region, lang, host, map, mode, PlayerControl.AllPlayerControls.Count, Main.NormalOptions.MaxPlayers);
    }
    private static bool Current(Session session)
    {
        try
        {
            if (!ReferenceEquals(current, session)) return false;
            Snapshot? snapshot = Capture();
            return snapshot != null && Same(session.Identity, snapshot);
        }
        catch (Exception) { return false; }
    }
    private static IEnumerator Contained(IEnumerator source, Session? owner = null)
    {
        try
        {
            while (true)
            {
                bool moved; object? value;
                try { moved = source.MoveNext(); value = moved ? source.Current : null; }
                catch (Exception) { if (owner != null && ReferenceEquals(current, owner)) Reset(); moved = false; value = null; }
                if (!moved) yield break;
                yield return value;
            }
        }
        finally { try { (source as IDisposable)?.Dispose(); } catch (Exception) { } }
    }
    private static void Begin(Snapshot snapshot, LobbyStatus status)
    {
        Reset();
        if (nextGeneration == ulong.MaxValue) return;
        var session = new Session(++nextGeneration, snapshot, status); current = session;
        session.Running = true;
        try { Main.Instance.StartCoroutine(Contained(Pump(session), session)); }
        catch (Exception) { if (ReferenceEquals(current, session)) Reset(); session.Running = false; }
    }
    public static void Tick()
    {
        if (!EHRDirectoryGate.IsMain || current != null) return;
        try
        {
            if (!Enabled || Capture() == null) return;
            NotifyLobbyStatusChanged(GameStates.InGame ? LobbyStatus.In_Game : LobbyStatus.In_Lobby);
        }
        catch (Exception) { Reset(); }
    }
    public static void NotifyLobbyStatusChanged(LobbyStatus status)
    {
        if (!EHRDirectoryGate.IsMain) return;
        try
        {
            if (status == LobbyStatus.Closed)
            {
                Session? previous = current; string? token = previous?.Token; Reset();
                if (previous != null && token != null && Enabled) Main.Instance.StartCoroutine(Contained(Close(previous, token)));
                return;
            }
            if (!Enabled) { Reset(); return; }
            if (current is { Running: true } running) { running.Desired = status; return; }
            Snapshot? snapshot = Capture();
            if (snapshot == null) { Reset(); return; }
            Begin(snapshot, status);
        }
        catch (Exception) { Reset(); }
    }

    private static IEnumerator Close(Session session, string token)
    {
        using var cancellation = new System.Threading.CancellationTokenSource();
        long deadline = EHRDirectoryClock.Now + EHRDirectoryTransport.TimeoutSeconds * 1000L;
        try
        {
            while (EHRDirectoryClock.Now < nextRequestAt)
            {
                if (!Enabled || EHRDirectoryClock.Now > deadline) yield break;
                yield return null;
            }
            if (!Enabled) yield break;
            Snapshot snapshot = session.Latest;
            byte[] body = EHRDirectoryTransport.Json(("roomCode", snapshot.Room), ("token", token), ("newStatus", "Closed"), ("playerCount", "0"), ("maxPlayers", Number(snapshot.Maximum)), ("map", snapshot.Map), ("gameMode", snapshot.Mode));
            nextRequestAt = EHRDirectoryClock.Now + MinimumSpacing;
            var task = EHRDirectoryTransport.PostAsync(DirectoryEndpoint.Status, body, null, cancellation.Token);
            while (!task.IsCompleted)
            {
                if (!Enabled) { cancellation.Cancel(); yield break; }
                yield return null;
            }
            _ = task.GetAwaiter().GetResult();
            // Closing uses only this former listing's room-management token.
            // Its response never changes a new room, owner or generation.
        }
        finally { cancellation.Cancel(); }
    }

    private static IEnumerator Pump(Session session)
    {
        System.Threading.CancellationTokenSource? cancellation = null;
        long nextSample = 0, nextUpdate = 0;
        try
        {
            while (ReferenceEquals(current, session))
            {
                long now = EHRDirectoryClock.Now;
                if (now < nextSample) { yield return null; continue; }
                nextSample = now + 250;
                Snapshot? snapshot;
                try { snapshot = Capture(); } catch (Exception) { snapshot = null; }
                if (snapshot == null) { Reset(); yield break; }
                if (!Same(session.Identity, snapshot)) { Begin(snapshot, session.Desired); yield break; }
                if (!SameListing(session.Latest, snapshot) || session.Sent != session.Desired) session.Dirty = true;
                session.Latest = snapshot;
                if (now < nextRequestAt || (!session.Dirty && now < nextUpdate)) { yield return null; continue; }

                bool creating = string.IsNullOrEmpty(session.Token);
                string? bearer = null;
                if (creating)
                {
                    try { bearer = EOSManager.Instance.UserIDToken; } catch (Exception) { }
                    if (string.IsNullOrWhiteSpace(bearer) || bearer.Length > EHRDirectoryTransport.MaxRequestBytes) { Reset(); yield break; }
                }
                if (!Current(session)) { Reset(); yield break; }
                LobbyStatus dispatchedStatus = session.Desired;
                string version = $"{Main.ModName} v{Main.PluginVersion}";
                byte[] body = creating
                    ? EHRDirectoryTransport.Json(("roomCode", snapshot.Room), ("serverName", snapshot.Region), ("language", snapshot.Language), ("version", version), ("gameId", Number(snapshot.GameId)), ("hostName", snapshot.Host), ("map", snapshot.Map), ("gameMode", snapshot.Mode), ("maxPlayers", Number(snapshot.Maximum)))
                    : EHRDirectoryTransport.Json(("roomCode", snapshot.Room), ("token", session.Token!), ("newStatus", dispatchedStatus.ToString().Replace('_', ' ')), ("playerCount", Number(snapshot.Players)), ("maxPlayers", Number(snapshot.Maximum)), ("map", snapshot.Map), ("gameMode", snapshot.Mode));
                cancellation = new System.Threading.CancellationTokenSource();
                var task = EHRDirectoryTransport.PostAsync(creating ? DirectoryEndpoint.Create : DirectoryEndpoint.Status, body, bearer, cancellation.Token);
                bearer = null; nextRequestAt = now + MinimumSpacing; LastRequestTimeStamp = Utils.TimeStamp;
                while (!task.IsCompleted)
                {
                    if (!Current(session)) { cancellation.Cancel(); if (ReferenceEquals(current, session)) Reset(); yield break; }
                    yield return null;
                }
                DirectoryReply reply = task.GetAwaiter().GetResult(); cancellation.Dispose(); cancellation = null;
                if (!Current(session)) { if (ReferenceEquals(current, session)) Reset(); yield break; }
                LastRequestTimeStamp = Utils.TimeStamp;
                if (creating)
                {
                    string? token = reply.Success ? EHRDirectoryTransport.RoomToken(reply.Body) : null;
                    if (token == null) { nextRequestAt = EHRDirectoryClock.Now + RetrySpacing; }
                    else { session.Token = token; LastRoomCode = snapshot.Room; session.Dirty = true; Local("EHR website listing created.", session.Identity.PlayerId); }
                }
                else if (reply.Success) { session.Sent = dispatchedStatus; session.Dirty = session.Desired != dispatchedStatus; }
                else if (reply.HttpStatus == 404) { session.Token = null; LastRoomCode = string.Empty; nextRequestAt = EHRDirectoryClock.Now + MinimumSpacing; }
                else { nextRequestAt = EHRDirectoryClock.Now + RetrySpacing; }
                nextUpdate = EHRDirectoryClock.Now + Math.Clamp(Options.LobbyUpdateInterval.GetInt(), 10, 30) * 1000L;
                yield return null;
            }
        }
        finally { cancellation?.Cancel(); cancellation?.Dispose(); session.Running = false; if (!ReferenceEquals(current, session)) session.Token = null; }
    }

    public static void ConfirmAuth(PlayerControl player, string[] args)
    {
        if (!EHRDirectoryGate.IsMain || player == null) return;
        if (!Enabled) { Local("Enable EHR website listing and complete sign-in first.", player.PlayerId); return; }
        if (args == null || args.Length < 2 || args[1] == null || args[1].Trim().Length is < 1 or > 128) { Local("Invalid EHR verification code.", player.PlayerId); return; }
        string uuid = args[1].Trim();
        foreach (char unit in uuid) if (unit < 0x21 || unit > 0x7e) { Local("Invalid EHR verification code.", player.PlayerId); return; }
        try
        {
            Snapshot? snapshot = Capture();
            if (snapshot == null || current?.Token == null || !Same(current.Identity, snapshot)) { Local("List this lobby on the EHR website first.", player.PlayerId); return; }
            if (verifying) { Local("An EHR verification request is already pending.", player.PlayerId); return; }
            var client = player.GetClient();
            string friend = player.FriendCode, puid = client?.ProductUserId ?? string.Empty;
            if (client == null || string.IsNullOrWhiteSpace(friend) || friend.Length > 128 || string.IsNullOrWhiteSpace(puid) || puid.Length > 128) { Local("Player verification identifiers are unavailable.", player.PlayerId); return; }
            verifying = true;
            Main.Instance.StartCoroutine(Contained(Verify(current, player.PlayerId, player.NetId, player.OwnerId, client.Id, uuid, friend, puid)));
        }
        catch (Exception) { verifying = false; Local("EHR verification could not start.", player.PlayerId); }
    }
    private static bool SamePlayer(byte id, uint netId, int owner, int clientId, string friend, string puid)
    {
        try
        {
            var player = Utils.GetPlayerById(id); var client = player?.GetClient();
            return player != null && client != null && player.NetId == netId && player.OwnerId == owner && client.Id == clientId && player.FriendCode == friend && client.ProductUserId == puid;
        }
        catch (Exception) { return false; }
    }
    private static IEnumerator Verify(Session session, byte id, uint netId, int owner, int clientId, string uuid, string friend, string puid)
    {
        using var cancellation = new System.Threading.CancellationTokenSource();
        try
        {
            while (EHRDirectoryClock.Now < nextRequestAt)
            {
                if (!Current(session) || !SamePlayer(id, netId, owner, clientId, friend, puid)) yield break;
                yield return null;
            }
            if (!Current(session) || !SamePlayer(id, netId, owner, clientId, friend, puid)) yield break;
            byte[] body = EHRDirectoryTransport.Json(("uuid", uuid), ("friend_code", friend), ("puid", puid), ("game_id", Number(session.Identity.GameId)));
            nextRequestAt = EHRDirectoryClock.Now + MinimumSpacing;
            var task = EHRDirectoryTransport.PostAsync(DirectoryEndpoint.Verify, body, null, cancellation.Token);
            while (!task.IsCompleted)
            {
                if (!Current(session) || !SamePlayer(id, netId, owner, clientId, friend, puid)) { cancellation.Cancel(); yield break; }
                yield return null;
            }
            var reply = task.GetAwaiter().GetResult();
            if (Current(session) && SamePlayer(id, netId, owner, clientId, friend, puid)) Local(reply.Success ? "Verification request accepted. Check the EHR website." : "EHR verification failed. Check the website and try again.", id);
        }
        finally { cancellation.Cancel(); verifying = false; }
    }
    private static void Local(string message, byte id)
    {
        try { Utils.SendMessage("\n", id, message); } catch (Exception) { }
    }
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
