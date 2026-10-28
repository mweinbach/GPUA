// Swift-only: unit tests for GPUIUtil/lib.swift

import Testing
@testable import GPUIUtil

@Suite("GPUIUtil Tests")
struct GPUIUtilTests {
    @Test func test_post_inc() {
        var x = 0
        #expect(postInc(&x) == 0)
        #expect(x == 1)
        #expect(postInc(&x) == 1)
        #expect(x == 2)
    }

    @Test func test_deferred_executes_on_drop() {
        var executed = false
        do {
            let _ = Deferred {
                executed = true
            }
        }
        #expect(executed)
    }

    @Test func test_deferred_abort_cancels_execution() {
        var executed = false
        do {
            let guard_ = Deferred {
                executed = true
            }
            guard_.abort()
        }
        #expect(!executed)
    }

    @Test func test_result_ext() {
        enum TestErr: Error, CustomStringConvertible {
            case fail
            var description: String { "fail" }
        }

        let success: Result<Int, TestErr> = .success(42)
        #expect(success.logErr() == 42)
        #expect(success.warnOnErr() == 42)

        let failure: Result<Int, TestErr> = .failure(.fail)
        #expect(failure.logErr() == nil)
        #expect(failure.warnOnErr() == nil)
    }

    @Test func test_measure_runs_closure() {
        let result = measure("test") {
            40 + 2
        }
        #expect(result == 42)
    }
}
