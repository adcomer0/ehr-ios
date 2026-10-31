using System.Text.RegularExpressions;
using HarmonyLib;
using UnityEngine;

namespace EHR;

[HarmonyPatch(typeof(JoinGameButton), "OnClick")]
internal class JoinGameButtonPatch
{
    public static void Prefix(JoinGameButton __instance)
    {
        if (__instance.GameIdText == null) return;

        if (__instance.GameIdText.text == "" && Regex.IsMatch(GUIUtility.systemCopyBuffer.Trim('\r', '\n'), "^[A-Z]{6}$"))
        {
            __instance.GameIdText.SetText(GUIUtility.systemCopyBuffer.Trim('\r', '\n'));
        }
    }

    internal static void __EHRStaticCallback_171(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        JoinGameButton __ehrp0 = __ehrFrame.GetInstance<JoinGameButton>();
        try
        {
            Prefix(__ehrp0);
        }
        finally
        {
        }
    }

}