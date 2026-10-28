## What

<!-- e.g. port(GPUI): geometry.rs + tests -->

Upstream: `crates/...` → Swift: `Sources/...`

## Checklist

- [ ] Items translated in upstream order; deviations marked `// PORT NOTE:`
- [ ] Tests ported (paired file in `Tests/`) and passing
- [ ] File header `Port status:` / `Upstream commit:` updated
- [ ] `swift build` passes
- [ ] `Scripts/port.py status --write && Scripts/port.py check` passes
- [ ] New dependency / deviation? → ADR linked
