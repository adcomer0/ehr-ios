using AmongUs.Data;
using HarmonyLib;

namespace EHR;

// ˛ÎżĽŁşhttps://github.com/ykundesu/SuperNewRoles/blob/master/SuperNewRoles/Patches/SNROnlySearch.cs
public static class EHROnlySearch
{
    public const string FilterText = "EHR";

    [HarmonyPatch(typeof(FilterTagManager), "RefreshTags")]
    public static class FilterTagManagerPatch
    {
        public static void Postfix()
        {
            DataManager.Settings.Multiplayer.ValidGameFilterOptions.FilterTags.Add(FilterText);
        }
    
    internal static void __EHRStaticCallback_94(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        try
        {
            Postfix();
        }
        finally
        {
        }
    }

}

    [HarmonyPatch(typeof(FilterTagsMenu), "ChooseOption")]
    public static class FilterTagsMenuChooseOptionPatch
    {
        public static void Postfix(FilterTagsMenu __instance, ChatLanguageButton button, string filter)
        {
            if (__instance.targetOpts.FilterTags.Contains(FilterText))
            {
                if (filter == FilterText)
                {
                    __instance.targetOpts.FilterTags = new();
                    __instance.targetOpts.FilterTags.Add(FilterText);
                    foreach (UiElement btn in __instance.controllerSelectable) btn.GetComponent<ChatLanguageButton>().SetSelected(false);

                    button.SetSelected(true);
                }
                else
                {
                    __instance.targetOpts.FilterTags.Remove(FilterText);

                    foreach (UiElement btn in __instance.controllerSelectable)
                    {
                        var LangBtn = btn.GetComponent<ChatLanguageButton>();
                        if (LangBtn.Text.text == FilterText) LangBtn.SetSelected(false);
                    }
                }

                __instance.UpdateButtonText();
            }
        }
    
    internal static void __EHRStaticCallback_95(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        FilterTagsMenu __ehrp0 = __ehrFrame.GetInstance<FilterTagsMenu>();
        ChatLanguageButton __ehrp1 = __ehrFrame.GetArgument<ChatLanguageButton>("button");
        string __ehrp2 = __ehrFrame.GetArgument<string>("filter");
        try
        {
            Postfix(__ehrp0, __ehrp1, __ehrp2);
        }
        finally
        {
        }
    }

}
}