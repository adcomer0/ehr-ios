#!/usr/bin/env python3
"""Add opt-in, natively gated directory support to the exact protected snapshot.

Writes a fresh derived six-file overlay and manifest outside Git. It never
opens a game, reads a credential, contacts a service or alters the six protected
callback exclusions. The unrelated callback/command tails stay byte-identical.
"""
from pathlib import Path
import argparse
import hashlib
import json

HERE = Path(__file__).resolve().parent
FILES = {
    "compiled/81/LobbySharingAPI.cs": "5bb57c0d8246d05ba63fe95105ef03b5d40fed27ca70c192908b06bc1d4f416e",
    "compiled/102/OptionHolder.cs": "1e6245db5b1aabe290cd9f721de33c0442472ad7d8e4bb940de87e54d1e835ac",
    "compiled/106/OptionItem.cs": "b507632168bb2ca6568242f9f8a8fb7a08f574f9608e8637fc7d1e5d260d8274",
    "compiled/117/RPC.cs": "321fe6e7daaff0b6fc9bf3879298aeb79106416a69a011f3cc60f87a8fef0f39",
    "compiled/138/ChatCommandPatch.cs": "95eadf5ba14556a177feef5c3b6a3278c0ba3674d42eec97df86d5b3e6ba357e",
    "compiled/780/EHRProtectedLobbyDirectoryOption.cs": "a42ba328faf04fbb44a37d70df48191793d7a67ae584201d324c8ee9d1a61f1e",
}
LOG_SITES = {
    "compiled/138/ChatCommandPatch.cs": [
        b'Logger.Info(text, "SendChat");',
        b'Logger.Info($" Recognized command: {text}", "ChatCommand");',
        b'Logger.Info($" Recognized command: {text}", "ReceiveChat");',
    ],
    "compiled/117/RPC.cs": [
        b'Logger.Info($"({__instance.FriendCode}|{__instance.GetClient()?.GetHashedPuid()}) {__instance.GetNameWithRole()}: {text}", "ReceiveChat");',
        b'Logger.Info($"Invoke Command: {command.Action.Method.Name} ({__instance.Data?.PlayerName}, {text})", "RequestCommandProcessing");',
    ],
}


def redact_logs(inputs):
    result = dict(inputs)
    for name, sites in LOG_SITES.items():
        for site in sites:
            safe = site.replace(b"{text}", b"{EHRDirectoryLog.ForLog(text)}") if b"{text}" in site else site.replace(b"Logger.Info(text,", b"Logger.Info(EHRDirectoryLog.ForLog(text),")
            result[name] = once(result[name], site, safe)
    return result


def sha(data):
    return hashlib.sha256(data).hexdigest()


def once(data, old, new):
    if data.count(old) != 1:
        raise ValueError("Directory overlay anchor absent, changed or ambiguous")
    return data.replace(old, new)


def replace_span(data, start, end, replacement):
    if data.count(start) != 1:
        raise ValueError("Directory declaration absent or ambiguous")
    begin = data.index(start)
    finish = data.find(end, begin)
    if finish < 0:
        raise ValueError("Directory declaration end absent")
    return data[:begin] + replacement + data[finish:]


def adapt(inputs):
    result = dict(inputs)
    body = (HERE / "lobby_directory/LobbySharingAPI.body.cs").read_bytes()
    name = "compiled/81/LobbySharingAPI.cs"
    result[name] = replace_span(inputs[name], b"// The optional EHR directory is unavailable", b'[SuppressMessage(', body + b'\n\n')
    name = "compiled/102/OptionHolder.cs"
    result[name] = once(inputs[name], b'new EHRProtectedLobbyDirectoryOption(19422,', b'new EHRLobbyDirectoryOption(19422,')
    result[name] = once(result[name], b'.SetValueFormat(OptionFormat.Seconds)\n            .SetHidden(true);', b'.SetValueFormat(OptionFormat.Seconds);')
    name = "compiled/106/OptionItem.cs"
    result[name] = once(inputs[name], b'if (this is EHRProtectedLobbyDirectoryOption) return EHRProtectedLobbyDirectoryOption.Label;', b'if (this is EHRLobbyDirectoryOption) return EHRLobbyDirectoryOption.Label;')
    name = "compiled/138/ChatCommandPatch.cs"
    start = b'    private static void ConfirmAuthCommand(PlayerControl player, string text, string[] args)'
    end = b'    public static void RetributeCommand('
    command = b'''    private static void ConfirmAuthCommand(PlayerControl player, string text, string[] args)
    {
        EHR.Modules.LobbySharingAPI.ConfirmAuth(player, args);
    }

'''
    result[name] = replace_span(inputs[name], start, end, command)
    result["compiled/780/EHRProtectedLobbyDirectoryOption.cs"] = (HERE / "lobby_directory/DirectorySupport.cs").read_bytes()
    return redact_logs(result)


def prepare(source_root, output):
    if output.exists() or any((parent / ".git").exists() for parent in (output, *output.parents)):
        raise ValueError("Directory output must be a fresh path outside Git")
    inputs = {name: (source_root / name).read_bytes() for name in FILES}
    for name, expected in FILES.items():
        if sha(inputs[name]) != expected:
            raise ValueError("Protected source pin differs: " + name)
    manifest = json.loads((source_root / "manifest.json").read_text())
    if len(manifest["sources"]) != 796:
        raise ValueError("Expected the reviewed 796-source selection")
    for name in FILES:
        rows = [row for row in manifest["sources"] if row["path"] == name]
        if len(rows) != 1 or rows[0]["sha256"] != FILES[name]:
            raise ValueError("Protected manifest pin differs: " + name)
    result = adapt(inputs)
    for row in manifest["sources"]:
        if row["path"] in result:
            row["sha256"] = sha(result[row["path"]])
    output.mkdir(parents=True)
    for name, data in result.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    report = {"schema": "ehr.opt-in-directory-overlay.v1", "sourceCount": 796,
              "resourceCatalogUnchanged": True, "sixProtectedExclusionsUnchanged": True,
              "levelCommandUnchanged": True, "directoryDefaultEnabled": False,
              "nativeGateDefaultDeny": True, "mainThreadRecoveryTickIncluded": True,
              "genericCommandLogSitesRedacted": 5,
              "httpRequestsPerformed": 0,
              "files": {name: {"before": FILES[name], "after": sha(data)} for name, data in result.items()}}
    (output / "directory-overlay.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = prepare(args.source_root.resolve(), args.output.resolve())
    print(json.dumps(report))


if __name__ == "__main__":
    main()
