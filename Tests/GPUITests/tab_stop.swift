// Tests ported from: crates/gpui/src/tab_stop.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("Tab Stop Tests")
struct TabStopTests {
    @Test("Tab handles next and prev navigation with wrapping")
    func testTabHandles() {
        let focusMap = FocusMap()
        var tabIndexMap = TabStopMap()

        let focusHandles = [
            FocusHandle(handles: focusMap).tabStop(true).tabIndex(0),
            FocusHandle(handles: focusMap).tabStop(true).tabIndex(1),
            FocusHandle(handles: focusMap).tabStop(true).tabIndex(1),
            FocusHandle(handles: focusMap),
            FocusHandle(handles: focusMap).tabIndex(2),
            FocusHandle(handles: focusMap).tabStop(true).tabIndex(0),
            FocusHandle(handles: focusMap).tabStop(true).tabIndex(2),
        ]

        for handle in focusHandles {
            tabIndexMap.insert(handle)
        }

        let expected = [
            focusHandles[0],
            focusHandles[5],
            focusHandles[1],
            focusHandles[2],
            focusHandles[6],
        ]

        var prev: FocusId? = nil
        var found: [FocusId] = []
        for _ in 0..<expected.count {
            let handle = tabIndexMap.next(prev)!
            prev = handle.id
            found.append(handle.id)
        }

        #expect(found == expected.map(\.id))

        // Select first tab index if no handle is currently focused.
        #expect(tabIndexMap.next(nil) == expected[0])
        // Select last tab index if no handle is currently focused.
        #expect(tabIndexMap.prev(nil) == expected.last)

        #expect(tabIndexMap.next(expected[0].id) == expected[1])
        #expect(tabIndexMap.next(expected[1].id) == expected[2])
        #expect(tabIndexMap.next(expected[2].id) == expected[3])
        #expect(tabIndexMap.next(expected[3].id) == expected[4])
        #expect(tabIndexMap.next(expected[4].id) == expected[0])

        // prev
        #expect(tabIndexMap.prev(nil) == expected[4])
        #expect(tabIndexMap.prev(expected[0].id) == expected[4])
        #expect(tabIndexMap.prev(expected[1].id) == expected[0])
        #expect(tabIndexMap.prev(expected[2].id) == expected[1])
        #expect(tabIndexMap.prev(expected[3].id) == expected[2])
        #expect(tabIndexMap.prev(expected[4].id) == expected[3])
    }

    @Test("Tab non-stop filtering skips non-stops and queries from non-stops")
    func testTabNonStopFiltering() {
        let focusMap = FocusMap()
        var tabIndexMap = TabStopMap()

        // Check that we can query next from a non-stop tab
        let tabNonStop1 = FocusHandle(handles: focusMap).tabStop(false).tabIndex(1)
        let tabStop2 = FocusHandle(handles: focusMap).tabStop(true).tabIndex(2)
        tabIndexMap.insert(tabNonStop1)
        tabIndexMap.insert(tabStop2)
        let result = tabIndexMap.next(tabNonStop1.id)!
        #expect(result.id == tabStop2.id)

        // Check that we skip over non-stop tabs
        let tabStop0 = FocusHandle(handles: focusMap).tabStop(true).tabIndex(0)
        let tabNonStop0 = FocusHandle(handles: focusMap).tabStop(false).tabIndex(0)
        tabIndexMap.insert(tabStop0)
        tabIndexMap.insert(tabNonStop0)
        let result2 = tabIndexMap.next(tabStop0.id)!
        #expect(result2.id == tabStop2.id)
    }

    final class TabStopMapTest {
        var tabMap: TabStopMap
        let focusMap: FocusMap
        var expected: [(expected: Int, id: FocusId)]

        init() {
            self.tabMap = TabStopMap()
            self.focusMap = FocusMap()
            self.expected = []
        }

        func tabNonStop(_ index: Int) -> Self {
            let handle = FocusHandle(handles: focusMap)
                .tabStop(false)
                .tabIndex(index)
            tabMap.insert(handle)
            return self
        }

        func tabStop(_ index: Int, _ expectedOrder: Int) -> Self {
            let handle = FocusHandle(handles: focusMap)
                .tabStop(true)
                .tabIndex(index)
            tabMap.insert(handle)
            expected.append((expected: expectedOrder, id: handle.id))
            expected.sort { $0.expected < $1.expected }
            return self
        }

        func tabGroup(_ tabIndex: Int, _ children: (TabStopMapTest) -> TabStopMapTest) -> TabStopMapTest {
            tabMap.beginGroup(tabIndex)
            let result = children(self)
            result.tabMap.endGroup()
            return result
        }

        func traverseTabMap(_ traverse: (TabStopMap, FocusId?) -> FocusHandle?) -> [FocusId] {
            var lastFocusId: FocusId? = nil
            var found: [FocusId] = []
            for _ in 0..<expected.count {
                guard let handle = traverse(tabMap, lastFocusId) else { break }
                lastFocusId = handle.id
                found.append(handle.id)
            }
            return found
        }

        func assertMatches() {
            var expectedIds = expected.map(\.id)

            // Check next order
            let forwardFound = traverseTabMap { tabMap, prev in tabMap.next(prev) }
            #expect(forwardFound == expectedIds)

            // Test overflow. Last to first
            if let last = forwardFound.last {
                #expect(tabMap.next(last)?.id == expectedIds.first)
            }

            // Check previous order
            let reversedFound = traverseTabMap { tabMap, prev in tabMap.prev(prev) }
            expectedIds.reverse()
            #expect(reversedFound == expectedIds)

            // Test overflow. First to last
            if let last = reversedFound.last {
                #expect(tabMap.prev(last)?.id == expectedIds.first)
            }
        }
    }

    @Test("With disabled tab stop")
    func testWithDisabledTabStop() {
        TabStopMapTest()
            .tabStop(0, 0)
            .tabNonStop(1)
            .tabStop(2, 1)
            .tabStop(3, 2)
            .assertMatches()
    }

    @Test("With multiple disabled tab stops")
    func testWithMultipleDisabledTabStops() {
        TabStopMapTest()
            .tabNonStop(0)
            .tabStop(1, 0)
            .tabNonStop(3)
            .tabStop(3, 1)
            .tabNonStop(4)
            .assertMatches()
    }

    @Test("Tab group functionality")
    func testTabGroupFunctionality() {
        TabStopMapTest()
            .tabStop(0, 0)
            .tabStop(0, 1)
            .tabGroup(2) { t in t.tabStop(0, 2).tabStop(1, 3) }
            .tabStop(3, 4)
            .tabStop(4, 5)
            .assertMatches()
    }

    @Test("Sibling groups")
    func testSiblingGroups() {
        TabStopMapTest()
            .tabStop(0, 0)
            .tabStop(1, 1)
            .tabGroup(2) { test in test.tabStop(0, 2).tabStop(1, 3) }
            .tabStop(3, 4)
            .tabStop(4, 5)
            .tabGroup(6) { test in test.tabStop(0, 6).tabStop(1, 7) }
            .tabStop(7, 8)
            .tabStop(8, 9)
            .assertMatches()
    }

    @Test("Nested group")
    func testNestedGroup() {
        TabStopMapTest()
            .tabStop(0, 0)
            .tabStop(1, 1)
            .tabGroup(2) { t in
                t.tabGroup(0) { t2 in t2.tabStop(0, 2).tabStop(1, 3) }
                    .tabStop(1, 4)
            }
            .tabStop(3, 5)
            .tabStop(4, 6)
            .assertMatches()
    }

    @Test("Sibling nested groups")
    func testSiblingNestedGroups() {
        TabStopMapTest()
            .tabStop(0, 0)
            .tabStop(1, 1)
            .tabGroup(2) { builder in
                builder
                    .tabStop(0, 2)
                    .tabStop(2, 5)
                    .tabGroup(1) { b in b.tabStop(0, 3).tabStop(1, 4) }
                    .tabGroup(3) { b in b.tabStop(0, 6).tabStop(1, 7) }
            }
            .tabStop(3, 8)
            .tabStop(4, 9)
            .assertMatches()
    }

    @Test("Sibling nested groups out of order")
    func testSiblingNestedGroupsOutOfOrder() {
        TabStopMapTest()
            .tabStop(9, 9)
            .tabStop(8, 8)
            .tabGroup(7) { builder in
                builder
                    .tabStop(0, 2)
                    .tabStop(2, 5)
                    .tabGroup(3) { b in b.tabStop(1, 7).tabStop(0, 6) }
                    .tabGroup(1) { b in b.tabStop(0, 3).tabStop(1, 4) }
            }
            .tabStop(3, 0)
            .tabStop(4, 1)
            .assertMatches()
    }
}
