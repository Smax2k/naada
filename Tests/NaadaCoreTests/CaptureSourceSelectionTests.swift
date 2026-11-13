import Foundation
import XCTest
@testable import NaadaCore

final class CaptureSourceSelectionTests: XCTestCase {
    private let chrome = RememberedSource(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
    private let safari = RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari")
    private let usbMicrophone = MicrophoneChoice.selected(
        uid: "AppleUSBAudioEngine:Micro:1234",
        name: "Micro USB"
    )
    private let outputFolder = "/tmp/naada-capture"

    private func decision(
        _ selection: CaptureSourceSelection,
        outputFolderPath: String? = "/tmp/naada-capture",
        applications: [RememberedSource] = [],
        microphones: [MicrophoneChoice] = []
    ) -> CaptureStartDecision {
        selection.startDecision(
            outputFolderPath: outputFolderPath,
            isApplicationAvailable: { applications.contains($0) },
            isMicrophoneAvailable: { microphones.contains($0) }
        )
    }

    // MARK: - Trois modes autorisés

    func testMicrophoneOnlyIsAllowed() {
        let selection = CaptureSourceSelection(microphone: usbMicrophone)

        XCTAssertEqual(
            decision(selection, microphones: [usbMicrophone]),
            .allowed
        )
    }

    func testApplicationOnlyIsAllowed() {
        let selection = CaptureSourceSelection(application: chrome)

        XCTAssertEqual(
            decision(selection, applications: [chrome]),
            .allowed
        )
    }

    func testApplicationAndMicrophoneTogetherAreAllowed() {
        let selection = CaptureSourceSelection(application: chrome, microphone: usbMicrophone)

        XCTAssertEqual(
            decision(selection, applications: [chrome], microphones: [usbMicrophone]),
            .allowed
        )
    }

    // MARK: - Refus explicites

    func testBothSourcesMissingIsRefusedWithoutQueryingAvailability() {
        var applicationQueries = 0
        var microphoneQueries = 0

        let result = CaptureSourceSelection().startDecision(
            outputFolderPath: outputFolder,
            isApplicationAvailable: { _ in
                applicationQueries += 1
                return true
            },
            isMicrophoneAvailable: { _ in
                microphoneQueries += 1
                return true
            }
        )

        XCTAssertEqual(result, .noSourceSelected)
        XCTAssertEqual(applicationQueries, 0)
        XCTAssertEqual(microphoneQueries, 0)
    }

    func testUnavailableApplicationBlocksEvenWhenMicrophoneIsAvailable() {
        let selection = CaptureSourceSelection(application: chrome, microphone: usbMicrophone)

        XCTAssertEqual(
            decision(selection, applications: [], microphones: [usbMicrophone]),
            .applicationUnavailable(chrome),
            "aucun repli sur le microphone quand l'application choisie manque"
        )
    }

    func testUnavailableMicrophoneBlocksEvenWhenApplicationIsAvailable() {
        let selection = CaptureSourceSelection(application: chrome, microphone: usbMicrophone)

        XCTAssertEqual(
            decision(selection, applications: [chrome], microphones: []),
            .microphoneUnavailable(usbMicrophone),
            "aucun repli sur l'application quand le microphone choisi manque"
        )
    }

    func testUnavailableSystemDefaultMicrophoneIsRefused() {
        let selection = CaptureSourceSelection(application: chrome, microphone: .systemDefault)

        XCTAssertEqual(
            decision(selection, applications: [chrome], microphones: []),
            .microphoneUnavailable(.systemDefault)
        )
    }

    func testAbsentMicrophoneIsNeverQueried() {
        var microphoneQueries = 0

        let result = CaptureSourceSelection(application: chrome).startDecision(
            outputFolderPath: outputFolder,
            isApplicationAvailable: { _ in true },
            isMicrophoneAvailable: { _ in
                microphoneQueries += 1
                return true
            }
        )

        XCTAssertEqual(result, .allowed)
        XCTAssertEqual(microphoneQueries, 0)
    }

    func testMissingOrBlankOutputFolderIsRefused() {
        let selection = CaptureSourceSelection(microphone: usbMicrophone)

        XCTAssertEqual(
            decision(selection, outputFolderPath: nil, microphones: [usbMicrophone]),
            .outputFolderMissing
        )
        XCTAssertEqual(
            decision(selection, outputFolderPath: "", microphones: [usbMicrophone]),
            .outputFolderMissing
        )
        XCTAssertEqual(
            decision(selection, outputFolderPath: "   ", microphones: [usbMicrophone]),
            .outputFolderMissing
        )
    }

    func testUnavailableSourceIsReportedBeforeMissingFolder() {
        let selection = CaptureSourceSelection(application: chrome)

        XCTAssertEqual(
            decision(selection, outputFolderPath: nil),
            .applicationUnavailable(chrome)
        )
    }

    // MARK: - MicrophoneChoice

    func testMicrophoneChoiceRoundTripsThroughCodable() throws {
        let choices: [MicrophoneChoice] = [
            .none,
            .systemDefault,
            .selected(uid: "AppleUSBAudioEngine:Micro:1234", name: "Micro USB")
        ]

        for choice in choices {
            let data = try JSONEncoder().encode(choice)
            XCTAssertEqual(try JSONDecoder().decode(MicrophoneChoice.self, from: data), choice)
        }
    }

    func testMissingMicrophoneKindDecodesToNone() throws {
        let data = Data("{}".utf8)

        XCTAssertEqual(try JSONDecoder().decode(MicrophoneChoice.self, from: data), .none)
    }

    func testSelectedMicrophoneWithoutUIDDecodesToNone() throws {
        let data = Data(#"{"kind":"selected","name":"Micro sans UID"}"#.utf8)

        XCTAssertEqual(try JSONDecoder().decode(MicrophoneChoice.self, from: data), .none)
    }
}
