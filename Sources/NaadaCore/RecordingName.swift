import Foundation

/// Construit le nom d'un enregistrement et garantit qu'aucun fichier existant
/// n'est écrasé.
///
/// Format demandé : `AAAA MM JJ <titre de session>.mp3`.
/// Les collisions deviennent `<base> (2).mp3`, `<base> (3).mp3`, etc.
public enum RecordingName {
    public static let fileExtension = "mp3"
    public static let maximumTitleLength = 120
    public static let maximumTitleUTF8Bytes = 180
    public static let fallbackTitle = "Session"

    /// Nettoie le titre saisi par la personne.
    ///
    /// Les caractères interdits par le format demandé (`/` et `:`) deviennent
    /// des tirets. Les sauts de ligne et caractères de contrôle deviennent des
    /// espaces, et les espaces consécutifs sont réduits à un seul.
    public static func sanitizedTitle(_ raw: String) -> String {
        var title = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        title = String(title.unicodeScalars.map { scalar -> Character in
            if CharacterSet.newlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) {
                return " "
            }
            return Character(scalar)
        })

        title = title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title == "." || title == ".." {
            title = fallbackTitle
        }

        if title.count > maximumTitleLength {
            title = String(title.prefix(maximumTitleLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // La limite du système de fichiers est exprimée en octets, pas en
        // caractères : un titre d'emoji peut dépasser 255 octets.
        while title.utf8.count > maximumTitleUTF8Bytes {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? fallbackTitle : title
    }

    /// Base commune au nom et aux suffixes de collision : `2026 11 12 Réunion`.
    public static func baseName(
        date: Date,
        title: String,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let stamp = String(format: "%04d %02d %02d", year, month, day)
        return "\(stamp) \(sanitizedTitle(title))"
    }

    /// Nom candidat pour une tentative donnée. `attempt == 1` n'ajoute aucun
    /// suffixe ; les suivantes ajoutent ` (2)`, ` (3)`, etc. avant `.mp3`.
    public static func candidateFileName(
        date: Date,
        title: String,
        attempt: Int,
        timeZone: TimeZone = .current
    ) -> String {
        let base = baseName(date: date, title: title, timeZone: timeZone)
        if attempt <= 1 {
            return "\(base).\(fileExtension)"
        }
        return "\(base) (\(attempt)).\(fileExtension)"
    }

    /// Premier nom libre, testé par le prédicat fourni. Aucune écriture n'est
    /// faite ici : la décision reste pure et testable.
    public static func uniqueFileName(
        date: Date,
        title: String,
        timeZone: TimeZone = .current,
        fileExists: (String) -> Bool
    ) throws -> String {
        for attempt in 1...10_000 {
            let candidate = candidateFileName(
                date: date,
                title: title,
                attempt: attempt,
                timeZone: timeZone
            )
            if !fileExists(candidate) {
                return candidate
            }
        }
        throw RecordingNameError.noAvailableName
    }
}

public enum RecordingNameError: Error, Equatable, LocalizedError {
    case noAvailableName

    public var errorDescription: String? {
        switch self {
        case .noAvailableName:
            return NSLocalizedString(
                "No available file name was found for this recording.",
                bundle: .main,
                comment: "Recording name exhaustion error"
            )
        }
    }
}
