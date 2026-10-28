using System;
using HarmonyLib;

namespace EHR.Patches;

// By https://github.com/TouseefX
[HarmonyPatch]
internal static class ButtonClickCrashFix
{
    [HarmonyPatch(typeof(PassiveButton), "ReceiveClickDown"), HarmonyPrefix]
    public static bool ReceiveClickDownPrefix(PassiveButton __instance)
    {
        return __instance != null
#if IL2CPP
               && __instance.Token != 0 && EHR.Generated.FacadeRuntime.TokenIsValid(__instance.Token)
#endif
            ;
    }

    [HarmonyPatch(typeof(PassiveButton), "ReceiveClickUp"), HarmonyPrefix]
    public static bool ReceiveClickUpPrefix(PassiveButton __instance)
    {
        return __instance != null
#if IL2CPP
               && __instance.Token != 0 && EHR.Generated.FacadeRuntime.TokenIsValid(__instance.Token)
#endif
            ;
    }

    internal static void __EHRStaticCallback_10(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        PassiveButton __ehrp0 = __ehrFrame.GetInstance<PassiveButton>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = ReceiveClickDownPrefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_11(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        PassiveButton __ehrp0 = __ehrFrame.GetInstance<PassiveButton>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = ReceiveClickUpPrefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}