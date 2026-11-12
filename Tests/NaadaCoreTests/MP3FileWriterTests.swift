import AVFoundation
import Foundation
import XCTest
@testable import NaadaCore

final class MP3FileWriterTests: XCTestCase {
    func testSyntheticPCMProducesReadableStereoMP3() throws {
        let folder = try TestWorkspace.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = try MP3FileWriter(
            folder: folder,
            date: Date(timeIntervalSince1970: 1_763_000_000),
            title: "Test synthétique",
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let framesPerChunk = 1_024
        let chunkCount = 48 // environ 1,024 s à 48 kHz
        let sine = Self.makeSineFrames(
            count: framesPerChunk * chunkCount,
            sampleRate: MP3FileWriter.sampleRate
        )

        var offset = 0
        for _ in 0..<chunkCount {
            let end = offset + framesPerChunk * MP3FileWriter.channelCount
            let slice = Array(sine[offset..<end])
            try writer.append(slice)
            offset = end
        }

        let url = try writer.finish()
        XCTAssertGreaterThan(writer.bytesWritten, 1_000)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1] & 0xE0, 0xE0, "sync MP3 attendu")

        let version = (data[1] >> 3) & 0x03
        let layer = (data[1] >> 1) & 0x03
        let sampleRateIndex = (data[2] >> 2) & 0x03
        XCTAssertEqual(version, 0x03, "MPEG-1 attendu")
        XCTAssertEqual(layer, 0x01, "Layer III attendu")
        XCTAssertEqual(sampleRateIndex, 0x01, "48 kHz attendu")

        // Décodage réel par Core Audio : prouve que le MP3 est lisible.
        let audioFile = try AVAudioFile(forReading: url)
        XCTAssertEqual(audioFile.processingFormat.sampleRate, 48_000, accuracy: 1)
        XCTAssertEqual(audioFile.processingFormat.channelCount, 2)
        XCTAssertGreaterThan(audioFile.length, 0)

        let decoded = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: 8_192
        )!
        try audioFile.read(into: decoded)
        XCTAssertGreaterThan(decoded.frameLength, 0, "des échantillons doivent être décodés")
    }

    func testEmptyRecordingStillProducesReadableMP3() throws {
        let folder = try TestWorkspace.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = try MP3FileWriter(
            folder: folder,
            date: Date(timeIntervalSince1970: 1_763_000_000),
            title: "Arrêt immédiat",
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let url = try writer.finish()

        XCTAssertGreaterThan(writer.bytesWritten, 100)
        let audioFile = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(audioFile.length, 0)
    }

    func testWriterRefusesToOverwriteExistingFile() throws {
        let folder = try TestWorkspace.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let date = Date(timeIntervalSince1970: 1_763_000_000)
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let first = try MP3FileWriter(folder: folder, date: date, title: "Réunion", timeZone: timeZone)
        try first.finish()
        let firstBytes = try Data(contentsOf: first.url)

        let second = try MP3FileWriter(folder: folder, date: date, title: "Réunion", timeZone: timeZone)
        try second.append([0, 0, 0, 0])
        let secondURL = try second.finish()
        defer { try? FileManager.default.removeItem(at: secondURL) }

        XCTAssertEqual(secondURL.lastPathComponent, first.url.lastPathComponent
            .replacingOccurrences(of: ".mp3", with: " (2).mp3"))
        XCTAssertEqual(try Data(contentsOf: first.url), firstBytes)
    }

    private static func makeSineFrames(count: Int, sampleRate: Int) -> [Int16] {
        var samples = [Int16]()
        samples.reserveCapacity(count * MP3FileWriter.channelCount)
        for frame in 0..<count {
            let phase = 2 * Double.pi * 440 * Double(frame) / Double(sampleRate)
            let value = Int16(0.2 * 32_767 * sin(phase))
            samples.append(value)
            samples.append(value)
        }
        return samples
    }
}
