using HarmonyLib;
using Hazel;

namespace EHR.Patches;

// From: https://github.com/Rabek009/MoreGamemodes/blob/master/Patches/ClientPatch.cs

[HarmonyPatch(typeof(VoteBanSystem), "CmdAddVote")]
internal static class CmdAddVotePatch
{
    public static bool Prefix([HarmonyArgument(0)] int clientId)
    {
        if (!AmongUsClient.Instance.AmHost) return true;

        PlayerControl pc = PlayerControl.LocalPlayer;
        PlayerControl target = Utils.GetClientById(clientId)?.Character;
        if (target != null) Main.PlayerStates[pc.PlayerId].Role.OnVoteKick(pc, target);
        Logger.Info($" {pc.GetNameWithRole()} => {target.GetNameWithRole()}", "VoteKick");

        return false;
    }

    internal static void __EHRStaticCallback_332(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetArgument<int>(0);
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

[HarmonyPatch(typeof(VoteBanSystem), "AddVote")]
internal static class AddVotePatch
{
    public static bool Prefix(VoteBanSystem __instance, [HarmonyArgument(0)] int srcClient, [HarmonyArgument(1)] int clientId)
    {
        if (!AmongUsClient.Instance.AmHost) return true;

        PlayerControl pc = Utils.GetClientById(srcClient)?.Character;
        PlayerControl target = Utils.GetClientById(clientId)?.Character;
        if (pc != null && target != null) Main.PlayerStates[pc.PlayerId].Role.OnVoteKick(pc, target);
        Logger.Info($" {pc.GetNameWithRole()} => {target.GetNameWithRole()}", "VoteKick");

        if (AmongUsClient.Instance.ClientId == srcClient || __instance != VoteBanSystem.Instance) return false;

        VoteBanSystem.Instance = Object.Instantiate(AmongUsClient.Instance.VoteBanPrefab);
        AmongUsClient.Instance.Spawn(VoteBanSystem.Instance);

        LateTask.New(() =>
        {
            MessageWriter writer = MessageWriter.Get(SendOption.Reliable);
            writer.StartMessage(5);
            writer.Write(AmongUsClient.Instance.GameId);
            writer.StartMessage(5);
            writer.WritePacked(__instance.NetId);
            writer.EndMessage();
            writer.EndMessage();
            AmongUsClient.Instance.SendOrDisconnect(writer);
            writer.Recycle();
        }, 0.5f);

        LateTask.New(() =>
        {
            AmongUsClient.Instance.RemoveNetObject(__instance);
            Object.Destroy(__instance.gameObject);
        }, 5f);

        return false;
    }

    internal static void __EHRStaticCallback_333(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        VoteBanSystem __ehrp0 = __ehrFrame.GetInstance<VoteBanSystem>();
        int __ehrp1 = __ehrFrame.GetArgument<int>(0);
        int __ehrp2 = __ehrFrame.GetArgument<int>(1);
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0, __ehrp1, __ehrp2);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}