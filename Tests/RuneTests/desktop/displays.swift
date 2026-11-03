// Tests ported from: crates/rune/src/desktop/displays.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("DesktopDisplaysTests")
struct DesktopDisplaysTests {
    @Test("headless place resolves against the scripted desktop")
    func headlessPlaceResolvesAgainstTheScriptedDesktop() throws {
        let script: [String: Any] = [
            "displays": [
                ["id": 1, "frame": [0, 0, 1512, 982], "scale": 2, "primary": true],
                ["id": 7, "frame": [1512, -100, 1920, 1080], "scale": 1],
            ],
            "pointer": [2000, 300],
            "events": [Any](),
        ]
        let desktop = try VirtualDesktop.fromScript(script, 2.0).get()
        let top = OverlayPlacement.edge(edge: .top, margin: 160.0, align: .center, inset: 0.0)
        func req(_ display: DisplayTarget) -> PlaceRequest {
            PlaceRequest(display: display, placement: top)
        }
        let pPrimary = desktop.place(req(.primary), (600.0, 80.0))
        #expect(pPrimary.0 == 1 && pPrimary.1 == [456.0, 160.0, 600.0, 80.0])

        let pUnder = desktop.place(req(.underPointer), (600.0, 80.0))
        #expect(pUnder.0 == 7 && pUnder.1 == [2172.0, 60.0, 600.0, 80.0])

        #expect(desktop.place(req(.native(.macOS(7))), (600.0, 80.0)).0 == 7)
        #expect(desktop.place(req(.native(.macOS(9))), (600.0, 80.0)).0 == 1)

        let full = PlaceRequest.new(.native(.macOS(7)), .fullScreen)
        let pFull = desktop.place(full, (600.0, 80.0))
        #expect(pFull.0 == 7 && pFull.1 == [1512.0, -100.0, 1920.0, 1080.0])
        #expect(desktop.publicDisplays()[1].position == (1512, -100))
        #expect(desktop.publicDisplays()[0].size == (3024, 1964))

        let def = try VirtualDesktop.fromScript(nil, 2.0).get()
        #expect(
            def.publicDisplays() == [
                Display(
                    id: nil,
                    name: "headless",
                    position: (0, 0),
                    size: (1920, 1080),
                    scale: 2.0,
                    primary: true
                )
            ]
        )
        if case .success = VirtualDesktop.fromScript(["displays": [["frame": [0, 0]]]], 2.0) {
            Issue.record("expected invalid frame error")
        }
        if case .success = VirtualDesktop.fromScript(["displays": [["frame": [0, 0, 10, 10], "scale": 0]]], 2.0) {
            Issue.record("expected invalid scale error")
        }
    }

    @Test("positions on mixed scale displays convert by the display they land on")
    func positionsOnMixedScaleDisplaysConvertByTheDisplayTheyLandOn() throws {
        let script1: [String: Any] = [
            "displays": [
                ["id": 1, "frame": [0, 0, 1512, 982], "scale": 2, "primary": true],
                ["id": 2, "frame": [1512, 0, 1920, 1080], "scale": 1],
            ]
        ]
        let d1 = try VirtualDesktop.fromScript(script1, 2.0).get()
        func on1(_ p: (Int32, Int32)) -> (UInt32, (Float, Float)) {
            (d1.virtualDisplayAt(p).numericId, d1.toPoints(p))
        }
        #expect(on1((200, 100)).0 == 1 && on1((200, 100)).1 == (100.0, 50.0))
        #expect(on1((1300, 1800)).0 == 1 && on1((1300, 1800)).1 == (650.0, 900.0))
        let monPos = d1.publicDisplays()[1].position
        #expect(on1(monPos).0 == 2 && on1(monPos).1 == (1512.0, 0.0))
        #expect(on1((1612, 100)).0 == 2 && on1((1612, 100)).1 == (1612.0, 100.0))
        #expect(on1((-50, 0)).0 == 1)

        #expect(d1.openAt(nil, (400.0, 300.0)) == [556.0, 341.0, 400.0, 300.0])
        #expect(d1.openAt((1612, 100), (400.0, 300.0)) == [1612.0, 100.0, 400.0, 300.0])

        let script2: [String: Any] = [
            "displays": [
                ["id": 1, "frame": [0, 0, 1920, 1080], "scale": 1, "primary": true],
                ["id": 2, "frame": [1920, 0, 1512, 982], "scale": 2],
            ]
        ]
        let d2 = try VirtualDesktop.fromScript(script2, 2.0).get()
        #expect(d2.virtualDisplayAt((3840 + 200, 1500)).numericId == 2)
        #expect(d2.toPoints((3840 + 200, 1500)) == (2020.0, 750.0))
        #expect(d2.virtualDisplayAt((100, 100)).numericId == 1)
        #expect(d2.toPoints((100, 100)) == (100.0, 100.0))
    }
}
