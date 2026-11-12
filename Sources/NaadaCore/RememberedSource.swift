import Foundation

/// Identité stable de l'application source retenue entre deux lancements.
///
/// L'identité est le couple identifiant de bundle + nom de l'application.
/// Le PID est volontairement absent : il change à chaque lancement et ne
/// désigne jamais durablement la même source.
public struct RememberedSource: Hashable, Codable, Sendable {
    public let bundleIdentifier: String?
    public let name: String

    public init(bundleIdentifier: String?, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    /// Clé de sélection stable pour l'interface, indépendante du PID.
    public var stableIdentifier: String {
        let bundle = bundleIdentifier ?? ""
        return "\(bundle)\u{1F}\(name)"
    }

    /// Deux applications désignent la même source si leur identifiant de
    /// bundle et leur nom correspondent. Aucun PID n'entre dans ce test.
    public func matches(bundleIdentifier: String?, name: String) -> Bool {
        self.bundleIdentifier == bundleIdentifier && self.name == name
    }
}

/// Décision de titre prise lorsqu'une source est choisie, sans effet de bord.
///
/// Le titre restauré n'est jamais écrasé par une suggestion : seule une
/// saisie vide, ou un titre encore égal à la suggestion précédente, est
/// remplacée.
public enum SessionTitlePolicy {
    public static func suggestedTitle(
        currentTitle: String,
        lastSuggestedTitle: String,
        sourceName: String
    ) -> String? {
        let trimmed = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || currentTitle == lastSuggestedTitle {
            return sourceName
        }
        return nil
    }
}
