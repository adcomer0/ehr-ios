#!/usr/bin/env python3
"""Compile the selected chat-mode gate with owned settings/writer stand-ins.

No game assembly, native gateway, network writer, or authentication is loaded.
An optional original source verifies that only the helper and guard were added.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise ValueError("Incomplete selected guard block")


def selected(source, baseline=None):
    helper = block(source, "    private static bool CanSendSystemNetworkChat()")
    expected = """private static bool CanSendSystemNetworkChat()
    { try { return DataManager.Settings?.Multiplayer?.ChatMode == QuickChatModes.FreeChatOrQuickChat; }
      catch { return false; } }"""
    if helper.split() != expected.split():
        raise ValueError("Selected helper must use the unchanged native current-mode decision and fail closed")
    local = block(source, "            if (sendTo != byte.MaxValue && receiver.AmOwner)")
    gate = block(source, "            if (!CanSendSystemNetworkChat())")
    expected_gate = """if (!CanSendSystemNetworkChat())
    { if (sendTo == byte.MaxValue) SendLocally(sender); return writer; }"""
    if gate.split() != expected_gate.split():
        raise ValueError("Selected denied path must preserve only local broadcast and return the supplied writer")
    start = source.index("    public static CustomRpcSender SendMessage(")
    for marker in ("SplitByNumberLimit(text)", "writer = CustomRpcSender.Create(", "writer.AutoStartRpc("):
        if not start < source.index(local, start) < source.index(gate, start) < source.index(marker, start):
            raise ValueError("Permission gate must precede every writer/splitting path and follow local-only delivery")
    if source.count("if (!CanSendSystemNetworkChat())") != 1:
        raise ValueError("Duplicate permission guard")
    allocation = re.search(r'            if \(writer == null \|\| writer.CurrentState == CustomRpcSender.State.Finished\)\n'
                           r'                writer = CustomRpcSender.Create\("Utils.SendMessage\(1\)", sendOption\);', source)
    if allocation is None:
        raise ValueError("Original writer-selection branch changed")
    if baseline is not None:
        restored = source.replace(helper + "\n\n", "", 1).replace(gate + "\n\n", "", 1)
        if restored != baseline:
            raise ValueError("Changes beyond the permission helper/gate")
    return helper, local, gate, allocation.group()


def fixture_source(parts):
    helper, local, gate, allocation = parts
    return r'''using System;
using System.Collections.Generic;
static class Context {
    public static bool NoSettings,NoMultiplayer,ThrowSettings,ThrowMultiplayer,ThrowMode;
    public static int Mode,Reads,LocalDisplays,Creates,NetworkWrites;
    public static void Reset(int mode,int flags) {
        Mode=mode;NoSettings=(flags&1)!=0;NoMultiplayer=(flags&2)!=0;
        ThrowSettings=(flags&4)!=0;ThrowMultiplayer=(flags&8)!=0;ThrowMode=(flags&16)!=0;
        Reads=LocalDisplays=Creates=NetworkWrites=0;ChatUpdatePatch.LastMessages.Clear();
    }
}
enum QuickChatModes { FreeChatOrQuickChat=1,QuickChatOnly=2 }
enum SendOption { Reliable }
static class DataManager { public static Settings? Settings {get {
    ++Context.Reads;if(Context.ThrowSettings)throw new InvalidOperationException();
    return Context.NoSettings?null:new Settings(); }} }
sealed class Settings { public Multiplayer? Multiplayer {get {
    ++Context.Reads;if(Context.ThrowMultiplayer)throw new InvalidOperationException();
    return Context.NoMultiplayer?null:new Multiplayer(); }} }
sealed class Multiplayer { public QuickChatModes ChatMode {get {
    ++Context.Reads;if(Context.ThrowMode)throw new InvalidOperationException();return (QuickChatModes)Context.Mode; }} }
sealed class Receiver {public bool AmOwner;}
sealed class CustomRpcSender {
    public enum State {Ready,Finished}
    public State CurrentState;public int Mutations=17;
    public static CustomRpcSender Create(string ignored,SendOption option) {
        ++Context.Creates;return new CustomRpcSender();
    }
    public void OwnedNetworkSentinel() {++Mutations;++Context.NetworkWrites;}
}
static class ChatUpdatePatch {public static List<(string,byte,string,long)> LastMessages=new();}
static class Program {
    static long checks,cases;
    static void Check(bool value) {++checks;if(!value)throw new Exception("Owned mode-gate assertion "+checks);}
    static void SendLocally(object sender) {++Context.LocalDisplays;}
''' + helper + r'''
    static CustomRpcSender? Send(byte sendTo,bool own,CustomRpcSender? writer,bool addToHistory) {
        var receiver=new Receiver{AmOwner=own};object sender=new();string text="owned",title="owned";
        long TimeStamp=0;SendOption sendOption=SendOption.Reliable;
''' + local + "\n" + gate + "\n" + allocation + r'''
        writer.OwnedNetworkSentinel();return writer;
    }
    static void Main() {
        int[] modes={int.MinValue,-1,0,1,2,3,int.MaxValue};
        foreach(int mode in modes)for(int flags=0;flags<32;++flags)
        for(int target=0;target<3;++target)for(int state=0;state<3;++state)for(int history=0;history<2;++history) {
            ++cases;Context.Reset(mode,flags);
            byte sendTo=target==0?byte.MaxValue:(byte)7;bool own=target==2;
            var original=state==0?null:new CustomRpcSender {CurrentState=state==2?CustomRpcSender.State.Finished:CustomRpcSender.State.Ready};
            bool permitted=mode==1 && flags==0;
            var result=Send(sendTo,own,original,history==1);
            if(own) {
                Check(Context.Reads==0);Check(Context.LocalDisplays==1);
                Check(ChatUpdatePatch.LastMessages.Count==history);
            } else if(!permitted) {
                Check(Context.LocalDisplays==(target==0?1:0));Check(ChatUpdatePatch.LastMessages.Count==0);
            } else {
                Check(Context.LocalDisplays==0);Check(ChatUpdatePatch.LastMessages.Count==0);
            }
            if(own || !permitted) {
                Check(Context.Creates==0);Check(Context.NetworkWrites==0);Check(ReferenceEquals(result,original));
                Check(original is null || original.Mutations==17);
                Check(original is null || original.CurrentState==(state==2?CustomRpcSender.State.Finished:CustomRpcSender.State.Ready));
            } else {
                Check(Context.NetworkWrites==1);Check(Context.Creates==(state==1?0:1));
                Check(result is not null && result.Mutations==18);
                Check(state!=1 || ReferenceEquals(result,original));
                Check(state==1 || !ReferenceEquals(result,original));
                Check(original is null || state==1 || original.Mutations==17);
            }
        }
        Console.WriteLine("{\"pass\":true,\"checks\":"+checks+",\"cases\":"+cases+
            ",\"gameCalls\":0,\"networkOperations\":0,\"accountOperations\":0,\"originalSelectedCode\":true}");
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "source-app/compiled/131/Utils.cs")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dotnet", default=os.environ.get("EHR_DOTNET", "dotnet"))
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or any((parent / ".git").exists() for parent in output.parents):
        parser.error("A fresh output directory outside Git is required")
    source = args.source.read_text()
    baseline = args.baseline.read_text() if args.baseline else None
    parts = selected(source, baseline)
    output.mkdir(parents=True)
    (output / "Program.cs").write_text(fixture_source(parts))
    (output / "Own.csproj").write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>'
        '<TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable><ImplicitUsings>disable</ImplicitUsings>'
        '<RestoreIgnoreFailedSources>true</RestoreIgnoreFailedSources></PropertyGroup></Project>')
    environment = {**os.environ,"DOTNET_CLI_TELEMETRY_OPTOUT":"1","DOTNET_GENERATE_ASPNET_CERTIFICATE":"false","DOTNET_NOLOGO":"1"}
    result = subprocess.run([args.dotnet,"run","--project",str(output / "Own.csproj"),"-c","Release","--nologo"],
        text=True,capture_output=True,env=environment,timeout=90)
    (output / "compile.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError("Owned fixture compilation/execution failed; see output compile.log")
    proof = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{"pass"')))
    proof.update(schema="ehr.system-chat-mode-proof.v1",sourceSHA256=hashlib.sha256(source.encode()).hexdigest(),
        exactOriginalBodyPreserved=baseline is not None,
        scope="Selected helper, local early branch, guard and writer selection; remaining network code uses an owned sentinel")
    (output / "proof.json").write_text(json.dumps(proof,indent=2)+"\n")
    print(json.dumps(proof))


if __name__ == "__main__":
    main()
