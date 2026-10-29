#!/usr/bin/env python3
"""Compile the extracted original/adapted iterator control flow, with own actions."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("prepare_settings_build_cleanup", HERE / "prepare_settings_build_cleanup.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

# These delimiters cover only game/UI work. The actual for/yield/catch,
# generation branch and finally are copied into the compiled fixture intact.
SETUP_START = "            var num = 2.0f;"
LOOP_START = "            for (var index = 0; index < OptionItem.AllOptions.Count; index++)"
WORK_START = "                    OptionItem option = OptionItem.AllOptions[index];"
WORK_END = "                    if (enabledOrNotCollapsed) num -= 0.45f;"
FINISH_START = "            __instance.ControllerSelectable.Clear();"
FINISH_END = "            Canvas.ForceUpdateCanvases();"


def extract_control_flow(source):
    _, _, routine = prepare.split_routine(source)
    # Normalize the added try indentation temporarily, so both variants have
    # identical work anchors. Restore it before compiling the actual variant.
    adapted = routine.startswith(prepare.START + prepare.TRY_START)
    body = routine[len(prepare.START):-len("        }\n")]
    if adapted:
        if not body.endswith(prepare.FINALLY):
            raise ValueError("adapted finally changed")
        body = prepare.unindent(body[len(prepare.TRY_START):-len(prepare.FINALLY)])
    for marker in (SETUP_START, LOOP_START, WORK_START, WORK_END, FINISH_START, FINISH_END):
        if body.count(marker) != 1:
            raise ValueError("game-work extraction delimiter changed: " + marker)
    setup_start, setup_end = body.index(SETUP_START), body.index(LOOP_START)
    body = body[:setup_start] + body[setup_end:]
    work_start = body.index(WORK_START)
    work_end = body.index(WORK_END, work_start) + len(WORK_END)
    body = body[:work_start] + "                    Step(index);" + body[work_end:]
    finish_start = body.index(FINISH_START)
    finish_end = body.index(FINISH_END, finish_start) + len(FINISH_END)
    body = body[:finish_start] + "            FinishUi();" + body[finish_end:]
    if adapted:
        body = prepare.TRY_START + prepare.indent(body) + prepare.FINALLY
    return prepare.START + body + "        }\n"


def check(project, output, dotnet, source=None):
    output = output.resolve()
    if output.exists():
        raise ValueError("fresh output required")
    if source is None:
        _, (_, source) = prepare.selected_source(project.resolve())
    else:
        source = source.resolve()
    changed = source.read_text()
    original = prepare.reverse(changed)
    if hashlib.sha256(original.encode()).hexdigest() != prepare.EXPECTED_SOURCE_SHA256:
        raise ValueError("recovered baseline source pin changed")
    output.mkdir(parents=True)
    generated = []
    for name, text in (("ActualSettingsBuild", changed), ("BaselineSettingsBuild", original)):
        path = output / (name + ".cs")
        path.write_text("using System;\nusing System.Collections;\nnamespace EHR.OwnBuildFixture;\n"
                        + "internal sealed class " + name + " : BuildState\n{\n"
                        + "    internal override IEnumerator Routine(int gen) => CoRoutine(gen);\n"
                        + extract_control_flow(text) + "}\n")
        generated.append(path)
    fixture_source = HERE.parent / "tests/SettingsBuildCleanupFixture.cs"
    tree = ET.Element("Project", Sdk="Microsoft.NET.Sdk")
    properties = ET.SubElement(tree, "PropertyGroup")
    for key, value in {"TargetFramework": "net10.0", "OutputType": "Exe", "EnableDefaultCompileItems": "false", "Nullable": "enable"}.items():
        ET.SubElement(properties, key).text = value
    items = ET.SubElement(tree, "ItemGroup")
    for path in [fixture_source] + generated:
        ET.SubElement(items, "Compile", Include=str(path))
    fixture_project = output / "Fixture.csproj"
    ET.ElementTree(tree).write(fixture_project, encoding="unicode")
    result = subprocess.run([str(dotnet), "run", "--project", str(fixture_project), "-c", "Release", "--nologo"], capture_output=True, text=True, env=os.environ.copy())
    (output / "fixture.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError("control-flow fixture failed: " + (result.stdout + result.stderr)[-6000:])
    proof = json.loads(next(line for line in result.stdout.splitlines() if line.startswith("{")))
    proof["sourcePins"] = {str(path): prepare.sha(path) for path in [source, fixture_source] + generated}
    proof["baselineSourceSha256"] = prepare.EXPECTED_SOURCE_SHA256
    proof["actualIteratorControlFlowExtracted"] = True
    proof["gameUiWorkReplacedByOwnInjectedActions"] = True
    proof["gameAccountDeviceOperations"] = False
    (output / "proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    return output / "proof.json"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    selected = parser.add_mutually_exclusive_group(required=True)
    selected.add_argument("--project", type=Path)
    selected.add_argument("--source", type=Path, help="Exact selected adapted settings source; needs no game or resource inputs")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dotnet", type=Path, required=True)
    args = parser.parse_args()
    print(check(args.project, args.output, args.dotnet, args.source))
