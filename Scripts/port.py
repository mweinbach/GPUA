#!/usr/bin/env python3
"""
port.py — tooling for the file-for-file Swift port of GPUI.

Every upstream Rust file maps to exactly one Swift file at the same relative
path (see docs/PORTING_GUIDE.md, "File mapping rules"). This script is the single
source of truth for that mapping, so humans and agents never have to guess.

Usage:
  Scripts/port.py fetch [--full]          Clone/fetch the pinned upstream into .upstream/gpui
  Scripts/port.py map <path>              Show the counterpart of a Rust or Swift path
  Scripts/port.py scaffold [--dry-run]    Create missing stub files (never overwrites)
  Scripts/port.py status [--write]        Print (or write docs/PORTING_STATUS.md) progress
  Scripts/port.py todo [--target T]       List not-started files, smallest first
  Scripts/port.py check                   Validate mapping, headers, and orphans (CI)
  Scripts/port.py stale                   Files ported from an older upstream commit + diffstat
  Scripts/port.py bump <commit>           Re-pin upstream and list changed upstream files

Only the Python 3 standard library is used.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "porting.json"
STATUS_DOC = ROOT / "docs" / "PORTING_STATUS.md"

STATUSES = ["not-started", "in-progress", "ported", "verified", "skipped"]
DONE_STATUSES = {"ported", "verified", "skipped"}
TEST_MARKERS = re.compile(r"#\[\s*(cfg\(\s*test\s*\)|test\b|gpui::test\b)")
HEADER_SCAN_LINES = 12

RE_PORTED_FROM = re.compile(r"^//\s*(?:Tests ported from|Ported from):\s*(\S+)")
RE_COMMIT = re.compile(r"^//\s*Upstream commit:\s*([0-9a-fA-F]+)")
RE_STATUS = re.compile(r"^//\s*Port status:\s*([a-z-]+)")
RE_SWIFT_ONLY = re.compile(r"^//\s*Swift-only:\s*(.+)")
RE_SKIP_REASON = re.compile(r"^//\s*Skip reason:\s*(.+)")


# --------------------------------------------------------------------------- #
# Config / upstream
# --------------------------------------------------------------------------- #


def load_config() -> dict:
    with CONFIG_PATH.open() as f:
        return json.load(f)


def upstream_dir(cfg: dict) -> Path:
    return ROOT / cfg["upstream"]["checkout"]


def git(*args: str, cwd: Path | None = None, check: bool = True) -> str:
    res = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and res.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed:\n{res.stderr}")
    return res.stdout


def require_upstream(cfg: dict) -> Path:
    up = upstream_dir(cfg)
    if not (up / "Cargo.toml").exists():
        raise SystemExit(
            f"Upstream checkout not found at {up.relative_to(ROOT)}.\n"
            f"Run: Scripts/port.py fetch"
        )
    head = git("rev-parse", "HEAD", cwd=up).strip()
    if head != cfg["upstream"]["commit"]:
        print(
            f"warning: {up.relative_to(ROOT)} is at {head[:12]}, porting.json pins "
            f"{cfg['upstream']['commit'][:12]}. Run: Scripts/port.py fetch",
            file=sys.stderr,
        )
    return up


def cmd_fetch(args, cfg):
    up = upstream_dir(cfg)
    commit = cfg["upstream"]["commit"]
    if not (up / ".git").exists():
        up.mkdir(parents=True, exist_ok=True)
        git("init", "-q", cwd=up)
        git("remote", "add", "origin", cfg["upstream"]["repo"], cwd=up)
    depth = [] if args.full else ["--depth", "1"]
    if args.full and (up / ".git" / "shallow").exists():
        depth = ["--unshallow"]
    print(f"Fetching {cfg['upstream']['repo']} @ {commit[:12]} ...")
    git("fetch", "-q", *depth, "origin", commit, cwd=up)
    git("checkout", "-q", "--detach", commit, cwd=up)
    print(f"Upstream ready at {up.relative_to(ROOT)}")


# --------------------------------------------------------------------------- #
# Mapping
# --------------------------------------------------------------------------- #


@dataclass
class Entry:
    kind: str  # source | test | inline-test | asset
    crate: str
    target: str
    upstream: str  # posix path relative to upstream root
    swift: str = ""  # posix path relative to repo root (filled in by resolve)
    guard: str | None = None
    lines: int = 0

    # internal: the root this entry is resolved within, and its dir/stem
    root: str = ""
    rel_dir: str = ""
    stem: str = ""
    ext: str = ".swift"


def _rel_parts(rel: PurePosixPath) -> tuple[str, str]:
    """(directory, stem) for a Rust file relative to its source root.

    `foo/mod.rs` becomes (`foo`, `foo`) — i.e. a module named after its directory.
    """
    if rel.name == "mod.rs":
        return str(rel.parent), rel.parent.name
    stem = rel.stem
    if stem == "main":
        stem = "main_rs"  # main.swift is special in Swift (top-level code)
    return ("" if str(rel.parent) == "." else str(rel.parent)), stem


def build_entries(cfg: dict, up: Path) -> list[Entry]:
    entries: list[Entry] = []
    asset_exts = set(cfg.get("asset_extensions", []))

    for c in cfg["crates"]:
        if c["decision"] != "port":
            continue
        crate_root = up / c["path"]
        target = c["target"]
        guard = c.get("guard")
        excludes = [crate_root / e for e in c.get("exclude", [])]

        def excluded(p: Path) -> bool:
            return any(ex == p or ex in p.parents for ex in excludes)

        layout = [
            ("src", f"Sources/{target}", "", "source"),
            ("examples", f"Sources/{target}", "examples", "source"),
            ("tests", f"Tests/{target}Tests", "tests", "test"),
        ]
        for sub, root, prefix, kind in layout:
            base = crate_root / sub
            if not base.is_dir():
                continue
            for p in sorted(base.rglob("*")):
                if not p.is_file() or excluded(p):
                    continue
                rel = PurePosixPath(p.relative_to(base).as_posix())
                upstream_rel = p.relative_to(up).as_posix()
                text = None
                if p.suffix == ".rs":
                    d, stem = _rel_parts(rel)
                    d = str(PurePosixPath(prefix) / d) if prefix else d
                    d = "" if d == "." else d
                    text = p.read_text(errors="replace")
                    e = Entry(kind, c["crate"], target, upstream_rel, guard=guard,
                              lines=text.count("\n"), root=root, rel_dir=d, stem=stem)
                    entries.append(e)
                    if kind == "source" and sub == "src" and TEST_MARKERS.search(text):
                        entries.append(Entry("inline-test", c["crate"], target, upstream_rel,
                                             guard=guard, lines=0,
                                             root=f"Tests/{target}Tests", rel_dir=d, stem=stem))
                elif p.suffix in asset_exts:
                    d = str(PurePosixPath(prefix) / rel.parent) if prefix else str(rel.parent)
                    d = "" if d == "." else d
                    entries.append(Entry("asset", c["crate"], target, upstream_rel, guard=guard,
                                         root=root, rel_dir=d, stem=p.stem, ext=p.suffix))
    resolve_collisions(entries)
    return entries


def resolve_collisions(entries: list[Entry]) -> None:
    """SwiftPM forbids two sources with the same basename in one target
    (the object files collide). Disambiguate by prefixing parent directory
    names, shallowest file keeps the plain name. Comparison is case-insensitive
    because macOS/Windows filesystems are."""
    by_root: dict[str, list[Entry]] = defaultdict(list)
    for e in entries:
        if e.ext == ".swift":
            by_root[e.root].append(e)
        else:
            e.swift = str(PurePosixPath(e.root) / e.rel_dir / f"{e.stem}{e.ext}")

    # Inline-test files reuse the (already unique) name of their source file so
    # `Sources/T/a/b.swift` always pairs with `Tests/TTests/a/b.swift`.
    fixed: dict[int, str] = {}

    def resolve_group(group: list[Entry]) -> None:
        level: dict[int, int] = {id(e): 0 for e in group}

        def name_of(e: Entry) -> str:
            if id(e) in fixed:
                return fixed[id(e)]
            k = level[id(e)]
            dirs = [d for d in PurePosixPath(e.rel_dir).parts if d not in ("", ".")]
            # mod.rs-style stems already equal their dir; don't repeat it.
            if dirs and dirs[-1] == e.stem:
                dirs = dirs[:-1]
            prefix = dirs[len(dirs) - k:] if k else []
            return "_".join([*prefix, e.stem])

        for _ in range(16):
            names: dict[str, list[Entry]] = defaultdict(list)
            for e in group:
                names[name_of(e).lower()].append(e)
            clashes = [g for g in names.values() if len(g) > 1]
            if not clashes:
                break
            for g in clashes:
                g.sort(key=lambda e: (id(e) not in fixed, len(PurePosixPath(e.rel_dir).parts), e.upstream))
                movable = [e for e in g if id(e) not in fixed]
                if len(movable) == len(g):
                    depth0 = len(PurePosixPath(g[0].rel_dir).parts)
                    if len(PurePosixPath(g[1].rel_dir).parts) > depth0:
                        movable = movable[1:]  # shallowest file keeps the plain name
                if not movable:
                    raise SystemExit(f"Unresolvable collision: {[e.upstream for e in g]}")
                for e in movable:
                    level[id(e)] += 1
        else:
            raise SystemExit(f"Could not resolve filename collisions in {group[0].root}")

        for e in group:
            e.swift = str(PurePosixPath(e.root) / e.rel_dir / f"{name_of(e)}.swift")

    # 1. Source roots.
    for root, group in by_root.items():
        if not root.startswith("Tests/"):
            resolve_group(group)
    # 2. Test roots: inline tests are pinned to their source's name.
    by_source = {(e.target, e.upstream): e for e in entries if e.kind == "source"}
    for root, group in by_root.items():
        if root.startswith("Tests/"):
            for e in group:
                if e.kind == "inline-test":
                    fixed[id(e)] = PurePosixPath(by_source[(e.target, e.upstream)].swift).stem
            resolve_group(group)


# --------------------------------------------------------------------------- #
# Headers
# --------------------------------------------------------------------------- #


def read_header(path: Path) -> dict:
    info = {"ported_from": None, "commit": None, "status": None, "swift_only": None, "skip_reason": None}
    try:
        with path.open(errors="replace") as f:
            for _, line in zip(range(HEADER_SCAN_LINES), f):
                line = line.strip()
                for key, rx in (("ported_from", RE_PORTED_FROM), ("commit", RE_COMMIT),
                                ("status", RE_STATUS), ("swift_only", RE_SWIFT_ONLY),
                                ("skip_reason", RE_SKIP_REASON)):
                    m = rx.match(line)
                    if m and info[key] is None:
                        info[key] = m.group(1).strip()
    except FileNotFoundError:
        pass
    return info


def stub_text(e: Entry, commit: str) -> str:
    short = commit[:12]
    if e.kind == "inline-test":
        head = (f"// Tests ported from: {e.upstream} (#[cfg(test)] items)\n"
                f"// Upstream commit: {short}\n"
                f"// Port status: not-started\n")
        body = f"import Testing\n@testable import {e.target}\n"
    elif e.kind == "test":
        head = (f"// Tests ported from: {e.upstream}\n"
                f"// Upstream commit: {short}\n"
                f"// Port status: not-started\n")
        body = f"import Testing\n@testable import {e.target}\n"
    else:
        head = (f"// Ported from: {e.upstream}\n"
                f"// Upstream commit: {short}\n"
                f"// Port status: not-started\n")
        body = ""
    if e.guard:
        body = f"#if {e.guard}\n{body}\n#endif\n" if body else f"#if {e.guard}\n\n#endif\n"
    return head + ("\n" + body if body else "")


# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #


def cmd_map(args, cfg):
    up = require_upstream(cfg)
    entries = build_entries(cfg, up)
    q = args.path.replace("\\", "/").lstrip("./")
    hits = [e for e in entries if e.upstream == q or e.swift == q
            or e.upstream.endswith("/" + q) or e.swift.endswith("/" + q)]
    if not hits:
        for c in cfg["crates"]:
            if q.startswith(c["path"] + "/") and c["decision"] != "port":
                print(f"{q}: crate `{c['crate']}` is `{c['decision']}` — {c.get('note', '')}")
                return
        raise SystemExit(f"No mapping for {q}")
    for e in hits:
        print(f"{e.kind:12} {e.upstream}  ->  {e.swift}")


def cmd_scaffold(args, cfg):
    up = require_upstream(cfg)
    commit = cfg["upstream"]["commit"]
    created = 0
    for e in build_entries(cfg, up):
        dest = ROOT / e.swift
        if dest.exists():
            continue
        created += 1
        if args.dry_run:
            print(f"would create {e.swift}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        if e.kind == "asset":
            shutil.copyfile(up / e.upstream, dest)
        else:
            dest.write_text(stub_text(e, commit))
    print(f"{'Would create' if args.dry_run else 'Created'} {created} file(s).")


def collect(cfg):
    up = require_upstream(cfg)
    entries = build_entries(cfg, up)
    rows = []
    for e in entries:
        if e.kind == "asset":
            status = "copied" if (ROOT / e.swift).exists() else "missing"
            rows.append((e, status, None))
            continue
        h = read_header(ROOT / e.swift)
        status = h["status"] if (ROOT / e.swift).exists() else "missing"
        rows.append((e, status or "unknown", h))
    return up, rows


def render_status(cfg, rows) -> str:
    commit = cfg["upstream"]["commit"]
    repo_web = cfg["upstream"]["repo"].removesuffix(".git")
    per_target: dict[str, Counter] = defaultdict(Counter)
    lines_total: Counter = Counter()
    lines_done: Counter = Counter()
    for e, status, _ in rows:
        if e.kind != "source":
            continue
        per_target[e.target][status] += 1
        lines_total[e.target] += e.lines
        if status in DONE_STATUSES:
            lines_done[e.target] += e.lines

    out = [
        "# Porting Status",
        "",
        "<!-- GENERATED by `Scripts/port.py status --write`. Do not edit by hand. -->",
        "",
        f"Upstream: [{repo_web.split('github.com/')[-1]}@{commit[:12]}]({repo_web}/tree/{commit})",
        "",
        "Status comes from the `// Port status:` header of each Swift file. "
        "Lines are upstream Rust lines (a rough size signal, not a goal).",
        "",
        "## Summary (source files)",
        "",
        "| Target | Files | Not started | In progress | Ported | Verified | Skipped | Upstream lines | Lines done |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    grand = Counter()
    for t in sorted(per_target, key=lambda t: -lines_total[t]):
        c = per_target[t]
        n = sum(c.values())
        pct = (100 * lines_done[t] / lines_total[t]) if lines_total[t] else 0
        out.append(f"| `{t}` | {n} | {c['not-started']} | {c['in-progress']} | {c['ported']} | "
                   f"{c['verified']} | {c['skipped']} | {lines_total[t]:,} | {pct:.0f}% |")
        grand.update(c)
    tl, td = sum(lines_total.values()), sum(lines_done.values())
    out.append(f"| **Total** | **{sum(grand.values())}** | {grand['not-started']} | {grand['in-progress']} | "
               f"{grand['ported']} | {grand['verified']} | {grand['skipped']} | {tl:,} | "
               f"{(100 * td / tl) if tl else 0:.0f}% |")
    out += ["", "## Files", ""]

    by_target: dict[str, list] = defaultdict(list)
    for r in rows:
        by_target[r[0].target].append(r)
    for t in sorted(by_target):
        out += [f"### `{t}`", "", "| Upstream | Swift | Kind | Lines | Status |", "|---|---|---|---:|---|"]
        for e, status, _ in sorted(by_target[t], key=lambda r: (r[0].kind != "source", r[0].upstream)):
            up_link = f"[{e.upstream}]({repo_web}/blob/{commit}/{e.upstream})"
            sw_link = f"[{e.swift}](../{e.swift})"
            out.append(f"| {up_link} | {sw_link} | {e.kind} | {e.lines or ''} | {status} |")
        out.append("")
    return "\n".join(out)


def cmd_status(args, cfg):
    _, rows = collect(cfg)
    text = render_status(cfg, rows)
    if args.write:
        STATUS_DOC.parent.mkdir(parents=True, exist_ok=True)
        STATUS_DOC.write_text(text + "\n")
        print(f"Wrote {STATUS_DOC.relative_to(ROOT)}")
    else:
        # Summary only on stdout.
        print("\n".join(text.split("\n## Files")[0].splitlines()[6:]))


def cmd_todo(args, cfg):
    _, rows = collect(cfg)
    todo = [(e, s) for e, s, _ in rows
            if e.kind == "source" and s == "not-started" and (not args.target or e.target == args.target)]
    for e, _ in sorted(todo, key=lambda r: r[0].lines):
        print(f"{e.lines:6}  {e.swift:70}  <- {e.upstream}")


def cmd_check(args, cfg):
    up, rows = collect(cfg)
    errors: list[str] = []
    mapped = {e.swift for e, _, _ in rows}
    commit = cfg["upstream"]["commit"]

    for e, status, h in rows:
        if status == "missing":
            errors.append(f"missing: {e.swift} (run Scripts/port.py scaffold)")
            continue
        if e.kind == "asset":
            continue
        if status not in STATUSES:
            errors.append(f"{e.swift}: invalid or missing `// Port status:` ({status}); "
                          f"expected one of {', '.join(STATUSES)}")
        if status == "skipped" and not h["skip_reason"]:
            errors.append(f"{e.swift}: `skipped` files need a `// Skip reason: <why>` header line")
        if h["ported_from"] != e.upstream:
            errors.append(f"{e.swift}: header says ported from {h['ported_from']!r}, mapping says {e.upstream!r}")
        if not h["commit"]:
            errors.append(f"{e.swift}: missing `// Upstream commit:` header")
        elif not commit.startswith(h["commit"]):
            pass  # stale, reported by `stale`, not an error

    known_targets = {c["target"] for c in cfg["crates"] if c.get("target")}
    known_targets |= {t["target"] for t in cfg.get("swift_only_targets", [])}
    for base in ("Sources", "Tests"):
        for p in sorted((ROOT / base).rglob("*.swift")):
            rel = p.relative_to(ROOT).as_posix()
            if rel in mapped:
                continue
            h = read_header(p)
            if not h["swift_only"]:
                errors.append(f"orphan: {rel} has no upstream counterpart and no `// Swift-only: <reason>` header")
        for d in sorted((ROOT / base).iterdir()) if (ROOT / base).exists() else []:
            name = d.name.removesuffix("Tests") if base == "Tests" else d.name
            if d.is_dir() and name not in known_targets:
                errors.append(f"unknown target directory: {d.relative_to(ROOT)} (add it to porting.json)")

    if STATUS_DOC.exists() and STATUS_DOC.read_text().rstrip() != render_status(cfg, rows).rstrip():
        errors.append("docs/PORTING_STATUS.md is out of date (run Scripts/port.py status --write)")

    if errors:
        print("\n".join(errors))
        raise SystemExit(f"\n{len(errors)} problem(s).")
    print(f"OK — {len(rows)} mapped files, upstream {commit[:12]}.")


def cmd_stale(args, cfg):
    up, rows = collect(cfg)
    pinned = cfg["upstream"]["commit"]
    any_stale = False
    for e, status, h in rows:
        if not h or not h["commit"] or pinned.startswith(h["commit"]) or status == "not-started":
            continue
        any_stale = True
        res = subprocess.run(["git", "diff", "--stat", h["commit"], pinned, "--", e.upstream],
                             cwd=up, capture_output=True, text=True)
        stat = res.stdout.strip().splitlines()[-1] if res.returncode == 0 and res.stdout.strip() else \
            "(no diff or commit unavailable — try `Scripts/port.py fetch --full`)"
        print(f"{e.swift}\n    ported @ {h['commit']}, pinned @ {pinned[:12]}: {stat}")
    if not any_stale:
        print("No stale files.")


def cmd_bump(args, cfg):
    up = upstream_dir(cfg)
    old = cfg["upstream"]["commit"]
    new = args.commit
    git("fetch", "-q", "origin", old, new, cwd=up)
    new = git("rev-parse", new, cwd=up).strip()
    print(git("diff", "--name-status", old, new, "--", "crates", cwd=up))
    cfg["upstream"]["commit"] = new
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n")
    git("checkout", "-q", "--detach", new, cwd=up)
    print(f"Pinned {new[:12]}. Next: Scripts/port.py scaffold && Scripts/port.py stale && "
          f"Scripts/port.py status --write")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("fetch"); p.add_argument("--full", action="store_true"); p.set_defaults(fn=cmd_fetch)
    p = sub.add_parser("map"); p.add_argument("path"); p.set_defaults(fn=cmd_map)
    p = sub.add_parser("scaffold"); p.add_argument("--dry-run", action="store_true"); p.set_defaults(fn=cmd_scaffold)
    p = sub.add_parser("status"); p.add_argument("--write", action="store_true"); p.set_defaults(fn=cmd_status)
    p = sub.add_parser("todo"); p.add_argument("--target"); p.set_defaults(fn=cmd_todo)
    p = sub.add_parser("check"); p.set_defaults(fn=cmd_check)
    p = sub.add_parser("stale"); p.set_defaults(fn=cmd_stale)
    p = sub.add_parser("bump"); p.add_argument("commit"); p.set_defaults(fn=cmd_bump)
    args = ap.parse_args()
    os.chdir(ROOT)
    args.fn(args, load_config())


if __name__ == "__main__":
    main()
