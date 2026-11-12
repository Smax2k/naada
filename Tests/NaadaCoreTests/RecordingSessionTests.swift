import Foundation
import XCTest
@testable import NaadaCore

final class RecordingSessionTests: XCTestCase {
    func testMockCaptureStartThenStopEndsIdleWithFrozenElapsed() {
        var session = RecordingSession()

        session.beginPreparation(at: 100)
        XCTAssertEqual(session.state, .preparing)

        session.captureStarted(at: 101)
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.elapsed(at: 106), 5, accuracy: 0.0001)

        session.stopRequested(at: 111)
        XCTAssertEqual(session.state, .stopping)
        XCTAssertFalse(session.clock.isRunning)
        XCTAssertEqual(session.elapsed(at: 500), 10, accuracy: 0.0001)

        session.finalized()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.elapsed(at: 9_999), 10, accuracy: 0.0001)
    }

    func testFailureFreezesElapsedAndKeepsMessage() {
        var session = RecordingSession()
        session.beginPreparation(at: 10)
        session.captureStarted(at: 11)
        session.fail("source disparue", at: 16)

        XCTAssertEqual(session.state, .failed("source disparue"))
        XCTAssertEqual(session.failure, "source disparue")
        XCTAssertEqual(session.elapsed(at: 100), 5, accuracy: 0.0001)
    }

    func testCaptureStartedCannotOverwriteStartupFailure() {
        var session = RecordingSession()
        session.beginPreparation(at: 10)
        session.fail("arrêt pendant le démarrage", at: 11)

        session.captureStarted(at: 12)

        XCTAssertEqual(session.state, .failed("arrêt pendant le démarrage"))
        XCTAssertEqual(session.elapsed(at: 100), 0, accuracy: 0.0001)
    }

    func testStaleTransitionsAreIgnored() {
        var session = RecordingSession()
        session.captureStarted(at: 5) // pas de préparation : ignoré
        XCTAssertEqual(session.state, .idle)

        session.beginPreparation(at: 10)
        session.stopRequested(at: 11) // pas encore enregistré : ignoré
        XCTAssertEqual(session.state, .preparing)

        session.captureStarted(at: 12)
        session.finalized() // pas en cours d'arrêt : ignoré
        XCTAssertEqual(session.state, .recording)
    }

    func testNewPreparationResetsThePreviousClockAndFailure() {
        var session = RecordingSession()
        session.beginPreparation(at: 0)
        session.captureStarted(at: 1)
        session.fail("erreur", at: 6)
        XCTAssertEqual(session.elapsed(at: 100), 5, accuracy: 0.0001)

        session.beginPreparation(at: 200)
        XCTAssertEqual(session.state, .preparing)
        XCTAssertNil(session.failure)
        XCTAssertEqual(session.elapsed(at: 300), 0, accuracy: 0.0001)
    }
}
