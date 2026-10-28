# Contributing to GPUA

Thanks for helping bring GPUI to Swift. The project is a **faithful, file-for-file port**, so contributing is mostly translation work. The process is designed to be mechanical and easy to review.

## Setup

```sh
git clone https://github.com/mweinbach/GPUA && cd GPUA
Scripts/port.py fetch     # pinned upstream → .upstream/gpui
swift build
```

You need Swift 6.2+ (Xcode 26+ on macOS, swift.org toolchains on Linux/Windows) and Python 3.9+ for `Scripts/port.py`.

## Workflow

1. **Pick a file.** Use `Scripts/port.py todo --target <Target>` and the phase order in [docs/ROADMAP.md](docs/ROADMAP.md). Comment on or open a "Port file" issue so two people don't port the same thing.
2. **Port it.** Open `.upstream/gpui/<path>` next to the Swift file (`Scripts/port.py map <path>`) and follow [docs/PORTING_GUIDE.md](docs/PORTING_GUIDE.md). Keep item order and doc comments.
3. **Port its tests** into the paired file under `Tests/`.
4. **Update the header** (`Port status:`), then run:
   ```sh
   swift build && swift test
   Scripts/port.py status --write
   Scripts/port.py check
   ```
5. **Open a PR** titled `port(<Target>): <path>`, e.g. `port(GPUI): geometry.rs`. Small PRs get reviewed fastest.

## Review checklist

Reviewers compare the Swift and Rust files side by side:

- [ ] Every upstream item is present and in the same order, or omitted with a `// PORT NOTE:`
- [ ] Naming follows the guide (types verbatim, members lowerCamelCase, unlabeled params)
- [ ] Visibility maps correctly (`public` / `package` / `internal` / `private`)
- [ ] There are no behavior changes. Deviations are explained
- [ ] Tests are ported and passing
- [ ] There are no unexplained `@unchecked Sendable`, `nonisolated(unsafe)`, or force unwraps
- [ ] The header status is accurate, and `check` passes

## Bigger changes

New dependencies, deviations from the mapping, new targets/traits, or platform technology choices need an **ADR** ([docs/adr/](docs/adr)) first.

## AI agents

AI agents are welcome. [AGENTS.md](AGENTS.md) has the rules, and they apply to humans too.

## License

By contributing, you agree that your contributions are licensed under Apache-2.0, the same license as the project and upstream GPUI.
