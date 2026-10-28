// Original descriptor policy; no game state or provider calls.
#nullable enable
namespace EHR;

internal static class EHRSourceAccountPolicy
{
    internal const string UpstreamCommit = "ce23f0d050f617a59507e5bb0fbfff751d4b5134";
    internal const int ExcludedCallbackCount = 6;
    internal static bool TryExclude(string callbackId, out string reason)
    {
        reason = callbackId switch
        {
            "EHR.Modules.PrivacyPolicyScreenShowPatch::Prefix#15" => "Replaces native privacy consent controls and lowers vanilla LastAcceptedPrivacyPolicyVersion.",
            "EHR.Modules.PrivacyPolicyScreenClosePatch::Postfix#16" => "Writes and saves vanilla LastAcceptedPrivacyPolicyVersion for the mod consent flow.",
            "EHR.ChatControllerAwakePatch::Postfix#41" => "Forces native QuickChatOnly mode to FreeChatOrQuickChat.",
            "EHR.RunLoginPatch::Prefix#54" => "Forces canOnline true under a mod debugger or missing mod consent.",
            "EHR.CheckOnlinePermissionsPatch::Prefix#60" => "Resets vanilla player banPoints to zero before native permission checks.",
            "EHR.GameStartManagerBeginPatch+GameStartManagerStartPatch::Prefix#138" => "Writes and saves vanilla player onboarding warning flags.",
            _ => string.Empty
        };
        return reason.Length != 0;
    }
}
