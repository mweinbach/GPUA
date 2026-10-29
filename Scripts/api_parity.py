#!/usr/bin/env python3
"""
Scripts/api_parity.py — Mechanical upstream-to-Swift API parity verification tool.

Parses upstream GPUI Rust source files for every `pub` and `pub(crate)` function,
method, struct, enum, trait, typealias, and constant, and verifies their
corresponding declaration in Swift target file(s).

Usage:
  python3 Scripts/api_parity.py <upstream_rust_file> <swift_files...> [--ledger <ledger.json>] [--markdown <output.md>]
"""

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


def snake_to_camel(name: str) -> str:
    """Convert snake_case or SCREAMING_SNAKE_CASE to lowerCamelCase."""
    if name.isupper():
        parts = [p.lower() for p in name.split("_") if p]
        if not parts:
            return name
        return parts[0] + "".join(p.capitalize() for p in parts[1:])

    parts = name.split("_")
    non_empty = [p for p in parts if p]
    if not non_empty:
        return name
    return non_empty[0].lower() + "".join(p[:1].upper() + p[1:] for p in non_empty[1:])


def snake_to_pascal(name: str) -> str:
    """Convert snake_case to PascalCase, preserving existing PascalCase."""
    if "_" not in name:
        return name[:1].upper() + name[1:]
    parts = name.split("_")
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


def parse_var_let_names(line: str) -> List[str]:
    """Extract declared variable/constant names from a Swift `var` or `let` line."""
    names = []
    for m in re.finditer(r"\b(?:var|let)\s+([^;{]+)", line):
        content = m.group(1)
        depth = 0
        current = ""
        parts = []
        for ch in content:
            if ch in "<([{'\"":
                depth += 1
                current += ch
            elif ch in ">)]}'\"":
                depth = max(0, depth - 1)
                current += ch
            elif ch == "," and depth == 0:
                parts.append(current.strip())
                current = ""
            else:
                current += ch
        if current.strip():
            parts.append(current.strip())

        for part in parts:
            m_name = re.match(r"^\s*`?([a-zA-Z0-9_]+)`?", part)
            if m_name:
                names.append(m_name.group(1))
    return names


def extract_rust_target_type(raw_header: str) -> str:
    """Extract the target type name from an `impl ...` header."""
    header = re.sub(r"\bwhere\b.*$", "", raw_header).strip()
    parts = re.split(r"\s+for\s+", header, maxsplit=1)
    if len(parts) == 2:
        target_str = parts[1].strip()
    else:
        target_str = parts[0].strip()
        target_str = re.sub(r"^(?:<[^>]+>\s*)", "", target_str).strip()

    target_str = re.sub(r"^&(?:\'[a-zA-Z0-9_]+\s*)?", "", target_str)
    target_str = re.sub(r"^(?:mut|\*const|\*mut)\s+", "", target_str)
    target_str = target_str.split("<")[0].strip()
    target_name = target_str.split("::")[-1].strip()
    return target_name


def parse_rust_file(path: str) -> List[Dict]:
    """Parse a Rust file for all pub and pub(crate) items."""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    in_block_comment = False
    impl_stack: List[Tuple[str, int]] = []
    pending_impl: Optional[str] = None
    brace_depth = 0
    items: List[Dict] = []
    in_test = False
    test_brace_depth: Optional[int] = None

    decl_pattern = re.compile(
        r"^[ \t]*(pub(?:\(crate\))?)\s+"
        r"(?:(?:async|unsafe|const|extern\s+\"[^\"]+\")\s+)*"
        r"(fn|struct|enum|trait|type|const|static)\s+([a-zA-Z0-9_]+)"
    )

    for line_num, line in enumerate(lines, 1):
        clean = ""
        i = 0
        n = len(line)
        while i < n:
            if in_block_comment:
                if line[i : i + 2] == "*/":
                    in_block_comment = False
                    i += 2
                else:
                    i += 1
            else:
                if line[i : i + 2] == "/*":
                    in_block_comment = True
                    i += 2
                elif line[i : i + 2] == "//":
                    break
                elif line[i] == '"':
                    clean += line[i]
                    i += 1
                    while i < n:
                        if line[i] == "\\":
                            clean += line[i : i + 2]
                            i += 2
                        elif line[i] == '"':
                            clean += line[i]
                            i += 1
                            break
                        else:
                            clean += line[i]
                            i += 1
                elif line[i] == "'":
                    clean += line[i]
                    i += 1
                    if i + 1 < n and line[i + 1] == "'":
                        clean += line[i : i + 2]
                        i += 2
                else:
                    clean += line[i]
                    i += 1

        if "#[cfg(test)]" in clean:
            in_test = True
            test_brace_depth = brace_depth

        if not in_block_comment and not in_test:
            # Check for `impl` header
            m_impl = re.search(r"^[ \t]*impl\b([^{;]+)(?:\{)?", clean)
            if m_impl:
                raw_header = m_impl.group(1).strip()
                target_type = extract_rust_target_type(raw_header)
                if "{" in clean:
                    impl_stack.append((target_type, brace_depth + 1))
                else:
                    pending_impl = target_type
            elif pending_impl and "{" in clean:
                impl_stack.append((pending_impl, brace_depth + 1))
                pending_impl = None

            # Check for pub / pub(crate) declaration
            m_decl = decl_pattern.search(clean)
            if m_decl:
                vis = m_decl.group(1)
                kind = m_decl.group(2)
                name = m_decl.group(3)
                enclosing = impl_stack[-1][0] if impl_stack else None

                if kind == "fn" and enclosing:
                    item_key = f"{enclosing}::{name}"
                elif enclosing and kind in ("const", "static"):
                    item_key = f"{enclosing}::{name}"
                else:
                    item_key = name

                if kind in ("fn", "const", "static"):
                    swift_name = snake_to_camel(name)
                else:
                    swift_name = snake_to_pascal(name)

                items.append(
                    {
                        "line": line_num,
                        "vis": vis,
                        "kind": kind,
                        "rust_name": name,
                        "enclosing": enclosing,
                        "item": item_key,
                        "swift_name": swift_name,
                    }
                )

        # Track brace nesting
        for ch in clean:
            if ch == "{":
                brace_depth += 1
            elif ch == "}":
                if impl_stack and impl_stack[-1][1] == brace_depth:
                    impl_stack.pop()
                if (
                    in_test
                    and test_brace_depth is not None
                    and brace_depth == test_brace_depth + 1
                ):
                    in_test = False
                    test_brace_depth = None
                brace_depth -= 1

    return items


def strip_swift_comments(code: str) -> str:
    """Strip single-line and nested block comments from Swift code while preserving string literals."""
    res = []
    i = 0
    n = len(code)
    in_str = False
    str_quote = ""
    while i < n:
        c = code[i]
        if in_str:
            res.append(c)
            if c == "\\" and i + 1 < n:
                res.append(code[i + 1])
                i += 2
                continue
            if c == str_quote:
                in_str = False
            i += 1
        else:
            if c == '"':
                in_str = True
                str_quote = '"'
                res.append(c)
                i += 1
            elif c == "/" and i + 1 < n and code[i + 1] == "/":
                i += 2
                while i < n and code[i] != "\n":
                    i += 1
            elif c == "/" and i + 1 < n and code[i + 1] == "*":
                depth = 1
                i += 2
                while i < n and depth > 0:
                    if i + 1 < n and code[i : i + 2] == "/*":
                        depth += 1
                        i += 2
                    elif i + 1 < n and code[i : i + 2] == "*/":
                        depth -= 1
                        i += 2
                    else:
                        i += 1
            else:
                res.append(c)
                i += 1
    return "".join(res)


def check_is_stub(raw_body: Optional[str]) -> Tuple[bool, str]:
    """
    Analyze a Swift function/method/property implementation body between `{` and `}`.
    Returns (is_stub: bool, reason: str).
    """
    if raw_body is None:
        return False, ""
    cleaned = strip_swift_comments(raw_body).strip()
    if not cleaned:
        return True, "Empty body ({})"

    # Check for placeholder calls: fatalError, todo, unimplemented
    m_ph = re.match(
        r"^(?:return\s+)?(fatalError|todo|unimplemented)\s*(?:\(.*\))?;?$",
        cleaned,
        re.DOTALL,
    )
    if m_ph:
        return True, f"Placeholder ({m_ph.group(1)})"

    # Strip trailing semicolon
    cleaned_expr = cleaned.rstrip(";").strip()

    # Check for trivial returns or bare expression bodies
    if cleaned_expr.startswith("return "):
        expr = cleaned_expr[7:].strip().rstrip(";").strip()
    elif cleaned_expr == "return":
        expr = ""
    else:
        expr = cleaned_expr

    trivial_map = {
        "": "Empty return",
        "nil": "Trivial return (nil)",
        "false": "Trivial return (false)",
        "true": "Trivial return (true)",
        ".zero": "Trivial return (.zero)",
        "[]": "Trivial return ([])",
        '""': 'Trivial return ("")',
        "''": 'Trivial return ("")',
        "[:]": "Trivial return ([:])",
        "()": "Trivial return (())",
        "0": "Trivial return (0)",
        "0.0": "Trivial return (0.0)",
        "-1": "Trivial return (-1)",
        "default": "Trivial return (default)",
    }

    if expr in trivial_map:
        return True, trivial_map[expr]

    return False, ""


def tokenize_swift(text: str) -> List[Tuple[str, str, int, int, int]]:
    """Tokenize Swift source code into (kind, value, line, start_char, end_char)."""
    tokens = []
    i = 0
    n = len(text)
    line = 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in " \t\r":
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if text[i] == "\n":
                    line += 1
                if i + 1 < n and text[i : i + 2] == "/*":
                    depth += 1
                    i += 2
                elif i + 1 < n and text[i : i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
        elif c == '"':
            start_i = i
            start_line = line
            if text[i : i + 3] == '"""':
                i += 3
                while i + 2 < n and text[i : i + 3] != '"""':
                    if text[i] == "\n":
                        line += 1
                    elif text[i] == "\\" and i + 1 < n:
                        i += 1
                    i += 1
                i += 3
            else:
                i += 1
                while i < n and text[i] != '"':
                    if text[i] == "\n":
                        line += 1
                    elif text[i] == "\\" and i + 1 < n:
                        i += 1
                    i += 1
                if i < n:
                    i += 1
            tokens.append(("STRING", text[start_i:i], start_line, start_i, i))
        elif c.isalpha() or c == "_" or c == "`":
            start_i = i
            if c == "`":
                i += 1
                while i < n and text[i] != "`":
                    i += 1
                if i < n:
                    i += 1
                val = text[start_i + 1 : i - 1]
            else:
                while i < n and (text[i].isalnum() or text[i] == "_"):
                    i += 1
                val = text[start_i:i]
            tokens.append(("WORD", val, line, start_i, i))
        elif text[i : i + 2] == "->":
            tokens.append(("SYMBOL", "->", line, i, i + 2))
            i += 2
        else:
            tokens.append(("SYMBOL", c, line, i, i + 1))
            i += 1
    return tokens


def parse_swift_declarations(text: str, file_path: str) -> List[Dict]:
    """
    Parse a Swift source file for member-level and top-level declarations,
    including their enclosing type and implementation body between `{` and `}`.
    """
    tokens = tokenize_swift(text)
    type_stack: List[Tuple[str, int, bool]] = []
    brace_depth = 0
    decls: List[Dict] = []

    type_keywords = {"struct", "class", "enum", "actor", "extension", "protocol"}
    decl_keywords = {"func", "init", "subscript", "var", "let", "typealias", "case"}
    all_stop = type_keywords | decl_keywords | {"}"}

    idx = 0
    n = len(tokens)
    while idx < n:
        tok_type, val, line, s_pos, e_pos = tokens[idx]

        if tok_type == "SYMBOL" and val == "{":
            brace_depth += 1
            idx += 1
            continue
        elif tok_type == "SYMBOL" and val == "}":
            if type_stack and type_stack[-1][1] == brace_depth:
                type_stack.pop()
            brace_depth -= 1
            idx += 1
            continue

        # Skip import statements (e.g. import protocol Foo.Bar)
        if tok_type == "WORD" and val == "import":
            idx += 1
            while idx < n and tokens[idx][2] == line:
                idx += 1
            continue

        is_member_level = (not type_stack and brace_depth == 0) or (
            type_stack and brace_depth == type_stack[-1][1]
        )

        # Type declaration
        if tok_type == "WORD" and val in type_keywords:
            is_proto = val == "protocol"
            j = idx + 1
            while j < n and tokens[j][0] != "WORD":
                j += 1
            if j < n:
                t_name = tokens[j][1]
                while j < n and not (
                    tokens[j][0] == "SYMBOL" and tokens[j][1] == "{"
                ):
                    j += 1
                if j < n:
                    type_stack.append((t_name, brace_depth + 1, is_proto))
                    brace_depth += 1
                    enclosing = type_stack[-2][0] if len(type_stack) > 1 else None
                    decls.append(
                        {
                            "kind": val,
                            "name": t_name,
                            "enclosing": enclosing,
                            "file": file_path,
                            "line": line,
                            "body": None,
                            "body_line": None,
                        }
                    )
                    idx = j + 1
                    continue

        # Function / Initializer / Subscript declaration
        if is_member_level and tok_type == "WORD" and val in ("func", "init", "subscript"):
            decl_kind = val
            f_name = val
            j = idx + 1
            if decl_kind == "func":
                f_name = None
                while j < n:
                    if tokens[j][0] == "WORD":
                        f_name = tokens[j][1]
                        j += 1
                        break
                    elif tokens[j][0] == "SYMBOL" and tokens[j][1] in {
                        "==", "!=", "+", "-", "<", ">", "<=", ">="
                    }:
                        f_name = tokens[j][1]
                        j += 1
                        break
                    j += 1
            if f_name:
                paren_depth = 0
                body = None
                body_line = None
                while j < n:
                    t_j = tokens[j]
                    if t_j[0] == "SYMBOL" and t_j[1] == "(":
                        paren_depth += 1
                    elif t_j[0] == "SYMBOL" and t_j[1] == ")":
                        paren_depth = max(0, paren_depth - 1)
                    elif paren_depth == 0:
                        if t_j[0] == "SYMBOL" and t_j[1] == "{":
                            body_line = t_j[2]
                            body_s = t_j[4]
                            b_depth = 1
                            k = j + 1
                            while k < n and b_depth > 0:
                                if tokens[k][0] == "SYMBOL" and tokens[k][1] == "{":
                                    b_depth += 1
                                elif tokens[k][0] == "SYMBOL" and tokens[k][1] == "}":
                                    b_depth -= 1
                                k += 1
                            body_e = tokens[k - 1][3] if k <= n else len(text)
                            body = text[body_s:body_e]
                            idx = k
                            break
                        elif (
                            t_j[0] == "WORD" and t_j[1] in all_stop
                        ) or (t_j[0] == "SYMBOL" and t_j[1] == "}"):
                            idx = j
                            break
                    j += 1
                enclosing = type_stack[-1][0] if type_stack else None
                decls.append(
                    {
                        "kind": decl_kind,
                        "name": f_name,
                        "enclosing": enclosing,
                        "file": file_path,
                        "line": line,
                        "body": body,
                        "body_line": body_line,
                    }
                )
                if body is not None:
                    continue

        # Property declaration (var / let)
        if is_member_level and tok_type == "WORD" and val in ("var", "let"):
            decl_kind = val
            j = idx + 1
            names = []
            while j < n and not (
                tokens[j][0] == "SYMBOL" and tokens[j][1] in (":", "=", "{")
            ):
                if tokens[j][0] == "WORD":
                    names.append(tokens[j][1])
                j += 1

            body = None
            body_line = None
            is_computed = False
            paren_depth = 0
            while j < n:
                t_j = tokens[j]
                if t_j[0] == "SYMBOL" and t_j[1] == "(":
                    paren_depth += 1
                elif t_j[0] == "SYMBOL" and t_j[1] == ")":
                    paren_depth = max(0, paren_depth - 1)
                elif paren_depth == 0:
                    if t_j[0] == "SYMBOL" and t_j[1] == "=":
                        break
                    elif t_j[0] == "SYMBOL" and t_j[1] == "{":
                        if type_stack and type_stack[-1][2]:
                            # Protocol requirement
                            pass
                        else:
                            is_computed = True
                            body_line = t_j[2]
                            body_s = t_j[4]
                            b_depth = 1
                            k = j + 1
                            while k < n and b_depth > 0:
                                if tokens[k][0] == "SYMBOL" and tokens[k][1] == "{":
                                    b_depth += 1
                                elif tokens[k][0] == "SYMBOL" and tokens[k][1] == "}":
                                    b_depth -= 1
                                k += 1
                            body_e = tokens[k - 1][3] if k <= n else len(text)
                            body = text[body_s:body_e]
                            idx = k
                        break
                    elif (
                        t_j[0] == "WORD" and t_j[1] in all_stop
                    ) or (t_j[0] == "SYMBOL" and t_j[1] == "}"):
                        break
                j += 1

            enclosing = type_stack[-1][0] if type_stack else None
            for nm in names:
                decls.append(
                    {
                        "kind": "var" if is_computed else decl_kind,
                        "name": nm,
                        "enclosing": enclosing,
                        "file": file_path,
                        "line": line,
                        "body": body,
                        "body_line": body_line,
                    }
                )
            if body is not None:
                continue

        # Typealias
        if is_member_level and tok_type == "WORD" and val == "typealias":
            j = idx + 1
            while j < n and tokens[j][0] != "WORD":
                j += 1
            if j < n:
                ta_name = tokens[j][1]
                enclosing = type_stack[-1][0] if type_stack else None
                decls.append(
                    {
                        "kind": "typealias",
                        "name": ta_name,
                        "enclosing": enclosing,
                        "file": file_path,
                        "line": line,
                        "body": None,
                        "body_line": None,
                    }
                )
                idx = j + 1
                continue

        # Enum case
        if is_member_level and tok_type == "WORD" and val == "case":
            j = idx + 1
            while j < n and tokens[j][0] != "WORD":
                j += 1
            if j < n:
                case_name = tokens[j][1]
                enclosing = type_stack[-1][0] if type_stack else None
                decls.append(
                    {
                        "kind": "case",
                        "name": case_name,
                        "enclosing": enclosing,
                        "file": file_path,
                        "line": line,
                        "body": None,
                        "body_line": None,
                    }
                )
                idx = j + 1
                continue

        idx += 1
    return decls


def parse_swift_files(
    paths: List[str],
) -> Tuple[
    Set[str],
    Set[str],
    Dict[str, List[Tuple[str, int, str]]],
    Dict[str, List[Dict]],
    Dict[str, List[Dict]],
]:
    """
    Parse Swift files for declarations and implementation bodies.
    Returns:
      declared_names: Set of unqualified identifiers
      qualified_names: Set of `EnclosingType.identifier`
      locations: Dict of identifier -> list of (file, line, kind)
      decls_by_qual: Dict of `EnclosingType.identifier` -> list of decl dicts
      decls_by_name: Dict of `identifier` -> list of decl dicts
    """
    declared_names: Set[str] = set()
    qualified_names: Set[str] = set()
    locations: Dict[str, List[Tuple[str, int, str]]] = {}
    decls_by_qual: Dict[str, List[Dict]] = {}
    decls_by_name: Dict[str, List[Dict]] = {}

    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()

        file_decls = parse_swift_declarations(text, path)
        for d in file_decls:
            name = d["name"]
            enc = d["enclosing"]
            line = d["line"]
            kind = d["kind"]

            declared_names.add(name)
            locations.setdefault(name, []).append((path, line, kind))
            decls_by_name.setdefault(name, []).append(d)

            if enc:
                qual = f"{enc}.{name}"
                qualified_names.add(qual)
                decls_by_qual.setdefault(qual, []).append(d)

    return declared_names, qualified_names, locations, decls_by_qual, decls_by_name


def load_ledger(ledger_path: str) -> Dict[str, Dict]:
    """
    Load deferral / rename / stub exemption ledger JSON file.
    Validates that each entry contains:
      - item
      - status: 'deferred' | 'renamed' | 'omitted' | 'stub_allowed'
      - target_batch (optional for stub_allowed)
      - reason
    """
    with open(ledger_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    ledger: Dict[str, Dict] = {}
    valid_statuses = {"deferred", "renamed", "omitted", "stub_allowed"}

    if isinstance(data, list):
        entries = data
    elif isinstance(data, dict):
        entries = []
        for k, v in data.items():
            if isinstance(v, dict):
                v.setdefault("item", k)
                entries.append(v)
            else:
                raise ValueError(
                    f"Invalid ledger entry for key '{k}': expected dict"
                )
    else:
        raise ValueError("Ledger JSON must be an array or an object")

    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError(f"Ledger entry must be a dict: {entry}")
        item = entry.get("item")
        status = entry.get("status")
        target_batch = entry.get("target_batch")
        reason = entry.get("reason")

        if not item or not isinstance(item, str):
            raise ValueError(f"Ledger entry missing string 'item': {entry}")
        if status not in valid_statuses:
            raise ValueError(
                f"Ledger entry '{item}' has invalid status '{status}'. Expected one of {valid_statuses}"
            )
        if status != "stub_allowed" and (
            not target_batch or not isinstance(target_batch, str)
        ):
            raise ValueError(
                f"Ledger entry '{item}' missing string 'target_batch'"
            )
        if not reason or not isinstance(reason, str):
            raise ValueError(f"Ledger entry '{item}' missing string 'reason'")

        ledger[item] = entry

    return ledger


def resolve_file_path(path_str: str) -> str:
    """Resolve a file path, checking common prefixes if needed."""
    p = Path(path_str)
    if p.exists():
        return str(p.resolve())

    # Check .upstream/gpui/<path>
    repo_root = Path(__file__).resolve().parent.parent
    candidate = repo_root / ".upstream" / "gpui" / path_str
    if candidate.exists():
        return str(candidate.resolve())

    candidate_direct = repo_root / path_str
    if candidate_direct.exists():
        return str(candidate_direct.resolve())

    return str(p)


def generate_markdown_report(
    upstream_file: str,
    swift_files: List[str],
    ledger_file: Optional[str],
    rust_items: List[Dict],
    genuine: List[Dict],
    deferred: List[Dict],
    renamed: List[Dict],
    omitted: List[Dict],
    stub_allowed: List[Dict],
    stubs: List[Dict],
    missing: List[Dict],
) -> str:
    """Generate Markdown parity report with dedicated stub detection and summary tables."""
    total = len(rust_items)
    n_genuine = len(genuine)
    n_deferred = len(deferred)
    n_renamed = len(renamed)
    n_omitted = len(omitted)
    n_stub_allowed = len(stub_allowed)
    n_stubs = len(stubs)
    n_missing = len(missing)
    n_exempted = n_deferred + n_renamed + n_omitted + n_stub_allowed

    pct_covered = (
        ((n_genuine + n_exempted) / total * 100.0) if total > 0 else 0.0
    )
    pct_genuine = (n_genuine / total * 100.0) if total > 0 else 0.0
    pct_exempted = (n_exempted / total * 100.0) if total > 0 else 0.0
    pct_deferred = (n_deferred / total * 100.0) if total > 0 else 0.0
    pct_renamed = (n_renamed / total * 100.0) if total > 0 else 0.0
    pct_omitted = (n_omitted / total * 100.0) if total > 0 else 0.0
    pct_stub_allowed = (n_stub_allowed / total * 100.0) if total > 0 else 0.0
    pct_stubs = (n_stubs / total * 100.0) if total > 0 else 0.0
    pct_missing = (n_missing / total * 100.0) if total > 0 else 0.0

    is_passing = n_stubs == 0 and n_missing == 0
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    md = []
    md.append(f"# API Parity Audit: `{Path(upstream_file).name}`")
    md.append("")
    md.append(f"- **Generated At**: {now_iso}")
    md.append(f"- **Upstream Rust File**: `{upstream_file}`")
    md.append("- **Swift Target Files**:")
    for sf in swift_files:
        md.append(f"  - `{sf}`")
    if ledger_file:
        md.append(f"- **Ledger File**: `{ledger_file}`")
    else:
        md.append("- **Ledger File**: None (no exemptions applied)")
    md.append("")
    md.append("## Executive Summary")
    md.append("")
    md.append("| Metric | Count | Percentage |")
    md.append("| :--- | :--- | :--- |")
    md.append(f"| **Total Upstream `pub`/`pub(crate)` Items** | **{total}** | 100.0% |")
    md.append(f"| Genuine Swift Implementations | {n_genuine} | {pct_genuine:.1f}% |")
    md.append(f"| Legitimate Ledger Exemptions | {n_exempted} | {pct_exempted:.1f}% |")
    md.append(f"| — *Deferred to Later Batch* | {n_deferred} | {pct_deferred:.1f}% |")
    md.append(f"| — *Renamed in Swift* | {n_renamed} | {pct_renamed:.1f}% |")
    md.append(f"| — *Omitted (Obsolete/OS-specific)* | {n_omitted} | {pct_omitted:.1f}% |")
    md.append(f"| — *Allowed Stubs (Exempted)* | {n_stub_allowed} | {pct_stub_allowed:.1f}% |")
    md.append(f"| **Stubs Detected (FAIL)** | **{n_stubs}** | **{pct_stubs:.1f}%** |")
    md.append(f"| **Missing Items (FAIL)** | **{n_missing}** | **{pct_missing:.1f}%** |")
    md.append("")
    if is_passing:
        status_badge = "✅ PASS"
        md.append(f"**Audit Status**: {status_badge} (100.0% accounted for, all implementations verified genuine)")
    else:
        status_badge = "❌ FAILED"
        reasons = []
        if n_stubs > 0:
            reasons.append(f"{n_stubs} stubs detected")
        if n_missing > 0:
            reasons.append(f"{n_missing} missing items")
        md.append(f"**Audit Status**: {status_badge} ({pct_covered:.1f}% accounted for; {', '.join(reasons)})")
    md.append("")

    # Section for Stubs Detected
    if stubs:
        md.append("## Stubs Detected (Action Required)")
        md.append("")
        md.append("These Swift declarations were matched to upstream items but flagged as stubs (empty implementation body, trivial return, or placeholder). They must be implemented genuinely or explicitly documented in the ledger with `\"status\": \"stub_allowed\"` and technical rationale:")
        md.append("")
        md.append("| Upstream Item | Swift Declaration Location | Stub Reason / Body Excerpt |")
        md.append("| :--- | :--- | :--- |")
        for it in stubs:
            sd = it.get("stub_decl", {})
            loc_str = f"{Path(sd.get('file', '')).name}:{sd.get('line', '?')}"
            reason_str = it.get("stub_reason", "Stub body")
            excerpt = it.get("stub_excerpt", "")
            if excerpt:
                info = f"`{reason_str}`: `{excerpt}`"
            else:
                info = f"`{reason_str}`"
            md.append(f"| `{it['item']}` | `{loc_str}` | {info} |")
        md.append("")

    # Section for Missing Items
    if missing:
        md.append("## Missing Items (Action Required)")
        md.append("")
        md.append("These upstream `pub` or `pub(crate)` items were not detected in the provided Swift files and have no entry in the deferral/rename ledger:")
        md.append("")
        md.append("| Line | Upstream Item | Kind | Expected Swift Name | Enclosing Type |")
        md.append("| :--- | :--- | :--- | :--- | :--- |")
        for it in missing:
            enc = it["enclosing"] if it["enclosing"] else "*(top-level)*"
            md.append(f"| {it['line']} | `{it['item']}` | `{it['kind']}` | `{it['swift_name']}` | `{enc}` |")
        md.append("")

    # Section for Ledger Exemptions
    exemptions = deferred + renamed + omitted + stub_allowed
    if exemptions:
        md.append("## Legitimate Ledger Exemptions")
        md.append("")
        md.append("| Upstream Item | Status | Target Batch | Technical Rationale |")
        md.append("| :--- | :--- | :--- | :--- |")
        for it in exemptions:
            entry = it["ledger_entry"]
            target_batch = entry.get("target_batch", "N/A")
            md.append(f"| `{it['item']}` | `{entry['status']}` | {target_batch} | {entry['reason']} |")
        md.append("")

    # Section for Genuine Items
    md.append("## Genuine Swift Implementations")
    md.append("")
    md.append(f"Found {n_genuine} matching genuine declarations in Swift target files:")
    md.append("")
    md.append("<details>")
    md.append(f"<summary>Click to view genuine declarations ({n_genuine} total)</summary>")
    md.append("")
    md.append("| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |")
    md.append("| :--- | :--- | :--- | :--- | :--- |")
    for it in genuine:
        decl = it.get("swift_decl", {})
        loc = f"{Path(decl.get('file', '')).name}:{decl.get('line', '?')}" if decl else ""
        md.append(f"| {it['line']} | `{it['item']}` | `{it['kind']}` | `{it['swift_name']}` | `{loc}` |")
    md.append("")
    md.append("</details>")
    md.append("")

    return "\n".join(md)


def main():
    parser = argparse.ArgumentParser(
        description="Verify API parity between upstream Rust and Swift target files."
    )
    parser.add_argument(
        "upstream_rust_file",
        help="Path to upstream Rust source file (e.g. crates/gpui/src/window.rs)",
    )
    parser.add_argument(
        "swift_files",
        nargs="+",
        help="Path(s) to Swift file(s) that port the upstream file",
    )
    parser.add_argument(
        "--ledger",
        dest="ledger_file",
        default=None,
        help="Path to deferral / rename ledger JSON file",
    )
    parser.add_argument(
        "--markdown",
        dest="markdown_file",
        default=None,
        help="Path to write Markdown parity report",
    )
    parser.add_argument(
        "--json",
        dest="json_file",
        default=None,
        help="Path to write JSON parity report",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Suppress detailed console output",
    )

    args = parser.parse_args()

    # Resolve upstream file
    upstream_path = resolve_file_path(args.upstream_rust_file)
    if not os.path.exists(upstream_path):
        print(
            f"Error: Upstream Rust file not found: {args.upstream_rust_file}",
            file=sys.stderr,
        )
        sys.exit(2)

    # Resolve swift files
    swift_paths = []
    for sf in args.swift_files:
        p = resolve_file_path(sf)
        if not os.path.exists(p):
            print(f"Error: Swift file not found: {sf}", file=sys.stderr)
            sys.exit(2)
        swift_paths.append(p)

    # Load ledger if specified
    ledger: Dict[str, Dict] = {}
    if args.ledger_file:
        ledger_path = resolve_file_path(args.ledger_file)
        if not os.path.exists(ledger_path):
            print(
                f"Error: Ledger file not found: {args.ledger_file}",
                file=sys.stderr,
            )
            sys.exit(2)
        try:
            ledger = load_ledger(ledger_path)
        except Exception as e:
            print(f"Error parsing ledger file: {e}", file=sys.stderr)
            sys.exit(2)

    # Parse Rust items
    rust_items = parse_rust_file(upstream_path)

    # Parse Swift symbols & declarations
    (
        declared_names,
        qualified_names,
        locations,
        decls_by_qual,
        decls_by_name,
    ) = parse_swift_files(swift_paths)

    genuine: List[Dict] = []
    deferred: List[Dict] = []
    renamed: List[Dict] = []
    omitted: List[Dict] = []
    stub_allowed: List[Dict] = []
    stubs: List[Dict] = []
    missing: List[Dict] = []

    for it in rust_items:
        item_key = it["item"]
        rust_name = it["rust_name"]
        swift_name = it["swift_name"]
        enclosing = it["enclosing"]
        kind = it["kind"]

        # Check ledger entry
        ledger_entry = ledger.get(item_key) or ledger.get(rust_name)
        target_swift_name = swift_name
        if ledger_entry and ledger_entry["status"] == "renamed":
            target_swift_name = ledger_entry.get("swift_name", swift_name)

        # Lookup candidate Swift declarations
        candidates: List[Dict] = []
        if enclosing:
            candidates.extend(decls_by_qual.get(f"{enclosing}.{target_swift_name}", []))
            if not candidates:
                candidates.extend(decls_by_qual.get(f"{enclosing}.{rust_name}", []))
        if not candidates:
            candidates.extend(decls_by_name.get(target_swift_name, []))
            if not candidates:
                candidates.extend(decls_by_name.get(rust_name, []))
        if not candidates and kind in ("const", "static"):
            candidates.extend(decls_by_name.get(rust_name.upper(), []))
            if not candidates:
                candidates.extend(decls_by_name.get(rust_name.lower(), []))

        # Check if declaration was not found in Swift
        if not candidates:
            if ledger_entry:
                it["ledger_entry"] = ledger_entry
                st = ledger_entry["status"]
                it["status"] = st
                if st == "deferred":
                    deferred.append(it)
                elif st == "renamed":
                    # Renamed target not found in Swift
                    it["status"] = "missing"
                    missing.append(it)
                elif st == "omitted":
                    omitted.append(it)
                elif st == "stub_allowed":
                    stub_allowed.append(it)
                else:
                    missing.append(it)
            else:
                it["status"] = "missing"
                missing.append(it)
            continue

        # Declaration found in Swift: perform mechanical stub analysis
        if kind == "fn" or any(
            c["kind"] in ("func", "init", "subscript", "var") for c in candidates
        ):
            non_stub_candidates = []
            stub_candidates = []
            for c in candidates:
                if c["body"] is not None:
                    is_s, reason = check_is_stub(c["body"])
                    if is_s:
                        cleaned = strip_swift_comments(c["body"]).strip().rstrip(";").strip()
                        if not cleaned:
                            excerpt = "{}"
                        else:
                            first_line = cleaned.split("\n")[0].strip()
                            excerpt = first_line[:50] + ("..." if len(first_line) > 50 else "")
                        stub_candidates.append((c, reason, excerpt))
                    else:
                        non_stub_candidates.append(c)
                else:
                    # Protocol requirement without body or stored property
                    non_stub_candidates.append(c)

            if non_stub_candidates:
                it["status"] = "genuine"
                it["swift_decl"] = non_stub_candidates[0]
                genuine.append(it)
            else:
                # All candidates are stubs
                c, reason, excerpt = stub_candidates[0]
                it["stub_decl"] = c
                it["stub_reason"] = reason
                it["stub_excerpt"] = excerpt

                if ledger_entry and ledger_entry.get("status") == "stub_allowed":
                    it["status"] = "stub_allowed"
                    it["ledger_entry"] = ledger_entry
                    stub_allowed.append(it)
                else:
                    it["status"] = "stub"
                    stubs.append(it)
        else:
            # Type, enum, struct, typealias, const, static
            it["status"] = "genuine"
            it["swift_decl"] = candidates[0]
            genuine.append(it)

    total = len(rust_items)
    n_genuine = len(genuine)
    n_deferred = len(deferred)
    n_renamed = len(renamed)
    n_omitted = len(omitted)
    n_stub_allowed = len(stub_allowed)
    n_stubs = len(stubs)
    n_missing = len(missing)
    n_exempted = n_deferred + n_renamed + n_omitted + n_stub_allowed

    if not args.quiet:
        print("=" * 64)
        print(f"API Parity Audit: {Path(upstream_path).name}")
        print("=" * 64)
        print(f"Upstream file: {upstream_path}")
        print(f"Swift files:   {', '.join(Path(p).name for p in swift_paths)}")
        if args.ledger_file:
            print(f"Ledger file:   {args.ledger_file}")
        print("-" * 64)
        print(f"Total Upstream `pub`/`pub(crate)` Items: {total}")
        kind_counts = Counter(it["kind"] for it in rust_items)
        for k, v in sorted(kind_counts.items()):
            print(f"  - {k:8s}: {v}")
        print("-" * 64)
        print(
            f"Genuine Swift Implementations: {n_genuine:3d} ({(n_genuine/total*100.0 if total else 0):5.1f}%)"
        )
        print(
            f"Legitimate Ledger Exemptions:  {n_exempted:3d} ({(n_exempted/total*100.0 if total else 0):5.1f}%)"
        )
        if n_exempted > 0:
            print(f"  - Deferred to later batch: {n_deferred}")
            print(f"  - Renamed in Swift:        {n_renamed}")
            print(f"  - Omitted:                 {n_omitted}")
            print(f"  - Allowed stubs:           {n_stub_allowed}")
        print(
            f"Stubs Detected (FAIL):         {n_stubs:3d} ({(n_stubs/total*100.0 if total else 0):5.1f}%)"
        )
        print(
            f"Missing Items (FAIL):          {n_missing:3d} ({(n_missing/total*100.0 if total else 0):5.1f}%)"
        )
        print("=" * 64)

        if stubs:
            print(f"\n[!] Stubs Detected (Action Required) ({n_stubs} total):")
            for it in stubs[:30]:
                sd = it.get("stub_decl", {})
                loc = f"{Path(sd.get('file', '')).name}:{sd.get('line', '?')}"
                reason = it.get("stub_reason", "")
                excerpt = it.get("stub_excerpt", "")
                detail = f"[{reason}: {excerpt}]" if excerpt else f"[{reason}]"
                print(f"  {it['item']:36s} -> {loc} {detail}")
            if len(stubs) > 30:
                print(f"  ... and {len(stubs) - 30} more stubs detected.")

        if missing:
            print(f"\n[!] Missing Items ({n_missing} total):")
            for it in missing[:30]:
                print(
                    f"  L{it['line']:4d} [{it['kind']:6s}] {it['item']:36s} -> expected: {it['swift_name']}"
                )
            if len(missing) > 30:
                print(f"  ... and {len(missing) - 30} more missing items.")
        print()

    # Generate Markdown Report if requested
    if args.markdown_file:
        md_content = generate_markdown_report(
            upstream_path,
            swift_paths,
            args.ledger_file,
            rust_items,
            genuine,
            deferred,
            renamed,
            omitted,
            stub_allowed,
            stubs,
            missing,
        )
        out_dir = os.path.dirname(os.path.abspath(args.markdown_file))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.markdown_file, "w", encoding="utf-8") as f:
            f.write(md_content)
        if not args.quiet:
            print(f"Markdown report written to: {args.markdown_file}")

    # Generate JSON Report if requested
    if args.json_file:
        report_data = {
            "upstream_file": upstream_path,
            "swift_files": swift_paths,
            "ledger_file": args.ledger_file,
            "total_items": total,
            "genuine_count": n_genuine,
            "exempted_count": n_exempted,
            "deferred_count": n_deferred,
            "renamed_count": n_renamed,
            "omitted_count": n_omitted,
            "stub_allowed_count": n_stub_allowed,
            "stubs_count": n_stubs,
            "missing_count": n_missing,
            "stubs": [
                {
                    "item": it["item"],
                    "kind": it["kind"],
                    "location": f"{Path(it.get('stub_decl', {}).get('file', '')).name}:{it.get('stub_decl', {}).get('line', '?')}",
                    "reason": it.get("stub_reason", ""),
                    "excerpt": it.get("stub_excerpt", ""),
                }
                for it in stubs
            ],
            "missing": [
                {
                    "item": it["item"],
                    "kind": it["kind"],
                    "line": it["line"],
                    "swift_name": it["swift_name"],
                    "enclosing": it["enclosing"],
                }
                for it in missing
            ],
            "items": rust_items,
        }
        out_dir = os.path.dirname(os.path.abspath(args.json_file))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.json_file, "w", encoding="utf-8") as f:
            json.dump(report_data, f, indent=2)
        if not args.quiet:
            print(f"JSON report written to: {args.json_file}")

    # Exit code
    if n_stubs == 0 and n_missing == 0:
        if not args.quiet:
            print("Audit Result: PASSED (100% accounted for, genuine implementations verified)")
        sys.exit(0)
    else:
        failure_parts = []
        if n_stubs > 0:
            failure_parts.append(f"{n_stubs} stubs detected")
        if n_missing > 0:
            failure_parts.append(f"{n_missing} items missing")
        if not args.quiet:
            print(f"Audit Result: FAILED ({', '.join(failure_parts)})")
        sys.exit(1)


if __name__ == "__main__":
    main()
