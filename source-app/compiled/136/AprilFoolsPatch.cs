using System;
using HarmonyLib;
using static CosmeticsLayer;

namespace EHR.Patches;

//[HarmonyPatch(typeof(AprilFoolsMode), nameof(AprilFoolsMode.ShouldShowAprilFoolsToggle))]
//public static class ShouldShowTogglePatch
//{
//    public static void Postfix(ref bool __result)
//    {
//        __result = false;
//    }
//}
[HarmonyPatch(typeof(NormalGameManager), "GetBodyType")]
public static class GetNormalBodyTypePatch
{
    public static void Postfix(ref PlayerBodyTypes __result)
    {
        try
        {
            if (Main.HorseMode.Value || AprilFoolsMode.ShouldHorseAround())
            {
                __result = PlayerBodyTypes.Horse;
                return;
            }
            if (Main.LongMode.Value || AprilFoolsMode.ShouldLongAround())
            {
                __result = PlayerBodyTypes.Long;
                return;
            }
            if (Main.ClassicMode.Value || AprilFoolsMode.ShouldClassicMode())
            {
                __result = PlayerBodyTypes.Classic;
            }
        }
        catch { }
    }

    internal static void __EHRStaticCallback_28(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        PlayerBodyTypes __ehrp0 = __ehrFrame.GetResult<PlayerBodyTypes>();
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

[HarmonyPatch(typeof(HideAndSeekManager), "GetBodyType")]
public static class GetHnsBodyTypePatch
{
    public static void Postfix(ref PlayerBodyTypes __result, [HarmonyArgument(0)] PlayerControl player)
    {
        try
        {
            if (player == null || player.Data == null || player.Data.Role == null)
            {
                if (Main.HorseMode.Value || AprilFoolsMode.ShouldHorseAround())
                {
                    __result = PlayerBodyTypes.Horse;
                    return;
                }
                if (Main.LongMode.Value || AprilFoolsMode.ShouldLongAround())
                {
                    __result = PlayerBodyTypes.Long;
                    return;
                }
                if (Main.ClassicMode.Value || AprilFoolsMode.ShouldClassicMode())
                {
                    __result = PlayerBodyTypes.Classic;
                    return;
                }
                __result = PlayerBodyTypes.Normal;
            }
            else if (Main.HorseMode.Value || AprilFoolsMode.ShouldHorseAround())
            {
                if (player.Data.Role.IsImpostor)
                {
                    __result = PlayerBodyTypes.Normal;
                    return;
                }
                __result = PlayerBodyTypes.Horse;
            }
            else if (Main.LongMode.Value || AprilFoolsMode.ShouldLongAround())
            {
                if (player.Data.Role.IsImpostor)
                {
                    __result = PlayerBodyTypes.LongSeeker;
                    return;
                }
                __result = PlayerBodyTypes.Long;
            }
            else if (Main.ClassicMode.Value || AprilFoolsMode.ShouldClassicMode())
            {
                if (player.Data.Role.IsImpostor)
                {
                    __result = PlayerBodyTypes.Seeker;
                }
                __result = PlayerBodyTypes.Classic;
            }
        }
        catch { }
    }

    internal static void __EHRStaticCallback_29(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        PlayerBodyTypes __ehrp0 = __ehrFrame.GetResult<PlayerBodyTypes>();
        PlayerControl __ehrp1 = __ehrFrame.GetArgument<PlayerControl>(0);
        try
        {
            Postfix(ref __ehrp0, __ehrp1);
        }
        finally
        {
            __ehrFrame.Result = __ehrp0;
        }
    }

}

[HarmonyPatch(typeof(LongBoiPlayerBody))]
public static class LongBoiPatches
{
    [HarmonyPatch("Awake")]
    [HarmonyPrefix]
    public static bool LongBoyAwake_Patch(LongBoiPlayerBody __instance)
    {
        try
        {
            if (!AprilFoolsMode.ShouldLongAround() && !Main.LongMode.Value) return false;

            __instance.cosmeticLayer.OnSetBodyAsGhost += (Action)__instance.SetPoolableGhost;
            __instance.cosmeticLayer.OnColorChange += (Action<int>)__instance.SetHeightFromColor;
            __instance.cosmeticLayer.OnCosmeticSet += (Action<string, int, CosmeticKind>)__instance.OnCosmeticSet;
            __instance.gameObject.layer = 8;
        }
        catch { }

        return false;
    }

    [HarmonyPatch("Start")]
    [HarmonyPrefix]
    public static bool LongBoyStart_Patch(LongBoiPlayerBody __instance)
    {
        try
        {
            if (!AprilFoolsMode.ShouldLongAround() && !Main.LongMode.Value)
            {
                __instance.ShouldLongAround = false;
                __instance.headSprite.gameObject.SetActive(false);
                __instance.neckSprite.gameObject.SetActive(false);
                __instance.foregroundNeckSprite.gameObject.SetActive(false);
                return false;
            }
            __instance.ShouldLongAround = true;
            if (__instance.hideCosmeticsQC) __instance.cosmeticLayer.SetHatVisorVisible(false);

            __instance.SetupNeckGrowth();

            if (__instance.isExiledPlayer)
            {
                var instance = ShipStatus.Instance;
                if (instance == null || instance.Type != ShipStatus.MapType.Fungle) __instance.cosmeticLayer.AdjustCosmeticRotations(-17.75f);
            }

            if (!__instance.isPoolablePlayer) __instance.cosmeticLayer.ValidateCosmetics();

            if (__instance.myPlayerControl)
            {
                __instance.StopAllCoroutines();
                __instance.SetHeightFromColor(__instance.myPlayerControl.Data.DefaultOutfit.ColorId);
            }
        }
        catch { }

        return false;
    }

    [HarmonyPatch("SetHeightFromColor")]
    [HarmonyPrefix]
    public static bool SetHeightFromColor_Prefix(int colorIndex)
    {
        return colorIndex != byte.MaxValue;
    }

    [HarmonyPatch("SetHeighFromDistanceHnS")]
    [HarmonyPrefix]
    public static bool LongBoyNeckSize_Patch(LongBoiPlayerBody __instance, ref float distance)
    {
        try
        {
            __instance.targetHeight = distance / 10f + 0.5f;
            __instance.SetupNeckGrowth(true);
        }
        catch { }

        return false;
    }

    [HarmonyPatch(typeof(HatManager), "CheckLongModeValidCosmetic")]
    [HarmonyPrefix]
    public static bool CheckLongMode_Patch(HatManager __instance, out bool __result, ref string cosmeticID, ref bool ignoreLongMode)
    {
        if (AprilFoolsMode.ShouldHorseAround() || AprilFoolsMode.ShouldLongAround())
        {
            __result = true;
            return false;
        }

        if (string.Equals("skin_rhm", cosmeticID))
        {
            __result = false;
            return false;
        }

        __result = true;
        return false;
    }

    internal static void __EHRStaticCallback_30(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        LongBoiPlayerBody __ehrp0 = __ehrFrame.GetInstance<LongBoiPlayerBody>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = LongBoyAwake_Patch(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_31(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        LongBoiPlayerBody __ehrp0 = __ehrFrame.GetInstance<LongBoiPlayerBody>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = LongBoyStart_Patch(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_32(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetArgument<int>("colorIndex");
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = SetHeightFromColor_Prefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_33(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        LongBoiPlayerBody __ehrp0 = __ehrFrame.GetInstance<LongBoiPlayerBody>();
        float __ehrp1 = __ehrFrame.GetArgument<float>("distance");
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = LongBoyNeckSize_Patch(__ehrp0, ref __ehrp1);
        }
        finally
        {
            __ehrFrame.SetArgument("distance", __ehrp1);
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_34(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        HatManager __ehrp0 = __ehrFrame.GetInstance<HatManager>();
        bool __ehrp1 = default!;
        string __ehrp2 = __ehrFrame.GetArgument<string>("cosmeticID");
        bool __ehrp3 = __ehrFrame.GetArgument<bool>("ignoreLongMode");
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = CheckLongMode_Patch(__ehrp0, out __ehrp1, ref __ehrp2, ref __ehrp3);
        }
        finally
        {
            __ehrFrame.Result = __ehrp1;
            __ehrFrame.SetArgument("cosmeticID", __ehrp2);
            __ehrFrame.SetArgument("ignoreLongMode", __ehrp3);
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}