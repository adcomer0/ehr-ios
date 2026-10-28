using System.Linq;
using EHR.Patches;
using HarmonyLib;
using Exception = System.Exception;

namespace EHR;

[HarmonyPatch(typeof(GameStartManager))]
internal static class AllMapIconsPatch
{
    private static void EnsureMapIcon(GameStartManager instance, MapNames map, string spritePath, float pixelsPerUnit)
    {
#if IL2CPP
        if (instance.AllMapIcons.TrueForAll((Il2CppSystem.Predicate<MapIconByName>)(x => x.Name != map)))
#else
        if (instance.AllMapIcons.TrueForAll(x => x.Name != map))
#endif
        {
            instance.AllMapIcons.Insert((int)map, new MapIconByName
            {
                Name = map,
                MapIcon = Utils.LoadSprite(spritePath, pixelsPerUnit)
            });
        }
    }

    [HarmonyPatch(typeof(GameStartManager), "Start")]
    [HarmonyPriority(Priority.First)]
    [HarmonyPrefix]
    public static void GameStartManagerStart_Prefix(GameStartManager __instance)
    {
        try
        {
            EnsureMapIcon(__instance, MapNames.Dleks, "EHR.Resources.Images.DleksBanner-Wordart.png", 160f);

            if (SubmergedCompatibility.Loaded)
                EnsureMapIcon(__instance, (MapNames)6, "EHR.Resources.Images.Submerged-Wordart.png", 380f);
        }
        catch { }
    }

    [HarmonyPatch("Start")]
    [HarmonyPostfix]
    public static void Postfix_AllMapIcons(GameStartManager __instance)
    {
        try
        {
            if (!__instance) return;

            LateTask.New(() =>
            {
                if (Main.NormalOptions.MapId != 3) return;

                Main.NormalOptions.MapId = 0;

                if (__instance && __instance.MapImage)
                    __instance.UpdateMapImage(MapNames.Skeld);

                // Only force Dleks if random maps mode isn't active
                if (!Options.RandomMapsMode.GetBool())
                    GameOptionsMapPickerPatch.SetDleks = true;
            }, AmongUsClient.Instance.AmHost ? 1f : 4f, "Set Skeld Icon For Dleks Map");
        }
        catch (Exception e) { Utils.ThrowException(e); }
    }

    [HarmonyPatch(typeof(GameStartManager), "UpdateMapImage")]
    [HarmonyPrefix]
    public static bool Prefix_UpdateMapImage(GameStartManager __instance)
    {
        if (!__instance || !__instance.MapImage) return false;

        if (GameOptionsMapPickerPatch.SetDleks)
        {
            __instance.MapImage.sprite = Utils.LoadSprite("EHR.Resources.Images.DleksBanner-Wordart.png", 160f);
            return false;
        }

        return true;
    }

    internal static void __EHRStaticCallback_87(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameStartManager __ehrp0 = __ehrFrame.GetInstance<GameStartManager>();
        try
        {
            GameStartManagerStart_Prefix(__ehrp0);
        }
        finally
        {
        }
    }


    internal static void __EHRStaticCallback_88(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameStartManager __ehrp0 = __ehrFrame.GetInstance<GameStartManager>();
        try
        {
            Postfix_AllMapIcons(__ehrp0);
        }
        finally
        {
        }
    }


    internal static void __EHRStaticCallback_89(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        GameStartManager __ehrp0 = __ehrFrame.GetInstance<GameStartManager>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix_UpdateMapImage(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}

[HarmonyPatch(typeof(StringOption), "Start")]
public static class AutoselectDleksPatch
{
    public static void Postfix(StringOption __instance)
    {
        if (__instance.Title == StringNames.GameMapName)
        {
            // vanilla clamps this to not autoselect dleks
            __instance.Value = GameOptionsManager.Instance.CurrentGameOptions.MapId;
        }
    }

    internal static void __EHRStaticCallback_90(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        StringOption __ehrp0 = __ehrFrame.GetInstance<StringOption>();
        try
        {
            Postfix(__ehrp0);
        }
        finally
        {
        }
    }

}

[HarmonyPatch]
public static class CreateGameOptionsPatch
{
    private const string DleksSpritePath = "EHR.Resources.Images.DleksBanner-Wordart.png";

    [HarmonyPatch(typeof(CreateGameOptions), "MapChanged")]
    [HarmonyPrefix]
    public static bool MapChangedPrefix(CreateGameOptions __instance)
    {
        if (__instance.mapPicker.GetSelectedID() == (int)MapNames.Dleks)
        {
            __instance.mapBanner.flipX = false;
            __instance.rendererBGCrewmates.sprite = __instance.bgCrewmates[0];
            __instance.mapBanner.sprite = Utils.LoadSprite(DleksSpritePath, 100f);
            __instance.TurnOffCrewmates();
            __instance.currentCrewSprites = __instance.skeldCrewSprites;
            __instance.SetCrewmateGraphic(__instance.capacityOption.Value - 1f);
            return false;
        }

        return !SubmergedCompatibility.Loaded || __instance.mapPicker.GetSelectedID() != 6;
    }

    [HarmonyPatch(typeof(CreateGameOptions), "Start")]
    [HarmonyPrefix]
    public static void SetupMapBackground(CreateGameOptions __instance)
    {
        if (__instance.currentCrewSprites == null)
            __instance.mapBanner.sprite = Utils.LoadSprite(DleksSpritePath, 100f);

        __instance.currentCrewSprites ??= __instance.skeldCrewSprites;
        __instance.mapTooltips[3] = StringNames.ToolTipSkeld;
    }

    internal static void __EHRStaticCallback_91(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        CreateGameOptions __ehrp0 = __ehrFrame.GetInstance<CreateGameOptions>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = MapChangedPrefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_92(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        CreateGameOptions __ehrp0 = __ehrFrame.GetInstance<CreateGameOptions>();
        try
        {
            SetupMapBackground(__ehrp0);
        }
        finally
        {
        }
    }

}

[HarmonyPatch]
public static class MapSelectionGameSettingPatch
{
    [HarmonyPriority(Priority.VeryLow)]
    [HarmonyPatch(typeof(MapSelectionGameSetting), "GetValueString")]
    [HarmonyPrefix]
    public static void AddToActualOptions(MapSelectionGameSetting __instance)
    {
        if (__instance.Values.All(x => (int)x != (int)StringNames.MapNameSkeld))
        {
            var list = __instance.Values.ToList();
            list.Insert((int)MapNames.Dleks, StringNames.MapNameSkeld);
            __instance.Values = list.ToArray();
        }
    }

    internal static void __EHRStaticCallback_93(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        MapSelectionGameSetting __ehrp0 = __ehrFrame.GetInstance<MapSelectionGameSetting>();
        try
        {
            AddToActualOptions(__ehrp0);
        }
        finally
        {
        }
    }

}
