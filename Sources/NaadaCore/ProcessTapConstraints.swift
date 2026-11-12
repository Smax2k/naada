import Foundation

/// Contraintes pures d'un tap de processus Core Audio.
///
/// Un seul chemin est autorisé : un unique processus ciblé par son
/// `AudioObjectID`, un tap privé et non muet, et aucun ciblage par bundle ID
/// ni par périphérique de sortie par défaut. Ces invariants sont testables
/// sans créer de tap ni ouvrir de périphérique audio.
public struct ProcessTapConstraints: Equatable {
    /// Comportement de sortie du processus tapé. `unmuted` est le seul admis :
    /// le son continue d'aller vers la sortie système pendant la capture.
    public enum MuteBehavior: String, Equatable, CaseIterable {
        case unmuted
        case muted
        case mutedWhenTapped
    }

    /// Raisons de refus, toutes vérifiables sans Core Audio.
    public enum Violation: String, Error, Equatable, CaseIterable {
        case noProcess
        case multipleProcesses
        case unknownProcessObject
        case notPrivate
        case outputMuted
        case bundleIDTargeting
        case defaultOutputTargeting
        case globalSystemTargeting
    }

    public var processObjectIDs: [UInt32]
    public var isPrivate: Bool
    public var muteBehavior: MuteBehavior
    public var usesBundleIdentifiers: Bool
    public var targetsDefaultOutputDevice: Bool
    public var isExclusive: Bool

    public init(
        processObjectIDs: [UInt32],
        isPrivate: Bool,
        muteBehavior: MuteBehavior,
        usesBundleIdentifiers: Bool,
        targetsDefaultOutputDevice: Bool,
        isExclusive: Bool
    ) {
        self.processObjectIDs = processObjectIDs
        self.isPrivate = isPrivate
        self.muteBehavior = muteBehavior
        self.usesBundleIdentifiers = usesBundleIdentifiers
        self.targetsDefaultOutputDevice = targetsDefaultOutputDevice
        self.isExclusive = isExclusive
    }

    /// Configuration canonique : le processus choisi, rien d'autre.
    public static func processOnly(processObjectID: UInt32) -> ProcessTapConstraints {
        ProcessTapConstraints(
            processObjectIDs: [processObjectID],
            isPrivate: true,
            muteBehavior: .unmuted,
            usesBundleIdentifiers: false,
            targetsDefaultOutputDevice: false,
            isExclusive: false
        )
    }

    public var violations: [Violation] {
        var found: [Violation] = []

        if processObjectIDs.isEmpty {
            found.append(.noProcess)
        } else if processObjectIDs.count > 1 {
            found.append(.multipleProcesses)
        }
        if processObjectIDs.contains(0) {
            found.append(.unknownProcessObject)
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
        return "Configuration de tap de processus refusée : \(reasons)."
    }
}
