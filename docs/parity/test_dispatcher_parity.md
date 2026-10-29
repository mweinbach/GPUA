# API Parity Audit: `dispatcher.rs`

- **Generated At**: 2026-10-29T04:27:44Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/platform/test/dispatcher.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/platform/test/dispatcher.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **12** | 100.0% |
| Genuine Swift Implementations | 12 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 12 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (12 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 17 | `TestDispatcher` | `struct` | `TestDispatcher` | `dispatcher.swift:9` |
| 24 | `TestDispatcher::new` | `fn` | `new` | `dispatcher.swift:31` |
| 43 | `TestDispatcher::scheduler` | `fn` | `scheduler` | `dispatcher.swift:35` |
| 47 | `TestDispatcher::session_id` | `fn` | `sessionId` | `dispatcher.swift:10` |
| 51 | `TestDispatcher::drain_tasks` | `fn` | `drainTasks` | `dispatcher.swift:39` |
| 55 | `TestDispatcher::advance_clock` | `fn` | `advanceClock` | `dispatcher.swift:43` |
| 59 | `TestDispatcher::advance_clock_to_next_timer` | `fn` | `advanceClockToNextTimer` | `dispatcher.swift:53` |
| 63 | `TestDispatcher::simulate_random_delay` | `fn` | `simulateRandomDelay` | `dispatcher.swift:57` |
| 67 | `TestDispatcher::tick` | `fn` | `tick` | `dispatcher.swift:61` |
| 75 | `TestDispatcher::run_until_parked` | `fn` | `runUntilParked` | `dispatcher.swift:69` |
| 81 | `TestDispatcher::set_num_cpus` | `fn` | `setNumCpus` | `dispatcher.swift:73` |
| 86 | `TestDispatcher::num_cpus_override` | `fn` | `numCpusOverride` | `dispatcher.swift:79` |

</details>
