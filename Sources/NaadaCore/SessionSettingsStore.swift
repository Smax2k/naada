import Foundation

public struct SessionSettings: Equatable, Sendable {
    public var rememberedSource: RememberedSource?
    public var microphone: MicrophoneChoice
    public var title: String

    public init(
        rememberedSource: RememberedSource? = nil,
        microphone: MicrophoneChoice = .none,
        title: String = ""
    ) {
        self.rememberedSource = rememberedSource
        self.microphone = microphone
        self.title = title
    }
}

/// Persiste la source, le microphone et le titre de la dernière session.
///
/// Trois clés nouvelles et distinctes sont utilisées. La clé historique du
/// dossier de sortie (`naada.outputFolderPath`) n'est ni lue, ni réécrite, ni
/// migrée ici : une installation existante garde son dossier tel quel.
public final class SessionSettingsStore {
    public static let rememberedSourceKey = "naada.rememberedSource"
    public static let rememberedMicrophoneKey = "naada.rememberedMicrophone"
    public static let sessionTitleKey = "naada.sessionTitle"
    public static let outputFolderPathKey = "naada.outputFolderPath"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var rememberedSource: RememberedSource? {
        get {
            guard let data = defaults.data(forKey: Self.rememberedSourceKey) else {
                return nil
            }
            return try? JSONDecoder().decode(RememberedSource.self, from: data)
        }
        set {
            guard let source = newValue else {
                defaults.removeObject(forKey: Self.rememberedSourceKey)
                return
            }
            guard let data = try? JSONEncoder().encode(source) else { return }
            defaults.set(data, forKey: Self.rememberedSourceKey)
        }
    }

    /// Choix de microphone mémorisé. La valeur « aucun » efface la clé : une
    /// installation sans microphone choisi n'écrit rien.
    public var rememberedMicrophone: MicrophoneChoice {
        get {
            guard let data = defaults.data(forKey: Self.rememberedMicrophoneKey) else {
                return .none
            }
            return (try? JSONDecoder().decode(MicrophoneChoice.self, from: data)) ?? .none
        }
        set {
            guard newValue != .none else {
                defaults.removeObject(forKey: Self.rememberedMicrophoneKey)
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.rememberedMicrophoneKey)
        }
    }

    public var sessionTitle: String {
        get {
            defaults.string(forKey: Self.sessionTitleKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: Self.sessionTitleKey)
            } else {
                defaults.set(newValue, forKey: Self.sessionTitleKey)
            }
        }
    }

    /// Relit l'état depuis le disque, comme le ferait une nouvelle instance
    /// de l'application. Aucune écriture n'est faite ici.
    public func restore() -> SessionSettings {
        SessionSettings(
            rememberedSource: rememberedSource,
            microphone: rememberedMicrophone,
            title: sessionTitle
        )
    }
}
