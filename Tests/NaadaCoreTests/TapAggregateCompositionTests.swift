import CoreAudio
import XCTest
@testable import NaadaCore

final class TapAggregateCompositionTests: XCTestCase {
    func testCanonicalCompositionTargetsOnePrivateTap() {
        let composition = TapAggregateComposition(
            name: "Naada — Test",
            uid: "aggregate-uid",
            tapUID: "tap-uid"
        )

        XCTAssertTrue(composition.isCanonical)
        let dictionary = composition.dictionary
        XCTAssertEqual(dictionary[TapAggregateKey.name] as? String, "Naada — Test")
        XCTAssertEqual(dictionary[TapAggregateKey.uid] as? String, "aggregate-uid")

        let taps = dictionary[TapAggregateKey.tapList] as? [[String: Any]]
        XCTAssertEqual(taps?.count, 1, "un seul tap doit composer l'agrégat")
        XCTAssertEqual(
            taps?.first?[TapAggregateKey.tapUID] as? String,
            "tap-uid"
        )
    }

    func testAggregateNumbersAreCFNumbersNotBooleans() throws {
        let dictionary = TapAggregateComposition(
            name: "Naada — Test",
            uid: "aggregate-uid",
            tapUID: "tap-uid"
        ).dictionary

        for key in [
            TapAggregateKey.isPrivate,
            TapAggregateKey.isStacked,
            TapAggregateKey.tapAutoStart,
        ] {
            let number = try XCTUnwrap(dictionary[key] as? NSNumber)
            XCTAssertEqual(
                CFGetTypeID(number),
                CFNumberGetTypeID(),
                "\(key) doit être un CFNumber"
            )
            XCTAssertNotEqual(
                CFGetTypeID(number),
                CFBooleanGetTypeID(),
                "\(key) ne doit jamais être un CFBoolean"
            )
        }

        XCTAssertEqual(
            (dictionary[TapAggregateKey.isPrivate] as? NSNumber)?.intValue,
            1
        )
        XCTAssertEqual(
            (dictionary[TapAggregateKey.isStacked] as? NSNumber)?.intValue,
            0
        )
        XCTAssertEqual(
            (dictionary[TapAggregateKey.tapAutoStart] as? NSNumber)?.intValue,
            0,
            "le démarrage ne doit jamais attendre le premier son"
        )
    }

    func testTapEntryCarriesIntegerDriftCompensation() throws {
        let dictionary = TapAggregateComposition(
            name: "Naada — Test",
            uid: "aggregate-uid",
            tapUID: "tap-uid"
        ).dictionary

        let taps = try XCTUnwrap(
            dictionary[TapAggregateKey.tapList] as? [[String: Any]]
        )
        let entry = try XCTUnwrap(taps.first)
        let drift = try XCTUnwrap(
            entry[TapAggregateKey.tapDriftCompensation] as? NSNumber
        )

        XCTAssertEqual(drift.intValue, 1)
        XCTAssertEqual(CFGetTypeID(drift), CFNumberGetTypeID())
        XCTAssertNotEqual(CFGetTypeID(drift), CFBooleanGetTypeID())
        XCTAssertEqual(entry[TapAggregateKey.tapUID] as? String, "tap-uid")
    }

    func testNonCanonicalFlagsStayIntegers() throws {
        let composition = TapAggregateComposition(
            name: "Naada — Test",
            uid: "aggregate-uid",
            tapUID: "tap-uid",
            isPrivate: false,
            isStacked: true,
            tapAutoStart: true,
            usesDriftCompensation: false
        )
        XCTAssertFalse(composition.isCanonical)

        let dictionary = composition.dictionary
        for key in [
            TapAggregateKey.isPrivate,
            TapAggregateKey.isStacked,
            TapAggregateKey.tapAutoStart,
        ] {
            let number = try XCTUnwrap(dictionary[key] as? NSNumber)
            XCTAssertEqual(CFGetTypeID(number), CFNumberGetTypeID())
            XCTAssertNotEqual(CFGetTypeID(number), CFBooleanGetTypeID())
        }
        XCTAssertEqual(
            (dictionary[TapAggregateKey.isPrivate] as? NSNumber)?.intValue,
            0
        )
        XCTAssertEqual(
            (dictionary[TapAggregateKey.isStacked] as? NSNumber)?.intValue,
            1
        )
        XCTAssertEqual(
            (dictionary[TapAggregateKey.tapAutoStart] as? NSNumber)?.intValue,
            1
        )

        let taps = try XCTUnwrap(
            dictionary[TapAggregateKey.tapList] as? [[String: Any]]
        )
        let drift = try XCTUnwrap(
            taps.first?[TapAggregateKey.tapDriftCompensation] as? NSNumber
        )
        XCTAssertEqual(drift.intValue, 0)
        XCTAssertEqual(CFGetTypeID(drift), CFNumberGetTypeID())
    }

    func testAggregateDoesNotAddAnOutputClockOrSubDevice() {
        let dictionary = TapAggregateComposition(
            name: "Naada — Test",
            uid: "aggregate-uid",
            tapUID: "tap-uid"
        ).dictionary

        // Seul le tap choisi entre dans l'agrégat : aucun périphérique de
        // sortie, aucune horloge ni sous-périphérique supplémentaire.
        XCTAssertNil(dictionary[kAudioAggregateDeviceSubDeviceListKey])
        XCTAssertNil(dictionary[kAudioAggregateDeviceMainSubDeviceKey])
        XCTAssertNil(dictionary[kAudioAggregateDeviceClockDeviceKey])
    }

    func testLiteralKeysMatchTheCoreAudioSDK() {
        XCTAssertEqual(TapAggregateKey.name, kAudioAggregateDeviceNameKey)
        XCTAssertEqual(TapAggregateKey.uid, kAudioAggregateDeviceUIDKey)
        XCTAssertEqual(
            TapAggregateKey.isPrivate,
            kAudioAggregateDeviceIsPrivateKey
        )
        XCTAssertEqual(
            TapAggregateKey.isStacked,
            kAudioAggregateDeviceIsStackedKey
        )
        XCTAssertEqual(
            TapAggregateKey.tapAutoStart,
            kAudioAggregateDeviceTapAutoStartKey
        )
        XCTAssertEqual(
            TapAggregateKey.tapList,
            kAudioAggregateDeviceTapListKey
        )
        XCTAssertEqual(TapAggregateKey.tapUID, kAudioSubTapUIDKey)
        XCTAssertEqual(
            TapAggregateKey.tapDriftCompensation,
            kAudioSubTapDriftCompensationKey
        )
    }
}
