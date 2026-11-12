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
