// Tests ported from: crates/rune/src/memo.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Tests exercising `MemoCache`, `memo(...)`, `memoNamespace.layout*`, nested memo survival,
// duplicate memo IDs, and `Runtime` environment invalidation are ported below. Full `Runtime` wheel/IME
// virtual-row scroll integration tests depend on `runtime.swift` layout/input subsystems owned outside
// this module cluster.

private struct MemoCardState {
    var version: UInt32 = 0
    var ticks: UInt32 = 0
    var presses: UInt32 = 0
}

private func commitFrame<S>(_ rt: Runtime<S>) {
    rt.update { _, _ in }
    rt.frame(1.0 / 60.0)
}

@Suite("MemoTests")
struct MemoTests {
    @Test("an unchanged version reuses the subtree and a new version or theme builds")
    func unchangedVersionReusesAndNewVersionOrThemeBuilds() {
        var builds = 0
        func counted(_ e: El) -> El {
            builds += 1
            return e
        }
        func view(_ s: MemoCardState, _ cx: Cx<MemoCardState>) -> El {
            col().size(200.0, 200.0).children([
                memo("card", s.version) {
                    counted(
                        col().child(
                            el().key("button").size(40.0, 40.0).fill(Color.WHITE).onPress { (st: inout MemoCardState) in
                                st.presses += 1
                            }
                        )
                    )
                },
                text("tick \(s.ticks)").key("tick"),
            ])
        }

        let rt = Runtime(MemoCardState(), view, (200.0, 200.0), Env(systemDark: true, scale: 1.0))
        rt.frame(0.0)
        #expect(builds == 1)

        for _ in 0..<3 {
            rt.state.ticks += 1
            commitFrame(rt)
        }
        #expect(builds == 1)

        rt.state.version += 1
        commitFrame(rt)
        #expect(builds == 2)

        rt.env.systemDark = false
        commitFrame(rt)
        #expect(builds == 3)

        rt.env.scale = 2.0
        commitFrame(rt)
        #expect(builds == 4)

        rt.memo.clear()
        commitFrame(rt)
        #expect(builds == 5)
        #expect(rt.elements().contains { $0.key == "button" })
    }

    @Test("a memo inside a reused memo survives to the outer ones next build")
    func memoInsideReusedMemoSurvivesToOuterNextBuild() {
        struct PairState {
            var outer: UInt32 = 0
            var inner: UInt32 = 0
        }
        var builds = 0
        func counted(_ e: El) -> El {
            builds += 1
            return e
        }
        func view(_ s: PairState, _ cx: Cx<PairState>) -> El {
            col().child(
                memo("outer", s.outer) {
                    counted(
                        col().children([
                            memo("inner", s.inner) { counted(text("inner").key("t")) },
                            text("outer \(s.outer)"),
                        ])
                    )
                }
            )
        }

        let rt = Runtime(PairState(), view, (200.0, 200.0), Env())
        rt.frame(0.0)
        #expect(builds == 2)

        commitFrame(rt)
        commitFrame(rt)
        #expect(builds == 2)

        rt.state.outer += 1
        commitFrame(rt)
        #expect(builds == 3)

        rt.state.inner += 1
        commitFrame(rt)
        #expect(builds == 3)
    }

    @Test("an id used twice in one build builds both")
    func idUsedTwiceInOneBuildBuildsBoth() {
        var builds = 0
        func counted(_ e: El) -> El {
            builds += 1
            return e
        }
        func view(_ s: (), _ cx: Cx<()>) -> El {
            col().children([
                col().key("a").child(memo("same", 0) { counted(text("a").key("t")) }),
                col().key("b").child(memo("same", 0) { counted(text("b").key("t")) }),
            ])
        }

        let rt = Runtime((), view, (200.0, 200.0), Env())
        rt.frame(0.0)
        commitFrame(rt)
        let texts = rt.elements().compactMap(\.text)
        #expect(texts == ["a", "b"])
        #expect(builds == 3)
    }

    @Test("layout and size reads inside a memo rebuild only when their read value changes")
    func layoutAndSizeReadsRebuildOnlyWhenChanged() {
        var builds = 0
        func counted(_ e: El) -> El {
            builds += 1
            return e
        }
        func view(_ ticks: UInt32, _ cx: Cx<UInt32>) -> El {
            col().children([
                memo("sizeOnly", 0) {
                    let sz = memoNamespace.layoutSize("probe")
                    return counted(text("\(String(describing: sz))").key("sizeOnly"))
                },
                memo("rect", 0) {
                    let r = memoNamespace.layout("probe")
                    return counted(text("\(String(describing: r))").key("rect"))
                },
                text("tick \(ticks)").key("tick"),
            ])
        }

        let rt = Runtime(UInt32(0), view, (300.0, 300.0), Env())
        rt.memo.layoutRects["probe"] = [0.0, 0.0, 100.0, 10.0]
        rt.frame(0.0)
        #expect(builds == 2)

        rt.state += 1
        commitFrame(rt)
        #expect(builds == 2)

        // Move `probe` without changing its 100x10 size: only `rect` rebuilds, `sizeOnly` reuses.
        rt.memo.layoutRects["probe"] = [0.0, 40.0, 100.0, 50.0]
        rt.state += 1
        commitFrame(rt)
        #expect(builds == 3)

        // Resize `probe` to 150x10: both `sizeOnly` and `rect` rebuild.
        rt.memo.layoutRects["probe"] = [0.0, 40.0, 150.0, 50.0]
        rt.state += 1
        commitFrame(rt)
        #expect(builds == 5)
    }

    @Test("TextEdit selection changes its Hashable version for memo")
    func textEditSelectionChangesHashVersion() {
        var edit = TextEdit("ab")
        var h1 = Hasher()
        edit.hash(into: &h1)
        let caretHash = h1.finalize()

        edit.anchor = 0
        var h2 = Hasher()
        edit.hash(into: &h2)
        #expect(h2.finalize() != caretHash)
    }
}
