using System;

namespace EHR.SourceHost;

// A signed iOS application cannot replace itself with a desktop mod assembly.
// This backend only opens host-configured update instructions after a source UI
// action. It performs no download, installation, file move, or account operation.
public static class SourceSignedUpdates
{
    private static Uri? instructions;
    private static Action<Uri>? open;
    private static Func<bool>? main;
    private static bool configured;
    public static string? ConfiguredUrl=>instructions?.AbsoluteUri;
    public static bool HasInstructions=>instructions is not null;
    public static string ActionTitle=>HasInstructions?"iPhone Update Instructions":"Update Details";
    public static string StatusMessage=>HasInstructions
        ?"Install the rebuilt, signed iPhone app using the configured update instructions. Opening instructions does not install an update."
        :"A rebuilt, signed iPhone app is required for this update. No iPhone update instructions are configured for this build.";
    public static void Configure(Uri? signedAppInstructions,Action<Uri>? openInstructions,Func<bool> isMainThread)
    {
        ArgumentNullException.ThrowIfNull(isMainThread);
        if(!isMainThread())throw new InvalidOperationException("Configure iOS updates on the main thread.");
        if(configured)throw new InvalidOperationException("iOS update configuration is immutable.");
        if(signedAppInstructions is not null&&(!signedAppInstructions.IsAbsoluteUri||signedAppInstructions.Scheme!=Uri.UriSchemeHttps||!string.IsNullOrEmpty(signedAppInstructions.UserInfo)))
            throw new ArgumentException("Update instructions require an absolute HTTPS URL without credentials.",nameof(signedAppInstructions));
        if((signedAppInstructions is null)!=(openInstructions is null))throw new ArgumentException("An update URL and its opener must be configured together.");
        instructions=signedAppInstructions;open=openInstructions;main=isMainThread;configured=true;
    }
    public static bool OpenInstructions()
    {
        if(!configured||main is null)throw new InvalidOperationException("Configure the signed iOS update backend before source startup.");
        if(!main())throw new InvalidOperationException("Open update instructions on the main thread.");
        if(instructions is null)return false;
        open!(instructions);return true;
    }
}
