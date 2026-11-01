#!/usr/bin/env python3
"""Pin and scope settings-build retirement to the iterator's own generation."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import xml.etree.ElementTree as ET

EXPECTED_SOURCE_SHA256 = "8f0c225439e6b56546b5e6da120d4acc981c7d6bc4f547176ffac1b735e3feee"
START = "        IEnumerator CoRoutine(int gen)\n        {\n"
FOLLOWING = "\n        float CalculateScrollBarYBoundsMax()"
STALE_OLD = """            if (!BuildGenerations.TryGetValue(__instance, out int latestGen) || latestGen != gen)
            {
                BuildCoroutines.Remove(__instance);
                yield break;
            }"""
STALE_NEW = STALE_OLD.replace("                BuildCoroutines.Remove(__instance);\n", "")
NORMAL_OLD = "            Canvas.ForceUpdateCanvases();\n            BuildCoroutines.Remove(__instance);\n"
NORMAL_NEW = "            Canvas.ForceUpdateCanvases();\n"
TRY_START = "            try\n            {\n"
FINALLY = """            }
            finally
            {
                // A retired iterator must not remove a replacement generation.
                if (BuildGenerations.TryGetValue(__instance, out int completedGen) && completedGen == gen)
                    BuildCoroutines.Remove(__instance);
            }
"""


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def selected_source(project):
    tree = ET.parse(project)
    selected = []
    for item in tree.getroot().iter():
        if local_name(item.tag) != "Compile":
            continue
        path = Path(item.get("Include", ""))
        path = path if path.is_absolute() else (project.parent / path).resolve()
        if path.name == "GameOptionsMenuPatch.cs":
            selected.append((item, path))
    if len(selected) != 1:
        raise ValueError("one selected GameOptionsMenuPatch.cs required")
    return tree, selected[0]


def split_routine(source):
    if source.count(START) != 1 or source.count(FOLLOWING) != 1:
        raise ValueError("settings build routine boundaries changed")
    start = source.index(START)
    end = source.index(FOLLOWING, start)
    routine = source[start:end]
    if not routine.endswith("        }\n"):
        raise ValueError("settings build routine terminator changed")
    return start, end, routine


def indent(text):
    return "".join("    " + line if line.strip() else line for line in text.splitlines(True))


def unindent(text):
    result = []
    for line in text.splitlines(True):
        if line.strip():
            if not line.startswith("    "):
                raise ValueError("adapted routine indentation changed")
            line = line[4:]
        result.append(line)
    return "".join(result)


def adapt(source):
    start, end, routine = split_routine(source)
    body = routine[len(START):-len("        }\n")]
    if body.count(STALE_OLD) != 1 or body.count(NORMAL_OLD) != 1 or FINALLY in routine:
        raise ValueError("pinned build cleanup anchors changed")
    body = body.replace(STALE_OLD, STALE_NEW).replace(NORMAL_OLD, NORMAL_NEW)
    changed = START + TRY_START + indent(body) + FINALLY + "        }\n"
    return source[:start] + changed + source[end:]


def reverse(source):
    source = before_loading_adaptation(source)
    start, end, routine = split_routine(source)
    if not routine.startswith(START + TRY_START) or not routine.endswith(FINALLY + "        }\n"):
        raise ValueError("adapted cleanup wrapper changed")
    body = unindent(routine[len(START + TRY_START):-len(FINALLY + "        }\n")])
    if body.count(STALE_NEW) != 1 or body.count(NORMAL_NEW) != 1:
        raise ValueError("adapted cleanup anchors changed")
    body = body.replace(STALE_NEW, STALE_OLD).replace(NORMAL_NEW, NORMAL_OLD)
    return source[:start] + START + body + "        }\n" + source[end:]


def before_loading_adaptation(source):
    """Recover this older cleanup profile before checking its exact anchors."""
    if "ehr_source_settings_loading_v1" not in source:
        return source
    path = Path(__file__).resolve().parent / "source_port/prepare_settings_loading.py"
    spec = importlib.util.spec_from_file_location("settings_loading_reversal", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.reverse(source)


def normalize_paths(tree, project):
    tags = {"Compile", "EmbeddedResource", "Content", "None", "AdditionalFiles", "Reference", "ProjectReference", "Import"}
    for element in tree.getroot().iter():
        tag = local_name(element.tag)
        if tag not in tags:
            continue
        for attribute in ("Include", "Update", "Project"):
            value = element.get(attribute)
            if not value or "$(" in value or "@(" in value or (tag == "Reference" and attribute == "Include"):
                continue
            path = Path(value)
            if not path.is_absolute():
                element.set(attribute, str((project.parent / path).resolve()))
        for child in element:
            if local_name(child.tag) == "HintPath" and child.text and "$(" not in child.text and not Path(child.text).is_absolute():
                child.text = str((project.parent / child.text).resolve())


def prepare(project, output):
    project, output = project.resolve(), output.resolve()
    if output.exists():
        raise ValueError("fresh output required")
    tree, (item, source) = selected_source(project)
    if sha(source) != EXPECTED_SOURCE_SHA256:
        raise ValueError("selected settings source pin changed")
    original = source.read_text()
    changed = adapt(original)
    if reverse(changed) != original:
        raise ValueError("source outside exact cleanup adaptation changed")
    normalize_paths(tree, project)
    output.mkdir(parents=True)
    target = output / "GameOptionsMenuPatch.cs"
    target.write_text(changed)
    item.set("Include", str(target))
    result = output / "EHR.csproj"
    tree.write(result, encoding="unicode")
    manifest = {
        "schema": "ehr.settings-build-cleanup.v1",
        "inputProject": str(project), "inputProjectSha256": sha(project),
        "inputSource": str(source), "inputSourceSha256": sha(source),
        "outputSourceSha256": sha(target), "outputProjectSha256": sha(result),
        "iterator": "EHR.GameOptionsMenuPatch.CreateSettingsPrefix.CoRoutine(int gen)",
        "generationGuard": "current stored generation equals iterator gen",
        "originalSourceRecoveredByExactReverse": True,
        "normalUiActionsAndYieldSitesUnchanged": True,
        "startStopAndCancellationCallsUnchanged": True,
        "cleanupOfReplacementGenerationAllowed": False,
        "physicalStatus8CauseProven": False,
        "nativeChanges": False, "capacityChanges": False, "forcedGc": False,
        "gameAccountDeviceOperations": False,
    }
    (output / "settings-build-cleanup.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.project, args.output))
