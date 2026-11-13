import Foundation

/// États pures du cycle de vie du moteur de capture, sans Core Audio.
///
/// Le moteur ne repasse à `.idle` qu'après la libération effective des
/// ressources et le drainage du writer. Un démarrage suivant n'est donc
/// possible qu'une fois le teardown terminé, jamais pendant.
///
/// Un démarrage matériel réussi ne prouve pas que des échantillons arrivent :
/// l'état reste `.waitingForAudio` tant qu'aucun buffer non vide n'a été reçu.
/// Seul un vrai buffer fait passer à `.receiving`. Un buffer de silence
/// numérique reste un buffer reçu : la jauge affiche 0, mais la capture est
/// établie. L'arrêt reste possible dans les deux états.
public struct CaptureLifecycleState: Equatable {
    public enum Phase: String, Equatable {
        case idle
        case starting
        case waitingForAudio
        case receiving
        case stopping
    }

    public private(set) var phase: Phase
    /// Vrai dès qu'un buffer non vide a été reçu, même avant la fin du
    /// démarrage. Ce drapeau évite de perdre le premier buffer si l'IOProc
    /// appelle avant que `markCaptureStarted()` n'ait posé l'état d'attente.
    public private(set) var hasReceivedAudio: Bool

    public init(phase: Phase = .idle, hasReceivedAudio: Bool = false) {
        self.phase = phase
        self.hasReceivedAudio = hasReceivedAudio
    }

    /// Un démarrage n'est possible que depuis l'état idle.
    public var canStart: Bool { phase == .idle }

    public var isStarting: Bool { phase == .starting }

    public var isStopping: Bool { phase == .stopping }

    /// La capture matérielle est active dès la fin du démarrage, même si
    /// aucun échantillon n'est encore arrivé. Cela permet d'arrêter une
    /// capture en attente sans attendre un premier buffer.
    public var isCaptureActive: Bool {
        phase == .waitingForAudio || phase == .receiving
    }

    /// Le moteur attend le premier buffer non vide.
    public var isWaitingForAudio: Bool { phase == .waitingForAudio }

    /// Au moins un buffer non vide a été reçu pendant cette capture.
    public var isReceivingAudio: Bool { phase == .receiving }

    /// Réserve un démarrage. Refuse si un cycle est déjà en cours.
    @discardableResult
    public mutating func beginStart() -> Bool {
        guard phase == .idle else { return false }
        phase = .starting
        hasReceivedAudio = false
        return true
    }

    /// Le démarrage matériel a réussi. Sans buffer déjà reçu, la capture
    /// reste en attente ; avec un buffer reçu pendant `.starting`, elle est
    /// immédiatement en réception.
    public mutating func markCaptureStarted() {
        guard phase == .starting else { return }
        phase = hasReceivedAudio ? .receiving : .waitingForAudio
    }

    /// Signale le premier buffer non vide. Idempotent. Ignoré hors démarrage
    /// et capture active, et jamais transmis à un cycle suivant.
    public mutating func markFirstBufferReceived() {
        guard phase == .starting || phase == .waitingForAudio || phase == .receiving else {
            return
        }
        hasReceivedAudio = true
        if phase == .waitingForAudio {
            phase = .receiving
        }
    }

    /// Réserve l'arrêt. Accepté en attente comme en réception.
    @discardableResult
    public mutating func beginStop() -> Bool {
        guard isCaptureActive else { return false }
        phase = .stopping
        return true
    }

    /// À appeler seulement après libération des ressources et drainage du
    /// writer : remet le moteur dans l'état réutilisable.
    public mutating func finishTeardown() {
        phase = .idle
        hasReceivedAudio = false
    }
}
