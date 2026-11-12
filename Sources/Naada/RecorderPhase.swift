import Foundation
import NaadaCore

enum RecorderPhase: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case failed(String)

    init(_ state: RecordingSessionState) {
        switch state {
        case .idle:
            self = .idle
        case .preparing:
            self = .preparing
        case .recording:
            self = .recording
        case .stopping:
            self = .stopping
        case let .failed(message):
            self = .failed(message)
        }
    }

    var isBusy: Bool {
        switch self {
        case .preparing, .recording, .stopping:
            return true
        case .idle, .failed:
            return false
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle:
            return "Prêt"
        case .preparing:
            return "Préparation"
        case .recording:
            return "Enregistrement"
        case .stopping:
            return "Finalisation"
        case .failed:
            return "Erreur"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Choisissez une application et un dossier, puis démarrez."
        case .preparing:
            return "Connexion à la source audio…"
        case .recording:
            return "Le son système reste audible pendant la capture."
        case .stopping:
            return "Écriture de la dernière frame MP3…"
        case let .failed(message):
            return message
        }
    }
}
