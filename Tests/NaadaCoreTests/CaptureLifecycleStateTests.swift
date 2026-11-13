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
        XCTAssertEqual(state.phase, .waitingForAudio)
        XCTAssertTrue(state.isCaptureActive)
        XCTAssertTrue(state.isWaitingForAudio)
        XCTAssertFalse(state.isReceivingAudio)
        XCTAssertFalse(state.hasReceivedAudio)
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
        XCTAssertFalse(state.hasReceivedAudio)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(
            state.beginStart(),
            "le moteur doit être réutilisable après un arrêt complet"
        )
    }

    func testFirstBufferMovesWaitingToReceiving() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.beginStart())
        state.markCaptureStarted()
        XCTAssertEqual(state.phase, .waitingForAudio)

        state.markFirstBufferReceived()
        XCTAssertEqual(state.phase, .receiving)
        XCTAssertTrue(state.isReceivingAudio)
        XCTAssertTrue(state.isCaptureActive)
        XCTAssertTrue(state.hasReceivedAudio)

        // Un deuxième buffer ne change rien et ne rejoue aucune transition.
        state.markFirstBufferReceived()
        XCTAssertEqual(state.phase, .receiving)
    }

    func testFirstBufferDuringStartingIsNotLost() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.beginStart())

        // L'IOProc peut livrer avant que markCaptureStarted() ne s'exécute.
        state.markFirstBufferReceived()
        XCTAssertEqual(state.phase, .starting)
        XCTAssertTrue(state.hasReceivedAudio)

        state.markCaptureStarted()
        XCTAssertEqual(
            state.phase,
            .receiving,
            "un buffer déjà reçu doit établir la réception au démarrage"
        )
    }

    func testFirstBufferAfterStopIsIgnored() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.beginStart())
        state.markCaptureStarted()
        XCTAssertTrue(state.beginStop())

        state.markFirstBufferReceived()
        XCTAssertEqual(state.phase, .stopping)
        XCTAssertFalse(state.hasReceivedAudio)
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
            XCTAssertTrue(
                state.isWaitingForAudio,
                "cycle \(cycle) : un démarrage sans buffer ne doit pas être pris pour une réception"
            )
            XCTAssertTrue(
                state.beginStop(),
                "cycle \(cycle) : l'arrêt doit rester possible en attente"
            )
            state.finishTeardown()
            XCTAssertTrue(state.canStart, "cycle \(cycle) : moteur non réutilisable")
            XCTAssertFalse(state.hasReceivedAudio)
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

    func testTeardownResetsReceivingForTheNextCycle() {
        var state = CaptureLifecycleState()
        XCTAssertTrue(state.beginStart())
        state.markCaptureStarted()
        state.markFirstBufferReceived()
        XCTAssertEqual(state.phase, .receiving)

        XCTAssertTrue(state.beginStop())
        state.finishTeardown()
        XCTAssertFalse(state.hasReceivedAudio)

        XCTAssertTrue(state.beginStart())
        state.markCaptureStarted()
        XCTAssertEqual(
            state.phase,
            .waitingForAudio,
            "la réception du cycle précédent ne doit pas fuiter"
        )
    }
}
