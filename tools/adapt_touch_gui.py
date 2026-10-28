#!/usr/bin/env python3
"""Pinned, explicit iOS rendering adaptation of EHR ClientControlGUI only.

Does not edit upstream. All host command bodies (DrawButtons through EOF) are
verified unchanged. Scene subscription ownership is a later independent pass.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

UPSTREAM_SHA256 = 'c88b2c3a95d223445a1b444237f0c2c91071c2ed616f57c79510315f0cf92281'

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def once(text: str, before: str, after: str) -> str:
    if text.count(before) != 1:
        raise ValueError("Expected exactly one pinned rendering anchor: " + before[:80])
    return text.replace(before, after, 1)

def section(text: str, start: str, end: str, replacement: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError("Rendering section anchor mismatch")
    first = text.index(start)
    last = text.index(end, first)
    return text[:first] + replacement + text[last:]

def transform(data: bytes, expected_sha256: str = UPSTREAM_SHA256) -> tuple[bytes, dict]:
    if sha(data) != expected_sha256:
        raise ValueError("ClientControlGUI input hash does not match reviewed source")
    text = data.decode("utf-8")
    command_start = "    private void DrawButtons(ref float y, float w)"
    command_body = text[text.index(command_start):]
    text = once(text, "using static EHR.Translator;", "using static EHR.Translator;\nusing GUI = EHR.Generated.TouchGUI;\nusing GUIStyle = EHR.Generated.TouchGUIStyle;\nusing Texture2D = EHR.Generated.TouchTexture;")
    text = once(text, "private static float Scale   => Screen.width / 1080f * PlatformScale;", "private static float Scale   => GUI.PixelsPerPoint * 0.72f;")
    text = once(text, "    private void OnDestroy()\n    {", "    private void OnDestroy()\n    {\n        GUI.Hide();")
    start = "    private static Texture2D RoundedTexture(int width, int height, int radius, Color fill, Color edge)"
    end = "    /// <summary>\n    /// Returns 0 if outside (transparent)"
    text = section(text, start, end, start + "\n        => new Texture2D(Math.Max(1, width), Math.Max(1, height), Math.Max(0, radius), fill, edge);\n\n")
    start = "    private void OnGUI()"
    end = "    // Draws the small toggle button"
    text = section(text, start, end, """    private void OnGUI()
    {
        if (!HudManager.InstanceExists) { GUI.Hide(); return; }
        if (!GUI.BeginFrame(Screen.width, Screen.height)) return;
        bool committed = false;
        try
        {
            if (!_windowInitialized) InitWindowRect();
            if (Math.Abs(_lastScale - Scale) > 0.01f) RebuildStyles();
            HandleDrag();
            DrawToggle();
            if (IsOpen) DrawWindow();
            committed = true;
        }
        finally { GUI.EndFrame(committed); }
    }

""")
    start = "    private void HandleDrag()"
    end = "    // Draws the window background"
    text = section(text, start, end, """    private void HandleDrag()
    {
        if (IsOpen) GUI.MoveWindow(ref _windowRect, ButtonHeight * 0.80f + Padding);
    }

""")
    text = once(text, "float size = 48f * Scale;", "float size = 64f * Scale;")
    text = once(text, "        ToggleRect = new Rect(x, y, size, size);", "        GUI.ClampToSafeArea(ref x, ref y, size, size);\n        ToggleRect = new Rect(x, y, size, size);")
    start = "    private static string Label(string label, string shortcut = null)"
    end = "    // Draws buttons based on game state"
    text = section(text, start, end, start + " => label; // UIKit touch controls omit desktop shortcut chips.\n\n")
    rendered_commands = text[text.index(command_start):]
    if rendered_commands != command_body:
        raise ValueError("Host command body changed")
    output = text.encode("utf-8")
    return output, {"inputSha256":sha(data),"outputSha256":sha(output),"drawButtonsSha256":sha(command_body.encode()),"drawButtonsUnchanged":True,"scope":"ClientControlGUI rendering only","sceneSubscriptionOwnership":"separate required pass","runtimeStatus":"requires bound native UIKit renderer and tested source component lifecycle","knownSeparateGap":"Original Android-only NoClip collider adjustment is unchanged; iOS behavior not claimed."}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--expected-sha256",default=UPSTREAM_SHA256)
    args=parser.parse_args()
    try:
        output,report=transform(args.input.read_bytes(),args.expected_sha256)
        if args.output.resolve()==args.input.resolve():
            raise ValueError("Output must be separate from input")
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_bytes(output)
        args.output.with_suffix(args.output.suffix+".provenance.json").write_text(json.dumps(report,indent=2)+"\n")
    except (ValueError,OSError,UnicodeError) as error:
        parser.exit(2,str(error)+"\n")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
