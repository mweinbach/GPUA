// Tests ported from: crates/util/src/disambiguate.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import ZedUtil

@Suite("Disambiguate Tests")
struct DisambiguateTests {
    @Test
    func test_no_conflicts() {
        let items = ["alpha", "beta", "gamma"]
        let details = computeDisambiguationDetails(items) { item, _ in item }
        #expect(details == [0, 0, 0])
    }

    @Test
    func test_simple_two_way_conflict() {
        let items = [("src/foo.rs", "foo.rs"), ("lib/foo.rs", "foo.rs")]
        let details = computeDisambiguationDetails(items) { item, detail in
            detail == 0 ? item.1 : item.0
        }
        #expect(details == [1, 1])
    }

    @Test
    func test_three_way_conflict() {
        let items = [
            ("foo.rs", "a/foo.rs"),
            ("foo.rs", "b/foo.rs"),
            ("foo.rs", "c/foo.rs"),
        ]
        let details = computeDisambiguationDetails(items) { item, detail in
            detail == 0 ? item.0 : item.1
        }
        #expect(details == [1, 1, 1])
    }

    @Test
    func test_deeper_conflict() {
        let items = [
            ["file.rs", "src/file.rs", "a/src/file.rs"],
            ["file.rs", "src/file.rs", "b/src/file.rs"],
            ["file.rs", "lib/file.rs", "x/lib/file.rs"],
        ]
        let details = computeDisambiguationDetails(items) { item, detail in
            let clamped = min(detail, item.count - 1)
            return item[clamped]
        }
        #expect(details == [2, 2, 1])
    }

    @Test
    func test_mixed_conflicting_and_unique() {
        let items = [
            ("src/foo.rs", "foo.rs"),
            ("lib/foo.rs", "foo.rs"),
            ("src/bar.rs", "bar.rs"),
        ]
        let details = computeDisambiguationDetails(items) { item, detail in
            detail == 0 ? item.1 : item.0
        }
        #expect(details == [1, 1, 0])
    }

    @Test
    func test_identical_items_terminates() {
        let items = ["same", "same", "same"]
        let details = computeDisambiguationDetails(items) { item, _ in item }
        #expect(details == [1, 1, 1])
    }

    @Test
    func test_single_item() {
        let items = ["only"]
        let details = computeDisambiguationDetails(items) { item, _ in item }
        #expect(details == [0])
    }

    @Test
    func test_empty_input() {
        let items: [String] = []
        let details = computeDisambiguationDetails(items) { item, _ in item }
        let expected: [Int] = []
        #expect(details == expected)
    }

    @Test
    func test_duplicate_paths_from_multiple_groups() {
        func pathSuffix(_ path: String, _ detail: Int) -> String {
            let components = path
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            let count = components.count
            let takeCount = min(detail + 1, count)
            let suffixComponents = components[(count - takeCount)...]
            return suffixComponents.joined(separator: "/")
        }

        let allPaths = [
            "/Users/rtfeldman/code/worktrees/zed/focal-arrow/zed",
            "/Users/rtfeldman/code/zed",
            "/Users/rtfeldman/code/roc",
        ]

        let details = computeDisambiguationDetails(allPaths) { path, detail in
            pathSuffix(path, detail)
        }

        #expect(details == [1, 1, 0])
        #expect(pathSuffix(allPaths[0], details[0]) == "focal-arrow/zed")
        #expect(pathSuffix(allPaths[1], details[1]) == "code/zed")
        #expect(pathSuffix(allPaths[2], details[2]) == "roc")
    }
}
