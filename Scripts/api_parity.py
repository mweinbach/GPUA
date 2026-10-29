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


def parse_swift_files(
    paths: List[str],
) -> Tuple[Set[str], Set[str], Dict[str, List[Tuple[str, int, str]]]]:
    """
    Parse Swift files for declarations.
    Returns:
      declared_names: Set of unqualified identifiers
      qualified_names: Set of `EnclosingType.identifier`
      locations: Dict of identifier -> list of (file, line, kind)
    """
    declared_names: Set[str] = set()
    qualified_names: Set[str] = set()
    locations: Dict[str, List[Tuple[str, int, str]]] = {}

    type_decl_re = re.compile(
        r"\b(?:struct|class|actor|enum|protocol|extension)\s+`?([a-zA-Z0-9_]+)`?"
    )
    func_decl_re = re.compile(r"\bfunc\s+`?([a-zA-Z0-9_]+)`?")
    typealias_decl_re = re.compile(r"\btypealias\s+`?([a-zA-Z0-9_]+)`?")
    case_decl_re = re.compile(r"\bcase\s+`?([a-zA-Z0-9_]+)`?")

    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        type_stack: List[Tuple[str, int]] = []
        brace_depth = 0
        in_block_comment = False

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
                    else:
                        clean += line[i]
                        i += 1

            if not in_block_comment:
                # Track type / extension boundaries
                m_type = type_decl_re.search(clean)
                if m_type and "{" in clean:
                    type_name = m_type.group(1)
                    type_stack.append((type_name, brace_depth + 1))
                    declared_names.add(type_name)
                    locations.setdefault(type_name, []).append(
                        (path, line_num, "type")
                    )

                # Functions
                for m_func in func_decl_re.finditer(clean):
                    name = m_func.group(1)
                    declared_names.add(name)
                    locations.setdefault(name, []).append(
                        (path, line_num, "func")
                    )
                    if type_stack:
                        qualified_names.add(f"{type_stack[-1][0]}.{name}")

                # Initializers
                if re.search(r"\binit\b", clean):
                    declared_names.add("init")
                    locations.setdefault("init", []).append(
                        (path, line_num, "init")
                    )
                    if type_stack:
                        qualified_names.add(f"{type_stack[-1][0]}.init")

                # Typealiases
                for m_ta in typealias_decl_re.finditer(clean):
                    name = m_ta.group(1)
                    declared_names.add(name)
                    locations.setdefault(name, []).append(
                        (path, line_num, "typealias")
                    )
                    if type_stack:
                        qualified_names.add(f"{type_stack[-1][0]}.{name}")

                # Variables & Constants
                for name in parse_var_let_names(clean):
                    declared_names.add(name)
                    locations.setdefault(name, []).append(
                        (path, line_num, "var/let")
                    )
                    if type_stack:
                        qualified_names.add(f"{type_stack[-1][0]}.{name}")

                # Enum Cases
                for m_case in case_decl_re.finditer(clean):
                    name = m_case.group(1)
                    declared_names.add(name)
                    locations.setdefault(name, []).append(
                        (path, line_num, "case")
                    )
                    if type_stack:
                        qualified_names.add(f"{type_stack[-1][0]}.{name}")

            # Track brace depth
            for ch in clean:
                if ch == "{":
                    brace_depth += 1
                elif ch == "}":
                    if type_stack and type_stack[-1][1] == brace_depth:
                        type_stack.pop()
                    brace_depth -= 1

    return declared_names, qualified_names, locations


def load_ledger(ledger_path: str) -> Dict[str, Dict]:
    """
    Load deferral / rename ledger JSON file.
    Validates that each entry contains:
      - item
      - status: 'deferred' | 'renamed' | 'omitted'
      - target_batch
      - reason
    """
    with open(ledger_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    ledger: Dict[str, Dict] = {}
    valid_statuses = {"deferred", "renamed", "omitted"}

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
        if not target_batch or not isinstance(target_batch, str):
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
    matched: List[Dict],
    deferred: List[Dict],
    renamed: List[Dict],
    omitted: List[Dict],
    missing: List[Dict],
) -> str:
    """Generate Markdown parity report."""
    total = len(rust_items)
    n_matched = len(matched)
    n_deferred = len(deferred)
    n_renamed = len(renamed)
    n_omitted = len(omitted)
    n_missing = len(missing)
    n_exempted = n_deferred + n_renamed + n_omitted

    pct_covered = (
        ((n_matched + n_exempted) / total * 100.0) if total > 0 else 0.0
    )
    pct_matched = (n_matched / total * 100.0) if total > 0 else 0.0

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
    md.append(f"| Found in Swift Target(s) | {n_matched} | {pct_matched:.1f}% |")
    md.append(f"| Legitimate Ledger Exemptions | {n_exempted} | {(n_exempted/total*100.0 if total else 0):.1f}% |")
    md.append(f"| — *Deferred to Later Batch* | {n_deferred} | {(n_deferred/total*100.0 if total else 0):.1f}% |")
    md.append(f"| — *Renamed in Swift* | {n_renamed} | {(n_renamed/total*100.0 if total else 0):.1f}% |")
    md.append(f"| — *Omitted (Obsolete/OS-specific)* | {n_omitted} | {(n_omitted/total*100.0 if total else 0):.1f}% |")
    md.append(f"| **MISSING (Unaccounted / Unported)** | **{n_missing}** | **{(n_missing/total*100.0 if total else 0):.1f}%** |")
    md.append("")
    status_badge = "✅ PASS" if n_missing == 0 else "❌ FAILED"
    md.append(f"**Audit Status**: {status_badge} ({pct_covered:.1f}% accounted for)")
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
    exemptions = deferred + renamed + omitted
    if exemptions:
        md.append("## Legitimate Ledger Exemptions")
        md.append("")
        md.append("| Upstream Item | Status | Target Batch | Technical Rationale |")
        md.append("| :--- | :--- | :--- | :--- |")
        for it in exemptions:
            entry = it["ledger_entry"]
            md.append(f"| `{it['item']}` | `{entry['status']}` | {entry['target_batch']} | {entry['reason']} |")
        md.append("")

    # Section for Matched Items
    md.append("## Matched Items")
    md.append("")
    md.append(f"Found {n_matched} matching declarations in Swift target files:")
    md.append("")
    md.append("<details>")
    md.append("<summary>Click to view matched declarations</summary>")
    md.append("")
    md.append("| Line | Upstream Item | Kind | Swift Declaration / Symbol |")
    md.append("| :--- | :--- | :--- | :--- |")
    for it in matched:
        md.append(f"| {it['line']} | `{it['item']}` | `{it['kind']}` | `{it['swift_name']}` |")
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

    # Parse Swift symbols
    declared_names, qualified_names, locations = parse_swift_files(swift_paths)

    matched: List[Dict] = []
    deferred: List[Dict] = []
    renamed: List[Dict] = []
    omitted: List[Dict] = []
    missing: List[Dict] = []

    for it in rust_items:
        item_key = it["item"]
        rust_name = it["rust_name"]
        swift_name = it["swift_name"]
        enclosing = it["enclosing"]
        kind = it["kind"]

        # Check in Swift
        is_matched = False
        if enclosing and f"{enclosing}.{swift_name}" in qualified_names:
            is_matched = True
        elif enclosing and f"{enclosing}.{rust_name}" in qualified_names:
            is_matched = True
        elif swift_name in declared_names:
            is_matched = True
        elif rust_name in declared_names:
            is_matched = True
        elif kind in ("const", "static") and (
            rust_name.upper() in declared_names
            or rust_name.lower() in declared_names
        ):
            is_matched = True

        if is_matched:
            it["status"] = "matched"
            matched.append(it)
            continue

        # Check ledger
        ledger_entry = ledger.get(item_key) or ledger.get(rust_name)
        if ledger_entry:
            it["ledger_entry"] = ledger_entry
            entry_status = ledger_entry["status"]
            it["status"] = entry_status
            if entry_status == "deferred":
                deferred.append(it)
            elif entry_status == "renamed":
                renamed.append(it)
            elif entry_status == "omitted":
                omitted.append(it)
            continue

        # Not matched and not in ledger
        it["status"] = "missing"
        missing.append(it)

    total = len(rust_items)
    n_matched = len(matched)
    n_deferred = len(deferred)
    n_renamed = len(renamed)
    n_omitted = len(omitted)
    n_missing = len(missing)
    n_exempted = n_deferred + n_renamed + n_omitted

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
            f"Found in Swift Target(s):  {n_matched:3d} ({(n_matched/total*100.0 if total else 0):5.1f}%)"
        )
        print(
            f"Ledger Exemptions:         {n_exempted:3d} ({(n_exempted/total*100.0 if total else 0):5.1f}%)"
        )
        if n_exempted > 0:
            print(f"  - Deferred to later batch: {n_deferred}")
            print(f"  - Renamed in Swift:        {n_renamed}")
            print(f"  - Omitted:                 {n_omitted}")
        print(
            f"MISSING (Unaccounted):     {n_missing:3d} ({(n_missing/total*100.0 if total else 0):5.1f}%)"
        )
        print("=" * 64)

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
            matched,
            deferred,
            renamed,
            omitted,
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
            "matched_count": n_matched,
            "deferred_count": n_deferred,
            "renamed_count": n_renamed,
            "omitted_count": n_omitted,
            "missing_count": n_missing,
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
    if n_missing == 0:
        if not args.quiet:
            print("Audit Result: PASSED (100% accounted for)")
        sys.exit(0)
    else:
        if not args.quiet:
            print(f"Audit Result: FAILED ({n_missing} items missing)")
        sys.exit(1)


if __name__ == "__main__":
    main()
