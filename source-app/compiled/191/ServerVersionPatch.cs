using HarmonyLib;

namespace EHR.Patches;

[HarmonyPatch(typeof(Constants), "GetBroadcastVersion")]
internal static class ServerUpdatePatch
{
    public static void Postfix(ref int __result)
    {
        if (GameStates.IsLocalGame) Logger.Info($"IsLocalGame: {__result}", "VersionServer");

        if (GameStates.IsOnlineGame)
        {
            // Changing server version for AU mods
            var revision = __result % 50;
            if (revision < 25)
            {
                __result += 25;
            }
            Logger.Info($"IsOnlineGame: {__result}", "VersionServer");
        }
    }

    internal static void __EHRStaticCallback_293(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetResult<int>();
        try
        {
            Postfix(ref __ehrp0);
        }
        finally
        {
            __ehrFrame.Result = __ehrp0;
        }
    }

}

[HarmonyPatch(typeof(Constants), "IsVersionModded")]
public static class IsVersionModdedPatch
{
    public static bool Prefix(ref bool __result)
    {
        __result = true;
        return false;
    }

    internal static void __EHRStaticCallback_294(global::EHR.EHRStaticPatchFrame __ehrFrame)
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