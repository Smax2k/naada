import Foundation

/// Un processus tel que lu dans la table du système, sans Core Audio.
///
/// Cette structure ne contient que ce que le plan pur doit vérifier : le PID,
/// son parent et sa ligne de commande complète. Aucun accès au HAL, aucun tap,
/// aucune permission ne sont nécessaires pour la construire.
public struct ApplicationAudioProcess: Equatable {
    public let pid: pid_t
    public let parentPID: pid_t
    public let command: String

    public init(pid: pid_t, parentPID: pid_t, command: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
    }
}

/// Rôle d'un processus vis-à-vis de l'application choisie.
public enum ApplicationAudioProcessKind: String, Equatable, CaseIterable {
    case application
    case audioService
    case renderer
    case gpu
    case network
    case videoCapture
    case crashpad
    case unrelated
}

/// Preuve qu'un PID a été retenu par le plan comme descendant audio vérifié.
///
/// L'initialiseur est interne au module : hors de `NaadaCore`, seul
/// `ApplicationAudioProcesses.plan` peut en produire. Un identifiant de
/// processus arbitraire ne peut donc pas être présenté comme un helper audio.
public struct VerifiedAudioHelperProcess: Equatable {
    public let pid: pid_t
    public let parentPID: pid_t
    public let command: String

    init(pid: pid_t, parentPID: pid_t, command: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
    }
}

/// Un helper vérifié, traduit en objet processus Core Audio par le moteur.
///
/// La traduction reste dans le moteur : le plan pur ne connaît que des PID.
public struct TranslatedAudioHelper: Equatable {
    public let process: VerifiedAudioHelperProcess
    public let processObjectID: UInt32

    public init(process: VerifiedAudioHelperProcess, processObjectID: UInt32) {
        self.process = process
        self.processObjectID = processObjectID
    }
}

/// Résultat pur de l'analyse d'une application et de ses descendants.
///
/// Le PID choisi reste toujours la racine du plan. Les helpers audio ne sont
/// ajoutés que s'ils sont à la fois descendants de cette racine et porteurs
/// d'une commande de service audio reconnue.
public struct ApplicationAudioProcessPlan: Equatable {
    public let rootPID: pid_t
    public let audioHelpers: [VerifiedAudioHelperProcess]

    public init(rootPID: pid_t, audioHelpers: [VerifiedAudioHelperProcess]) {
        self.rootPID = rootPID
        self.audioHelpers = audioHelpers
    }

    /// Le PID choisi d'abord, puis les helpers vérifiés, sans doublon.
    public var selectedPIDs: [pid_t] {
        var pids: [pid_t] = []
        if rootPID > 0 {
            pids.append(rootPID)
        }
        pids.append(contentsOf: audioHelpers.map(\.pid))
        return pids
    }

    public var hasAudioHelper: Bool { !audioHelpers.isEmpty }
}

/// Traduction d'un plan en cibles réellement tapables.
///
/// La racine demandée reste distincte de la racine traduite : un PID choisi
/// peut n'avoir aucun objet processus Core Audio alors qu'un helper vérifié en
/// a un. Les PID non traduisibles sont conservés dans `untranslatedPIDs` pour
/// le diagnostic, jamais présentés comme tapés.
public struct ApplicationAudioTapSelection: Equatable {
    public let requestedRootPID: pid_t
    public let rootObjectID: UInt32?
    public let tappedPIDs: [pid_t]
    public let untranslatedPIDs: [pid_t]
    public let processObjectIDs: [UInt32]
    public let translatedHelpers: [TranslatedAudioHelper]

    public init(
        plan: ApplicationAudioProcessPlan,
        translatedObjectIDs: [pid_t: UInt32]
    ) {
        self.requestedRootPID = plan.rootPID

        var tapped: [pid_t] = []
        var objects: [UInt32] = []
        var untranslated: [pid_t] = []
        var helpers: [TranslatedAudioHelper] = []

        let rootObject = plan.rootPID > 0
            ? Self.validObjectID(translatedObjectIDs[plan.rootPID])
            : nil
        self.rootObjectID = rootObject
        if let rootObject {
            tapped.append(plan.rootPID)
            objects.append(rootObject)
        } else if plan.rootPID > 0 {
            untranslated.append(plan.rootPID)
        }

        for helper in plan.audioHelpers {
            if let objectID = Self.validObjectID(translatedObjectIDs[helper.pid]) {
                helpers.append(
                    TranslatedAudioHelper(
                        process: helper,
                        processObjectID: objectID
                    )
                )
                tapped.append(helper.pid)
                objects.append(objectID)
            } else {
                untranslated.append(helper.pid)
            }
        }

        self.tappedPIDs = tapped
        self.untranslatedPIDs = untranslated
        self.processObjectIDs = objects
        self.translatedHelpers = helpers
    }

    public var rootIsTranslated: Bool { rootObjectID != nil }

    public var isUsable: Bool { !processObjectIDs.isEmpty }

    /// Contraintes du tap : racine traduite si elle existe, plus les seuls
    /// helpers traduits. Un ensemble vide est refusé par les contraintes.
    public var constraints: ProcessTapConstraints {
        ProcessTapConstraints.verifiedApplicationAudio(
            applicationObjectID: rootObjectID,
            translatedHelpers: translatedHelpers
        )
    }

    private static func validObjectID(_ value: UInt32?) -> UInt32? {
        guard let value, value != 0 else { return nil }
        return value
    }
}

/// Plan pur des processus à taper pour une application choisie.
///
/// Règle unique : le PID choisi, plus uniquement ses descendants dont la ligne
/// de commande désigne le service audio de Chromium. Les renderers, le GPU, le
/// réseau, la capture vidéo, crashpad et tout processus hors de l'arbre sont
/// rejetés. Sans helper, le plan ne contient que le PID choisi.
public enum ApplicationAudioProcesses {
    /// Marqueur du service audio dans les arguments d'un helper Chromium.
    public static let audioServiceUtilityMarker = "--utility-sub-type=audio.mojom.AudioService"
    /// Marqueur de bac à sable du même service ; l'un ou l'autre suffit.
    public static let audioServiceSandboxMarker = "--service-sandbox-type=audio"
    public static let rendererMarker = "--type=renderer"
    public static let gpuMarker = "--type=gpu-process"
    public static let networkUtilityMarker = "network.mojom.NetworkService"
    public static let networkSandboxMarker = "--service-sandbox-type=network"
    public static let videoCaptureMarker = "video_capture.mojom.VideoCaptureService"
    public static let videoCaptureSandboxMarker = "--service-sandbox-type=video_capture"
    public static let crashpadMarker = "chrome_crashpad_handler"

    /// Classe une ligne de commande, sans consulter l'arbre des processus.
    ///
    /// Les marqueurs de rejet sont examinés avant le marqueur audio : une
    /// commande qui porterait les deux reste refusée.
    public static func classify(command: String) -> ApplicationAudioProcessKind {
        if command.contains(crashpadMarker) {
            return .crashpad
        }
        if command.contains(rendererMarker) {
            return .renderer
        }
        if command.contains(gpuMarker) {
            return .gpu
        }
        if command.contains(videoCaptureMarker)
            || command.contains(videoCaptureSandboxMarker) {
            return .videoCapture
        }
        if command.contains(networkUtilityMarker)
            || command.contains(networkSandboxMarker) {
            return .network
        }
        if command.contains(audioServiceUtilityMarker)
            || command.contains(audioServiceSandboxMarker) {
            return .audioService
        }
        return .unrelated
    }

    /// Vrai si `process` descend de `rootPID` en suivant les parents.
    ///
    /// Un processus ne descend jamais de lui-même. Une chaîne cyclique ou
    /// profonde de plus de 64 niveaux est refusée plutôt que suivie sans fin.
    public static func isDescendant(
        _ process: ApplicationAudioProcess,
        of rootPID: pid_t,
        processes: [ApplicationAudioProcess]
    ) -> Bool {
        let byPID = Dictionary(
            processes.map { ($0.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return isDescendant(process, of: rootPID, byPID: byPID)
    }

    /// Rôle effectif : la racine est l'application, un descendant est classé
    /// par sa commande, tout le reste est `unrelated`.
    public static func kind(
        of process: ApplicationAudioProcess,
        rootPID: pid_t,
        processes: [ApplicationAudioProcess]
    ) -> ApplicationAudioProcessKind {
        if process.pid == rootPID {
            return .application
        }
        guard isDescendant(process, of: rootPID, processes: processes) else {
            return .unrelated
        }
        return classify(command: process.command)
    }

    /// Construit le plan d'une application.
    ///
    /// Le PID racine est conservé même si son objet processus Core Audio est
    /// introuvable : le moteur omettra seulement sa traduction. Un helper dont
    /// la traduction échoue sera omis de la même façon, sans repli global.
    public static func plan(
        rootPID: pid_t,
        processes: [ApplicationAudioProcess]
    ) -> ApplicationAudioProcessPlan {
        guard rootPID > 0 else {
            return ApplicationAudioProcessPlan(rootPID: rootPID, audioHelpers: [])
        }

        let byPID = Dictionary(
            processes.map { ($0.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<pid_t>()
        let helpers = processes
            .filter { $0.pid != rootPID }
            .filter { isDescendant($0, of: rootPID, byPID: byPID) }
            .filter { classify(command: $0.command) == .audioService }
            .sorted { $0.pid < $1.pid }
            .compactMap { process -> VerifiedAudioHelperProcess? in
                guard seen.insert(process.pid).inserted else { return nil }
                return VerifiedAudioHelperProcess(
                    pid: process.pid,
                    parentPID: process.parentPID,
                    command: process.command
                )
            }

        return ApplicationAudioProcessPlan(
            rootPID: rootPID,
            audioHelpers: helpers
        )
    }

    private static func isDescendant(
        _ process: ApplicationAudioProcess,
        of rootPID: pid_t,
        byPID: [pid_t: ApplicationAudioProcess]
    ) -> Bool {
        guard process.pid > 0, process.pid != rootPID else { return false }

        var current = process.parentPID
        var visited: Set<pid_t> = [process.pid]

        for _ in 0..<64 {
            if current == rootPID {
                return true
            }
            guard current > 1, visited.insert(current).inserted else {
                return false
            }
            guard let parent = byPID[current] else {
                return false
            }
            current = parent.parentPID
        }
        return false
    }
}
