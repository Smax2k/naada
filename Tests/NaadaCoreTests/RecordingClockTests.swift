import Foundation
import XCTest
@testable import NaadaCore

final class RecordingClockTests: XCTestCase {
    func testElapsedFreezesAfterStop() {
        var clock = RecordingClock()
        clock.start(at: 100)
        XCTAssertEqual(clock.elapsed(at: 110.9), 10.9, accuracy: 0.0001)

        clock.stop(at: 145.5)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: 999), 45.5, accuracy: 0.0001)
        XCTAssertEqual(clock.elapsed(at: 10_000), 45.5, accuracy: 0.0001)
    }

    func testRestartAccumulatesWithoutDoubleCounting() {
        var clock = RecordingClock()
        clock.start(at: 0)
        clock.start(at: 50) // déjà démarrée : ignoré
        clock.stop(at: 10)
        clock.start(at: 20)
        clock.stop(at: 25)
        XCTAssertEqual(clock.elapsed(at: 500), 15, accuracy: 0.0001)
    }

    func testNegativeIntervalsAreClamped() {
        var clock = RecordingClock()
        clock.start(at: 100)
        XCTAssertEqual(clock.elapsed(at: 90), 0, accuracy: 0.0001)
        clock.stop(at: 80)
        XCTAssertEqual(clock.elapsed(at: 200), 0, accuracy: 0.0001)
    }

    func testFormatter() {
        XCTAssertEqual(ElapsedFormatter.string(seconds: 0), "00:00")
        XCTAssertEqual(ElapsedFormatter.string(seconds: 59.9), "00:59")
        XCTAssertEqual(ElapsedFormatter.string(seconds: 60), "01:00")
        XCTAssertEqual(ElapsedFormatter.string(seconds: 3_661), "1:01:01")
        XCTAssertEqual(ElapsedFormatter.string(seconds: -4), "00:00")
    }
}

enum TestWorkspace {
    static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NaadaCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // racine du projet
    }

    static func makeDirectory() throws -> URL {
        let root = projectRoot.appendingPathComponent(".test-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
