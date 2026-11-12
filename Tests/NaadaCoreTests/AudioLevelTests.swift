import XCTest
@testable import NaadaCore

final class AudioLevelTests: XCTestCase {
    func testEmptyAndZeroSamplesAreSilent() {
        XCTAssertEqual(AudioLevel.normalizedRMS([]), 0)
        XCTAssertEqual(AudioLevel.normalizedRMS([0, 0, 0, 0, 0]), 0)
        XCTAssertTrue(AudioLevel.isSilent(0))
        XCTAssertEqual(AudioLevel.meterFraction(0), 0)
    }

    func testFullScaleIsOne() {
        let positiveFullScale = [Int16](repeating: .max, count: 256)
        let negativeFullScale = [Int16](repeating: .min, count: 256)

        XCTAssertEqual(AudioLevel.normalizedRMS(positiveFullScale), 1, accuracy: 0.000_001)
        XCTAssertEqual(AudioLevel.normalizedRMS(negativeFullScale), 1, accuracy: 0.000_001)
        XCTAssertEqualToUnity(AudioLevel.normalizedRMS([.max, .min, .max, .min]))
    }

    func testKnownRMS() {
        // RMS de [16384, -16384] = 16384, soit 16384 / 32767 ≈ 0,500015.
        XCTAssertEqual(
            AudioLevel.normalizedRMS([16384, -16384]),
            0.5,
            accuracy: 0.000_1
        )

        // Une onde carrée à ±8192 donne un RMS de 8192, soit ≈ 0,250008.
        XCTAssertEqual(
            AudioLevel.normalizedRMS([8192, -8192, 8192, -8192]),
            0.25,
            accuracy: 0.000_1
        )

        // Un décalage continu positif a le même RMS que son amplitude.
        XCTAssertEqual(
            AudioLevel.normalizedRMS([16384, 16384, 16384, 16384]),
            0.5,
            accuracy: 0.000_1
        )
    }

    func testMeterFractionUsesDecibelsAndClampsSilence() {
        XCTAssertEqual(AudioLevel.meterFraction(0), 0)
        XCTAssertEqual(AudioLevel.meterFraction(AudioLevel.silenceThreshold), 0)
        XCTAssertEqual(AudioLevel.meterFraction(1), 1, accuracy: 0.000_1)
        XCTAssertGreaterThan(
            AudioLevel.meterFraction(0.1),
            AudioLevel.meterFraction(0.01)
        )
        XCTAssertGreaterThan(AudioLevel.meterFraction(0.25), 0.5)
    }

    private func XCTAssertEqualToUnity(
        _ value: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value, 1, accuracy: 0.000_001, file: file, line: line)
    }
}
