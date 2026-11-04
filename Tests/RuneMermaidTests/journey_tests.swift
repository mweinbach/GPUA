// Tests ported from: crates/rune-mermaid/src/journey_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct JourneyTests {
    private func parseJourney(_ src: String) -> journey.Journey {
        guard let parsed = RuneMermaid.parse(src), case .journey(let j) = parsed.diagram else {
            fatalError("not a journey: \(src)")
        }
        return j
    }

    @Test func sectionsTasksScoresAndActors() {
        let j = parseJourney(
            "journey\n    title My working day\n    section Go to work\n      Make tea: 5: Me\n      Go upstairs: 3: Me\n      Do work: 1: Me, Cat\n    section Go home\n      Go downstairs: 9: Cat\n      No score here\n      Bad: lots: Me\n      Sit down: 0"
        )
        #expect(j.title == "My working day")
        #expect(j.sections == ["Go to work", "Go home"])
        #expect(j.actors == ["Me", "Cat"])
        #expect(j.tasks == [
            journey.Task(name: "Make tea", score: 5.0, actors: [0], section: 0),
            journey.Task(name: "Go upstairs", score: 3.0, actors: [0], section: 0),
            journey.Task(name: "Do work", score: 1.0, actors: [0, 1], section: 0),
            journey.Task(name: "Go downstairs", score: 5.0, actors: [1], section: 1),
            journey.Task(name: "Sit down", score: 1.0, actors: [], section: 1),
        ])
        #expect(RuneMermaid.parse("journey\ntitle Empty\nsection A") == nil)
        let budget = "journey\n" + (0...MAX_ITEMS).map { "t\($0): 3: Me" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func drawsTasksSectionsAndActors() {
        let paint = DiagramStyle.neutral(false)
        let s = buildScene("journey\nsection Day\nGood: 5: Me\nBad: 1: Me", paint, nil)!
        let texts = s.labels.map { $0.text }
        for t in ["Day", "Good", "Bad", "Me"] {
            #expect(texts.contains(t))
        }
        #expect(journey.mood(5.0, paint).toOklab()[0] > 0.5 && journey.mood(1.0, paint).toOklab()[0] > 0.5)
    }
}
