import XCTest
@testable import NaadaCore

final class ProcessTapConstraintsTests: XCTestCase {
    func testCanonicalPlanTargetsOnlyTheChosenProcessWithoutMutingIt() {
        let plan = ProcessTapConstraints.processOnly(processObjectID: 4_242)

        XCTAssertEqual(plan.processObjectIDs, [4_242])
        XCTAssertTrue(plan.isPrivate)
        XCTAssertEqual(plan.muteBehavior, .unmuted)
        XCTAssertFalse(plan.usesBundleIdentifiers)
        XCTAssertFalse(plan.targetsDefaultOutputDevice)
        XCTAssertFalse(plan.isExclusive)
        XCTAssertTrue(plan.isValid)
        XCTAssertTrue(plan.violations.isEmpty)
        XCTAssertNoThrow(try plan.validate())
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

    func testGlobalTapWithoutProcessIsRejected() {
        var exclusivePlan = ProcessTapConstraints.processOnly(processObjectID: 12)
        exclusivePlan.isExclusive = true
        XCTAssertEqual(exclusivePlan.violations, [.globalSystemTargeting])
        assertValidationFails(exclusivePlan, with: [.globalSystemTargeting])

        var emptyPlan = ProcessTapConstraints.processOnly(processObjectID: 12)
        emptyPlan.processObjectIDs = []
        XCTAssertEqual(emptyPlan.violations, [.noProcess])

        let unknownPlan = ProcessTapConstraints.processOnly(processObjectID: 0)
        XCTAssertEqual(unknownPlan.violations, [.unknownProcessObject])
    }

    func testMultipleProcessesAreRejected() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.processObjectIDs = [12, 34]

        XCTAssertEqual(plan.violations, [.multipleProcesses])
        assertValidationFails(plan, with: [.multipleProcesses])
    }

    func testAllViolationsAreReportedTogether() {
        var plan = ProcessTapConstraints.processOnly(processObjectID: 12)
        plan.isPrivate = false
        plan.muteBehavior = .muted
        plan.usesBundleIdentifiers = true
        plan.targetsDefaultOutputDevice = true
        plan.isExclusive = true

        XCTAssertEqual(
            Set(plan.violations),
            Set([
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
