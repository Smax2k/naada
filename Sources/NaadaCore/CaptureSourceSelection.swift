import Foundation

/// Choix du microphone, indépendant de Core Audio.
///
/// L'identité d'un micro précis est son UID Core Audio : une chaîne stable
/// entre deux lancements. Un `AudioObjectID` n'est jamais conservé, car il
/// peut être réattribué après un rebranchement.
public enum MicrophoneChoice: Hashable, Codable, Sendable {
    /// Aucun microphone : seule l'application choisie est capturée.
    case none
    /// Microphone d'entrée système, celui que macOS considère par défaut.
    case systemDefault
    /// Microphone désigné par son UID Core Audio et son nom affichable.
    case selected(uid: String, name: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case uid
        case name
    }

    private enum Kind: String, Codable {
        case none
        case systemDefault
        case selected
    }

    /// Décodage tolérant : une valeur absente ou illisible vaut « aucun ».
    /// Un preset écrit avant l'ajout du microphone reste donc lisible.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .none

        switch kind {
        case .none:
            self = .none
        case .systemDefault:
            self = .systemDefault
        case .selected:
            let uid = (try? container.decodeIfPresent(String.self, forKey: .uid)) ?? ""
            let name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
            // Un micro précis sans UID n'est pas identifiable : il vaut aucun,
            // plutôt que de désigner un périphérique au hasard.
            self = uid.isEmpty ? .none : .selected(uid: uid, name: name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .systemDefault:
            try container.encode(Kind.systemDefault, forKey: .kind)
        case .selected(let uid, let name):
            try container.encode(Kind.selected, forKey: .kind)
            try container.encode(uid, forKey: .uid)
            try container.encode(name, forKey: .name)
        }
    }
}

/// Résultat explicite de la porte de démarrage d'une capture.
///
/// Un refus est toujours nommé : l'appelant peut l'expliquer sans replier
/// silencieusement sur l'autre source.
public enum CaptureStartDecision: Equatable, Sendable {
    /// Les sources choisies sont disponibles et le dossier de sortie est fixé.
    case allowed
    /// Ni application ni microphone ne sont choisis.
    case noSourceSelected
    /// L'application choisie n'est pas disponible.
    case applicationUnavailable(RememberedSource)
    /// Le microphone choisi n'est pas disponible.
    case microphoneUnavailable(MicrophoneChoice)
    /// Aucun dossier de sortie exploitable n'est choisi.
    case outputFolderMissing
}

/// Sources d'une capture : une application, un microphone, ou les deux.
///
/// Aucun accès matériel n'est fait ici. La disponibilité de chaque source est
/// fournie par l'appelant, qui seul sait interroger le système.
public struct CaptureSourceSelection: Equatable, Sendable {
    public var application: RememberedSource?
    public var microphone: MicrophoneChoice

    public init(
        application: RememberedSource? = nil,
        microphone: MicrophoneChoice = .none
    ) {
        self.application = application
        self.microphone = microphone
    }

    /// Vrai dès qu'au moins une source est choisie.
    public var hasAnySource: Bool {
        application != nil || microphone != .none
    }

    /// Décide si la capture peut démarrer.
    ///
    /// La porte n'autorise que si au moins une source est choisie, si chaque
    /// source choisie est disponible et si un dossier de sortie non vide est
    /// fixé. Une source indisponible bloque tout : jamais de repli sur l'autre.
    ///
    /// - Parameters:
    ///   - outputFolderPath: dossier de sortie choisi ; vide ou absent = refus.
    ///   - isApplicationAvailable: disponibilité de l'application choisie.
    ///   - isMicrophoneAvailable: disponibilité du microphone choisi.
    public func startDecision(
        outputFolderPath: String?,
        isApplicationAvailable: (RememberedSource) -> Bool,
        isMicrophoneAvailable: (MicrophoneChoice) -> Bool
    ) -> CaptureStartDecision {
        guard hasAnySource else {
            return .noSourceSelected
        }

        if let application, !isApplicationAvailable(application) {
            return .applicationUnavailable(application)
        }

        if microphone != .none, !isMicrophoneAvailable(microphone) {
            return .microphoneUnavailable(microphone)
        }

        let folder = outputFolderPath?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !folder.isEmpty else {
            return .outputFolderMissing
        }

        return .allowed
    }
}
