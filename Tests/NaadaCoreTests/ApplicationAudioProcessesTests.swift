import XCTest
@testable import NaadaCore

final class ApplicationAudioProcessesTests: XCTestCase {
    private let chromeMain = ApplicationAudioProcess(
        pid: 721,
        parentPID: 1,
        command: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    )

    func testChromePlanKeepsChosenPIDAndOnlyItsVerifiedAudioHelper() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )

        XCTAssertEqual(plan.rootPID, 721)
        XCTAssertEqual(plan.selectedPIDs, [721, 1_626])
        XCTAssertEqual(plan.audioHelpers.map(\.pid), [1_626])
        XCTAssertEqual(plan.audioHelpers.first?.parentPID, 721)
        XCTAssertTrue(plan.hasAudioHelper)
    }

    func testRendererGPUAndNetworkHelpersAreRejected() {
        let rejected: [pid_t] = [1_080, 951, 952]
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )

        for pid in rejected {
            XCTAssertFalse(
                plan.selectedPIDs.contains(pid),
                "Le processus \(pid) ne doit jamais être tapé."
            )
        }
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: chromeTree().first { $0.pid == 1_080 }!,
                rootPID: 721,
                processes: chromeTree()
            ),
            .renderer
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: chromeTree().first { $0.pid == 951 }!,
                rootPID: 721,
                processes: chromeTree()
            ),
            .gpu
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: chromeTree().first { $0.pid == 952 }!,
                rootPID: 721,
                processes: chromeTree()
            ),
            .network
        )
    }

    func testVideoCaptureHelperIsRejected() {
        let video = chromeTree().first { $0.pid == 1_627 }!
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: video,
                rootPID: 721,
                processes: chromeTree()
            ),
            .videoCapture
        )

        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )
        XCTAssertFalse(plan.selectedPIDs.contains(1_627))
    }

    func testCrashpadOutsideTheTreeIsRejected() {
        let crashpad = chromeTree().first { $0.pid == 942 }!
        XCTAssertEqual(crashpad.parentPID, 1)
        XCTAssertFalse(
            ApplicationAudioProcesses.isDescendant(
                crashpad,
                of: 721,
                processes: chromeTree()
            )
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: crashpad,
                rootPID: 721,
                processes: chromeTree()
            ),
            .unrelated
        )
    }

    func testAudioServiceOutsideTheTreeIsRejected() {
        let foreignAudio = ApplicationAudioProcess(
            pid: 4_242,
            parentPID: 1,
            command: "Helper --type=utility --utility-sub-type=audio.mojom.AudioService --service-sandbox-type=audio"
        )

        XCTAssertEqual(
            ApplicationAudioProcesses.classify(command: foreignAudio.command),
            .audioService
        )
        XCTAssertFalse(
            ApplicationAudioProcesses.isDescendant(
                foreignAudio,
                of: 721,
                processes: [chromeMain, foreignAudio]
            )
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: foreignAudio,
                rootPID: 721,
                processes: [chromeMain, foreignAudio]
            ),
            .unrelated
        )

        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: [chromeMain, foreignAudio]
        )
        XCTAssertEqual(plan.selectedPIDs, [721])
    }

    func testNoHelperKeepsOnlyTheChosenPID() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: [chromeMain]
        )

        XCTAssertEqual(plan.selectedPIDs, [721])
        XCTAssertFalse(plan.hasAudioHelper)
        XCTAssertTrue(plan.audioHelpers.isEmpty)
    }

    func testDeepDescendantAudioServiceIsAccepted() {
        let deepAudio = ApplicationAudioProcess(
            pid: 2_000,
            parentPID: 1_626,
            command: "Helper --type=utility --utility-sub-type=audio.mojom.AudioService --service-sandbox-type=audio"
        )
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree() + [deepAudio]
        )

        XCTAssertEqual(plan.selectedPIDs, [721, 1_626, 2_000])
        XCTAssertEqual(plan.audioHelpers.map(\.parentPID), [721, 1_626])
    }

    func testCycleInParentChainIsRejected() {
        let first = ApplicationAudioProcess(pid: 500, parentPID: 501, command: "audio")
        let second = ApplicationAudioProcess(pid: 501, parentPID: 500, command: "audio")

        XCTAssertFalse(
            ApplicationAudioProcesses.isDescendant(
                first,
                of: 721,
                processes: [chromeMain, first, second]
            )
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.plan(
                rootPID: 721,
                processes: [chromeMain, first, second]
            ).selectedPIDs,
            [721]
        )
    }

    func testDuplicateProcessEntriesAreCollapsed() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree() + chromeTree()
        )

        XCTAssertEqual(plan.audioHelpers.map(\.pid), [1_626])
    }

    func testInvalidRootProducesNoSelection() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 0,
            processes: chromeTree()
        )

        XCTAssertTrue(plan.selectedPIDs.isEmpty)
        XCTAssertFalse(plan.hasAudioHelper)
    }

    func testBothAudioMarkersAreRecognised() {
        let utility = ApplicationAudioProcess(
            pid: 10,
            parentPID: 1,
            command: "Helper --type=utility --utility-sub-type=audio.mojom.AudioService"
        )
        let sandbox = ApplicationAudioProcess(
            pid: 11,
            parentPID: 1,
            command: "Helper --type=utility --service-sandbox-type=audio"
        )

        XCTAssertEqual(
            ApplicationAudioProcesses.classify(command: utility.command),
            .audioService
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.classify(command: sandbox.command),
            .audioService
        )
    }

    func testRejectMarkersWinOverAnAudioMarker() {
        XCTAssertEqual(
            ApplicationAudioProcesses.classify(
                command: "Helper --type=renderer --service-sandbox-type=audio"
            ),
            .renderer
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.classify(
                command: "Helper --type=gpu-process --service-sandbox-type=audio"
            ),
            .gpu
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.classify(
                command: "chrome_crashpad_handler --service-sandbox-type=audio"
            ),
            .crashpad
        )
    }

    func testUnknownCommandIsUnrelated() {
        XCTAssertEqual(
            ApplicationAudioProcesses.classify(command: "/usr/bin/true"),
            .unrelated
        )
        XCTAssertEqual(
            ApplicationAudioProcesses.kind(
                of: ApplicationAudioProcess(pid: 30, parentPID: 721, command: "/usr/bin/true"),
                rootPID: 721,
                processes: [
                    chromeMain,
                    ApplicationAudioProcess(pid: 30, parentPID: 721, command: "/usr/bin/true"),
                ]
            ),
            .unrelated
        )
    }

    func testSelectionDistinguishesUntranslatedRootFromTappedHelper() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )
        let selection = ApplicationAudioTapSelection(
            plan: plan,
            translatedObjectIDs: [1_626: 8_888]
        )

        XCTAssertEqual(selection.requestedRootPID, 721)
        XCTAssertFalse(selection.rootIsTranslated)
        XCTAssertNil(selection.rootObjectID)
        XCTAssertEqual(selection.tappedPIDs, [1_626])
        XCTAssertEqual(selection.untranslatedPIDs, [721])
        XCTAssertEqual(selection.processObjectIDs, [8_888])
        XCTAssertEqual(selection.translatedHelpers.map(\.process.pid), [1_626])
        XCTAssertTrue(selection.isUsable)
        XCTAssertTrue(selection.constraints.isValid)
        XCTAssertTrue(selection.constraints.applicationProcessObjectIDs.isEmpty)
        XCTAssertEqual(
            selection.constraints.verifiedAudioHelperObjectIDs,
            [8_888]
        )
    }

    func testSelectionKeepsTranslatedRootAndOmitsUntranslatedHelper() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )
        let selection = ApplicationAudioTapSelection(
            plan: plan,
            translatedObjectIDs: [721: 4_242]
        )

        XCTAssertTrue(selection.rootIsTranslated)
        XCTAssertEqual(selection.rootObjectID, 4_242)
        XCTAssertEqual(selection.tappedPIDs, [721])
        XCTAssertEqual(selection.untranslatedPIDs, [1_626])
        XCTAssertEqual(selection.processObjectIDs, [4_242])
        XCTAssertTrue(selection.isUsable)
        XCTAssertEqual(selection.constraints.applicationProcessObjectIDs, [4_242])
        XCTAssertTrue(selection.constraints.verifiedAudioHelperObjectIDs.isEmpty)
    }

    func testSelectionWithNoTranslationIsUnusableAndKeepsBothPIDs() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )
        let selection = ApplicationAudioTapSelection(
            plan: plan,
            translatedObjectIDs: [:]
        )

        XCTAssertFalse(selection.rootIsTranslated)
        XCTAssertTrue(selection.tappedPIDs.isEmpty)
        XCTAssertEqual(selection.untranslatedPIDs, [721, 1_626])
        XCTAssertTrue(selection.processObjectIDs.isEmpty)
        XCTAssertFalse(selection.isUsable)
        XCTAssertEqual(selection.constraints.violations, [.noProcess])
    }

    func testZeroObjectIDIsTreatedAsUntranslated() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )
        let selection = ApplicationAudioTapSelection(
            plan: plan,
            translatedObjectIDs: [721: 0, 1_626: 0]
        )

        XCTAssertFalse(selection.rootIsTranslated)
        XCTAssertEqual(selection.untranslatedPIDs, [721, 1_626])
        XCTAssertFalse(selection.isUsable)
    }

    func testSelectionOrdersRootThenTranslatedHelpers() {
        let plan = ApplicationAudioProcesses.plan(
            rootPID: 721,
            processes: chromeTree()
        )
        let selection = ApplicationAudioTapSelection(
            plan: plan,
            translatedObjectIDs: [721: 4_242, 1_626: 8_888]
        )

        XCTAssertEqual(selection.tappedPIDs, [721, 1_626])
        XCTAssertEqual(selection.processObjectIDs, [4_242, 8_888])
        XCTAssertTrue(selection.untranslatedPIDs.isEmpty)
        XCTAssertEqual(selection.constraints.processObjectIDs, [4_242, 8_888])
        XCTAssertTrue(selection.constraints.isValid)
    }

    func testSelectionIgnoresNonPositiveRoot() {
        let selection = ApplicationAudioTapSelection(
            plan: ApplicationAudioProcessPlan(rootPID: 0, audioHelpers: []),
            translatedObjectIDs: [0: 42]
        )

        XCTAssertTrue(selection.tappedPIDs.isEmpty)
        XCTAssertTrue(selection.untranslatedPIDs.isEmpty)
        XCTAssertTrue(selection.processObjectIDs.isEmpty)
        XCTAssertFalse(selection.isUsable)
    }

    private func chromeTree() -> [ApplicationAudioProcess] {
        [
            chromeMain,
            ApplicationAudioProcess(
                pid: 951,
                parentPID: 721,
                command: "Helper --type=gpu-process --gpu-preferences=AAA"
            ),
            ApplicationAudioProcess(
                pid: 952,
                parentPID: 721,
                command: "Helper --type=utility --utility-sub-type=network.mojom.NetworkService --service-sandbox-type=network"
            ),
            ApplicationAudioProcess(
                pid: 1_626,
                parentPID: 721,
                command: "Helper --type=utility --utility-sub-type=audio.mojom.AudioService --service-sandbox-type=audio --message-loop-type-ui"
            ),
            ApplicationAudioProcess(
                pid: 1_627,
                parentPID: 721,
                command: "Helper --type=utility --utility-sub-type=video_capture.mojom.VideoCaptureService --service-sandbox-type=none"
            ),
            ApplicationAudioProcess(
                pid: 1_080,
                parentPID: 721,
                command: "Helper --type=renderer --extension-process --lang=fr"
            ),
            ApplicationAudioProcess(
                pid: 942,
                parentPID: 1,
                command: "chrome_crashpad_handler --monitor-self-annotation=ptype=crashpad-handler"
            ),
        ]
    }
}
