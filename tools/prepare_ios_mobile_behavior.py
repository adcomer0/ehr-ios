#!/usr/bin/env python3
"""Post-UIKit iOS collider behavior only; desktop/host/account guards unchanged."""
from pathlib import Path
import argparse,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--gui-source',type=Path,required=True);p.add_argument('--platform-source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);s=a.gui_source.read_text();before=s
def once(text,old,new):
 if text.count(old)!=1:raise ValueError('pinned source anchor changed: '+old)
 return text.replace(old,new)
if 'using GUI = EHR.Generated.TouchGUI;' not in s or 'EHR.Generated.SourceSceneEvents.Own(' not in s:raise ValueError('apply after UIKit presentation and exact Scene ownership adapters')
guard='bool canNoClip = canMove && Main.IntroDestroyed && (!AmongUsClient.Instance.IsGameStarted || !GameStates.IsOnlineGame) && (!GameStartManager.Instance || GameStartManager.Instance.startState == GameStartManager.StartingStates.NotStarting);'
if s.count(guard)!=1:raise ValueError('original lobby/offline/countdown NoClip predicate changed')
s=once(s,'if (OperatingSystem.IsAndroid()) PlayerControl.LocalPlayer.Collider.offset = ControllerManagerUpdatePatch.NoClipEnabled ?',
 'if (OperatingSystem.IsAndroid() || OperatingSystem.IsIOS()) PlayerControl.LocalPlayer.Collider.offset = ControllerManagerUpdatePatch.NoClipEnabled ?')
s=once(s,'else if (ControllerManagerUpdatePatch.NoClipEnabled && OperatingSystem.IsAndroid() && PlayerControl.LocalPlayer)',
 'else if (ControllerManagerUpdatePatch.NoClipEnabled && (OperatingSystem.IsAndroid() || OperatingSystem.IsIOS()) && PlayerControl.LocalPlayer)')
s=once(s,'    private void OnGUI()\n    {','    private void OnGUI()\n    {\n        ReconcileIOSNoClip();')
s=once(s,'    private void OnDestroy()\n    {\n        GUI.Hide();','    private void OnDestroy()\n    {\n        GUI.Hide();\n        ResetIOSNoClip();')
s=once(s,'        _cam = Camera.main;\n        HudHidden = false;','        _cam = Camera.main;\n        HudHidden = false;\n        ResetIOSNoClip();')
helpers='''    // iOS touch input uses the same eligibility rule as the original button.
    // Reconciliation only DISABLES; it never enables NoClip without a tap.
    private static bool IOSNoClipStillEligible()
    {
        var player = PlayerControl.LocalPlayer;
        if (!player) return false;
        var client = AmongUsClient.Instance;
        if (!client) return false;
        return GameStates.IsCanMove && Main.IntroDestroyed && (!client.IsGameStarted || !GameStates.IsOnlineGame) && (!GameStartManager.Instance || GameStartManager.Instance.startState == GameStartManager.StartingStates.NotStarting);
    }

    private static void ResetIOSNoClip()
    {
        if (!OperatingSystem.IsIOS() || !ControllerManagerUpdatePatch.NoClipEnabled) return;
        var player = PlayerControl.LocalPlayer;
        if (player && player.Collider) player.Collider.offset = new Vector2(0f, -0.3636f);
        ControllerManagerUpdatePatch.NoClipEnabled = false;
    }

    private static void ReconcileIOSNoClip()
    {
        if (OperatingSystem.IsIOS() && ControllerManagerUpdatePatch.NoClipEnabled && !IOSNoClipStillEligible()) ResetIOSNoClip();
    }

'''
s=once(s,'    private void DrawButtons(ref float y, float w)',helpers+'    private void DrawButtons(ref float y, float w)')
if s.count(guard)!=1:raise ValueError('NoClip guard unexpectedly modified')
(out/'ClientControlGUI.cs').write_text(s)
platform=a.platform_source.read_text();originalPlatform=platform
platform=once(platform,'    private static readonly bool Android = Application.platform == RuntimePlatform.Android;',
 '    private static readonly bool Android = Application.platform == RuntimePlatform.Android;\n    private static readonly bool IOS = Application.platform == RuntimePlatform.IPhonePlayer;')
platform=once(platform,'    public static bool IsAndroid() => Android;',
 '    public static bool IsAndroid() => Android;\n    public static bool IsIOS() => IOS;')
(out/'OperatingSystem.cs').write_text(platform)
report={'schema':'ehr.pinned-ios-collider-behavior.v1','inputs':{str(a.gui_source):hashlib.sha256(before.encode()).hexdigest(),str(a.platform_source):hashlib.sha256(originalPlatform.encode()).hexdigest()},'outputs':{'ClientControlGUI.cs':hashlib.sha256(s.encode()).hexdigest(),'OperatingSystem.cs':hashlib.sha256(platform.encode()).hexdigest()},'originalNoClipAvailabilityGuardUnchanged':True,'mobileColliderConditionsExtended':2,'reconcileBeforeHudAndFrameEarlyReturns':True,'reconciliationOnlyDisables':True,'sceneAndDestroyRestoreIOSCollider':True,'androidAndDesktopKeyboardBehaviorUnchanged':True,'hostOrOnlinePolicyWeakened':False,'accountsChanged':False,'actualGameplayVerified':False}
(out/'ios-behavior.json').write_text(json.dumps(report,indent=2)+'\n');print(out)
