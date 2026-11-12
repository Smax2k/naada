import Foundation

/// Horloge d'enregistrement volontairement simple : elle ne compte que pendant
/// la capture, et se fige dès l'arrêt. Aucune reprise implicite, aucune
/// estimation : la valeur affichée vient du temps réel écoulé.
public struct RecordingClock: Equatable, Sendable {
    public private(set) var accumulated: TimeInterval
    public private(set) var startedAt: TimeInterval?

    public init(accumulated: TimeInterval = 0, startedAt: TimeInterval? = nil) {
        self.accumulated = max(0, accumulated)
        self.startedAt = startedAt
    }

    public var isRunning: Bool {
        startedAt != nil
    }

    public mutating func start(at now: TimeInterval) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    @discardableResult
    public mutating func stop(at now: TimeInterval) -> TimeInterval {
        if let startedAt {
            accumulated += max(0, now - startedAt)
            self.startedAt = nil
        }
        return accumulated
    }

    public func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + max(0, now - startedAt)
    }

    public mutating func reset() {
        accumulated = 0
        startedAt = nil
    }
}

public enum ElapsedFormatter {
    /// `MM:SS` avant une heure, `H:MM:SS` ensuite. Les fractions sont
    /// tronquées : à 0,9 s on affiche encore 00:00.
    public static func string(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
