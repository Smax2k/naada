import Foundation

public enum RecordingSessionState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case stopping
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .preparing, .recording, .stopping:
            return true
        case .idle, .failed:
            return false
        }
    }

    public var isRecording: Bool {
        self == .recording
    }
}

/// Machine d'état pure d'une session. Elle ne connaît ni le moteur audio ni
/// le système de fichiers : elle peut donc être testée sans capture réelle.
public struct RecordingSession: Equatable, Sendable {
    public private(set) var state: RecordingSessionState
    public private(set) var clock: RecordingClock
    public private(set) var failure: String?

    public init(
        state: RecordingSessionState = .idle,
        clock: RecordingClock = RecordingClock(),
        failure: String? = nil
    ) {
        self.state = state
        self.clock = clock
        self.failure = failure
    }

    public mutating func beginPreparation(at now: TimeInterval) {
        guard !state.isBusy else { return }
        clock.reset()
        failure = nil
        state = .preparing
    }

    public mutating func captureStarted(at now: TimeInterval) {
        guard state == .preparing else { return }
        clock.start(at: now)
        state = .recording
    }

    public mutating func stopRequested(at now: TimeInterval) {
        guard state == .recording else { return }
        clock.stop(at: now)
        state = .stopping
    }

    public mutating func finalized() {
        guard state == .stopping else { return }
        state = .idle
    }

    public mutating func fail(_ message: String, at now: TimeInterval) {
        if clock.isRunning {
            clock.stop(at: now)
        }
        failure = message
        state = .failed(message)
    }

    public func elapsed(at now: TimeInterval) -> TimeInterval {
        clock.elapsed(at: now)
    }
}
