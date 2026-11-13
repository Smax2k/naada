import XCTest
@testable import NaadaCore

final class AudioBufferLayoutTests: XCTestCase {
    private func format(
        channels: Int = 2,
        bits: Int = 32,
        bytesPerFrame: Int = 8,
        interleaved: Bool = true
    ) throws -> AudioStreamFormat {
        try XCTUnwrap(
            AudioStreamFormat(
                sampleRate: 48_000,
                channelsPerFrame: channels,
                bitsPerChannel: bits,
                bytesPerFrame: bytesPerFrame,
                isInterleaved: interleaved
            )
        )
    }

    func testInterleavedStereoBufferYieldsFrames() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(),
            buffers: [.init(channelCount: 2, byteSize: 1_024)]
        )

        XCTAssertEqual(layout.kind, .interleaved)
        XCTAssertEqual(layout.frameCount, 128)
        XCTAssertFalse(layout.isEmpty)
        XCTAssertTrue(layout.isCompatible)
    }

    func testInterleavedFormatComputesMissingBytesPerFrame() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(bytesPerFrame: 0),
            buffers: [.init(channelCount: 2, byteSize: 512)]
        )

        XCTAssertEqual(layout.kind, .interleaved)
        XCTAssertEqual(layout.frameCount, 64)
    }

    func testDeinterleavedStereoUsesPerChannelBuffers() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(bytesPerFrame: 4, interleaved: false),
            buffers: [
                .init(channelCount: 1, byteSize: 1_024),
                .init(channelCount: 1, byteSize: 1_024),
            ]
        )

        XCTAssertEqual(layout.kind, .deinterleaved)
        XCTAssertEqual(layout.frameCount, 256)
        XCTAssertFalse(layout.isEmpty)
    }

    func testDeinterleavedUnevenBuffersUseTheShortest() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(bytesPerFrame: 4, interleaved: false),
            buffers: [
                .init(channelCount: 1, byteSize: 1_024),
                .init(channelCount: 1, byteSize: 512),
            ]
        )

        XCTAssertEqual(layout.kind, .deinterleaved)
        XCTAssertEqual(layout.frameCount, 128)
    }

    func testEmptyOrZeroSizedBuffersAreNotReceiving() throws {
        let empty = AudioBufferLayout.analyze(format: try format(), buffers: [])
        XCTAssertFalse(empty.isCompatible)
        XCTAssertTrue(empty.isEmpty)

        let zero = AudioBufferLayout.analyze(
            format: try format(),
            buffers: [.init(channelCount: 2, byteSize: 0)]
        )
        XCTAssertTrue(zero.isEmpty)
    }

    func testOneFrameOfSilenceIsStillAReceivedBuffer() throws {
        // Un buffer de silence numérique a la même taille qu'un buffer
        // audible : la réception se juge sur les frames, pas sur l'amplitude.
        let layout = AudioBufferLayout.analyze(
            format: try format(),
            buffers: [.init(channelCount: 2, byteSize: 8)]
        )

        XCTAssertEqual(layout.kind, .interleaved)
        XCTAssertEqual(layout.frameCount, 1)
        XCTAssertFalse(layout.isEmpty)
    }

    func testMismatchedChannelCountIsIncompatible() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(),
            buffers: [
                .init(channelCount: 1, byteSize: 512),
                .init(channelCount: 1, byteSize: 512),
                .init(channelCount: 1, byteSize: 512),
            ]
        )

        XCTAssertEqual(layout.kind, .incompatible)
        XCTAssertFalse(layout.isCompatible)
    }

    func testMonoBufferIsUsable() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(channels: 1, bytesPerFrame: 4),
            buffers: [.init(channelCount: 1, byteSize: 400)]
        )

        XCTAssertEqual(layout.kind, .interleaved)
        XCTAssertEqual(layout.frameCount, 100)
    }

    func testDeclaredFrameWidthSmallerThanChannelsIsCorrected() throws {
        let layout = AudioBufferLayout.analyze(
            format: try format(bytesPerFrame: 4),
            buffers: [.init(channelCount: 2, byteSize: 1_024)]
        )

        XCTAssertEqual(layout.frameCount, 128)
    }

    func testInvalidStreamFormatsAreRejected() {
        XCTAssertNil(
            AudioStreamFormat(
                sampleRate: 0,
                channelsPerFrame: 2,
                bitsPerChannel: 32,
                bytesPerFrame: 8,
                isInterleaved: true
            )
        )
        XCTAssertNil(
            AudioStreamFormat(
                sampleRate: 48_000,
                channelsPerFrame: 0,
                bitsPerChannel: 32,
                bytesPerFrame: 8,
                isInterleaved: true
            )
        )
        XCTAssertNil(
            AudioStreamFormat(
                sampleRate: 48_000,
                channelsPerFrame: 2,
                bitsPerChannel: 0,
                bytesPerFrame: 8,
                isInterleaved: true
            )
        )
    }
}
