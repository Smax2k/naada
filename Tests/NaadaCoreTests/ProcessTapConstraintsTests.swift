import XCTest
@testable import NaadaCore

final class ProcessTapConstraintsTests: XCTestCase {
    func testCanonicalPlanTargetsOnlyTheChosenProcessWithoutMutingIt() {
        let plan = ProcessTapConstraints.processOnly(processObjectID: 4_242)

        XCTAssertEqual(plan.processObjectIDs, [4_242])
        XCTAssertEqual(plan.applicationProcessObjectIDs, [4_242])
        XCTAssertTrue(plan.verifiedAudioHelperObjectIDs.isEmpty)
        XCTAssertTrue(plan.isPrivate)
        XCTAssertEqual(plan.muteBehavior, .unmuted)
        XCTAssertFalse(plan.usesBundleIdentifiers)
        XCTAssertFalse(plan.targetsDefaultOutputDevice)
        XCTAssertFalse(plan.isExclusive)
        XCTAssertTrue(plan.isValid)
        XCTAssertTrue(plan.violations.isEmpty)
        XCTAssertNoThrow(try plan.validate())
    }

    func testVerifiedApplicationAndAudioHelperAreBothTargeted() {
        let plan = ProcessTapConstraints.verifiedApplicationAudio(
            applicationObjectID: 4_242,
            translatedHelpers: [
                TranslatedAudioHelper(process: helper(), processObjectID: 8_888),
            ]
        )

        XCTAssertEqual(plan.processObjectIDs, [4_242, 8_888])
        XCTAssertEqual(plan.applicationProcessObjectIDs, [4_242])
        XCTAssertEqual(plan.verifiedAudioHelperObjectIDs, [8_888])
        XCTAssertEqual(plan.verifiedAudioHelperPIDs, [1_626])
        XCTAssertEqual(plan.targets.last?.helper?.pid, 1_626)
        XCTAssertTrue(plan.isValid)
        XCTAssertNoThrow(try plan.validate())
    }

    func testVerifiedHelperAloneIsAcceptedWhenTheChosenProcessHasNoAudioObject() {
        let plan = ProcessTapConstraints.verifiedApplicationAudio(
            applicationObjectID: nil,
            translatedHelpers: [
                TranslatedAudioHelper(process: helper(), processObjectID: 8_888),
            ]
        )

        XCTAssertEqual(plan.processObjectIDs, [8_888])
        XCTAssertTrue(plan.applicationProcessObjectIDs.isEmpty)
        XCTAssertEqual(plan.verifiedAudioHelperObjectIDs, [8_888])
        XCTAssertTrue(plan.isValid)
    }

    func testMissingApplicationAndMissingHelperAreRejected() {
        let plan = ProcessTapConstraints.verifiedApplicationAudio(
            applicationObjectID: nil,
            translatedHelpers: []
        )

        XCTAssertEqual(plan.violations, [.noProcess])
        assertValidationFails(plan, with: [.noProcess])
    }

    func testTwoApplicationProcessesAreAnArbitrarySetAndAreRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.targets.append(
            ProcessTapConstraints.Target(processObjectID: 34, role: .application)
        )

        XCTAssertEqual(plan.violations, [.multipleApplications])
        assertValidationFails(plan, with: [.multipleApplications])
    }

    func testAudioHelperWithoutThePlannerProofIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.targets.append(
            ProcessTapConstraints.Target(
                processObjectID: 34,
                role: .verifiedAudioHelper
            )
        )

        XCTAssertEqual(plan.violations, [.audioHelperWithoutProof])
        assertValidationFails(plan, with: [.audioHelperWithoutProof])
    }

    func testDuplicateProcessObjectIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.targets.append(
            ProcessTapConstraints.Target(
                processObjectID: 12,
                role: .verifiedAudioHelper,
                helper: helper()
            )
        )

        XCTAssertEqual(plan.violations, [.duplicateProcess])
        assertValidationFails(plan, with: [.duplicateProcess])
    }

    func testUnknownProcessObjectIsRejected() {
        let application = ProcessTapConstraints.processOnly(processObjectID: 0)
        XCTAssertEqual(application.violations, [.unknownProcessObject])

        let helperPlan = ProcessTapConstraints.verifiedApplicationAudio(
            applicationObjectID: nil,
            translatedHelpers: [
                TranslatedAudioHelper(process: helper(), processObjectID: 0),
            ]
        )
        XCTAssertEqual(helperPlan.violations, [.unknownProcessObject])
        assertValidationFails(helperPlan, with: [.unknownProcessObject])
    }

    func testMutedTapIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.muteBehavior = .muted

        XCTAssertFalse(plan.isValid)
        XCTAssertEqual(plan.violations, [.outputMuted])
        assertValidationFails(plan, with: [.outputMuted])
    }

    func testMutedWhenTappedIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.muteBehavior = .mutedWhenTapped

        XCTAssertEqual(plan.violations, [.outputMuted])
        assertValidationFails(plan, with: [.outputMuted])
    }

    func testNonPrivateTapIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.isPrivate = false

        XCTAssertEqual(plan.violations, [.notPrivate])
        assertValidationFails(plan, with: [.notPrivate])
    }

    func testBundleIDWideTargetingIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.usesBundleIdentifiers = true

        XCTAssertEqual(plan.violations, [.bundleIDTargeting])
        assertValidationFails(plan, with: [.bundleIDTargeting])
    }

    func testDefaultOutputTargetingIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.targetsDefaultOutputDevice = true

        XCTAssertEqual(plan.violations, [.defaultOutputTargeting])
        assertValidationFails(plan, with: [.defaultOutputTargeting])
    }

    func testExclusiveGlobalTapIsRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.isExclusive = true

        XCTAssertEqual(plan.violations, [.globalSystemTargeting])
        assertValidationFails(plan, with: [.globalSystemTargeting])
    }

    func testAllViolationsAreReportedTogether() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.isPrivate = false
        plan.muteBehavior = .muted
        plan.usesBundleIdentifiers = true
        plan.targetsDefaultOutputDevice = true
        plan.isExclusive = true
        plan.targets.append(
            ProcessTapConstraints.Target(processObjectID: 34, role: .application)
        )
        plan.targets.append(
            ProcessTapConstraints.Target(
                processObjectID: 56,
                role: .verifiedAudioHelper
            )
        )

        XCTAssertEqual(
            Set(plan.violations),
            Set([
                .multipleApplications,
                .audioHelperWithoutProof,
                .notPrivate,
                .outputMuted,
                .bundleIDTargeting,
                .defaultOutputTargeting,
                .globalSystemTargeting,
            ])
        )
        XCTAssertFalse(plan.isValid)
    }

    func testValidationErrorListsEveryReason() throws {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.isPrivate = false
        plan.muteBehavior = .mutedWhenTapped

        XCTAssertThrowsError(try plan.validate()) { error in
            guard let constraintError = error as? ProcessTapConstraintError else {
                return XCTFail("Type d'erreur inattendu : \(error)")
            }
            XCTAssertEqual(
                Set(constraintError.violations),
                Set([.notPrivate, .outputMuted])
            )
            XCTAssertTrue(
                constraintError.localizedDescription.contains("notPrivate")
            )
            XCTAssertTrue(
                constraintError.localizedDescription.contains("outputMuted")
            )
        }
    }

    private func helper(
        pid: pid_t = 1_626,
        parentPID: pid_t = 721
    ) -> VerifiedAudioHelperProcess {
        VerifiedAudioHelperProcess(
            pid: pid,
            parentPID: parentPID,
            command: ApplicationAudioProcesses.audioServiceUtilityMarker
        )
    }

    private func assertValidationFails(
        _ plan: ProcessTapConstraints,
        with expected: [ProcessTapConstraints.Violation],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try plan.validate(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? ProcessTapConstraintError,
                ProcessTapConstraintError(violations: expected),
                file: file,
                line: line
            )
        }
    }
}
