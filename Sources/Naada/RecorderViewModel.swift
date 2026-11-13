import AppKit
import Foundation
import NaadaCore

@MainActor
final class RecorderViewModel: ObservableObject {
    static let shared = RecorderViewModel()

    @Published private(set) var applications: [SourceApplication] = []
    @Published var selectedApplicationID: RememberedSource? {
        didSet {
            guard !isRestoringSettings else { return }

            settings.rememberedSource = selectedApplicationID
            applications.removeAll {
                !$0.isRunning && $0.rememberedSource != selectedApplicationID
            }

            guard let application = selectedApplication else { return }
            if let suggested = SessionTitlePolicy.suggestedTitle(
                currentTitle: sessionTitle,
                lastSuggestedTitle: lastSuggestedTitle,
                sourceName: application.name
            ) {
                sessionTitle = suggested
                lastSuggestedTitle = suggested
            }
        }
    }
    @Published var sessionTitle: String = "" {
        didSet {
            guard !isRestoringSettings else { return }
            settings.sessionTitle = sessionTitle
        }
    }
    @Published var outputFolder: URL? {
        didSet {
            if let outputFolder {
                UserDefaults.standard.set(outputFolder.path, forKey: Self.outputFolderKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.outputFolderKey)
            }
        }
    }
    @Published private(set) var session = RecordingSession()
    @Published private(set) var now = Date()
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var presets: [RecordingPreset] = []
    @Published var errorMessage: String?

    private static let outputFolderKey = SessionSettingsStore.outputFolderPathKey

    private let settings: SessionSettingsStore
    private let presetStore: RecordingPresetStore
    private var isRestoringSettings = false
    private var ticker: Timer?
    private var engine: AudioCaptureEngine?
    private var sessionToken: UUID?
    private var lastSuggestedTitle = ""
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Vrai dès le premier buffer non vide : la phase « enregistrement » ne
    /// s'affiche qu'après une réception réelle, jamais sur le seul démarrage
    /// matériel.
    private var hasReceivedAudio = false
    private var waitingForAudioTask: Task<Void, Never>?
    private var waitingWarningMessage: String?

    /// Délai borné avant d'expliquer qu'aucun son n'arrive. Ce n'est pas un
    /// arrêt automatique : l'utilisateur peut encore lancer la lecture.
    private static let firstAudioTimeout: TimeInterval = 8

    init(
        settings: SessionSettingsStore = SessionSettingsStore(),
        presetStore: RecordingPresetStore = RecordingPresetStore(),
        observesWorkspace: Bool = true
    ) {
        self.settings = settings
        self.presetStore = presetStore
        restoreOutputFolder()

        // La source et le titre restaurés sont posés avant la première liste
        // d'applications : la sélection retrouvée ne doit pas déclencher la
        // suggestion de titre.
        isRestoringSettings = true
        let restored = settings.restore()
        selectedApplicationID = restored.rememberedSource
        sessionTitle = restored.title
        refreshApplications()
        isRestoringSettings = false

        // Une première utilisation n'écrit rien : la liste vide ne remplace ni
        // la source, ni le titre, ni le dossier restaurés ci-dessus.
        presets = presetStore.load()

        if observesWorkspace {
            observeWorkspace()
        }
    }

    deinit {
        ticker?.invalidate()
        waitingForAudioTask?.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var selectedApplication: SourceApplication? {
        guard let selectedApplicationID else { return nil }
        return applications.first { $0.rememberedSource == selectedApplicationID }
    }

    /// La source ne peut être capturée que si un processus vivant correspond
    /// à l'identité mémorisée. Une source absente reste sélectionnée et
    /// visible, mais ne démarre rien.
    var selectedLiveApplication: SourceApplication? {
        guard let application = selectedApplication, application.isRunning else {
            return nil
        }
        return application
    }

    var phase: RecorderPhase {
        // Un démarrage matériel réussi n'est pas encore une capture : tant
        // qu'aucun buffer non vide n'est arrivé, l'interface reste en
        // « préparation » et la jauge ne s'anime pas. L'arrêt reste possible
        // car `canStop` suit l'état de la session, pas cette phase affichée.
        if session.state == .recording, !hasReceivedAudio {
            return .preparing
        }
        return RecorderPhase(session.state)
    }

    var elapsedText: String {
        ElapsedFormatter.string(seconds: session.elapsed(at: now.timeIntervalSinceReferenceDate))
    }

    var canStart: Bool {
        !session.state.isBusy
            && selectedLiveApplication != nil
            && outputFolder != nil
    }

    var canStop: Bool {
        session.state.isRecording
    }

    var isBusy: Bool {
        session.state.isBusy
    }

    /// Créer un preset exige une source sélectionnée. Le dossier reste
    /// facultatif : sans lui, le preset n'effacera pas le dossier courant.
    var canSavePreset: Bool {
        !isBusy && selectedApplicationID != nil
    }

    var currentConfiguration: RecordingConfiguration {
        RecordingConfiguration(
            source: selectedApplicationID,
            title: sessionTitle,
            folderPath: outputFolder?.path
        )
    }

    func refreshApplications() {
        applications = RunningApplicationCatalog.list(
            remembering: selectedApplicationID
        )
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Choose", comment: "Open panel choose button")
        panel.message = NSLocalizedString(
            "Destination folder for MP3 recordings",
            comment: "Open panel message"
        )
        panel.directoryURL = outputFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url
    }

    // MARK: - Presets

    /// Enregistre la configuration courante sous un nom. Un dossier absent
    /// reste absent du preset, sans jamais modifier le dossier hors preset.
    @discardableResult
    func createPreset(named name: String) -> RecordingPreset? {
        guard canSavePreset,
              let source = selectedApplicationID,
              let preset = presetStore.create(
                  name: name,
                  source: source,
                  title: sessionTitle,
                  folderPath: outputFolder?.path
              )
        else {
            return nil
        }

        presets = presetStore.load()
        return preset
    }

    /// Applique un preset aux trois réglages visibles. Une source fermée
    /// reste sélectionnée et visible ; aucun enregistrement ne démarre.
    func applyPreset(_ preset: RecordingPreset) {
        guard !isBusy else { return }

        let applied = preset.applied(to: currentConfiguration)
        selectedApplicationID = applied.source
        refreshApplications()
        sessionTitle = applied.title

        if let folderPath = applied.folderPath,
           folderPath != outputFolder?.path {
            outputFolder = URL(fileURLWithPath: folderPath, isDirectory: true)
        }
    }

    @discardableResult
    func renamePreset(id: UUID, to name: String) -> Bool {
        guard !isBusy, presetStore.rename(id: id, to: name) != nil else {
            return false
        }
        presets = presetStore.load()
        return true
    }

    /// Remplace les champs du preset par la configuration courante, en
    /// conservant son nom et son identifiant.
    @discardableResult
    func updatePreset(id: UUID) -> Bool {
        guard !isBusy,
              let source = selectedApplicationID,
              var updated = presets.first(where: { $0.id == id })
        else {
            return false
        }

        updated.source = source
        updated.title = sessionTitle
        updated.folderPath = outputFolder?.path

        guard presetStore.update(updated) != nil else { return false }
        presets = presetStore.load()
        return true
    }

    @discardableResult
    func deletePreset(id: UUID) -> Bool {
        guard !isBusy, presetStore.delete(id: id) else { return false }
        presets = presetStore.load()
        return true
    }

    func startRecording() {
        guard canStart,
              let application = selectedLiveApplication,
              let folder = outputFolder
        else {
            return
        }

        errorMessage = nil
        lastOutputURL = nil
        hasReceivedAudio = false
        waitingWarningMessage = nil
        waitingForAudioTask?.cancel()
        waitingForAudioTask = nil
        resetAudioLevel()
        session.beginPreparation(at: Date.timeIntervalSinceReferenceDate)

        let token = UUID()
        sessionToken = token
        let startDate = Date()

        do {
            let writer = try MP3FileWriter(
                folder: folder,
                date: startDate,
                title: sessionTitle
            )
            let engine = AudioCaptureEngine()
            engine.onUnexpectedStop = { [weak self] error, url in
                Task { @MainActor in
                    self?.handleUnexpectedStop(error: error, url: url, token: token)
                }
            }
            engine.onAudioError = { [weak self] error in
                Task { @MainActor in
                    self?.handleAudioError(error, token: token)
                }
            }
            engine.onAudioLevel = { [weak self] level in
                Task { @MainActor in
                    self?.handleAudioLevel(level, token: token)
                }
            }
            self.engine = engine

            Task {
                do {
                    try await engine.start(application: application, writer: writer)

                    // Un arrêt inattendu peut avoir été signalé pendant le
                    // démarrage. Ne jamais réécrire cet échec en « recording ».
                    guard self.engine === engine, sessionToken == token else {
                        resetWaitingForAudio()
                        _ = try? await engine.stop()
                        return
                    }
                    guard session.state == .preparing else {
                        if self.engine === engine {
                            self.engine = nil
                        }
                        if sessionToken == token {
                            resetAudioLevel()
                            resetWaitingForAudio()
                            sessionToken = nil
                        }
                        _ = try? await engine.stop()
                        return
                    }
                    guard engine.isCaptureActive else {
                        let message = engine.startupStopMessage
                            ?? NSLocalizedString(
                                "Capture did not stabilize during startup.",
                                comment: "Capture startup failure"
                            )
                        resetAudioLevel()
                        resetWaitingForAudio()
                        sessionToken = nil
                        self.engine = nil
                        session.fail(
                            message,
                            at: Date.timeIntervalSinceReferenceDate
                        )
                        errorMessage = message
                        _ = try? await engine.stop()
                        return
                    }

                    session.captureStarted(at: Date.timeIntervalSinceReferenceDate)
                    // Un buffer peut être arrivé pendant le démarrage, avant
                    // que la session ne soit « recording » : son niveau a été
                    // filtré, mais l'état du moteur, lui, est déjà en
                    // réception.
                    hasReceivedAudio = engine.isReceivingAudio
                    now = Date()
                    startTicker()
                    startWaitingForAudioWatchdog(
                        engine: engine,
                        application: application,
                        token: token
                    )
                } catch {
                    guard sessionToken == token else { return }
                    resetAudioLevel()
                    resetWaitingForAudio()
                    sessionToken = nil
                    if self.engine === engine {
                        self.engine = nil
                    }
                    session.fail(
                        error.localizedDescription,
                        at: Date.timeIntervalSinceReferenceDate
                    )
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            resetAudioLevel()
            resetWaitingForAudio()
            sessionToken = nil
            session.fail(
                error.localizedDescription,
                at: Date.timeIntervalSinceReferenceDate
            )
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard session.state.isRecording, let engine else { return }

        // Remise à zéro immédiate : la jauge ne doit pas rester figée sur la
        // dernière mesure pendant la finalisation, ni après un arrêt en erreur.
        resetAudioLevel()
        let token = sessionToken
        session.stopRequested(at: Date.timeIntervalSinceReferenceDate)
        resetWaitingForAudio()
        now = Date()
        stopTicker()

        Task {
            do {
                let result = try await engine.stop()
                lastOutputURL = result.url
                self.engine = nil
                if sessionToken == token {
                    sessionToken = nil
                }
                session.finalized()
                if let warning = result.warning {
                    errorMessage = String(
                        format: NSLocalizedString(
                            "The file was finalized, but stopping the capture reported: %@",
                            comment: "Stop warning after finalizing"
                        ),
                        warning
                    )
                }
            } catch {
                self.engine = nil
                if sessionToken == token {
                    sessionToken = nil
                }
                session.fail(
                    error.localizedDescription,
                    at: Date.timeIntervalSinceReferenceDate
                )
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealLastOutput() {
        guard let lastOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
    }

    // MARK: - Private

    private func restoreOutputFolder() {
        guard let path = UserDefaults.standard.string(forKey: Self.outputFolderKey) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return
        }
        outputFolder = URL(fileURLWithPath: path, isDirectory: true)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.phase.isBusy else { return }
                    self.refreshApplications()
                }
            }
            workspaceObservers.append(observer)
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func handleUnexpectedStop(error: Error, url: URL?, token: UUID) {
        guard sessionToken == token else { return }
        guard session.state.isRecording || session.state == .preparing else { return }

        resetAudioLevel()
        resetWaitingForAudio()
        sessionToken = nil
        session.fail(
            error.localizedDescription,
            at: Date.timeIntervalSinceReferenceDate
        )
        now = Date()
        stopTicker()
        lastOutputURL = url
        var message = String(
            format: NSLocalizedString("Capture stopped: %@", comment: "Unexpected capture stop"),
            error.localizedDescription
        )
        if url != nil {
            message += " " + NSLocalizedString(
                "The partial file was kept.",
                comment: "Unexpected capture stop with kept partial file"
            )
        }
        errorMessage = message
        engine = nil
    }

    private func handleAudioError(_ error: Error, token: UUID) {
        guard sessionToken == token, session.state.isRecording else { return }
        errorMessage = String(
            format: NSLocalizedString(
                "Write error during capture: %@",
                comment: "Audio write error during capture"
            ),
            error.localizedDescription
        )
        stopRecording()
    }

    private func handleAudioLevel(_ level: Float, token: UUID) {
        // Un callback déjà en file après l'arrêt ne doit jamais rallumer la
        // jauge : le jeton et l'état « recording » filtrent ces mesures.
        guard sessionToken == token, session.state.isRecording else { return }

        // Un buffer non vide, même silencieux, établit la réception : le
        // silence numérique n'est pas une absence de source.
        if !hasReceivedAudio {
            hasReceivedAudio = true
            waitingForAudioTask?.cancel()
            waitingForAudioTask = nil
            if let warning = waitingWarningMessage, errorMessage == warning {
                errorMessage = nil
            }
            waitingWarningMessage = nil
        }

        audioLevel = min(1, max(0, level))
    }

    /// Explique, une seule fois et sans arrêter la capture, pourquoi aucun
    /// son n'arrive encore. Aucun repli global ou helper n'est tenté.
    private func startWaitingForAudioWatchdog(
        engine: AudioCaptureEngine,
        application: SourceApplication,
        token: UUID
    ) {
        waitingForAudioTask?.cancel()
        waitingForAudioTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.firstAudioTimeout * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            guard
                self.sessionToken == token,
                self.engine === engine,
                self.session.state.isRecording
            else {
                return
            }

            // Le moteur peut déjà être en réception si le callback de niveau a
            // été filtré pendant le démarrage : ne jamais afficher un faux
            // avertissement dans ce cas.
            if engine.isReceivingAudio {
                self.hasReceivedAudio = true
                return
            }
            guard !self.hasReceivedAudio, engine.isWaitingForAudio else {
                return
            }

            let message: String
            if engine.selectedProcessIsProducingOutput() == false {
                message = String(
                    format: NSLocalizedString(
                        "Naada is not receiving audio from “%@”. The selected process is not playing sound. Start playback and check that the application is not muted.",
                        comment: "No audio from the selected process"
                    ),
                    application.name
                )
            } else {
                message = String(
                    format: NSLocalizedString(
                        "No audio has arrived from “%@” yet. Start playback and check that the application is not muted. Naada also captures the application's audio helper processes.",
                        comment: "No audio yet from the selected application"
                    ),
                    application.name
                )
            }

            self.waitingWarningMessage = message
            self.errorMessage = message
        }
    }

    private func resetAudioLevel() {
        audioLevel = 0
    }

    private func resetWaitingForAudio() {
        hasReceivedAudio = false
        waitingWarningMessage = nil
        waitingForAudioTask?.cancel()
        waitingForAudioTask = nil
    }
}
