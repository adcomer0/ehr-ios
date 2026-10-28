using System;
using System.Collections;
using System.IO;
using System.Net.Http;
using System.Reflection;
using HarmonyLib;
using TMPro;
using Twitch;
using UnityEngine;
using UnityEngine.Networking;
using static EHR.Translator;

#if IL2CPP
using System.Text.Json;
#else
using Newtonsoft.Json.Linq;
#endif

namespace EHR;

[HarmonyPatch]
public static class ModUpdater
{
    private const string URLGithub = "https://api.github.com/repos/Gurge44/EndlessHostRoles";
    public const bool ForceUpdate = false;
    public static bool HasUpdate;
    private static bool FirstNotify = true;
    private static bool HasOutdate;
    public static bool IsBroken;
    private static Version LatestVersion;
    private static string LatestTitleModName;
    private static string LatestTitle;
    public static string DownloadUrl;
    private static GenericPopup InfoPopup;
    private static GenericPopup InfoPopupV2;
    public static readonly HttpClient HttpClient = new();

    [HarmonyPatch(typeof(MainMenuManager), "Start")]
    [HarmonyPrefix]
    [HarmonyPriority(2)]
    public static void Start_Prefix()
    {
        if (!OperatingSystem.IsAndroid())
        {
            // Version checks are not handled on Android
            
            Main.Instance.StartCoroutine(CheckReleaseFromGithub(Main.BetaBuildUrl.Value != ""));
        }
        
        InfoPopup = Object.Instantiate(TwitchManager.Instance.TwitchPopup);
        InfoPopup.name = "InfoPopup";
        InfoPopup.TextAreaTMP.GetComponent<RectTransform>().sizeDelta = new(2.5f, 2f);

        InfoPopupV2 = Object.Instantiate(TwitchManager.Instance.TwitchPopup);
        InfoPopupV2.name = "InfoPopupV2";
    }

    public static void ShowAvailableUpdate()
    {
        if (FirstNotify && HasUpdate)
        {
            FirstNotify = false;
            
            if (!string.IsNullOrWhiteSpace(LatestTitleModName))
                ShowPopupWithTwoButtons(string.Format(GetString("NewUpdateAvailable"), LatestTitleModName), global::EHR.SourceHost.SourceSignedUpdates.ActionTitle, onClickOnFirstButton: () => StartUpdate(DownloadUrl));
        }
    }

    private static IEnumerator CheckReleaseFromGithub(bool beta = false)
    {
        Logger.Msg("Checking GitHub Release", "CheckRelease");

        const string url = URLGithub + "/releases/latest";

        UnityWebRequest request = UnityWebRequest.Get(url);

        request.SetRequestHeader("User-Agent", "EHR Updater");
        request.downloadHandler = new DownloadHandlerBuffer();

        yield return request.SendWebRequest();

        try
        {
            if (request.result != UnityWebRequest.Result.Success)
            {
                Logger.Error($"GitHub request failed: {request.responseCode} {request.error}", "CheckRelease");
                if (!OperatingSystem.IsIOS()) IsBroken = true;
                yield break;
            }

#if IL2CPP
            JsonDocument data = JsonDocument.Parse(request.downloadHandler.text);

            LatestTitleModName = data.RootElement.GetProperty("name").GetString();

            if (beta)
            {
                LatestTitle = LatestTitleModName;

                // Beta builds still use the same EHR.dll release asset.
                DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;

                HasUpdate = LatestTitle != ThisAssembly.Git.Commit;
            }
            else
            {
                string versionString = data.RootElement.GetProperty("tag_name").GetString()?
#else
            JObject data = JObject.Parse(request.downloadHandler.text);

            LatestTitleModName = data["name"]?.ToString();

            if (beta)
            {
                LatestTitle = LatestTitleModName;

                // Beta builds still use the same EHR.dll release asset.
                DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;

                HasUpdate = LatestTitle != ThisAssembly.Git.Commit;
            }
            else
            {
                string versionString = data["tag_name"]?
                    .ToString()
#endif
                    .TrimStart('v');

                LatestVersion = new Version(versionString!);
                LatestTitle = $"Ver. {LatestVersion}";
                DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;
                HasUpdate = LatestVersion.CompareTo(Main.Version) > 0;
                HasOutdate = LatestVersion.CompareTo(Main.Version) < 0;
            }

            Logger.Info("hasupdate: " + HasUpdate, "GitHub");
            Logger.Info("hasoutdate: " + HasOutdate, "GitHub");
            Logger.Info("forceupdate: " + ForceUpdate, "GitHub");
            Logger.Info("downloadUrl: " + DownloadUrl, "GitHub");
            Logger.Info("latestVersion: " + LatestVersion, "GitHub");
            Logger.Info("latestTitle: " + LatestTitle, "GitHub");

            IsBroken = false;

            Logger.Msg("GitHub release check completed", "CheckRelease");
        }
        catch (Exception ex)
        {
            if (!OperatingSystem.IsIOS()) IsBroken = true;

            Logger.Error(
                $"Error while checking release from GitHub:\n{ex}",
                "CheckRelease",
                false
            );
        }
    }

#if IL2CPP
    private static string FindDllAssetUrl(JsonDocument release)
    {
        if (!release.RootElement.TryGetProperty("assets", out JsonElement assets))
            return null;

        foreach (JsonElement asset in assets.EnumerateArray())
        {
            if (asset.GetProperty("name").GetString() == "EHR.dll")
                return asset.GetProperty("browser_download_url").GetString();
        }

        return null;
    }
#else
    private static string FindDllAssetUrl(JObject release)
    {
        if (release["assets"] is not JArray assets)
            return null;

        for (int i = 0; i < assets.Count; i++)
        {
            JObject asset = assets[i] as JObject;

            if (asset?["name"]?.ToString() == "EHR.dll")
                return asset["browser_download_url"]?.ToString();
        }

        return null;
    }
#endif

    public static void StartUpdate(string url)
    {
        // The upstream URL may name a desktop DLL. Only the immutable native
        // host configuration can select this build's iPhone update instructions.
        global::EHR.SourceHost.SourceSignedUpdates.OpenInstructions();
        ShowPopup(global::EHR.SourceHost.SourceSignedUpdates.StatusMessage, StringNames.Close, true, false);
    }

    public static void UpdateFailed()
    {
        ShowPopup(global::EHR.SourceHost.SourceSignedUpdates.StatusMessage, StringNames.Close, true, false);
    }

    public static void ShowPopup(string message, StringNames buttonText, bool showButton = false, bool buttonIsExit = true)
    {
        if (!InfoPopup) return;

        InfoPopup.Show(message);
        Transform button = InfoPopup.transform.Find("ExitGame");

        if (button)
        {
            button.gameObject.SetActive(showButton);
            var textTranslatorTMP = button.GetChild(0).GetComponent<TextTranslatorTMP>();
            textTranslatorTMP.TargetText = buttonText;
            textTranslatorTMP.ResetText();
            var passiveButton = button.GetComponent<PassiveButton>();
            passiveButton.OnClick = new();

            if (buttonIsExit)
                passiveButton.OnClick.AddListener(SplashLogoAnimatorPatch.SceneChanger.ExitGame);
            else
                passiveButton.OnClick.AddListener(() => InfoPopup.Close());
        }
    }

    public static void ShowPopupWithTwoButtons(string message, string firstButtonText, string secondButtonText = "", Action onClickOnFirstButton = null, Action onClickOnSecondButton = null)
    {
        if (InfoPopupV2)
        {
            var templateExitGame = InfoPopupV2.transform.Find("ExitGame");
            if (!templateExitGame) return;

            var background = InfoPopupV2.transform.Find("Background");
            if (!background) return;
            background.localScale *= 2f;

            InfoPopupV2.Show(message);
            templateExitGame.gameObject.SetActive(false);
            var firstButton = Object.Instantiate(templateExitGame, InfoPopupV2.transform);
            var secondButton = Object.Instantiate(templateExitGame, InfoPopupV2.transform);
            
            if (firstButton)
            {
                firstButton.gameObject.SetActive(true);
                firstButton.name = "FirstButton";
                var firstButtonTransform = firstButton.transform;
                firstButton.transform.localPosition = new Vector3(firstButtonTransform.localPosition.x - 1f, firstButtonTransform.localPosition.y - 0.7f, firstButtonTransform.localPosition.z);
                firstButton.transform.localScale *= 1.2f;
                var firstButtonGetChild = firstButton.GetChild(0);
                var textTranslatorTMP = firstButtonGetChild.GetComponent<TextTranslatorTMP>();
                textTranslatorTMP.TargetText = StringNames.Cancel;
                textTranslatorTMP.ResetText();
                textTranslatorTMP.DestroyTranslator();
                firstButtonGetChild.GetComponent<TextMeshPro>().text = firstButtonText;
                firstButtonGetChild.GetComponent<TMP_Text>().text = firstButtonText;
                var passiveButton = firstButton.GetComponent<PassiveButton>();
                passiveButton.OnClick = new();
                if (onClickOnFirstButton != null)
                    passiveButton.OnClick.AddListener(() => { onClickOnFirstButton(); InfoPopupV2.Close();});
                else passiveButton.OnClick.AddListener(() => InfoPopupV2.Close());
            }
            
            if (secondButton)
            {
                secondButton.gameObject.SetActive(true);
                secondButton.name = "SecondButton";
                var secondButtonTransform = secondButton.transform;
                secondButton.transform.localPosition = new Vector3(secondButtonTransform.localPosition.x + 1f, secondButtonTransform.localPosition.y - 0.7f, secondButtonTransform.localPosition.z);
                secondButton.transform.localScale *= 1.2f;
                var secondButtonGetChild = secondButton.GetChild(0);
                var textTranslatorTMP = secondButtonGetChild.GetComponent<TextTranslatorTMP>();
                textTranslatorTMP.TargetText = StringNames.Cancel;
                textTranslatorTMP.ResetText();
                if (!string.IsNullOrWhiteSpace(secondButtonText))
                {
                    textTranslatorTMP.DestroyTranslator();
                    secondButtonGetChild.GetComponent<TextMeshPro>().text = secondButtonText;
                    secondButtonGetChild.GetComponent<TMP_Text>().text = secondButtonText;
                }

                var passiveButton = secondButton.GetComponent<PassiveButton>();
                passiveButton.OnClick = new();
                if (onClickOnSecondButton != null)
                    passiveButton.OnClick.AddListener(() => { onClickOnSecondButton(); InfoPopupV2.Close(); });
                else passiveButton.OnClick.AddListener(() => InfoPopupV2.Close());
            }
        }
    }

    internal static void __EHRStaticCallback_17(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        try
        {
            Start_Prefix();
        }
        finally
        {
        }
    }

}
