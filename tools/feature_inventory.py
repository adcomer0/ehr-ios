#!/usr/bin/env python3
"""Pinned, read-only EHR source inventory. Discovery is not native implementation.

Uses a bounded C# lexical scanner, not a compiler. It excludes comments/string
contents from symbol discovery, records source locations and unresolved source
expressions, and never evaluates C# or imports game assemblies/assets.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

PIN = "ce23f0d050f617a59507e5bb0fbfff751d4b5134"
REMOTE = "https://github.com/Gurge44/EndlessHostRoles"
UPSTREAM_DEFAULT = Path(os.environ.get("EHR_UPSTREAM_REPO", str(Path(__file__).resolve().parents[2] / "EndlessHostRoles")))
NATIVE_DEFAULT = Path(__file__).resolve().parents[1]
OPTION_TYPES = {"BooleanOptionItem", "IntegerOptionItem", "FloatOptionItem",
                "StringOptionItem", "TextOptionItem", "PresetOptionItem"}
FACTORIES = {"SetupRoleOptions", "SetupSingleRoleOptions", "SetupAdtRoleOptions",
             "AutoSetupOption", "CreatePetUseSetting", "CreateVoteCancellingUseSetting",
             "StartSetup", "CreateOverrideTasksData"}


def preprocess(source: str, symbols: set[str] | None = None) -> str:
    """Select the upstream IL2CPP compilation branch without changing locations."""
    symbols = set(symbols if symbols is not None else {"IL2CPP"})
    active, stack, output = True, [], []
    # A directive-looking line inside a multiline comment/raw/verbatim string
    # is data. Tokenization does not require balanced conditional branches.
    directive_offsets = {t.start for t in tokenize(source) if t.value == "#"}
    def condition(text):
        text = text.replace("&&", " and ").replace("||", " or ")
        text = re.sub(r"!(?!=)", " not ", text).strip()
        node = ast.parse(text, mode="eval").body
        def visit(n):
            if isinstance(n, ast.Name):
                return n.id == "true" or n.id in symbols
            if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.Not):
                return not visit(n.operand)
            if isinstance(n, ast.BoolOp):
                values = [visit(v) for v in n.values]
                return all(values) if isinstance(n.op, ast.And) else any(values)
            raise ValueError("Unsupported C# preprocessor condition")
        return visit(node)
    offset = 0
    for line in source.splitlines(keepends=True):
        match = re.match(r"\s*#(\w+)\s*(.*?)\s*$", line)
        is_directive = match and offset + line.find("#") in directive_offsets
        offset += len(line)
        if is_directive:
            directive, argument = match.groups()
            argument = argument.split("//", 1)[0].strip()
            if directive == "if":
                selected = condition(argument)
                stack.append([active, selected])
                active = active and selected
            elif directive == "elif":
                parent, taken = stack[-1]
                selected = condition(argument) and not taken
                stack[-1][1] |= selected
                active = parent and selected
            elif directive == "else":
                parent, taken = stack[-1]
                active = parent and not taken
                stack[-1][1] = True
            elif directive == "endif":
                active = stack.pop()[0]
            elif directive == "define" and active:
                symbols.add(argument)
            elif directive == "undef" and active:
                symbols.discard(argument)
            output.append("".join("\n" if c == "\n" else " " for c in line))
        else:
            output.append(line if active else "".join("\n" if c == "\n" else " " for c in line))
    if stack:
        raise ValueError("Unclosed C# preprocessor branch")
    return "".join(output)


@dataclass(frozen=True)
class Token:
    value: str
    kind: str
    start: int
    end: int
    line: int


def _quoted_end(source: str, start: int) -> int:
    """Consume char/regular/verbatim/interpolated/raw C# string as ONE token."""
    size = len(source)
    p = start
    while p < size and source[p] in "$@":
        p += 1
    quote = source[p]
    prefix = source[start:p]
    if quote == '"':
        count = 1
        while p + count < size and source[p + count] == '"':
            count += 1
        if count >= 3:
            end = source.find('"' * count, p + count)
            return size if end < 0 else end + count
    verbatim = "@" in prefix
    interpolated = "$" in prefix
    p += 1
    while p < size:
        char = source[p]
        if char == quote:
            if verbatim and p + 1 < size and source[p + 1] == quote:
                p += 2
                continue
            return p + 1
        if not verbatim and char == "\\":
            p += 2
            continue
        if interpolated and char == "{":
            if p + 1 < size and source[p + 1] == "{":
                p += 2
                continue
            depth = 1
            p += 1
            while p < size and depth:
                if source.startswith("//", p):
                    end = source.find("\n", p + 2)
                    p = size if end < 0 else end
                elif source.startswith("/*", p):
                    end = source.find("*/", p + 2)
                    p = size if end < 0 else end + 2
                elif source[p] in "\"'" or re.match(r'(?:\$@|@\$|\$|@)"', source[p:p + 4]):
                    p = _quoted_end(source, p)
                else:
                    depth += (source[p] == "{") - (source[p] == "}")
                    p += 1
            continue
        p += 1
    return size


def tokenize(source: str) -> list[Token]:
    result = []
    p, line, size = 0, 1, len(source)
    while p < size:
        start = p
        char = source[p]
        if char.isspace() or char == "\ufeff":
            line += char == "\n"
            p += 1
            continue
        if source.startswith("//", p):
            end = source.find("\n", p + 2)
            p = size if end < 0 else end
            continue
        if source.startswith("/*", p):
            end = source.find("*/", p + 2)
            p = size if end < 0 else end + 2
            line += source[start:p].count("\n")
            continue
        if char in "\"'" or re.match(r'(?:\$@|@\$|\$|@)"', source[p:p + 4]):
            p = _quoted_end(source, p)
            result.append(Token(source[start:p], "string" if char != "'" else "char", start, p, line))
            line += source[start:p].count("\n")
            continue
        if char.isalpha() or char == "_":
            p += 1
            while p < size and (source[p].isalnum() or source[p] == "_"):
                p += 1
            kind = "identifier"
        elif char.isdigit():
            p += 1
            while p < size and (source[p].isalnum() or source[p] in "._"):
                p += 1
            kind = "number"
        else:
            p += 1
            kind = "symbol"
        result.append(Token(source[start:p], kind, start, p, line))
    return result


def pairs(tokens: list[Token]) -> dict[int, int]:
    stack, result = [], {}
    closing = {")": "(", "]": "[", "}": "{"}
    for i, token in enumerate(tokens):
        if token.kind in {"string", "char"}:
            continue
        if token.value in "([{":
            stack.append((token.value, i))
        elif token.value in closing:
            if not stack or stack[-1][0] != closing[token.value]:
                raise ValueError(f"Unbalanced source delimiter near line {token.line}")
            _, start = stack.pop()
            result[start] = i
    if stack:
        raise ValueError("Unclosed source delimiter")
    return result


def split_top(tokens: list[Token], separator: str = ",") -> list[list[Token]]:
    result, current, stack = [], [], []
    for token in tokens:
        if token.kind not in {"string", "char"}:
            if token.value in "([{":
                stack.append(token.value)
            elif token.value in ")]}":
                if stack:
                    stack.pop()
            elif token.value == separator and not stack:
                result.append(current)
                current = []
                continue
        current.append(token)
    if current:
        result.append(current)
    return result


def expression(tokens: list[Token]) -> str:
    return " ".join(t.value for t in tokens)


def literal(tokens: list[Token], constants: dict | None = None):
    text = expression(tokens).strip()
    if text in {"true", "false"}:
        return text == "true"
    if len(tokens) == 1 and tokens[0].kind == "string":
        value = tokens[0].value
        if value.startswith('@"'):
            return value[2:-1].replace('""', '"')
        if value.startswith('"') and not value.startswith('"""'):
            try:
                return json.loads(value)
            except ValueError:
                return None
        return None
    normalized = []
    for token in tokens:
        value = token.value
        if token.kind == "number":
            value = value.replace("_", "")
            value = re.sub(r"[uUlL]+$" if value.lower().startswith("0x") else r"[fFdDmMuUlL]+$", "", value)
        normalized.append(value)
    text = " ".join(normalized).replace("< <", "<<").replace("> >", ">>")
    try:
        node = ast.parse(text, mode="eval").body
        def visit(n):
            if isinstance(n, ast.Constant) and type(n.value) in (int, float):
                return n.value
            if isinstance(n, ast.Name) and n.id in (constants or {}):
                return constants[n.id]
            if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name):
                if n.value.id == "int" and n.attr == "MaxValue":
                    return 2147483647
            if isinstance(n, ast.UnaryOp) and isinstance(n.op, (ast.USub, ast.UAdd)):
                return -visit(n.operand) if isinstance(n.op, ast.USub) else visit(n.operand)
            if isinstance(n, ast.BinOp):
                a, b = visit(n.left), visit(n.right)
                operators = {ast.Add: lambda: a + b, ast.Sub: lambda: a - b,
                             ast.Mult: lambda: a * b, ast.BitOr: lambda: a | b,
                             ast.LShift: lambda: a << b, ast.RShift: lambda: a >> b}
                if type(n.op) in operators:
                    return operators[type(n.op)]()
            raise ValueError("Expression is not a supported source literal")
        return visit(node)
    except (SyntaxError, ValueError, TypeError, KeyError, OverflowError):
        return None


def named_arguments(arguments: list[list[Token]]) -> tuple[list, dict]:
    positional, named = [], {}
    for argument in arguments:
        if len(argument) >= 2 and argument[0].kind == "identifier" and argument[1].value == ":":
            named[argument[0].value] = argument[2:]
        else:
            positional.append(argument)
    return positional, named


class Source:
    def __init__(self, path: str, text: str, symbols: set[str] | None = None):
        self.path, self.text = path, preprocess(text, symbols)
        self.tokens = tokenize(self.text)
        try:
            self.pairs = pairs(self.tokens)
        except ValueError as error:
            raise ValueError(f"{path}: {error}") from error
        self.types = self.extract_types()

    def ref(self, token_index: int) -> dict:
        line = self.tokens[token_index].line
        return {"file": self.path, "line": line,
                "url": f"{REMOTE}/blob/{PIN}/{self.path}#L{line}"}

    def extract_types(self) -> list[dict]:
        result, tokens = [], self.tokens
        for i, token in enumerate(tokens[:-1]):
            if token.value not in {"class", "interface", "enum", "struct"} or tokens[i + 1].kind != "identifier":
                continue
            j, colon = i + 2, None
            while j < len(tokens) and tokens[j].value not in {"{", ";"}:
                if tokens[j].value in {"(", "["}:
                    j = self.pairs[j] + 1
                    continue
                if tokens[j].value == ":":
                    colon = j
                j += 1
            if j >= len(tokens) or tokens[j].value != "{":
                continue
            bases = []
            if colon is not None:
                for group in split_top(tokens[colon + 1:j]):
                    head = []
                    for t in group:
                        if t.value == "<":
                            break
                        if t.kind == "identifier":
                            head.append(t.value)
                    if head:
                        bases.append(head[-1])
            result.append({"name": tokens[i + 1].value, "kind": token.value,
                           "bases": bases, "start": i, "body": j,
                           "end": self.pairs[j], "source": self.ref(i)})
        return result

    def owner(self, index: int) -> dict | None:
        candidates = [d for d in self.types if d["body"] < index < d["end"]]
        return max(candidates, key=lambda d: d["body"]) if candidates else None

    def constants(self, owner: dict | None) -> dict:
        start, end = (owner["body"], owner["end"]) if owner else (0, len(self.tokens))
        values = {}
        for i in range(start, end - 4):
            if self.tokens[i].value != "const":
                continue
            j = i + 1
            while j < end and self.tokens[j].value not in {"=", ";"}:
                j += 1
            if j >= end or self.tokens[j].value != "=":
                continue
            name = self.tokens[j - 1].value
            k = j + 1
            while k < end and self.tokens[k].value != ";":
                k += 1
            value = literal(self.tokens[j + 1:k], values)
            if isinstance(value, (int, float)):
                values[name] = value
        return values

    def enums(self) -> list[dict]:
        result = []
        for declaration in self.types:
            if declaration["kind"] != "enum":
                continue
            members, constants, next_value = [], {}, 0
            for group in split_top(self.tokens[declaration["body"] + 1:declaration["end"]]):
                if not group or group[0].kind != "identifier":
                    continue
                assigned = next((i for i, t in enumerate(group) if t.value == "="), None)
                value = next_value if assigned is None else literal(group[assigned + 1:], constants)
                members.append({"name": group[0].value, "value": value,
                                "value_expression": expression(group[assigned + 1:]) if assigned is not None else None,
                                "source": {**declaration["source"], "line": group[0].line,
                                           "url": f"{REMOTE}/blob/{PIN}/{self.path}#L{group[0].line}"}})
                if type(value) is int:
                    constants[group[0].value] = value
                    next_value = value + 1
                else:
                    next_value = None
            result.append({"name": declaration["name"], "members": members, "source": declaration["source"]})
        return result

    def calls(self):
        tokens = self.tokens
        for i in range(len(tokens) - 1):
            if tokens[i].kind == "identifier" and tokens[i + 1].value == "(" and i + 1 in self.pairs:
                yield i, tokens[i].value, split_top(tokens[i + 2:self.pairs[i + 1]])

    def options(self) -> list[dict]:
        result = []
        for i, name, arguments in self.calls():
            constructor = name in OPTION_TYPES and i > 0 and self.tokens[i - 1].value == "new"
            factory = name in FACTORIES and (i == 0 or self.tokens[i - 1].kind != "identifier" or
                self.tokens[i - 1].value in {"return", "await"})
            if not constructor and not factory:
                continue
            owner = self.owner(i)
            constants = self.constants(owner)
            positional, named = named_arguments(arguments)
            item = {"kind": "constructor" if constructor else "factory_or_template",
                    "factory": name, "owner_type": owner["name"] if owner else None,
                    "arguments": [expression(a) for a in arguments], "source": self.ref(i),
                    "id_expression": None, "resolved_id": None,
                    "label": None, "default": None, "default_expression": None, "range": None}
            if constructor and positional:
                item["id_expression"] = expression(positional[0])
                item["resolved_id"] = literal(positional[0], constants)
                if len(positional) > 1:
                    item["label"] = literal(positional[1], constants)
                default_index = 2 if name == "BooleanOptionItem" else 3
                if name not in {"TextOptionItem", "PresetOptionItem"} and len(positional) > default_index:
                    item["default_expression"] = expression(positional[default_index])
                    item["default"] = literal(positional[default_index], constants)
                if name in {"FloatOptionItem", "IntegerOptionItem"} and len(positional) > 2:
                    item["range"] = self.range_of(positional[2], constants)
            elif name == "AutoSetupOption" and len(positional) >= 2:
                field = positional[0][1:] if positional[0] and positional[0][0].value == "ref" else positional[0]
                item["field"] = expression(field)
                item["label"] = literal(named["overrideName"]) if "overrideName" in named else expression(field)
                item["default_expression"] = expression(positional[1])
                item["default"] = literal(positional[1], constants)
                if len(positional) > 2:
                    item["range"] = self.range_of(positional[2], constants)
            elif positional:
                item["id_expression"] = expression(positional[0])
                item["resolved_id"] = literal(positional[0], constants)
            item["role_references"] = sorted(set(re.findall(r"CustomRoles\s*\.\s*(\w+)", " ".join(item["arguments"]))))
            result.append(item)
        return result

    def range_of(self, tokens: list[Token], constants: dict) -> dict:
        opening = next((i for i, t in enumerate(tokens) if t.value == "("), None)
        values = []
        if tokens and tokens[0].value == "new" and opening is not None and tokens[-1].value == ")":
            values = split_top(tokens[opening + 1:-1])
        return {"expression": expression(tokens), "min": literal(values[0], constants) if len(values) >= 1 else None,
                "max": literal(values[1], constants) if len(values) >= 2 else None,
                "step": literal(values[2], constants) if len(values) >= 3 else None}

    def hooks(self) -> list[dict]:
        result = []
        for i, token in enumerate(self.tokens):
            if token.value != "HarmonyPatch" or i == 0 or self.tokens[i - 1].value != "[":
                continue
            arguments = []
            if i + 1 < len(self.tokens) and self.tokens[i + 1].value == "(":
                arguments = split_top(self.tokens[i + 2:self.pairs[i + 1]])
            text = " ".join(expression(a) for a in arguments)
            types = [re.sub(r"\s+", "", s) for s in re.findall(r"typeof\s*\(\s*([\w.\s]+)\s*\)", text)]
            names = [re.sub(r"\s+", "", s) for s in re.findall(r"nameof\s*\(\s*([\w.\s]+)\s*\)", text)]
            result.append({"declared_type": types[0] if types else None,
                           "declared_member": names[0].split(".")[-1] if names else None,
                           "arguments": [expression(a) for a in arguments], "source": self.ref(i),
                           "interpretation": "attribute_site_not_unique_or_proven_active_native_hook"})
        return result


CALLBACK_GROUPS = {
    "kill_validation": {"OnCheckMurder", "OnCheckMurderAsTarget", "CanUseKillButton", "OnMurder", "SetKillCooldown"},
    "per_player_options": {"ApplyGameOptions", "SetKillCooldown"},
    "meetings_votes": {"OnVote", "OnJudge", "OnVoteKick", "OnReportDeadBody", "CheckReportDeadBody", "AfterMeetingTasks"},
    "abilities_world": {"OnPet", "OnEnterVent", "OnExitVent", "CanUseVent", "CanUseSabotage", "OnSabotage", "OnShapeshift", "OnVanish"},
    "timers_positions": {"OnFixedUpdate", "OnGlobalFixedUpdate", "OnCheckPlayerPosition"},
    "tasks": {"OnTaskComplete"},
    "win_conditions": {"ManipulateGameEndCheckCrew"},
    "notifications_hud": {"GetSuffix", "SetButtonTexts", "GetProgressText", "KnowRole"},
}


def type_record(source: Source, declaration: dict) -> dict:
    overrides = []
    for i in range(declaration["body"] + 1, declaration["end"]):
        if source.tokens[i].value != "override" or source.owner(i) != declaration:
            continue
        j = i + 1
        while j < declaration["end"] and source.tokens[j].value not in {"(", "{", "=", ";"}:
            j += 1
        if source.tokens[j].value == "(" and source.tokens[j - 1].kind == "identifier":
            overrides.append(source.tokens[j - 1].value)
    references = set()
    for i in range(declaration["body"] + 1, declaration["end"] - 2):
        if source.tokens[i].value == "CustomRoles" and source.tokens[i + 1].value == ".":
            references.add(source.tokens[i + 2].value)
    dependencies = {"state_assignment", "settings"} if source.path.startswith("Roles/") else set()
    for group, callbacks in CALLBACK_GROUPS.items():
        if callbacks.intersection(overrides):
            dependencies.add(group)
    values = {t.value for t in source.tokens[declaration["body"]:declaration["end"]] if t.kind == "identifier"}
    if {"CustomWinnerHolder", "CustomWinner"}.intersection(values):
        dependencies.add("win_conditions")
    if {"Notify", "NotifyRoles", "RpcSetNamePrivate", "SendMessage"}.intersection(values):
        dependencies.add("notifications_hud")
    return {"name": declaration["name"], "kind": declaration["kind"], "bases": declaration["bases"],
            "source": declaration["source"], "override_methods": sorted(set(overrides)),
            "role_references": sorted(references), "inferred_dependency_groups": sorted(dependencies)}


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def inventory(repo: Path, profile: str = "IL2CPP") -> dict:
    commit = git(repo, "rev-parse", "HEAD")
    if commit != PIN:
        raise ValueError(f"Expected pinned EHR commit {PIN}, got {commit}")
    if git(repo, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Pinned upstream contains tracked modifications")
    remote = git(repo, "remote", "get-url", "origin")
    if remote.removesuffix(".git").lower() != REMOTE.lower():
        raise ValueError("Unexpected upstream origin")
    paths = git(repo, "ls-files", "*.cs").splitlines()
    excluded = [p for p in paths if p.startswith("CTA/")]
    symbols = {"IL2CPP"} if profile == "IL2CPP" else set()
    sources = [Source(p, (repo / p).read_text(encoding="utf-8-sig"), symbols) for p in paths if p not in excluded]
    types = [type_record(s, d) for s in sources for d in s.types]
    enums = [e for s in sources for e in s.enums()]
    options = [o for s in sources for o in s.options()]
    hooks = [h for s in sources for h in s.hooks()]
    enum_by_name = {e["name"]: e for e in enums}
    role_names = {r["name"] for r in enum_by_name["CustomRoles"]["members"]}
    type_by_name = defaultdict(list)
    for t in types:
        type_by_name[t["name"]].append(t)
    reference_sites = defaultdict(list)
    for source in sources:
        if source.path == "CustomRoles.cs":
            continue
        for i in range(len(source.tokens) - 2):
            if source.tokens[i].value == "CustomRoles" and source.tokens[i + 1].value == ".":
                name = source.tokens[i + 2].value
                if name in role_names:
                    reference_sites[name].append(source.ref(i))
    role_features = []
    for member in enum_by_name["CustomRoles"]["members"]:
        name = member["name"]
        definitions = [t for t in type_by_name[name] if t["source"]["file"].startswith("Roles/")]
        files = sorted({r["file"] for r in reference_sites[name]})
        role_features.append({**member, "named_role_types": definitions,
            "reference_files": files, "reference_site_count": len(reference_sites[name]),
            "central_reference_sites": [r for r in reference_sites[name] if not r["file"].startswith("Roles/")],
            "native_coverage": "partial_manual_Bait_subset" if name == "Bait" else "not_verified_in_live_native_game",
            "complete_EHR_role_compatibility": False})
    dependencies = []
    tree = ET.parse(repo / "EHR.csproj")
    for group in tree.findall(".//ItemGroup"):
        for item in group.findall("PackageReference"):
            dependencies.append({"package": item.attrib["Include"], "version": item.attrib.get("Version"),
                                 "item_condition": item.attrib.get("Condition"),
                                 "group_condition": group.attrib.get("Condition")})
    from patch_dispatch_inventory import manifest
    dispatch = manifest(sources)
    file_records = [{"file": s.path, "sha256": hashlib.sha256((repo / s.path).read_bytes()).hexdigest(),
                     "lines": len(s.text.splitlines())} for s in sources]
    return {"schema": "ehr.upstream-static-inventory.v1", "upstream": {"origin": remote, "commit": commit, "tag": "v8.0.3"},
        "compile_profile": profile,
        "limits": ["Lexical source discovery, not a C# compiler or semantic call graph.",
                   f"{profile} compile branch is selected; other undefined preprocessor symbols are false. Attributes are sites, not unique live hooks.",
                   "Option counts are static creation/factory sites, not expanded effective runtime option counts.",
                   "Only simple numeric constants/literals are evaluated; null preserves unresolved expressions.",
                   "Enum membership and source presence never count as native implementation."],
        "counts": {"compiled_scope_cs_files": len(sources), "excluded_CTA_cs_files": len(excluded),
            "compiled_scope_lines": sum(f["lines"] for f in file_records), "all_type_declarations": len(types),
            "role_source_files": sum(s.path.startswith("Roles/") for s in sources),
            "role_enum_members_including_vanilla_aliases_and_sentinels": len(role_features),
            "named_role_type_declarations": sum(len(r["named_role_types"]) for r in role_features),
            "game_modes_excluding_All_sentinel": sum(m["name"] != "All" for m in enum_by_name["CustomGameMode"]["members"]),
            "option_creation_or_factory_sites": len(options), "direct_option_constructor_sites": sum(o["kind"] == "constructor" for o in options),
            "harmony_attribute_sites": len(hooks), "complete_native_EHR_roles_verified": 0},
        "source_files": file_records, "roles": role_features,
        "game_modes": enum_by_name["CustomGameMode"], "option_sites": options, "harmony_attribute_sites": hooks,
        "role_base_contract": next(t for t in types if t["name"] == "RoleBase"),
        "patch_dispatch": dispatch,
        "role_source_groups": dict(sorted(Counter("/".join(s.path.split("/")[:3]) for s in sources if s.path.startswith("Roles/Standard/")).items())),
        "game_mode_sources": [{"file": s.path, "types": [t for t in types if t["source"]["file"] == s.path]} for s in sources if s.path.startswith("Gamemodes/")],
        "package_dependencies": dependencies,
        "licenses": {"mod": {"kind": "GPL-3.0", "source": f"{REMOTE}/blob/{PIN}/LICENSE"},
                     "excluded_CTA": {"kind": "separate four-condition attribution/advertising text", "source": f"{REMOTE}/blob/{PIN}/README.md#L589"}}}


def coverage(native: Path, runtime_proof: Path | None) -> dict:
    audited = ["native/EHRHostCore.cpp", "native/include/EHRHostCore.h", "native/EHRLiveBridge.mm",
               "native/EHRNativeHooks.mm", "native/EHRNativeOverlay.mm", "native/launcher/main.mm"]
    files = []
    for path in audited:
        data = (native / path).read_bytes()
        files.append({"file": path, "sha256": hashlib.sha256(data).hexdigest()})
    evidence = {"actual_runtime_boot": "not_attested_by_this_run", "actual_version_hook": "not_attested_by_this_run",
                "actual_murder_callback": "not_verified", "actual_body_report": "not_verified",
                "standalone_launch": "not_verified", "physical_iPhone_install": "not_verified", "multiplayer": "not_verified"}
    proof_record = None
    if runtime_proof:
        data = runtime_proof.read_bytes()
        proof = json.loads(data)
        before, after, getter = proof.get("nativeHooksBeforeGetter", {}), proof.get("nativeHooks", {}), proof.get("versionGetter", {})
        boot = proof.get("status") == "live_sample" and proof.get("gameAssemblyFound") is True
        hook = getter.get("success") is True and after.get("broadcastVersionCallbacks", 0) > before.get("broadcastVersionCallbacks", 0)
        evidence["actual_runtime_boot"] = "verified_under_app_hosted_XCTest" if boot else "not_verified"
        evidence["actual_version_hook"] = "verified_under_app_hosted_XCTest" if hook else "not_verified"
        proof_record = {"path": str(runtime_proof), "sha256": hashlib.sha256(data).hexdigest(),
                        "scope": proof.get("scope"), "termsAcceptedByTest": proof.get("termsAcceptedByTest"),
                        "getter_gc_round_trip_verified": all(getter.get(k) is True for k in ("gcHandleNonzero", "gcTargetMatchesBoxedObject", "gcBoxedValueUnchanged", "gcHandleFreedOnce"))}
    return {"schema": "ehr.native-coverage-audit.v1", "upstream_commit": PIN,
        "assessment": "Audited Bait adapter baseline; source compilation/inventory is not live game feature coverage.",
        "assessment_scope": "Manual behavioral audit of listed native Bait integration files. Concurrent managed-source/AOT/facade work is outside this behavior audit and does not automatically gain runtime verification.",
        "native_git_head": git(native, "rev-parse", "HEAD"), "native_worktree_dirty": bool(git(native, "status", "--porcelain")),
        "audited_native_files": files, "runtime_evidence": evidence, "runtime_proof": proof_record,
        "implemented_subset": [{"feature": "Bait", "status": "partial_native_implementation",
            "implemented": ["manual target ID", "enabled toggle", "integer delay min/max 0..90", "150ms minimum and inverted-range fallback",
                            "post-MurderPlayer callback adapter", "native GC roots and host/round/phase checks", "normal CmdReportDeadBody dispatch code"],
            "missing_for_EHR_parity": ["automatic add-on assignment", "source role interactions/exemptions", "forced-meeting mode",
                "delay notifications and sounds", "achievements", "resurrection and repeated deaths", "full settings/presets/localization"],
            "intentional_differences": ["pending work cancelled on host/phase/setting changes", "victim deduplicated for entire round"],
            "actual_multiplayer_verified": False}],
        "complete_native_EHR_roles_verified": 0, "all_other_upstream_roles": "not_verified_in_live_native_game_by_this_audit",
        "full_EHR_game_modes": "not_verified_in_live_native_game_by_this_audit", "full_EHR_option_schema": "not_verified_in_live_native_game_by_this_audit",
        "shared_kernel": {k: "required_not_verified_in_live_native_game_by_this_audit" for k in
            ["role_assignment", "role_and_addon_state", "pre_kill_validation", "per_recipient_base_roles_and_options",
             "meetings_and_votes", "custom_win_pipeline", "ability_dispatch", "settings_registry_and_persistence", "recipient_notifications"]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=UPSTREAM_DEFAULT)
    parser.add_argument("--native", type=Path, default=NATIVE_DEFAULT)
    parser.add_argument("--runtime-proof", type=Path)
    parser.add_argument("--profile", choices=["IL2CPP", "Mono"], default="IL2CPP")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inventory(args.upstream.resolve(), args.profile)
    baseline = coverage(args.native.resolve(), args.runtime_proof.resolve() if args.runtime_proof else None)
    args.output.mkdir(parents=True, exist_ok=True)
    outputs = [("feature_inventory.json", result), ("coverage_baseline.json", baseline),
               ("patch_dispatch.json", {**result["patch_dispatch"], "compile_profile": args.profile,
                   "upstream": result["upstream"]})]
    for name, _ in outputs:
        if (args.output / name).exists():
            raise ValueError(f"Refusing to overwrite {args.output / name}")
    for name, value in outputs:
        destination = args.output / name
        destination.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(result["counts"], indent=2))


if __name__ == "__main__":
    main()
