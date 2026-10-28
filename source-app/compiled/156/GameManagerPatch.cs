using HarmonyLib;
using Hazel;

namespace EHR;

[HarmonyPatch(typeof(GameManager), "Serialize")]
internal static class GameManagerSerializeFix
{
    public static bool InitialState = true;

    public static bool Prefix(GameManager __instance, [HarmonyArgument(0)] MessageWriter writer, [HarmonyArgument(1)] bool initialState, ref bool __result)
    {
        InitialState = initialState;

        var flag = false;

        for (var index = 0; index < __instance.LogicComponents.Count; ++index)
        {
            GameLogicComponent logicComponent = __instance.LogicComponents[index];

            if (initialState || logicComponent.IsDirty)
            {
                writer.StartMessage((byte)index);
                bool hasBody = logicComponent.Serialize(writer);

                if (hasBody)
                {
                    flag = true;
                    writer.EndMessage();
                }
                else
                    writer.CancelMessage();

                logicComponent.ClearDirtyFlag();
            }
        }

        __instance.ClearDirtyBits();
        __result = flag;
        return false;
    }

    internal static void __EHRStaticCallback_103(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameManager __ehrp0 = __ehrFrame.GetInstance<GameManager>();
        MessageWriter __ehrp1 = __ehrFrame.GetArgument<MessageWriter>(0);
        bool __ehrp2 = __ehrFrame.GetArgument<bool>(1);
        bool __ehrp3 = __ehrFrame.GetResult<bool>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0, __ehrp1, __ehrp2, ref __ehrp3);
        }
        finally
        {
            __ehrFrame.Result = __ehrp3;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}

[HarmonyPatch(typeof(LogicOptions), "Serialize")] // Only called by the patch above
internal static class LogicOptionsSerializePatch
{
    public static bool Prefix(ref bool __result)
    {
        // Block all but the first time and synchronize only with CustomSyncSettings
        if (!GameManagerSerializeFix.InitialState)
        {
            __result = false;
            return false;
        }

        return true;
    }

    internal static void __EHRStaticCallback_104(global::EHR.EHRStaticPatchFrame __ehrFrame)
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