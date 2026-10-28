using HarmonyLib;

namespace EHR;
// https://github.com/tukasa0001/TownOfHost/pull/1274/commits/164d1463e46f0ec453e136c7a2f28a8039cd7fc4

[HarmonyPatch(typeof(MovingPlatformBehaviour))]
public static class MovingPlatformBehaviourPatch
{
    private static bool IsDisabled;

    [HarmonyPatch("Start")]
    [HarmonyPrefix]
    public static void StartPrefix(MovingPlatformBehaviour __instance)
    {
        IsDisabled = Options.DisableAirshipMovingPlatform.GetBool();

        if (IsDisabled)
        {
            __instance.transform.localPosition = __instance.DisabledPosition;
            (ShipStatus.Instance as AirshipStatus)?.outOfOrderPlat.SetActive(true);
        }
    }

    [HarmonyPatch("IsDirty", MethodType.Getter)]
    [HarmonyPrefix]
    public static bool GetIsDirtyPrefix(ref bool __result)
    {
        if (IsDisabled)
        {
            __result = false;
            return false;
        }

        return true;
    }

    [HarmonyPatch("Use", typeof(PlayerControl))]
    [HarmonyPrefix]
    public static bool UsePrefix()
    {
        return !IsDisabled;
    }

    [HarmonyPatch("SetSide")]
    [HarmonyPrefix]
    public static bool SetSidePrefix()
    {
        return !IsDisabled;
    }

    internal static void __EHRStaticCallback_211(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        MovingPlatformBehaviour __ehrp0 = __ehrFrame.GetInstance<MovingPlatformBehaviour>();
        try
        {
            StartPrefix(__ehrp0);
        }
        finally
        {
        }
    }


    internal static void __EHRStaticCallback_212(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrp0 = __ehrFrame.GetResult<bool>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = GetIsDirtyPrefix(ref __ehrp0);
        }
        finally
        {
            __ehrFrame.Result = __ehrp0;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_213(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = UsePrefix();
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_214(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = SetSidePrefix();
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}