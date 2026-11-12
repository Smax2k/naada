import AppKit
import NaadaCore

/// Une application proposée comme source audio.
///
/// `pid` vaut `nil` lorsque l'application vient du souvenir de la dernière
/// session mais n'est pas ouverte. La sélection, elle, s'appuie toujours sur
/// l'identité `bundleIdentifier` + nom, jamais sur le PID.
/// Aucun tap, aucune capture n'est créé pour établir cette liste.
struct SourceApplication: Identifiable, Equatable {
    let pid: pid_t?
    let name: String
    let bundleIdentifier: String?

    init(pid: pid_t, name: String, bundleIdentifier: String?) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    init(remembering source: RememberedSource) {
        self.pid = nil
        self.name = source.name
        self.bundleIdentifier = source.bundleIdentifier
    }

    var id: String { rememberedSource.stableIdentifier }

    var rememberedSource: RememberedSource {
        RememberedSource(bundleIdentifier: bundleIdentifier, name: name)
    }

    var isRunning: Bool { pid != nil }

    func matches(_ source: RememberedSource) -> Bool {
        rememberedSource == source
    }
}

enum RunningApplicationCatalog {
    /// Liste les applications ouvertes, puis ajoute la source mémorisée si
    /// elle n'est pas actuellement ouverte afin qu'elle reste visible dans le
    /// sélecteur.
    static func list(remembering remembered: RememberedSource? = nil) -> [SourceApplication] {
        var applications = liveApplications()

        if let remembered, !applications.contains(where: { $0.matches(remembered) }) {
            applications.append(SourceApplication(remembering: remembered))
        }

        return applications.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame {
                return (lhs.bundleIdentifier ?? "") < (rhs.bundleIdentifier ?? "")
            }
            return order == .orderedAscending
        }
    }

    private static func liveApplications() -> [SourceApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier
        var seenIdentities = Set<String>()

        return NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular
                    && !application.isTerminated
                    && application.processIdentifier != ownPID
                    && application.bundleIdentifier != ownBundle
            }
            .compactMap { application in
                guard let name = application.localizedName, !name.isEmpty else { return nil }
                return SourceApplication(
                    pid: application.processIdentifier,
                    name: name,
                    bundleIdentifier: application.bundleIdentifier
                )
            }
            .filter { seenIdentities.insert($0.id).inserted }
    }
}
