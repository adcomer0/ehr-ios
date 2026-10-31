#!/usr/bin/env python3
"""Remove only the pinned join-prefix clipboard log from a fresh source copy.

Validation, trimming, SetText and the original callback remain byte-identical.
The adapter reads source bytes only, never the clipboard, game or account data.
"""
from pathlib import Path
import argparse
import hashlib
import json

REVIEWED_INPUT_SHA256 = "af3f50b07ee2f0e226a60f8f61e2c1a59fea8a7a3189ddd0e60055f0419876bc"
LOG_LINE = b'            Logger.Info($"{GUIUtility.systemCopyBuffer}", "ClipBoard");'
PREFIX = b"    public static void Prefix(JoinGameButton __instance)"
CALLBACK = b"    internal static void __EHRStaticCallback_171("
SET_TEXT = b"            __instance.GameIdText.SetText(GUIUtility.systemCopyBuffer.Trim('\\r', '\\n'));"


def transform(data, expected_sha256=REVIEWED_INPUT_SHA256):
    if hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError("Selected join source hash mismatch")
    if data.count(PREFIX) != 1 or data.count(CALLBACK) != 1 or data.count(LOG_LINE) != 1 or data.count(SET_TEXT) != 1:
        raise ValueError("Reviewed join prefix changed or ambiguous")
    index = data.index(LOG_LINE)
    if not data.index(PREFIX) < index < data.index(SET_TEXT) < data.index(CALLBACK):
        raise ValueError("Clipboard log is outside the reviewed join prefix")
    if index and data[index - 1:index] != b"\n":
        raise ValueError("Reviewed clipboard log is not an exact source line")
    end = index + len(LOG_LINE)
    ending = b"\r\n" if data[end:end + 2] == b"\r\n" else b"\n"
    if data[end:end + len(ending)] != ending:
        raise ValueError("Reviewed clipboard log line ending changed")
    result = data[:index] + data[end + len(ending):]
    return result, {
        "schema": "ehr.join-clipboard-log-removal.v1",
        "inputSha256": expected_sha256,
        "outputSha256": hashlib.sha256(result).hexdigest(),
        "clipboardLogRemoved": True,
        "joinValidationUnchanged": True,
        "originalJoinCallbackUnchanged": True,
        "clipboardWritesAdded": False,
        "actualClipboardRead": False,
        "actualGameJoin": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--input-sha256", default=REVIEWED_INPUT_SHA256)
    args = parser.parse_args()
    report_path = args.output.with_suffix(".join-privacy.json")
    if args.input.resolve() == args.output.resolve() or args.output.exists() or report_path.exists():
        parser.error("Choose fresh separate output and report paths")
    result, report = transform(args.input.read_bytes(), args.input_sha256)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(result)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
