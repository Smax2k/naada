import Foundation
import XCTest
@testable import NaadaCore

final class RecordingPresetTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "naada.recording-presets.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testFirstUseWithEmptyListLeavesSettingsAndFolderUntouched() {
        let source = RememberedSource(
            bundleIdentifier: "com.apple.Safari",
            name: "Safari"
        )
        let settings = SessionSettingsStore(defaults: defaults)
        settings.rememberedSource = source
        settings.sessionTitle = "Réglage existant"
        defaults.set("/tmp/naada-dossier-existant", forKey: SessionSettingsStore.outputFolderPathKey)

        let store = RecordingPresetStore(defaults: defaults)

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(settings.restore(), SessionSettings(rememberedSource: source, title: "Réglage existant"))
        XCTAssertEqual(
            defaults.string(forKey: SessionSettingsStore.outputFolderPathKey),
            "/tmp/naada-dossier-existant"
        )
        XCTAssertNil(defaults.data(forKey: RecordingPresetStore.presetsKey))
    }

    func testCreatePersistsSourceTitleAndFolderAcrossRelaunch() throws {
        let source = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        let firstLaunch = RecordingPresetStore(defaults: defaults)
        let created = try XCTUnwrap(
            firstLaunch.create(
                name: "  Réunion budget  ",
                source: source,
                title: "Budget 2027",
                folderPath: "/tmp/naada-preset-budget"
            )
        )

        let relaunch = RecordingPresetStore(defaults: defaults)
        let restored = try XCTUnwrap(relaunch.load().first)

        XCTAssertEqual(restored, created)
        XCTAssertEqual(restored.name, "Réunion budget")
        XCTAssertEqual(restored.source, source)
        XCTAssertEqual(restored.title, "Budget 2027")
        XCTAssertEqual(restored.folderPath, "/tmp/naada-preset-budget")
    }

    func testApplyingPresetReplacesSourceTitleAndFolder() throws {
        let chrome = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        let preset = try XCTUnwrap(
            RecordingPresetStore(defaults: defaults).create(
                name: "Chrome",
                source: chrome,
                title: "Cours du mardi",
                folderPath: "/tmp/naada-preset-cours"
            )
        )

        let current = RecordingConfiguration(
            source: RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari"),
            title: "Titre courant",
            folderPath: "/tmp/naada-dossier-courant"
        )
        let applied = preset.applied(to: current)

        XCTAssertEqual(applied.source, chrome)
        XCTAssertEqual(applied.title, "Cours du mardi")
        XCTAssertEqual(applied.folderPath, "/tmp/naada-preset-cours")
    }

    func testApplyingPresetWithoutFolderKeepsCurrentFolder() throws {
        let preset = try XCTUnwrap(
            RecordingPresetStore(defaults: defaults).create(
                name: "Sans dossier",
                source: RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                title: "Titre du preset",
                folderPath: nil
            )
        )

        let applied = preset.applied(
            to: RecordingConfiguration(
                title: "Ancien titre",
                folderPath: "/tmp/naada-dossier-hors-preset"
            )
        )

        XCTAssertEqual(applied.title, "Titre du preset")
        XCTAssertEqual(
            applied.folderPath,
            "/tmp/naada-dossier-hors-preset",
            "un preset sans dossier ne doit jamais effacer le dossier courant"
        )
    }

    func testApplyingPresetKeepsSourceIdentityWhileApplicationIsClosed() throws {
        let chrome = RememberedSource(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome"
        )
        let preset = try XCTUnwrap(
            RecordingPresetStore(defaults: defaults).create(
                name: "Chrome fermé",
                source: chrome,
                title: "Notes",
                folderPath: nil
            )
        )

        let applied = preset.applied(to: RecordingConfiguration())
        let runningSources: [(String?, String)] = []
        let live = runningSources.first {
            chrome.matches(bundleIdentifier: $0.0, name: $0.1)
        }

        XCTAssertEqual(applied.source, chrome)
        XCTAssertNil(live)
        XCTAssertTrue(applied.source?.matches(bundleIdentifier: "com.google.Chrome", name: "Google Chrome") == true)
    }

    func testRenamePersistsAndKeepsOtherFields() throws {
        let source = RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let store = RecordingPresetStore(defaults: defaults)
        let created = try XCTUnwrap(
            store.create(
                name: "Ancien nom",
                source: source,
                title: "Titre",
                folderPath: "/tmp/naada-preset-renomme"
            )
        )

        let renamed = try XCTUnwrap(store.rename(id: created.id, to: "  Nouveau nom  "))
        let relaunch = RecordingPresetStore(defaults: defaults)
        let restored = try XCTUnwrap(relaunch.load().first)

        XCTAssertEqual(renamed.id, created.id)
        XCTAssertEqual(restored.name, "Nouveau nom")
        XCTAssertEqual(restored.source, source)
        XCTAssertEqual(restored.title, "Titre")
        XCTAssertEqual(restored.folderPath, "/tmp/naada-preset-renomme")
    }

    func testUpdateEditsSourceTitleAndFolderAndPersists() throws {
        let store = RecordingPresetStore(defaults: defaults)
        var preset = try XCTUnwrap(
            store.create(
                name: "À modifier",
                source: RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                title: "Titre initial",
                folderPath: "/tmp/naada-preset-initial"
            )
        )

        preset.name = "Modifié"
        preset.source = RememberedSource(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        preset.title = "Titre modifié"
        preset.folderPath = "/tmp/naada-preset-modifie"
        let updated = try XCTUnwrap(store.update(preset))

        let restored = try XCTUnwrap(RecordingPresetStore(defaults: defaults).load().first)
        XCTAssertEqual(restored, updated)
        XCTAssertEqual(restored.id, preset.id)
        XCTAssertEqual(restored.name, "Modifié")
        XCTAssertEqual(restored.source?.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(restored.title, "Titre modifié")
        XCTAssertEqual(restored.folderPath, "/tmp/naada-preset-modifie")
    }

    func testDeleteRemovesOnlySelectedPresetAndPersists() throws {
        let store = RecordingPresetStore(defaults: defaults)
        let first = try XCTUnwrap(
            store.create(
                name: "Premier",
                source: RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                title: "Un",
                folderPath: nil
            )
        )
        let second = try XCTUnwrap(
            store.create(
                name: "Second",
                source: RememberedSource(bundleIdentifier: "com.google.Chrome", name: "Google Chrome"),
                title: "Deux",
                folderPath: "/tmp/naada-preset-second"
            )
        )

        XCTAssertTrue(store.delete(id: first.id))

        let restored = RecordingPresetStore(defaults: defaults).load()
        XCTAssertEqual(restored.map(\.id), [second.id])
        XCTAssertEqual(restored.first?.name, "Second")
        XCTAssertFalse(store.delete(id: first.id), "une seconde suppression ne doit rien changer")
    }

    func testBlankNameIsRejectedWithoutWriting() {
        let store = RecordingPresetStore(defaults: defaults)
        let source = RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari")

        XCTAssertNil(store.create(name: "   ", source: source, title: "Titre", folderPath: nil))
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(defaults.data(forKey: RecordingPresetStore.presetsKey))
    }

    func testStoreNeverTouchesLegacyOutputFolderKey() throws {
        let savedFolder = "/tmp/naada-dossier-legacy"
        defaults.set(savedFolder, forKey: SessionSettingsStore.outputFolderPathKey)
        let store = RecordingPresetStore(defaults: defaults)
        let preset = try XCTUnwrap(
            store.create(
                name: "Preset",
                source: RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                title: "Titre",
                folderPath: "/tmp/naada-preset-propre"
            )
        )

        store.rename(id: preset.id, to: "Preset renommé")
        store.delete(id: preset.id)

        XCTAssertEqual(RecordingPresetStore.presetsKey, "naada.recordingPresets")
        XCTAssertNotEqual(RecordingPresetStore.presetsKey, SessionSettingsStore.outputFolderPathKey)
        XCTAssertEqual(
            defaults.string(forKey: SessionSettingsStore.outputFolderPathKey),
            savedFolder,
            "le magasin de presets ne doit jamais réécrire la clé historique du dossier"
        )
    }

    // MARK: - Presets relus depuis une version antérieure

    func testLegacyPresetWithoutMicrophoneReadsWithNone() throws {
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"Ancien preset","source":{"bundleIdentifier":"com.apple.Safari","name":"Safari"},"title":"Titre ancien","folderPath":"/tmp/naada-preset-ancien"}]
        """
        defaults.set(Data(json.utf8), forKey: RecordingPresetStore.presetsKey)

        let presets = RecordingPresetStore(defaults: defaults).load()

        XCTAssertEqual(presets.count, 1)
        let preset = try XCTUnwrap(presets.first)
        XCTAssertEqual(preset.id, id)
        XCTAssertEqual(preset.name, "Ancien preset")
        XCTAssertEqual(
            preset.source,
            RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari")
        )
        XCTAssertEqual(preset.microphone, .none)
        XCTAssertEqual(preset.title, "Titre ancien")
        XCTAssertEqual(preset.folderPath, "/tmp/naada-preset-ancien")
    }

    func testLegacyPresetWithoutSourceKeepsTitleAndFolder() throws {
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"Sans application","title":"Titre conservé","folderPath":"/tmp/naada-preset-sans-source"}]
        """
        defaults.set(Data(json.utf8), forKey: RecordingPresetStore.presetsKey)

        let presets = RecordingPresetStore(defaults: defaults).load()

        XCTAssertEqual(presets.count, 1, "un preset sans source ne doit pas faire perdre la liste")
        let preset = try XCTUnwrap(presets.first)
        XCTAssertNil(preset.source)
        XCTAssertEqual(preset.microphone, .none)
        XCTAssertEqual(preset.title, "Titre conservé")
        XCTAssertEqual(preset.folderPath, "/tmp/naada-preset-sans-source")
    }

    func testCreateDefaultsToNoSourceAndNoMicrophone() throws {
        let store = RecordingPresetStore(defaults: defaults)
        let created = try XCTUnwrap(
            store.create(name: "Micro seul", title: "Titre", folderPath: nil)
        )

        XCTAssertNil(created.source)
        XCTAssertEqual(created.microphone, .none)

        let restored = try XCTUnwrap(RecordingPresetStore(defaults: defaults).load().first)
        XCTAssertNil(restored.source)
        XCTAssertEqual(restored.microphone, .none)
        XCTAssertEqual(restored.title, "Titre")
    }

    func testCreatePersistsMicrophoneAcrossRelaunch() throws {
        let microphone = MicrophoneChoice.selected(
            uid: "AppleUSBAudioEngine:Micro:1234",
            name: "Micro USB"
        )
        let created = try XCTUnwrap(
            RecordingPresetStore(defaults: defaults).create(
                name: "Micro USB",
                microphone: microphone,
                title: "Voix",
                folderPath: "/tmp/naada-preset-micro"
            )
        )

        let restored = try XCTUnwrap(RecordingPresetStore(defaults: defaults).load().first)

        XCTAssertEqual(restored, created)
        XCTAssertNil(restored.source)
        XCTAssertEqual(restored.microphone, microphone)
        XCTAssertEqual(restored.configuration.microphone, microphone)
    }

    func testApplyingPresetReplacesSourceAndMicrophone() throws {
        let usbMicrophone = MicrophoneChoice.selected(
            uid: "AppleUSBAudioEngine:Micro:1234",
            name: "Micro USB"
        )
        let preset = try XCTUnwrap(
            RecordingPresetStore(defaults: defaults).create(
                name: "Micro seul",
                microphone: usbMicrophone,
                title: "Voix du preset",
                folderPath: nil
            )
        )

        let applied = preset.applied(
            to: RecordingConfiguration(
                source: RememberedSource(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                microphone: .systemDefault,
                title: "Ancien titre",
                folderPath: "/tmp/naada-dossier-courant"
            )
        )

        XCTAssertNil(applied.source, "une source absente du preset doit effacer la source courante")
        XCTAssertEqual(applied.microphone, usbMicrophone)
        XCTAssertEqual(applied.title, "Voix du preset")
        XCTAssertEqual(applied.folderPath, "/tmp/naada-dossier-courant")
    }

    func testApplyingPresetWithNoMicrophoneClearsCurrentMicrophone() throws {
        let chrome = RememberedSource(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        let preset = try XCTUnwrap(
            RecordingPresetStore(defaults: defaults).create(
                name: "Application seule",
                source: chrome,
                title: "Écran",
                folderPath: nil
            )
        )

        let applied = preset.applied(
            to: RecordingConfiguration(
                microphone: .selected(uid: "AppleUSBAudioEngine:Micro:1234", name: "Micro USB")
            )
        )

        XCTAssertEqual(applied.source, chrome)
        XCTAssertEqual(applied.microphone, .none, "le microphone du preset remplace toujours le courant")
    }
}
