import Foundation
import XCTest
@testable import NaadaCore

final class PCMMixTests: XCTestCase {
    func testAddsSamplesWithoutGain() {
        let first: [Int16] = [1_000, -2_000, 300, 0]
        let second: [Int16] = [250, 500, -300, 0]

        XCTAssertEqual(PCMMix.mix(first, second), [1_250, -1_500, 0, 0])
    }

    func testSaturatesAtBothInt16Bounds() {
        let first: [Int16] = [32_767, -32_768, 30_000, -30_000]
        let second: [Int16] = [1, -1, 10_000, -10_000]

        XCTAssertEqual(PCMMix.mix(first, second), [32_767, -32_768, 32_767, -32_768])
    }

    func testMissingSideIsSilenceOfTheOtherLength() {
        let samples: [Int16] = [1, -2, 3, -4]

        XCTAssertEqual(PCMMix.mix(nil, samples), samples)
        XCTAssertEqual(PCMMix.mix(samples, nil), samples)
    }

    func testBothSidesMissingGivesEmptyBuffer() {
        XCTAssertEqual(PCMMix.mix(nil, nil), [])
    }

    func testEmptySideBehavesLikeSilence() {
        let samples: [Int16] = [5, -6]

        XCTAssertEqual(PCMMix.mix([], samples), samples)
        XCTAssertEqual(PCMMix.mix(samples, []), samples)
    }

    func testShorterSideIsTreatedAsTrailingSilence() {
        let first: [Int16] = [100, -100, 200]
        let second: [Int16] = [1]

        XCTAssertEqual(PCMMix.mix(first, second), [101, -100, 200])
        XCTAssertEqual(PCMMix.mix(second, first), [101, -100, 200])
    }

    func testStereoChannelsAreAddedInInterleavedOrder() {
        // Deux trames stéréo (gauche, droite) : chaque voie garde sa place.
        let first: [Int16] = [1_000, -1_000, 2_000, -2_000]
        let second: [Int16] = [500, -500, 1_000, -1_000]

        XCTAssertEqual(
            PCMMix.mix(first, second),
            [1_500, -1_500, 3_000, -3_000]
        )
    }
}
