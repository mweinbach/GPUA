#!/usr/bin/env python3
"""
Scripts/test_parity.py — Mechanical upstream-to-Swift test parity verification tool.

Catalogues every upstream Rust test function across all in-scope crates in
.upstream/ and pairs it with its Swift @Test counterpart in Tests/.
Computes passing test parity percentage, enforces acceptance criteria (>= 95%),
and generates docs/TEST_PARITY.md.

Invariants enforced:
1. Strict 1-to-1 bijective pairing (used_swift_tests set).
2. Disk-verified @Test required for "passed" (no phantom ledger passes).
3. Concrete, specific technical reasons required for all <= 5% non-passing tests.
4. Report freshness check in --check (docs/TEST_PARITY.md must match exactly).

Usage:
  python3 Scripts/test_parity.py [--write] [--check] [--verbose] [--target <TARGET>] [--json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "porting.json"
LEDGER_PATH = ROOT / "docs" / "parity" / "test_parity.json"
OUTPUT_MD_PATH = ROOT / "docs" / "TEST_PARITY.md"

# In-scope targets/crates per AC5 and specification analysis
IN_SCOPE_CRATES = [
    "gpui",
    "collections",
    "gpui_util",
    "scheduler",
    "sum_tree",
    "refineable",
    "util",
    "gpui_wgpu",
    "gpui_linux",
    "gpui_windows",
    "gpui_platform",
    "http_client",
    "media",
    "gpui_macros",
    "taffy",
]

PARITY_THRESHOLD_PERCENT = 95.0

# --------------------------------------------------------------------------- #
# Data structures
# --------------------------------------------------------------------------- #


@dataclass
class UpstreamTest:
    crate: str
    target: str
    upstream_file: str  # e.g. crates/gpui/src/app.rs
    rust_fn: str
    line_number: int


@dataclass
class SwiftTest:
    target: str
    swift_file: str  # relative to repo root, e.g. Tests/GPUITests/app.swift
    swift_func: str
    is_disabled: bool
    disabled_reason: str | None
    line_number: int


@dataclass
class TestPairing:
    upstream_crate: str
    upstream_target: str
    upstream_file: str
    upstream_test: str
    upstream_line: int
    swift_target: str | None = None
    swift_file: str | None = None
    swift_func: str | None = None
    swift_line: int | None = None
    status: str = "unported"  # "passed" | "disabled" | "unported"
    match_tier: str = "none"  # "exact" | "camel" | "normalized" | "sibling" | "ledger" | "none"
    reason: str | None = None


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def snake_to_camel(name: str) -> str:
    """Convert snake_case to lowerCamelCase."""
    if name.isupper():
        parts = [p.lower() for p in name.split("_") if p]
        return parts[0] + "".join(p.capitalize() for p in parts[1:]) if parts else name
    parts = name.split("_")
    non_empty = [p for p in parts if p]
    if not non_empty:
        return name
    return non_empty[0].lower() + "".join(p[:1].upper() + p[1:] for p in non_empty[1:])


def normalize_name(name: str) -> str:
    """Normalize test function name for fuzzy prefix-agnostic matching."""
    s = name.lower()
    if s.startswith("test_"):
        s = s[5:]
    elif s.startswith("test"):
        s = s[4:]
    return s.replace("_", "")


def load_config() -> dict:
    with CONFIG_PATH.open() as f:
        return json.load(f)


def load_ledger() -> list[dict]:
    if LEDGER_PATH.exists():
        try:
            with LEDGER_PATH.open() as f:
                return json.load(f)
        except Exception:
            return []
    return []


# --------------------------------------------------------------------------- #
# Scanners
# --------------------------------------------------------------------------- #


def scan_upstream_tests(cfg: dict, in_scope_crates: list[str]) -> list[UpstreamTest]:
    """Scan all Rust files in in-scope crates for compilable test functions."""
    test_attr_pattern = re.compile(
        r"^\s*#\[(?:[\w:]*test|gpui::test|tokio::test|gpui::property_test)"
    )
    fn_pattern = re.compile(
        r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([a-zA-Z0-9_]+)"
    )

    crate_map = {c["crate"]: c for c in cfg["crates"] if c["crate"] in in_scope_crates}
    upstream_tests: list[UpstreamTest] = []

    for c_name in in_scope_crates:
        c = crate_map.get(c_name)
        if not c:
            continue
        up_name = c.get("upstream", "gpui")
        up_checkout = ROOT / cfg["upstreams"][up_name]["checkout"]
        c_path = up_checkout / c["path"] if c.get("path") else up_checkout
        excludes = [c_path / e for e in c.get("exclude", [])]

        def is_excluded(p: Path) -> bool:
            return any(ex == p or ex in p.parents for ex in excludes)

        for rs_file in sorted(c_path.rglob("*.rs")):
            if is_excluded(rs_file):
                continue
            upstream_rel = rs_file.relative_to(up_checkout).as_posix()
            lines = rs_file.read_text(errors="replace").splitlines()
            i = 0
            while i < len(lines):
                line = lines[i].strip()
                if line.startswith("//"):
                    i += 1
                    continue
                if test_attr_pattern.match(line):
                    # Multi-line attribute buffering until ']'
                    j = i
                    while j < len(lines) and "]" not in lines[j]:
                        j += 1
                    # Search following non-comment lines for fn
                    k = j + 1
                    found_fn = None
                    fn_line = k
                    while k < len(lines) and k <= j + 10:
                        kline = lines[k].strip()
                        if kline.startswith("//"):
                            k += 1
                            continue
                        if kline.startswith("#["):
                            while k < len(lines) and "]" not in lines[k]:
                                k += 1
                            k += 1
                            continue
                        m = fn_pattern.match(kline)
                        if m:
                            found_fn = m.group(1)
                            fn_line = k + 1
                            break
                        if kline and not kline.startswith("#"):
                            break
                        k += 1
                    if found_fn:
                        upstream_tests.append(
                            UpstreamTest(
                                crate=c_name,
                                target=c["target"],
                                upstream_file=upstream_rel,
                                rust_fn=found_fn,
                                line_number=fn_line,
                            )
                        )
                    i = k
                else:
                    i += 1

    return upstream_tests


def scan_swift_tests() -> list[SwiftTest]:
    """Scan all Swift test files under Tests/ for @Test functions."""
    test_dir = ROOT / "Tests"
    swift_tests: list[SwiftTest] = []

    for sw_file in sorted(test_dir.rglob("*.swift")):
        target = sw_file.relative_to(test_dir).parts[0]
        file_rel = sw_file.relative_to(ROOT).as_posix()
        content = sw_file.read_text(errors="replace")

        for m in re.finditer(r"@Test\b", content):
            start = m.start()
            line_num = content[:start].count("\n") + 1
            snippet = content[start : start + 600]
            fn_match = re.search(
                r"@Test(\s*\([^)]*\))?.*?\bfunc\s+([a-zA-Z0-9_]+)",
                snippet,
                re.DOTALL,
            )
            if fn_match:
                args = fn_match.group(1) or ""
                fn_name = fn_match.group(2)
                is_disabled = ".disabled(" in args
                disabled_reason = None
                if is_disabled:
                    m_reason = re.search(r'\.disabled\(\s*"([^"]+)"', args)
                    if m_reason:
                        disabled_reason = m_reason.group(1)
                swift_tests.append(
                    SwiftTest(
                        target=target,
                        swift_file=file_rel,
                        swift_func=fn_name,
                        is_disabled=is_disabled,
                        disabled_reason=disabled_reason,
                        line_number=line_num,
                    )
                )

    return swift_tests


# --------------------------------------------------------------------------- #
# Pairing Engine
# --------------------------------------------------------------------------- #


def pair_tests(
    cfg: dict,
    upstream_tests: list[UpstreamTest],
    swift_tests: list[SwiftTest],
    ledger: list[dict],
) -> list[TestPairing]:
    """Match each upstream test function with its Swift @Test counterpart using strict 1-to-1 bijection."""
    # Build upstream rs -> paired swift test file map via port.py
    sys.path.insert(0, str(ROOT / "Scripts"))
    try:
        import port

        entries = port.build_entries(cfg)
        upstream_to_test_swift: dict[tuple[str, str], str] = {}
        for e in entries:
            if e.kind in ("test", "inline-test"):
                upstream_to_test_swift[(e.crate, e.upstream)] = e.swift
    except Exception:
        upstream_to_test_swift = {}

    swift_by_file: dict[str, list[SwiftTest]] = defaultdict(list)
    swift_by_target: dict[str, list[SwiftTest]] = defaultdict(list)
    for st in swift_tests:
        swift_by_file[st.swift_file].append(st)
        swift_by_target[st.target].append(st)

    # Invariant 1: Maintain used_swift_tests for strict 1-to-1 bijective pairing
    used_swift_tests: set[tuple[str, str, int]] = set()

    def is_available(candidate: SwiftTest) -> bool:
        return (candidate.swift_file, candidate.swift_func, candidate.line_number) not in used_swift_tests

    # Index ledger by (upstream_file, upstream_test) or (crate, upstream_test)
    ledger_map: dict[tuple[str, str], dict] = {}
    for entry in ledger:
        uf = entry.get("upstream_file", "")
        ut = entry.get("upstream_test", "")
        uc = entry.get("upstream_crate", "")
        if uf and ut:
            ledger_map[(uf, ut)] = entry
        if uc and ut:
            ledger_map[(uc, ut)] = entry

    pairings: list[TestPairing] = []

    for ut in upstream_tests:
        pairing = TestPairing(
            upstream_crate=ut.crate,
            upstream_target=ut.target,
            upstream_file=ut.upstream_file,
            upstream_test=ut.rust_fn,
            upstream_line=ut.line_number,
        )

        paired_swift_file = upstream_to_test_swift.get((ut.crate, ut.upstream_file))
        found_swift: SwiftTest | None = None
        match_tier = "none"

        # Tier 1, 2, 3: Search paired test file
        if paired_swift_file and paired_swift_file in swift_by_file:
            candidates = swift_by_file[paired_swift_file]
            # Tier 1: exact match
            for c in candidates:
                if c.swift_func == ut.rust_fn and is_available(c):
                    found_swift = c
                    match_tier = "exact"
                    break

            # Tier 2: camelCase match
            if not found_swift:
                camel = snake_to_camel(ut.rust_fn)
                for c in candidates:
                    if c.swift_func == camel and is_available(c):
                        found_swift = c
                        match_tier = "camel"
                        break

            # Tier 3: normalized match
            if not found_swift:
                norm = normalize_name(ut.rust_fn)
                for c in candidates:
                    if normalize_name(c.swift_func) == norm and is_available(c):
                        found_swift = c
                        match_tier = "normalized"
                        break

        # Tier 4: Search siblings in the same target (e.g. Tests/<Target>Tests/)
        if not found_swift:
            target_suite = ut.target + "Tests"
            candidates = swift_by_target.get(target_suite, [])
            norm = normalize_name(ut.rust_fn)
            camel = snake_to_camel(ut.rust_fn)

            for c in candidates:
                if not is_available(c):
                    continue
                if c.swift_func == ut.rust_fn:
                    found_swift = c
                    match_tier = "sibling"
                    break
                if c.swift_func == camel:
                    found_swift = c
                    match_tier = "sibling"
                    break
                if normalize_name(c.swift_func) == norm:
                    found_swift = c
                    match_tier = "sibling"
                    break

        # Tier 5: Consult manual ledger
        ledger_entry = ledger_map.get((ut.upstream_file, ut.rust_fn)) or ledger_map.get(
            (ut.crate, ut.rust_fn)
        )
        if ledger_entry:
            l_status = ledger_entry.get("status")
            l_func = ledger_entry.get("swift_func")
            l_file = ledger_entry.get("swift_file")
            l_reason = ledger_entry.get("reason")
            l_target = ledger_entry.get("swift_target")

            if l_status == "disabled":
                pairing.status = "disabled"
                pairing.swift_target = l_target or ut.target + "Tests"
                pairing.swift_file = l_file
                pairing.swift_func = l_func
                pairing.reason = l_reason
                pairing.match_tier = "ledger"
                pairings.append(pairing)
                continue

            if l_func and l_file:
                # Find matching swift test on disk
                for st in swift_tests:
                    if st.swift_file == l_file and st.swift_func == l_func and is_available(st):
                        found_swift = st
                        match_tier = "ledger"
                        break

                # Invariant 2: Disk-Verified @Test Required for "passed"
                # If not found on disk, it CANNOT be marked passed!
                if not found_swift:
                    pairing.status = "unported"
                    pairing.reason = (
                        f"Ledger references Swift test '{l_file}:{l_func}' which does not exist on disk"
                    )
                    pairing.match_tier = "none"
                    pairings.append(pairing)
                    continue

        if found_swift:
            used_swift_tests.add(
                (found_swift.swift_file, found_swift.swift_func, found_swift.line_number)
            )
            pairing.swift_target = found_swift.target
            pairing.swift_file = found_swift.swift_file
            pairing.swift_func = found_swift.swift_func
            pairing.swift_line = found_swift.line_number
            pairing.match_tier = match_tier
            pairing.status = "disabled" if found_swift.is_disabled else "passed"
            if found_swift.is_disabled:
                pairing.reason = found_swift.disabled_reason or (
                    ledger_entry.get("reason") if ledger_entry else None
                ) or "Marked .disabled in Swift test suite"
        else:
            pairing.status = "unported"
            pairing.match_tier = "none"
            if ledger_entry and ledger_entry.get("reason"):
                pairing.reason = ledger_entry.get("reason")

        pairings.append(pairing)

    return pairings


# --------------------------------------------------------------------------- #
# Report Generation
# --------------------------------------------------------------------------- #


def generate_markdown_report(cfg: dict, pairings: list[TestPairing]) -> str:
    """Generate docs/TEST_PARITY.md report."""
    total_tests = len(pairings)
    passed_tests = sum(1 for p in pairings if p.status == "passed")
    disabled_tests = sum(1 for p in pairings if p.status == "disabled")
    unported_tests = sum(1 for p in pairings if p.status == "unported")

    pass_pct = (passed_tests / total_tests * 100.0) if total_tests > 0 else 0.0
    disabled_pct = (disabled_tests / total_tests * 100.0) if total_tests > 0 else 0.0
    unported_pct = (unported_tests / total_tests * 100.0) if total_tests > 0 else 0.0

    overall_status = "✅ PASSED" if pass_pct >= PARITY_THRESHOLD_PERCENT else "❌ FAILED"

    # Per-target stats
    target_stats: dict[str, dict[str, int]] = defaultdict(
        lambda: {"total": 0, "passed": 0, "disabled": 0, "unported": 0}
    )
    for p in pairings:
        t = p.upstream_target
        stats = target_stats[t]
        stats["total"] += 1
        if p.status == "passed":
            stats["passed"] += 1
        elif p.status == "disabled":
            stats["disabled"] += 1
        else:
            stats["unported"] += 1

    lines: list[str] = []
    lines.append("# Test Parity Report")
    lines.append("")
    lines.append("<!-- GENERATED by `Scripts/test_parity.py --write`. Do not edit by hand. -->")
    lines.append("")
    lines.append("## Executive Summary")
    lines.append("")
    lines.append(
        f"- **Primary Upstream**: Glass-HQ/gpui @ {cfg['upstreams']['gpui']['commit'][:12]} "
        f"& DioxusLabs/taffy @ {cfg['upstreams']['taffy']['commit'][:12]}"
    )
    lines.append(f"- **Total Upstream Tests**: {total_tests}")
    lines.append(f"- **Total Passing Swift Tests**: {passed_tests} ({pass_pct:.1f}%)")
    lines.append(
        f"- **Total Disabled with Technical Reason**: {disabled_tests} ({disabled_pct:.1f}%)"
    )
    lines.append(f"- **Total Unported Tests**: {unported_tests} ({unported_pct:.1f}%)")
    lines.append(
        f"- **Test Parity Status**: {overall_status} (>= {PARITY_THRESHOLD_PERCENT:.1f}% target required for AC5)"
    )
    lines.append("")
    lines.append("## Target Breakdown")
    lines.append("")
    lines.append(
        "| Target | Upstream Tests | Matched & Passing | Disabled (Justified) | Missing | Parity % |"
    )
    lines.append(
        "|---|---:|---:|---:|---:|---:|"
    )

    for target in sorted(target_stats.keys()):
        s = target_stats[target]
        t_total = s["total"]
        t_passed = s["passed"]
        t_disabled = s["disabled"]
        t_missing = s["unported"]
        t_pct = (t_passed / t_total * 100.0) if t_total > 0 else 0.0
        lines.append(
            f"| `{target}` | {t_total} | {t_passed} | {t_disabled} | {t_missing} | {t_pct:.1f}% |"
        )

    lines.append(
        f"| **Total** | **{total_tests}** | **{passed_tests}** | **{disabled_tests}** | **{unported_tests}** | **{pass_pct:.1f}%** |"
    )
    lines.append("")

    # Detailed 1-to-1 Mapping Table
    lines.append("## Detailed 1-to-1 Test Mapping")
    lines.append("")
    lines.append(
        "| Upstream File | Rust Test Function | Swift Test File | Swift Function | Status | Match Tier |"
    )
    lines.append(
        "|---|---|---|---|---|---|"
    )

    for p in sorted(pairings, key=lambda x: (x.upstream_target, x.upstream_file, x.upstream_test)):
        sw_file = f"`{p.swift_file}`" if p.swift_file else "—"
        sw_func = f"`{p.swift_func}()`" if p.swift_func else "—"
        status_badge = (
            "✅ PASS" if p.status == "passed" else ("⏸ DISABLED" if p.status == "disabled" else "❌ MISSING")
        )
        lines.append(
            f"| `{p.upstream_file}` | `{p.upstream_test}` | {sw_file} | {sw_func} | {status_badge} | {p.match_tier} |"
        )

    lines.append("")

    # Unported or Disabled Tests Ledger
    non_passing = [p for p in pairings if p.status != "passed"]
    lines.append("## Unported or Disabled Tests Ledger")
    lines.append("")
    if non_passing:
        lines.append(
            "| Upstream File | Rust Function | Status | Technical Reason / Justification |"
        )
        lines.append(
            "|---|---|---|---|"
        )
        for p in non_passing:
            reason = p.reason or "Missing concrete justification"
            status_text = "DISABLED" if p.status == "disabled" else "UNPORTED"
            lines.append(f"| `{p.upstream_file}` | `{p.upstream_test}` | {status_text} | {reason} |")
    else:
        lines.append("All upstream tests are ported and passing! Zero unported or disabled tests.")
    lines.append("")

    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Main CLI
# --------------------------------------------------------------------------- #


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verify upstream-to-Swift test parity and generate test parity report."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Generate and commit docs/TEST_PARITY.md and initialize docs/parity/test_parity.json",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 0 if passing test parity is >= 95.0%%, exit 1 otherwise (for CI)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed per-test matching output",
    )
    parser.add_argument(
        "--target",
        type=str,
        default=None,
        help="Filter scan and report by target name (e.g. Taffy, ZedUtil, GPUI)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit results as JSON to stdout",
    )
    args = parser.parse_args()

    cfg = load_config()
    ledger = load_ledger()

    in_scope = IN_SCOPE_CRATES
    if args.target:
        # Match crate for target
        target_crates = [
            c["crate"]
            for c in cfg["crates"]
            if c.get("target") == args.target or c["crate"] == args.target
        ]
        if target_crates:
            in_scope = [c for c in IN_SCOPE_CRATES if c in target_crates]
        else:
            print(f"Error: Unknown target '{args.target}'", file=sys.stderr)
            sys.exit(1)

    upstream_tests = scan_upstream_tests(cfg, in_scope)
    swift_tests = scan_swift_tests()
    pairings = pair_tests(cfg, upstream_tests, swift_tests, ledger)

    if args.target:
        pairings = [p for p in pairings if p.upstream_target == args.target]

    total = len(pairings)
    passed = sum(1 for p in pairings if p.status == "passed")
    disabled = sum(1 for p in pairings if p.status == "disabled")
    unported = sum(1 for p in pairings if p.status == "unported")
    pass_pct = (passed / total * 100.0) if total > 0 else 0.0

    if args.json:
        result = {
            "total_upstream_tests": total,
            "passed_tests": passed,
            "disabled_tests": disabled,
            "unported_tests": unported,
            "parity_percentage": round(pass_pct, 2),
            "threshold_percentage": PARITY_THRESHOLD_PERCENT,
            "passed_threshold": pass_pct >= PARITY_THRESHOLD_PERCENT,
            "pairings": [asdict(p) for p in pairings],
        }
        try:
            print(json.dumps(result, indent=2))
        except BrokenPipeError:
            pass
        sys.exit(0 if not args.check or pass_pct >= PARITY_THRESHOLD_PERCENT else 1)

    if args.verbose:
        for p in pairings:
            status_str = f"[{p.status.upper()}]"
            sw = f"{p.swift_file}:{p.swift_func}" if p.swift_func else "None"
            print(f"{status_str:10} {p.upstream_file}:{p.upstream_test} -> {sw} ({p.match_tier})")
        print("-" * 60)

    print(
        f"Test Parity: {passed}/{total} passing ({pass_pct:.1f}%), "
        f"{disabled} disabled, {unported} unported"
    )

    if args.write:
        report_content = generate_markdown_report(cfg, pairings)
        OUTPUT_MD_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_MD_PATH.write_text(report_content)
        print(f"Wrote {OUTPUT_MD_PATH.relative_to(ROOT)}")

        # Ensure docs/parity/test_parity.json exists
        if not LEDGER_PATH.exists():
            LEDGER_PATH.parent.mkdir(parents=True, exist_ok=True)
            LEDGER_PATH.write_text("[]\n")
            print(f"Initialized {LEDGER_PATH.relative_to(ROOT)}")

    if args.check:
        # Invariant 4: Report Freshness Check in --check
        if not OUTPUT_MD_PATH.exists():
            print(
                f"ERROR: {OUTPUT_MD_PATH.relative_to(ROOT)} does not exist. Run 'python3 Scripts/test_parity.py --write' to generate.",
                file=sys.stderr,
            )
            sys.exit(1)

        expected_markdown = generate_markdown_report(cfg, pairings)
        actual_markdown = OUTPUT_MD_PATH.read_text(errors="replace")
        if actual_markdown.strip() != expected_markdown.strip():
            print(
                f"ERROR: {OUTPUT_MD_PATH.relative_to(ROOT)} is out of date. Run 'python3 Scripts/test_parity.py --write' to update.",
                file=sys.stderr,
            )
            sys.exit(1)

        # Invariant 3: Concrete Reasons Required for All Non-Passing Tests (<= 5%)
        missing_reasons = []
        for p in pairings:
            if p.status != "passed":
                if not p.reason or not p.reason.strip() or "Missing concrete justification" in p.reason:
                    missing_reasons.append(f"{p.upstream_file}:{p.upstream_test} ({p.status})")

        if missing_reasons:
            print(
                f"ERROR: {len(missing_reasons)} non-passing test(s) lack a specific technical reason:\n"
                + "\n".join(f"  - {mr}" for mr in missing_reasons[:10]),
                file=sys.stderr,
            )
            sys.exit(1)

        if pass_pct < PARITY_THRESHOLD_PERCENT:
            print(
                f"ERROR: Passing test parity {pass_pct:.1f}% is below required threshold "
                f"{PARITY_THRESHOLD_PERCENT:.1f}%",
                file=sys.stderr,
            )
            sys.exit(1)
        else:
            print(
                f"SUCCESS: Passing test parity {pass_pct:.1f}% satisfies threshold "
                f"{PARITY_THRESHOLD_PERCENT:.1f}%"
            )
            sys.exit(0)


if __name__ == "__main__":
    main()
