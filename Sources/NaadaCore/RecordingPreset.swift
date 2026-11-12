import Foundation

/// Configuration nommée d'une session : source durable, titre et dossier.
///
/// La source est une identité `RememberedSource` (bundle + nom), jamais un
/// PID : un preset retrouve la même application après un redémarrage, et
/// reste applicable lorsqu'elle est fermée.
public struct RecordingPreset: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var source: RememberedSource
    public var title: String
    public var folderPath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        source: RememberedSource,
        title: String,
        folderPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.title = title
        self.folderPath = folderPath
    }

    /// Les trois réglages visibles auxquels un preset s'applique.
    public var configuration: RecordingConfiguration {
        RecordingConfiguration(
            source: source,
            title: title,
            folderPath: folderPath
        )
    }

    /// Applique le preset à une configuration existante.
    ///
    /// La source et le titre sont toujours remplacés. Le dossier n'est
    /// remplacé que si le preset en porte un : un preset sans dossier ne doit
    /// jamais effacer le dossier choisi hors du preset.
    public func applied(to current: RecordingConfiguration) -> RecordingConfiguration {
        var result = current
        result.source = source
        result.title = title
        if let folderPath, !folderPath.isEmpty {
            result.folderPath = folderPath
        }
        return result
    }
}

/// Réglages courants d'une session, indépendants de l'interface.
public struct RecordingConfiguration: Equatable, Sendable {
    public var source: RememberedSource?
    public var title: String
    public var folderPath: String?

    public init(
        source: RememberedSource? = nil,
        title: String = "",
        folderPath: String? = nil
    ) {
        self.source = source
        self.title = title
        self.folderPath = folderPath
    }
}

/// Persiste les presets nommés dans une clé propre.
///
/// La clé historique `naada.outputFolderPath` reste la propriété du dossier de
/// sortie courant : ce magasin ne la lit ni ne la réécrit. Une première
/// utilisation, avec une liste vide, n'écrit rien et ne remplace donc aucun
/// réglage existant.
public final class RecordingPresetStore {
    public static let presetsKey = "naada.recordingPresets"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Liste enregistrée, ou liste vide si aucune donnée lisible n'existe.
    /// Aucune écriture n'est faite ici.
    public func load() -> [RecordingPreset] {
        guard let data = defaults.data(forKey: Self.presetsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([RecordingPreset].self, from: data)) ?? []
    }

    /// Crée un preset nommé à partir des réglages fournis.
    /// Un nom vide (ou uniquement des espaces) est refusé.
    @discardableResult
    public func create(
        name: String,
        source: RememberedSource,
        title: String,
        folderPath: String?
    ) -> RecordingPreset? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        var presets = load()
        let preset = RecordingPreset(
            name: trimmedName,
            source: source,
            title: title,
            folderPath: normalizedFolder(folderPath)
        )
        presets.append(preset)
        persist(presets)
        return preset
    }

    /// Remplace les champs d'un preset existant, en conservant son identifiant.
    @discardableResult
    public func update(_ preset: RecordingPreset) -> RecordingPreset? {
        var presets = load()
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            return nil
        }

        var updated = preset
        updated.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return nil }
        updated.folderPath = normalizedFolder(preset.folderPath)

        presets[index] = updated
        persist(presets)
        return updated
    }

    /// Renomme uniquement le preset désigné.
    @discardableResult
    public func rename(id: UUID, to name: String) -> RecordingPreset? {
        var presets = load()
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        presets[index].name = trimmedName
        persist(presets)
        return presets[index]
    }

    /// Supprime le preset désigné, sans toucher aux autres réglages.
    @discardableResult
    public func delete(id: UUID) -> Bool {
        var presets = load()
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            return false
        }

        presets.remove(at: index)
        persist(presets)
        return true
    }

    private func normalizedFolder(_ folderPath: String?) -> String? {
        guard let folderPath, !folderPath.isEmpty else { return nil }
        return folderPath
    }

    private func persist(_ presets: [RecordingPreset]) {
        guard !presets.isEmpty else {
            defaults.removeObject(forKey: Self.presetsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Self.presetsKey)
    }
}
