import AppKit

/// Une application actuellement ouverte, proposée comme source audio.
/// Aucun tap, aucune capture n'est créé pour établir cette liste.
struct SourceApplication: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?

    var id: pid_t { pid }
}

enum RunningApplicationCatalog {
    static func list() -> [SourceApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier

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
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
