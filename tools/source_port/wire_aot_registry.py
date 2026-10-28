#!/usr/bin/env python3
"""Create stage-only source replacements for pinned EHR role construction.

Token matches ignore comments/formatting, require exact pinned counts, and never
write upstream. Global Harmony/bootstrap reflection remains outside this pass.
"""
import argparse
import hashlib
import json
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import feature_inventory as f

# (source file, exact token pattern, explicit replacement, required count)
REPLACEMENTS = [
    ("Main.cs", "AllTypes.Where(t => t.IsClass && !t.IsAbstract && t.IsSubclassOf(typeof(RoleBase)))", "EHRAotRegistry.RoleBaseTypes()", 1),
    ("Main.cs", "(RoleBase)Activator.CreateInstance(t, null)", "EHRAotRegistry.CreateRoleBase(t)", 1),
    ("Modules/CustomRolesHelper.cs", "Activator.CreateInstance(roleClass.GetType()) as RoleBase", "EHRAotRegistry.CreateRoleBase(roleClass.GetType())", 1),
    ("Modules/OptionHolder.cs", "Main.AllTypes.Where(x => x.GetInterfaces().ToList().Contains(typeof(IAddon)))", "EHRAotRegistry.IAddonTypes()", 1),
    ("Modules/OptionHolder.cs", "(IAddon)Activator.CreateInstance(x)", "EHRAotRegistry.CreateIAddon(x)", 1),
    ("Modules/OptionHolder.cs", "Main.AllTypes.Where(t => IAddonType.IsAssignableFrom(t) && !t.IsInterface)", "EHRAotRegistry.IAddonTypes()", 1),
    ("Modules/OptionHolder.cs", "(IAddon)Activator.CreateInstance(type)", "EHRAotRegistry.CreateIAddon(type)", 1),
    ("Modules/OptionHolder.cs", "Main.AllTypes.Where(t => IVanillaType.IsAssignableFrom(t) && !t.IsInterface)", "EHRAotRegistry.IVanillaSettingHolderTypes()", 1),
    ("Modules/OptionHolder.cs", "(IVanillaSettingHolder)Activator.CreateInstance(type)", "EHRAotRegistry.CreateIVanillaSettingHolder(type)", 1),
    ("Modules/OptionHolder.cs", "Main.AllTypes.Where(t => IType.IsAssignableFrom(t) && !t.IsInterface)", "EHRAotRegistry.IGhostRoleTypes()", 1),
    ("Modules/OptionHolder.cs", "(IGhostRole)Activator.CreateInstance(type)", "EHRAotRegistry.CreateIGhostRole(type)", 1),
    ("Modules/OptionHolder.cs", "type.GetMethod(nameof(roleBase.ManipulateGameEndCheckCrew))?.DeclaringType != type", "!EHRAotRegistry.DeclaresCrewEndCheck(type)", 1),
    ("Modules/GhostRolesManager.cs", 'Main.AllTypes.First(x => typeof(IGhostRole).IsAssignableFrom(x) && !x.IsInterface && x.Name == $"{ghostRole}")', 'EHRAotRegistry.IGhostRoleTypes().First(x => x.Name == $"{ghostRole}")', 1),
    ("Modules/GhostRolesManager.cs", "(IGhostRole)Activator.CreateInstance(ghostRoleClass)", "EHRAotRegistry.CreateIGhostRole(ghostRoleClass)", 1),
    ("Gamemodes/CustomHnS.cs", "Main.AllTypes.Where(t => typeof(IHideAndSeekRole).IsAssignableFrom(t) && !t.IsInterface)", "EHRAotRegistry.IHideAndSeekRoleTypes()", 1),
    ("Gamemodes/CustomHnS.cs", "Main.AllTypes.Where(x => typeof(IHideAndSeekRole).IsAssignableFrom(x) && !x.IsInterface)", "EHRAotRegistry.IHideAndSeekRoleTypes()", 1),
    ("Gamemodes/CustomHnS.cs", "(IHideAndSeekRole)Activator.CreateInstance(x)", "EHRAotRegistry.CreateIHideAndSeekRole(x)", 2),
    ("Gamemodes/CustomHnS.cs", "(IHideAndSeekRole)Activator.CreateInstance(Main.AllTypes.First(t => t.Name == role.ToString()))", "EHRAotRegistry.CreateIHideAndSeekRole(Main.AllTypes.First(t => t.Name == role.ToString()))", 1),
    ("Patches/ChatCommandPatch.cs", "(IHideAndSeekRole)Activator.CreateInstance(x)", "EHRAotRegistry.CreateIHideAndSeekRole(x)", 1),
    ("Modules/Random/IRandom.cs", "Activator.CreateInstance(type) as IRandom", "EHRAotRegistry.CreateIRandom(type)", 1),
    ("Gamemodes/NaturalDisasters.cs", "Main.AllTypes.Where(x => x.IsClass && !x.IsAbstract && x.IsSubclassOf(typeof(Disaster)))", "EHRAotRegistry.DisasterTypes()", 1),
    ("Gamemodes/NaturalDisasters.cs", "Activator.CreateInstance(type, naturalDisaster.Position, naturalDisaster)", "EHRAotRegistry.CreateDisaster(type, naturalDisaster.Position, naturalDisaster)", 1),
    ("Gamemodes/NaturalDisasters.cs", 'type.GetMethod("SetupOwnCustomOption")?.Invoke(null, null)', "EHRAotRegistry.SetupDisasterOptions(type)", 1)
]


def rewrite(text, replacements):
    tokens = f.tokenize(text)
    values = [t.value for t in tokens]
    edits = []
    for original, replacement, count in replacements:
        pattern = [t.value for t in f.tokenize(original)]
        matches = [i for i in range(len(values) - len(pattern) + 1) if values[i:i + len(pattern)] == pattern]
        if len(matches) != count:
            raise ValueError(f"Expected {count} token matches, got {len(matches)}: {original}")
        for i in matches:
            edits.append((tokens[i].start, tokens[i + len(pattern) - 1].end, replacement,
                          {"original": original, "replacement": replacement, "line": tokens[i].line}))
    edits.sort()
    if any(a[1] > b[0] for a, b in zip(edits, edits[1:])):
        raise ValueError("Overlapping source rewrites")
    for start, end, replacement, _ in reversed(edits):
        text = text[:start] + replacement + text[end:]
    return text, [item[3] for item in edits]


def generate(repo, output, overlay=None):
    if f.git(repo, "rev-parse", "HEAD") != f.PIN or f.git(repo, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Wiring requires clean pinned upstream source")
    grouped = {}
    for path, old, new, count in REPLACEMENTS:
        grouped.setdefault(path, []).append((old, new, count))
    files, prepared = [], []
    for path, replacements in grouped.items():
        source_path = overlay / path if overlay and (overlay / path).exists() else repo / path
        original = source_path.read_text(encoding="utf-8-sig")
        if overlay and path == "Gamemodes/CustomHnS.cs":
            replacements = [(old.replace("Main.AllTypes.First(t => t.Name == role.ToString())", "EHRSourceBootstrap.FindHnsRoleType(role.ToString())"),
                             new.replace("Main.AllTypes.First(t => t.Name == role.ToString())", "EHRSourceBootstrap.FindHnsRoleType(role.ToString())"), count)
                            for old, new, count in replacements]
        transformed, edits = rewrite(original, replacements)
        destination = output / path
        if destination.exists():
            raise ValueError(f"Refusing to overwrite {destination}")
        prepared.append((destination, transformed))
        files.append({"file": path, "input_normalized_sha256": hashlib.sha256(original.encode()).hexdigest(),
            "output_sha256": hashlib.sha256(transformed.encode()).hexdigest(),
            "edits": [{**e, "url": f"{f.REMOTE}/blob/{f.PIN}/{path}#L{e['line']}"} for e in edits]})
    report = {"schema": "ehr.aot-registry-source-wiring.v1", "upstream_commit": f.PIN,
        "scope": "Stage-only source rewrites, not applied to upstream/canonical. Preserves upstream sorting, conditional selection, caches and instance-reuse guards.",
        "source_files": len(files), "edits": sum(len(row["edits"]) for row in files), "files": files,
        "bootstrap_overlay": str(overlay) if overlay else None,
        "remaining_reflection": ["Explicit bootstrap roots/name maps are supplied by the separately generated overlay." if overlay else "Main.AllTypes global Assembly.GetTypes bootstrap remains for separate static dispatch/full type-root work.",
            "HnS role-by-name uses an explicit generated map." if overlay else "HnS role-by-name lookup retains original Main.AllTypes.First predicate; only its constructor is replaced.",
            "Optional Submerged map integration's dynamic external generic types remain outside this registry.",
            "Harmony registration, game facade and live gameplay behavior are separate integration requirements."]}
    if (output / "wiring_report.json").exists():
        raise ValueError("Refusing to overwrite wiring report")
    for destination, transformed in prepared:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(transformed)
    (output / "wiring_report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=f.UPSTREAM_DEFAULT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-overlay", type=Path)
    args = parser.parse_args()
    report = generate(args.upstream.resolve(), args.output.resolve(), args.source_overlay.resolve() if args.source_overlay else None)
    print(json.dumps({"source_files": report["source_files"], "edits": report["edits"]}))
