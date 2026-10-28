using HarmonyLib;

namespace EHR;

[HarmonyPatch(typeof(GameData), "RecomputeTaskCounts")]
internal class CustomTaskCountsPatch
{
    public static bool Prefix(GameData __instance)
    {
        __instance.TotalTasks = 0;
        __instance.CompletedTasks = 0;

        foreach (NetworkedPlayerInfo p in __instance.AllPlayers)
        {
            if (!p) continue;

            bool hasTasks = Utils.HasTasks(p) && Main.PlayerStates[p.PlayerId].TaskState.AllTasksCount > 0;

            if (hasTasks)
            {
                foreach (NetworkedPlayerInfo.TaskInfo task in p.Tasks)
                {
                    __instance.TotalTasks++;
                    if (task.Complete) __instance.CompletedTasks++;
                }
            }
        }

        return false;
    }

    internal static void __EHRStaticCallback_273(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameData __ehrp0 = __ehrFrame.GetInstance<GameData>();
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