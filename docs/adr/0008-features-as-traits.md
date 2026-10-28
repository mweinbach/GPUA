# 0008: Cargo features → SwiftPM package traits

- **Status:** Accepted
- **Date:** 2026-10-27

## Context

Upstream gates code with Cargo features: `test-support`, `inspector`, `screen-capture`, `wayland`, `x11`, `runtime_shaders`, `font-kit`, `leak-detection`, and others. SwiftPM 6.1+ has **package traits** (SE-0450), which are exposed to code as compilation conditions.

## Decision

- Each upstream feature that gates GPUI code maps to a trait in `Package.swift` with a PascalCase name: `TestSupport`, `Inspector`, `ScreenCapture`, `Wayland`, `X11`, `RuntimeShaders`.
- `#[cfg(feature = "test-support")]` and `#[cfg(test)]` *in library code* become `#if TestSupport`.
- Default traits: `TestSupport`, `Wayland`, `X11`. `TestSupport` stays on by default while porting so the test suites work out of the box. Revisit before 1.0, since apps should be able to disable it.
- `leak-detection` folds into `TestSupport`. `font-kit` becomes moot because we don't use font-kit.

## Consequences

Consumers can do `.package(url: …, traits: ["Wayland"])` to slim Linux builds. New traits require an ADR.
