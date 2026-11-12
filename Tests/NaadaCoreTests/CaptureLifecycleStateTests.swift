import XCTest
@testable import NaadaCore

final class CaptureLifecycleStateTests: XCTestCase {
    func testNormalStopReturnsToIdleOnlyAfterTeardown() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.beginStart())
        XCTAssertEqual(state.phase, .starting)
        XCTAssertTrue(state.isStarting)
        XCTAssertFalse(state.canStart)
        XCTAssertFalse(state.isCaptureActive)

        state.markCaptureStarted()
        XCTAssertEqual(state.phase, .capturing)
        XCTAssertTrue(state.isCaptureActive)
        XCTAssertFalse(state.canStart)

        XCTAssertTrue(state.beginStop())
        XCTAssertEqual(state.phase, .stopping)
        XCTAssertTrue(state.isStopping)
        XCTAssertFalse(state.isCaptureActive)
        XCTAssertFalse(state.canStart)
        XCTAssertFalse(
            state.beginStart(),
            "un second démarrage doit attendre la fin du teardown"
        )

        state.finishTeardown()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.isStopping)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(
            state.beginStart(),
            "le moteur doit être réutilisable après un arrêt complet"
        )
    }

    func testFailedStartIsRetryableOnlyAfterTeardown() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.beginStart())

        XCTAssertFalse(
            state.beginStart(),
            "un échec en cours de démarrage ne doit pas permettre un second départ"
        )
        XCTAssertEqual(state.phase, .starting)

        state.finishTeardown()
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.beginStart())
    }

    func testUnsupportedSystemFailureDoesNotLeaveTheLifecycleStuck() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.beginStart())

        // Le chemin 14.0–14.1 échoue avant toute ressource : le teardown doit
        // tout de même remettre l'automate à idle.
        state.finishTeardown()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.canStart)
    }

    func testRepeatedNoAudioCyclesRemainStartable() {
        var state = CaptureLifecycleState()

        for cycle in 1...5 {
            XCTAssertTrue(state.beginStart(), "cycle \(cycle) : démarrage refusé")
            state.markCaptureStarted()
            XCTAssertTrue(state.beginStop(), "cycle \(cycle) : arrêt refusé")
            state.finishTeardown()
            XCTAssertTrue(state.canStart, "cycle \(cycle) : moteur non réutilisable")
        }
    }

    func testBeginStopRequiresAnActiveCapture() {
        var state = CaptureLifecycleState()
        XCTAssertFalse(state.beginStop())
        XCTAssertEqual(state.phase, .idle)

        XCTAssertTrue(state.beginStart())
        XCTAssertFalse(state.beginStop())
        XCTAssertEqual(state.phase, .starting)

        state.markCaptureStarted()
        XCTAssertTrue(state.beginStop())
        XCTAssertFalse(state.beginStop(), "un second arrêt ne doit pas être accepté")
        XCTAssertEqual(state.phase, .stopping)
    }

    func testCaptureStartedIsIgnoredOutsideStarting() {
        var state = CaptureLifecycleState()
        state.markCaptureStarted()
        XCTAssertEqual(state.phase, .idle)

        XCTAssertTrue(state.beginStart())
        XCTAssertTrue(state.beginStop() == false)
        state.finishTeardown()
        state.markCaptureStarted()
        XCTAssertEqual(state.phase, .idle)
    }
}
