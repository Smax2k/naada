import Foundation

/// Contraintes pures d'un tap de processus Core Audio.
///
/// Un seul chemin est autorisé : un unique processus choisi par son
/// `AudioObjectID`, éventuellement accompagné des seuls helpers audio que le
/// plan pur a prouvés descendants de ce processus. Un tap privé et non muet
/// reste obligatoire, et aucun ciblage par bundle ID, par périphérique de
/// sortie par défaut ou par le système entier n'est admis. Ces invariants sont
/// testables sans créer de tap ni ouvrir de périphérique audio.
public struct ProcessTapConstraints: Equatable {
    /// Comportement de sortie du processus tapé. `unmuted` est le seul admis :
    /// le son continue d'aller vers la sortie système pendant la capture.
    public enum MuteBehavior: String, Equatable, CaseIterable {
        case unmuted
        case muted
        case mutedWhenTapped
    }

    /// Rôle d'une cible dans le plan de tap.
    public enum Role: String, Equatable, CaseIterable {
        /// Le processus de l'application choisie.
        case application
        /// Un descendant audio vérifié par `ApplicationAudioProcesses`.
        case verifiedAudioHelper
    }

    /// Une cible du tap : son objet processus et sa provenance.
    ///
    /// Un helper doit porter la preuve produite par le plan. Un identifiant
    /// arbitraire étiqueté « helper » sans cette preuve est refusé.
    public struct Target: Equatable {
        public let processObjectID: UInt32
        public let role: Role
        public let helper: VerifiedAudioHelperProcess?

        public init(
            processObjectID: UInt32,
            role: Role,
            helper: VerifiedAudioHelperProcess? = nil
        ) {
            self.processObjectID = processObjectID
            self.role = role
            self.helper = helper
        }
    }

    /// Raisons de refus, toutes vérifiables sans Core Audio.
    public enum Violation: String, Error, Equatable, CaseIterable {
        case noProcess
        case unknownProcessObject
        case multipleApplications
        case audioHelperWithoutProof
        case duplicateProcess
        case notPrivate
        case outputMuted
        case bundleIDTargeting
        case defaultOutputTargeting
        case globalSystemTargeting
    }

    public var targets: [Target]
    public var isPrivate: Bool
    public var muteBehavior: MuteBehavior
    public var usesBundleIdentifiers: Bool
    public var targetsDefaultOutputDevice: Bool
    public var isExclusive: Bool

    public init(
        targets: [Target],
        isPrivate: Bool,
        muteBehavior: MuteBehavior,
        usesBundleIdentifiers: Bool,
        targetsDefaultOutputDevice: Bool,
        isExclusive: Bool
    ) {
        self.targets = targets
        self.isPrivate = isPrivate
        self.muteBehavior = muteBehavior
        self.usesBundleIdentifiers = usesBundleIdentifiers
        self.targetsDefaultOutputDevice = targetsDefaultOutputDevice
        self.isExclusive = isExclusive
    }

    /// Objets processus réellement passés au tap, dans l'ordre du plan.
    public var processObjectIDs: [UInt32] {
        targets.map(\.processObjectID)
    }

    public var applicationProcessObjectIDs: [UInt32] {
        targets
            .filter { $0.role == .application }
            .map(\.processObjectID)
    }

    public var verifiedAudioHelperObjectIDs: [UInt32] {
        targets
            .filter { $0.role == .verifiedAudioHelper }
            .map(\.processObjectID)
    }

    /// PID des helpers réellement traduits et retenus, sans les PID omis.
    public var verifiedAudioHelperPIDs: [pid_t] {
        targets.compactMap { target in
            guard target.role == .verifiedAudioHelper else { return nil }
            return target.helper?.pid
        }
    }

    /// Configuration canonique : le processus choisi, rien d'autre.
    public static func processOnly(processObjectID: UInt32) -> ProcessTapConstraints {
        ProcessTapConstraints(
            targets: [
                Target(processObjectID: processObjectID, role: .application),
            ],
            isPrivate: true,
            muteBehavior: .unmuted,
            usesBundleIdentifiers: false,
            targetsDefaultOutputDevice: false,
            isExclusive: false
        )
    }

    /// Configuration d'une application et de ses helpers audio vérifiés.
    ///
    /// `applicationObjectID` vaut `nil` lorsque le processus choisi n'expose
    /// aucun objet processus Core Audio mais qu'un helper vérifié, lui, en
    /// expose un : le tap ne cible alors que les helpers prouvés. Les
    /// identifiants non traduisibles sont omis par le moteur avant cet appel.
    public static func verifiedApplicationAudio(
        applicationObjectID: UInt32?,
        translatedHelpers: [TranslatedAudioHelper]
    ) -> ProcessTapConstraints {
        var targets: [Target] = []
        if let applicationObjectID {
            targets.append(
                Target(processObjectID: applicationObjectID, role: .application)
            )
        }
        targets.append(contentsOf: translatedHelpers.map { helper in
            Target(
                processObjectID: helper.processObjectID,
                role: .verifiedAudioHelper,
                helper: helper.process
            )
        })

        return ProcessTapConstraints(
            targets: targets,
            isPrivate: true,
            muteBehavior: .unmuted,
            usesBundleIdentifiers: false,
            targetsDefaultOutputDevice: false,
            isExclusive: false
        )
    }

    public var violations: [Violation] {
        var found: [Violation] = []

        if targets.isEmpty {
            found.append(.noProcess)
        }
        if targets.contains(where: { $0.processObjectID == 0 }) {
            found.append(.unknownProcessObject)
        }

        // Deux processus « application » constituent un ensemble arbitraire :
        // seul un choix unique, éventuellement complété par des helpers
        // prouvés, est admis.
        if targets.filter({ $0.role == .application }).count > 1 {
            found.append(.multipleApplications)
        }
        if targets.contains(where: {
            $0.role == .verifiedAudioHelper && $0.helper == nil
        }) {
            found.append(.audioHelperWithoutProof)
        }

        let identifiers = targets.map(\.processObjectID)
        if Set(identifiers).count != identifiers.count {
            found.append(.duplicateProcess)
        }

        if !isPrivate {
            found.append(.notPrivate)
        }
        if muteBehavior != .unmuted {
            found.append(.outputMuted)
        }
        if usesBundleIdentifiers {
            found.append(.bundleIDTargeting)
        }
        if targetsDefaultOutputDevice {
            found.append(.defaultOutputTargeting)
        }
        if isExclusive {
            found.append(.globalSystemTargeting)
        }

        return found
    }

    public var isValid: Bool {
        violations.isEmpty
    }

    /// Lève une erreur si le plan de tap sort du chemin audio seul autorisé.
    public func validate() throws {
        guard isValid else {
            throw ProcessTapConstraintError(violations: violations)
        }
    }
}

public struct ProcessTapConstraintError: Error, Equatable, LocalizedError {
    public let violations: [ProcessTapConstraints.Violation]

    public init(violations: [ProcessTapConstraints.Violation]) {
        self.violations = violations
    }

    public var errorDescription: String? {
        let reasons = violations.map(\.rawValue).joined(separator: ", ")
        return String(
            format: NSLocalizedString(
                "Process tap configuration rejected: %@.",
                bundle: .main,
                comment: "Process tap constraint violation list"
            ),
            reasons
        )
    }
}
