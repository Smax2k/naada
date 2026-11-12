import Foundation

/// États pures du cycle de vie du moteur de capture, sans Core Audio.
///
/// Le moteur ne repasse à `.idle` qu'après la libération effective des
/// ressources et le drainage du writer. Un démarrage suivant n'est donc
/// possible qu'une fois le teardown terminé, jamais pendant.
public struct CaptureLifecycleState: Equatable {
    public enum Phase: String, Equatable {
        case idle
        case starting
        case capturing
        case stopping
    }

    public private(set) var phase: Phase

    public init(phase: Phase = .idle) {
        self.phase = phase
    }

    /// Un démarrage n'est possible que depuis l'état idle.
    public var canStart: Bool { phase == .idle }

    public var isStarting: Bool { phase == .starting }

    public var isStopping: Bool { phase == .stopping }

    /// La capture n'est active qu'une fois le démarrage matériel stabilisé.
    public var isCaptureActive: Bool { phase == .capturing }

    /// Réserve un démarrage. Refuse si un cycle est déjà en cours.
    @discardableResult
    public mutating func beginStart() -> Bool {
        guard phase == .idle else { return false }
        phase = .starting
        return true
    }

    /// Le démarrage matériel a réussi et la capture est stable.
    public mutating func markCaptureStarted() {
        guard phase == .starting else { return }
        phase = .capturing
    }

    /// Réserve l'arrêt. Refuse si aucune capture n'est active.
    @discardableResult
    public mutating func beginStop() -> Bool {
        guard phase == .capturing else { return false }
        phase = .stopping
        return true
    }

    /// À appeler seulement après libération des ressources et drainage du
    /// writer : remet le moteur dans l'état réutilisable.
    public mutating func finishTeardown() {
        phase = .idle
    }
}
