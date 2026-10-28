# 0003: Concurrency model: `@MainActor` app state, GPUI-owned executors

- **Status:** Accepted
- **Date:** 2026-10-28

## Context

- GPUI app state (`App`, `Window`, entities) is **single-threaded and main-thread-only**. In Rust, `!Send` types plus `&mut App` threading enforce this.
- GPUI has its own executors. `ForegroundExecutor` runs `!Send` futures on the main thread through `PlatformDispatcher::dispatch_on_main_thread`. `BackgroundExecutor` runs `Send` futures on a thread pool through `PlatformDispatcher::dispatch`. `Task<T>` cancels on drop and has `.detach()`.
- **Tests depend on determinism.** `TestDispatcher` (via the `scheduler` crate) controls every task: random but seeded interleavings, `run_until_parked`, simulated time, and `#[gpui::test(iterations = N)]`. A large share of upstream's test value comes from this.
- Swift 6 has strict data-race checking, global actors, and custom executors (`SerialExecutor`, `TaskExecutor`, task executor preference).

## Decision

1. **App state is `@MainActor`.** `App`, `Window`, `Context<T>`, `Entity<T>` operations, element and render code, and the `Platform*` protocols' main-thread members are all `@MainActor`. That's the Swift spelling of "`!Send`, main thread".
2. **GPUI's `Task<T>` is ported as GPUI's own type**, not as a typealias for Swift's `Task`. It keeps upstream semantics: cancel on drop, `detach()`, `Task.ready(_:)`.
3. **Executors are driven by `PlatformDispatcher`.** Futures are Swift `async` closures. The executors run them as jobs on a custom executor that forwards to `PlatformDispatcher.dispatch`/`dispatchOnMainThread`:
   - Background: a `TaskExecutor` backed by the dispatcher. Spawns use `Task(executorPreference:)`.
   - Foreground: jobs are enqueued through the dispatcher's main-thread queue so `TestDispatcher` can order them. Code inside is `@MainActor`-isolated (asserted with `MainActor.assumeIsolated` at job entry).
4. **Under test,** `TestDispatcher` implements `PlatformDispatcher` and holds every job in its queues. `runUntilParked()` drains them deterministically with the seeded RNG, exactly as upstream does.
5. Platform callbacks from C (Wayland, Win32 WndProc, NDK looper) enter Swift as `nonisolated` and hop with `MainActor.assumeIsolated`, because they're already on the main thread by contract. Use `// PORT NOTE:` at each such site.

## Validated Concurrency Decisions

- **Deterministic cooperative scheduling**: `ForegroundExecutor` and `TestScheduler` maintain explicit runnable queues with session IDs and priority weights. When running under test, tasks scheduled through `cx.spawn` or executor methods are executed by `TestScheduler.run()` or `TestScheduler.step()` in order determined by the seed, avoiding unconstrained global executor thread hopping and ensuring reproducible interleavings.
- **Actor boundary crossing**: Background operations communicate back to `@MainActor` by returning `Sendable` types or dispatching explicitly onto the context (`cx.update`), ensuring clean Swift 6 strict concurrency compliance without relying on unjustified `@unchecked Sendable` annotations.

## Consequences

The Rust executor and scheduler logic ports faithfully into idiomatic Swift, and tests keep their power. Users write normal `async`/`await`, but use `cx.spawn`/`cx.backgroundExecutor().spawn` instead of bare `Task {}` when they want GPUI scheduling semantics (documented in API_DESIGN).
