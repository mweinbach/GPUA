// Tests ported from: crates/gpui/src/test.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
@testable import GPUI

@Suite("TestModuleTests")
struct TestModuleTests {
    @Test("calculateSeeds generates correct default single seed")
    func testCalculateSeedsDefault() {
        let (seeds, isMultiple) = calculateSeeds(iterations: 1, explicitSeeds: [])
        #expect(seeds == [0])
        #expect(!isMultiple)
    }

    @Test("calculateSeeds generates multiple seeds for iterations > 1")
    func testCalculateSeedsMultiple() {
        let (seeds, isMultiple) = calculateSeeds(iterations: 3, explicitSeeds: [])
        #expect(seeds == [0, 1, 2])
        #expect(isMultiple)
    }

    @Test("calculateSeeds appends explicit seeds")
    func testCalculateSeedsExplicit() {
        let (seeds, isMultiple) = calculateSeeds(iterations: 1, explicitSeeds: [100, 200])
        #expect(seeds == [100, 200])
        #expect(isMultiple)
    }

    @Test("runTestOnce runs test function")
    func testRunTestOnce() {
        var didRun = false
        runTestOnce(seed: 42) { dispatcher in
            didRun = true
        }
        #expect(didRun)
    }

    @Test("runTest runs for configured iterations")
    func testRunTestIterations() {
        var seedsRan: [UInt64] = []
        runTest(numIterations: 3) { dispatcher, seed in
            seedsRan.append(seed)
        }
        #expect(seedsRan == [0, 1, 2])
    }

    @Test("Observation async iteration receives items")
    func testObservation() async {
        let obs = Observation<Int>()
        obs.push(1)
        obs.push(2)
        obs.finish()

        var received: [Int] = []
        for await item in obs {
            received.append(item)
        }
        #expect(received == [1, 2])
    }

    @Test("GPUITestTrait configuration")
    func testGPUITestTrait() {
        let trait = GPUITestTrait(iterations: 5, seed: 1234, maxRetries: 2)
        #expect(trait.config.iterations == 5)
        #expect(trait.config.seed == 1234)
        #expect(trait.config.maxRetries == 2)
    }
}
