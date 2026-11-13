import Foundation
import XCTest
@testable import NaadaCore

final class SessionSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "naada.session-settings.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testNewStoreInstanceRestoresSourceAndTitle() {
        let source = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        let firstLaunch = SessionSettingsStore(defaults: defaults)
        firstLaunch.rememberedSource = source
        firstLaunch.sessionTitle = "Réunion budget 2027"

        let relaunch = SessionSettingsStore(defaults: defaults)

        XCTAssertEqual(
            relaunch.restore(),
            SessionSettings(rememberedSource: source, title: "Réunion budget 2027")
        )
    }

    func testRememberedSourceSurvivesWhileApplicationIsClosed() {
        let chrome = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        let firstLaunch = SessionSettingsStore(defaults: defaults)
        firstLaunch.rememberedSource = chrome

        // Relaunch : la source mémorisée reste la sélection même si aucune
        // application ouverte ne correspond encore.
        let relaunch = SessionSettingsStore(defaults: defaults)
        let selected = relaunch.rememberedSource
        var running: [RunningSource] = []

        XCTAssertEqual(selected, chrome)
        XCTAssertNil(liveSource(in: running, matching: selected))

        // L'application revient avec un nouveau PID : l'identité retrouve la
        // source vivante sans que la sélection change.
        running = [
            RunningSource(
                pid: 4242,
                bundleIdentifier: "com.google.Chrome",
                name: "Google Chrome"
            )
        ]
        let reconnected = liveSource(in: running, matching: selected)
        XCTAssertEqual(reconnected?.pid, 4242)
        XCTAssertEqual(selected, chrome)
    }

    func testIdentityUsesBundleIdentifierAndNameOnly() {
        let chrome = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )

        XCTAssertTrue(
            chrome.matches(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        )
        XCTAssertFalse(
            chrome.matches(bundleIdentifier: "com.google.Chrome", name: "Chromium")
        )
        XCTAssertFalse(
            chrome.matches(bundleIdentifier: "com.apple.Safari", name: "Google Chrome")
        )
        XCTAssertFalse(chrome.matches(bundleIdentifier: nil, name: "Google Chrome"))

        // Une même application relancée (donc un autre PID) garde la même
        // identité et la même clé de sélection.
        let relaunchedChrome = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        XCTAssertEqual(chrome, relaunchedChrome)
        XCTAssertEqual(chrome.stableIdentifier, relaunchedChrome.stableIdentifier)
    }

    func testApplicationWithoutBundleIdentifierMatchesByName() {
        let source = RememberedSource(bundleIdentifier: nil, name: "Outil local")

        XCTAssertTrue(source.matches(bundleIdentifier: nil, name: "Outil local"))
        XCTAssertFalse(source.matches(bundleIdentifier: nil, name: "Autre outil"))
    }

    func testRestoredTitleIsNotReplacedBySourceSuggestion() {
        let source = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        let firstLaunch = SessionSettingsStore(defaults: defaults)
        firstLaunch.rememberedSource = source
        firstLaunch.sessionTitle = "Notes de la réunion"

        let relaunch = SessionSettingsStore(defaults: defaults)
        let restored = relaunch.restore()

        XCTAssertEqual(restored.title, "Notes de la réunion")
        XCTAssertNil(
            SessionTitlePolicy.suggestedTitle(
                currentTitle: restored.title,
                lastSuggestedTitle: "",
                sourceName: source.name
            ),
            "le titre restauré doit rester intact lors de la sélection retrouvée"
        )
    }

    func testEmptyOrPreviousSuggestedTitleStillFollowsSource() {
        XCTAssertEqual(
            SessionTitlePolicy.suggestedTitle(
                currentTitle: "   ",
                lastSuggestedTitle: "",
                sourceName: "Safari"
            ),
            "Safari"
        )
        XCTAssertEqual(
            SessionTitlePolicy.suggestedTitle(
                currentTitle: "Google Chrome",
                lastSuggestedTitle: "Google Chrome",
                sourceName: "Safari"
            ),
            "Safari"
        )
    }

    func testOutputFolderKeyIsUnchangedAndSeparate() {
        let savedFolder = "/tmp/naada-dossier-existant"
        defaults.set(savedFolder, forKey: SessionSettingsStore.outputFolderPathKey)

        let store = SessionSettingsStore(defaults: defaults)
        store.rememberedSource = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        store.sessionTitle = "Session suivante"

        XCTAssertEqual(SessionSettingsStore.outputFolderPathKey, "naada.outputFolderPath")
        XCTAssertEqual(
            defaults.string(forKey: "naada.outputFolderPath"),
            savedFolder,
            "le magasin ne doit jamais réécrire ni supprimer la clé du dossier"
        )
        XCTAssertNotEqual(
            SessionSettingsStore.rememberedSourceKey,
            SessionSettingsStore.outputFolderPathKey
        )
        XCTAssertNotEqual(
            SessionSettingsStore.sessionTitleKey,
            SessionSettingsStore.outputFolderPathKey
        )
        XCTAssertNotEqual(
            SessionSettingsStore.rememberedSourceKey,
            SessionSettingsStore.sessionTitleKey
        )
    }

    func testClearingSourceKeepsTitle() {
        let store = SessionSettingsStore(defaults: defaults)
        store.rememberedSource = RememberedSource(
            bundleIdentifier: "com.apple.Safari",
            name: "Safari"
        )
        store.sessionTitle = "Titre conservé"

        store.rememberedSource = nil

        let relaunch = SessionSettingsStore(defaults: defaults)
        XCTAssertNil(relaunch.rememberedSource)
        XCTAssertEqual(relaunch.sessionTitle, "Titre conservé")
    }

    // MARK: - Microphone mémorisé

    func testRememberedMicrophoneRestoresAcrossRelaunch() {
        let chrome = RememberedSource(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        let microphone = MicrophoneChoice.selected(
            uid: "AppleUSBAudioEngine:Micro:1234",
            name: "Micro USB"
        )
        let firstLaunch = SessionSettingsStore(defaults: defaults)
        firstLaunch.rememberedSource = chrome
        firstLaunch.rememberedMicrophone = microphone
        firstLaunch.sessionTitle = "Réunion"

        let restored = SessionSettingsStore(defaults: defaults).restore()

        XCTAssertEqual(
            restored,
            SessionSettings(rememberedSource: chrome, microphone: microphone, title: "Réunion")
        )
        XCTAssertEqual(SessionSettingsStore.rememberedMicrophoneKey, "naada.rememberedMicrophone")
    }

    func testSystemDefaultMicrophoneRoundTrips() {
        let store = SessionSettingsStore(defaults: defaults)
        store.rememberedMicrophone = .systemDefault

        XCTAssertEqual(SessionSettingsStore(defaults: defaults).rememberedMicrophone, .systemDefault)
    }

    func testClearingMicrophoneKeepsSourceAndTitle() {
        let safari = RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let store = SessionSettingsStore(defaults: defaults)
        store.rememberedSource = safari
        store.sessionTitle = "Titre conservé"
        store.rememberedMicrophone = .selected(uid: "uid-1", name: "Micro USB")

        store.rememberedMicrophone = .none

        XCTAssertNil(defaults.data(forKey: SessionSettingsStore.rememberedMicrophoneKey))
        let restored = SessionSettingsStore(defaults: defaults).restore()
        XCTAssertEqual(restored.microphone, .none)
        XCTAssertEqual(restored.rememberedSource, safari)
        XCTAssertEqual(restored.title, "Titre conservé")
    }

    func testFirstLoadWritesNoKeyAtAll() throws {
        let spy = try XCTUnwrap(WriteTrackingDefaults(suiteName: suiteName))
        let store = SessionSettingsStore(defaults: spy)

        let restored = store.restore()

        XCTAssertEqual(restored, SessionSettings())
        XCTAssertEqual(restored.microphone, .none)
        XCTAssertTrue(spy.writtenKeys.isEmpty, "un premier chargement ne doit écrire aucune clé")
        XCTAssertNil(spy.data(forKey: SessionSettingsStore.rememberedSourceKey))
        XCTAssertNil(spy.data(forKey: SessionSettingsStore.rememberedMicrophoneKey))
        XCTAssertNil(spy.string(forKey: SessionSettingsStore.sessionTitleKey))
    }

    func testWritingMicrophoneNeverTouchesLegacyFolderKey() {
        let savedFolder = "/tmp/naada-dossier-legacy"
        defaults.set(savedFolder, forKey: SessionSettingsStore.outputFolderPathKey)
        let store = SessionSettingsStore(defaults: defaults)

        store.rememberedSource = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        store.rememberedMicrophone = .systemDefault

        XCTAssertEqual(
            defaults.string(forKey: SessionSettingsStore.outputFolderPathKey),
            savedFolder
        )
        XCTAssertNotEqual(
            SessionSettingsStore.rememberedMicrophoneKey,
            SessionSettingsStore.rememberedSourceKey
        )
        XCTAssertNotEqual(
            SessionSettingsStore.rememberedMicrophoneKey,
            SessionSettingsStore.sessionTitleKey
        )
        XCTAssertNotEqual(
            SessionSettingsStore.rememberedMicrophoneKey,
            SessionSettingsStore.outputFolderPathKey
        )
    }

    private struct RunningSource {
        let pid: pid_t
        let bundleIdentifier: String?
        let name: String
    }

    private func liveSource(
        in running: [RunningSource],
        matching remembered: RememberedSource?
    ) -> RunningSource? {
        guard let remembered else { return nil }
        return running.first {
            remembered.matches(
                bundleIdentifier: $0.bundleIdentifier,
                name: $0.name
            )
        }
    }
}

/// UserDefaults de test qui retient toute clé écrite, pour prouver qu'un
/// premier chargement ne modifie rien.
private final class WriteTrackingDefaults: UserDefaults {
    private(set) var writtenKeys: [String] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        writtenKeys.append(defaultName)
        super.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        writtenKeys.append(defaultName)
        super.removeObject(forKey: defaultName)
    }
}
