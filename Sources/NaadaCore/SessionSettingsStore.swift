import Foundation

public struct SessionSettings: Equatable, Sendable {
    public var rememberedSource: RememberedSource?
    public var title: String

    public init(rememberedSource: RememberedSource? = nil, title: String = "") {
        self.rememberedSource = rememberedSource
        self.title = title
    }
}

/// Persiste la source et le titre de la dernière session.
///
/// Deux clés nouvelles et distinctes sont utilisées. La clé historique du
/// dossier de sortie (`naada.outputFolderPath`) n'est ni lue, ni réécrite, ni
/// migrée ici : une installation existante garde son dossier tel quel.
public final class SessionSettingsStore {
    public static let rememberedSourceKey = "naada.rememberedSource"
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
    /// de l'application.
    public func restore() -> SessionSettings {
        SessionSettings(rememberedSource: rememberedSource, title: sessionTitle)
    }
}
