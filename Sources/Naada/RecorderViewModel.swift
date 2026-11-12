import AppKit
import Foundation
import NaadaCore

@MainActor
final class RecorderViewModel: ObservableObject {
    static let shared = RecorderViewModel()

    @Published private(set) var applications: [SourceApplication] = []
    @Published var selectedApplicationPID: pid_t? {
        didSet {
            guard let application = selectedApplication else { return }
            let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || sessionTitle == lastSuggestedTitle {
                sessionTitle = application.name
                lastSuggestedTitle = application.name
            }
        }
    }
    @Published var sessionTitle: String = ""
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
    @Published var errorMessage: String?

    private static let outputFolderKey = "naada.outputFolderPath"

    private var ticker: Timer?
    private var engine: AudioCaptureEngine?
    private var sessionToken: UUID?
    private var lastSuggestedTitle = ""
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        restoreOutputFolder()
        refreshApplications()
        observeWorkspace()
    }

    deinit {
        ticker?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var selectedApplication: SourceApplication? {
        applications.first { $0.pid == selectedApplicationPID }
    }

    var phase: RecorderPhase {
        RecorderPhase(session.state)
    }

    var elapsedText: String {
        ElapsedFormatter.string(seconds: session.elapsed(at: now.timeIntervalSinceReferenceDate))
    }

    var canStart: Bool {
        !session.state.isBusy
            && selectedApplication != nil
            && outputFolder != nil
    }

    var canStop: Bool {
        session.state.isRecording
    }

    var isBusy: Bool {
        session.state.isBusy
    }

    func refreshApplications() {
        let previous = selectedApplicationPID
        applications = RunningApplicationCatalog.list()
        if let previous, applications.contains(where: { $0.pid == previous }) {
            selectedApplicationPID = previous
        } else if selectedApplicationPID != nil {
            selectedApplicationPID = nil
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"
        panel.message = "Dossier de destination des enregistrements MP3"
        panel.directoryURL = outputFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url
    }

    func startRecording() {
        guard canStart, let application = selectedApplication, let folder = outputFolder else {
            return
        }

        errorMessage = nil
        lastOutputURL = nil
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
            self.engine = engine

            Task {
                do {
                    try await engine.start(application: application, writer: writer)

                    // Un arrêt inattendu peut avoir été signalé pendant le
                    // démarrage. Ne jamais réécrire cet échec en « recording ».
                    guard self.engine === engine, sessionToken == token else {
                        _ = try? await engine.stop()
                        return
                    }
                    guard session.state == .preparing else {
                        if self.engine === engine {
                            self.engine = nil
                        }
                        if sessionToken == token {
                            sessionToken = nil
                        }
                        _ = try? await engine.stop()
                        return
                    }
                    guard engine.isCaptureActive else {
                        let message = engine.startupStopMessage
                            ?? "La capture ne s'est pas stabilisée pendant le démarrage."
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
                    now = Date()
                    startTicker()
                } catch {
                    guard sessionToken == token else { return }
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

        let token = sessionToken
        session.stopRequested(at: Date.timeIntervalSinceReferenceDate)
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
                    errorMessage = "Le fichier a été finalisé, mais l'arrêt de la capture signale : \(warning)"
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

        sessionToken = nil
        session.fail(
            error.localizedDescription,
            at: Date.timeIntervalSinceReferenceDate
        )
        now = Date()
        stopTicker()
        lastOutputURL = url
        errorMessage = "La capture s'est arrêtée : \(error.localizedDescription)"
            + (url == nil ? "" : " Le fichier partiel a été conservé.")
        engine = nil
    }

    private func handleAudioError(_ error: Error, token: UUID) {
        guard sessionToken == token, session.state.isRecording else { return }
        errorMessage = "Erreur d'écriture pendant la capture : \(error.localizedDescription)"
        stopRecording()
    }
}
