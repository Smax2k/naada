import Foundation
import XCTest
@testable import NaadaCore

final class RecordingNameTests: XCTestCase {
    private let timeZone = TimeZone(secondsFromGMT: 0)!
    private let meetingDate = ISO8601DateFormatter().date(from: "2026-11-12T10:00:00Z")!

    func testExampleNameMatchesRequestedFormat() throws {
        let name = try RecordingName.uniqueFileName(
            date: meetingDate,
            title: "Réunion",
            timeZone: timeZone,
            fileExists: { _ in false }
        )
        XCTAssertEqual(name, "2026 11 12 Réunion.mp3")
    }

    func testSlashAndColonBecomeDashes() {
        XCTAssertEqual(
            RecordingName.sanitizedTitle("Atelier / Q&A : épisode 2"),
            "Atelier - Q&A - épisode 2"
        )
    }

    func testEmptyTitleFallsBack() {
        XCTAssertEqual(RecordingName.sanitizedTitle("   \n  "), "Session")
    }

    func testControlCharactersAndWhitespaceAreNormalized() {
        XCTAssertEqual(
            RecordingName.sanitizedTitle("  Voix\u{0}\tdu   matin  "),
            "Voix du matin"
        )
    }

    func testCollisionUsesTwoThenThreeBeforeExtension() throws {
        let existing: Set<String> = [
            "2026 11 12 Réunion.mp3",
            "2026 11 12 Réunion (2).mp3"
        ]
        let name = try RecordingName.uniqueFileName(
            date: meetingDate,
            title: "Réunion",
            timeZone: timeZone,
            fileExists: { existing.contains($0) }
        )
        XCTAssertEqual(name, "2026 11 12 Réunion (3).mp3")
        XCTAssertTrue(name.hasSuffix(".mp3"))
    }

    func testCandidateKeepsSuffixBeforeExtension() {
        XCTAssertEqual(
            RecordingName.candidateFileName(
                date: meetingDate,
                title: "Cours",
                attempt: 2,
                timeZone: timeZone
            ),
            "2026 11 12 Cours (2).mp3"
        )
    }

    func testLongTitleIsBoundedButKeepsExtension() {
        let long = String(repeating: "a", count: 400)
        let name = RecordingName.candidateFileName(
            date: meetingDate,
            title: long,
            attempt: 1,
            timeZone: timeZone
        )
        XCTAssertTrue(name.hasSuffix(".mp3"))
        XCTAssertLessThanOrEqual(name.count, RecordingName.maximumTitleLength + 16)
    }

    func testEmojiTitleRespectsFilesystemByteLimit() {
        let emoji = String(repeating: "🎙️", count: 200)
        let name = RecordingName.candidateFileName(
            date: meetingDate,
            title: emoji,
            attempt: 1,
            timeZone: timeZone
        )
        XCTAssertTrue(name.hasSuffix(".mp3"))
        XCTAssertLessThanOrEqual(
            name.utf8.count,
            RecordingName.maximumTitleUTF8Bytes + 16,
            "le nom complet doit rester très en dessous des 255 octets d'APFS"
        )
    }

    func testCreatedFileNeverOverwritesOriginalBytes() throws {
        let folder = try TestWorkspace.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let original = folder.appendingPathComponent("2026 11 12 Réunion.mp3")
        let originalBytes = Data("contenu original à préserver".utf8)
        try originalBytes.write(to: original)

        let created = try RecordingFile.create(
            in: folder,
            date: meetingDate,
            title: "Réunion",
            timeZone: timeZone
        )
        defer { try? created.handle.close() }

        XCTAssertEqual(created.url.lastPathComponent, "2026 11 12 Réunion (2).mp3")
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.url.path))
        XCTAssertEqual(try Data(contentsOf: created.url), Data())
    }
    func testFolderIsTheOnlyPlaceWritten() throws {
        let folder = try TestWorkspace.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let created = try RecordingFile.create(
            in: folder,
            date: meetingDate,
            title: "Session",
            timeZone: timeZone
        )
        defer { try? created.handle.close() }

        XCTAssertEqual(created.url.deletingLastPathComponent().standardizedFileURL.path,
                       folder.standardizedFileURL.path)
    }

    func testNoAvailableNameWhenEverythingCollides() {
        XCTAssertThrowsError(
            try RecordingName.uniqueFileName(
                date: meetingDate,
                title: "Réunion",
                timeZone: timeZone,
                fileExists: { _ in true }
            )
        ) { error in
            XCTAssertEqual(error as? RecordingNameError, .noAvailableName)
        }
    }
}
