import AVFoundation
import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import NaadaCore
import os

enum AudioCaptureEngineError: Error, LocalizedError {
    case sourceApplicationNotFound(String)
    case unsupportedSystemVersion
    case invalidTapConfiguration([ProcessTapConstraints.Violation])
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case tapFormatUnavailable(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case captureStartFailed(OSStatus)
    case notRecording
    case captureAlreadyRunning
    case audioConversionFailed
    case missingWriter
    case noSourceSelected
    case microphonePermissionDenied
    case selectedMicrophoneUnavailable
    case microphoneOpenFailed
    case microphoneFormatUnavailable
    case microphoneStartFailed

    var errorDescription: String? {
        switch self {
        case let .sourceApplicationNotFound(name):
            return String(
                format: NSLocalizedString(
                    "The application “%@” no longer exposes a capturable audio process. Please select it again.",
                    comment: "Audio tap source application error"
                ),
                name
            )
        case .unsupportedSystemVersion:
            return NSLocalizedString(
                "Process-tap audio capture requires macOS 14.2 or later.",
                comment: "Audio tap minimum system version error"
            )
        case let .invalidTapConfiguration(violations):
            let reasons = violations.map(\.rawValue).joined(separator: ", ")
            return String(
                format: NSLocalizedString(
                    "The audio tap configuration was rejected (%@).",
                    comment: "Audio tap configuration error"
                ),
                reasons
            )
        case let .tapCreationFailed(status):
            return String(
                format: NSLocalizedString(
                    "The application's audio tap could not be created (error %d).",
                    comment: "Audio tap creation error"
                ),
                status
            )
        case let .aggregateCreationFailed(status):
            return String(
                format: NSLocalizedString(
                    "The private audio aggregate could not be created (error %d).",
                    comment: "Audio aggregate creation error"
                ),
                status
            )
        case let .tapFormatUnavailable(status):
            return String(
                format: NSLocalizedString(
                    "The tap's audio format could not be read (error %d).",
                    comment: "Audio tap format error"
                ),
                status
            )
        case let .ioProcCreationFailed(status):
            return String(
                format: NSLocalizedString(
                    "The aggregate audio listener could not be created (error %d).",
                    comment: "Audio IOProc creation error"
                ),
                status
            )
        case let .captureStartFailed(status):
            return String(
                format: NSLocalizedString(
                    "Audio capture could not start (error %d).",
                    comment: "Audio capture start error"
                ),
                status
            )
        case .notRecording:
            return NSLocalizedString("No capture is in progress.", comment: "Audio engine not recording error")
        case .captureAlreadyRunning:
            return NSLocalizedString("A capture is already running in this engine.", comment: "Audio engine already running error")
        case .audioConversionFailed:
            return NSLocalizedString("An audio sample could not be converted to PCM.", comment: "Audio conversion error")
        case .missingWriter:
            return NSLocalizedString("The output MP3 file is no longer available.", comment: "Missing MP3 writer error")
        case .noSourceSelected:
            return NSLocalizedString(
                "Select an application, a microphone, or both before recording.",
                comment: "Missing capture source error"
            )
        case .microphonePermissionDenied:
            return NSLocalizedString(
                "Microphone access is not allowed. Allow it in System Settings, then try again.",
                comment: "Microphone permission denied error"
            )
        case .selectedMicrophoneUnavailable:
            return NSLocalizedString(
                "The selected microphone is no longer available.",
                comment: "Selected microphone unavailable error"
            )
        case .microphoneOpenFailed:
            return NSLocalizedString(
                "The microphone could not be opened.",
                comment: "Microphone opening error"
            )
        case .microphoneFormatUnavailable:
            return NSLocalizedString(
                "The microphone's audio format could not be read.",
                comment: "Microphone format error"
            )
        case .microphoneStartFailed:
            return NSLocalizedString(
                "The microphone could not start capturing audio.",
                comment: "Microphone start error"
            )
        }
    }
}

struct CaptureStopResult {
    let url: URL
    let warning: String?
}

/// Ressources Core Audio d'un tap prêt à démarrer, ou déjà démarré.
private struct CaptureResources {
    let tapID: AudioObjectID
    let aggregateID: AudioObjectID
    let ioProcID: AudioDeviceIOProcID
    let processObjectIDs: [AudioObjectID]
    let helperPIDs: [pid_t]
}

/// Identifiants à détruire, sans le convertisseur propre à chaque IOProc.
private struct CaptureEndpoints {
    let tapID: AudioObjectID
    let aggregateID: AudioObjectID
    let ioProcID: AudioDeviceIOProcID
}

/// Capture l'audio d'une application, d'un microphone, ou des deux.
///
/// Choix de conception :
/// - le PID choisi est la racine ; seuls ses descendants dont la commande
///   désigne le service audio sont ajoutés, après vérification du plan pur ;
/// - le tap est privé et `CATapUnmuted` : le son continue d'aller vers la
///   sortie système, sans coupure ni redirection ;
/// - l'agrégat qui porte le tap est privé et n'est jamais défini comme sortie
///   par défaut ; seule son entrée est lue par un IOProc, comme un micro ;
/// - le microphone n'est ouvert que s'il est choisi, après la permission
///   demandée au démarrage ; sans micro, aucune entrée n'est touchée ;
/// - quand les deux sources sont actives, elles sont converties séparément,
///   additionnées par `PCMMix`, et seul le résultat est écrit et mesuré ;
/// - aucun écran, aucune fenêtre et aucune image ne sont demandés ;
/// - le pipeline MP3 et la jauge restent inchangés.
final class AudioCaptureEngine {
    var onUnexpectedStop: ((Error, URL?) -> Void)?
    var onAudioError: ((Error) -> Void)?
    /// Niveau RMS normalisé [0, 1], appelé sur la file audio au plus 10 fois
    /// par seconde. Aucun envoi n'est planifié : seuls les échantillons réels
    /// déclenchent une mesure.
    var onAudioLevel: ((Float) -> Void)?

    private let audioQueue = DispatchQueue(
        label: "com.naada.audio-pipeline",
        qos: .userInitiated
    )
    private let lifecycleQueue = DispatchQueue(label: "com.naada.capture-lifecycle")

    // État du pipeline audio : accès exclusivement sur audioQueue.
    private var writer: MP3FileWriter?
    private var reportedAudioError = false
    private var lastAudioLevelSentAt: TimeInterval = 0

    // Capture du microphone et mélange : accès exclusivement sur audioQueue.
    private var microphoneCapture: MicrophoneCapture?
    private var isMicrophoneCaptureActive = false
    /// Vrai seulement quand l'application et le microphone sont tous deux
    /// capturés. Les échantillons des deux sources passent alors par
    /// `PCMMix` ; sinon le flux unique va directement au writer.
    private var mixingEnabled = false
    private var applicationPendingSamples: [Int16] = []
    private var microphonePendingSamples: [Int16] = []

    /// Jeton du cycle courant pour la note « premier buffer » du micro. Il
    /// suit la génération acceptée, y compris après un remplacement de tap,
    /// et vaut 0 hors capture micro.
    private let microphoneCycleGeneration = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    /// Intervalle minimal entre deux mesures publiées : 10 envois par seconde
    /// au plus, avant tout saut vers le MainActor.
    private static let audioLevelInterval: TimeInterval = 0.1

    /// Au-delà de cette attente sans contrepartie (100 ms de stéréo 48 kHz),
    /// les échantillons d'un seul flux sont écrits avec du silence : la
    /// latence et la mémoire restent bornées sans perdre de son.
    private static let maximumUnpairedSamples = 9_600

    // Cycle de vie du tap : accès exclusivement sur lifecycleQueue.
    private var tapID: AudioObjectID?
    private var aggregateID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var lifecycle = CaptureLifecycleState()
    private var unexpectedStopError: Error?
    private var requestedRootPID: pid_t?
    private var rootIsTranslated = false
    private var tappedPIDs: [pid_t] = []
    private var untranslatedPIDs: [pid_t] = []
    private var selectedApplicationName: String?
    private var selectedProcessObjectIDs: [AudioObjectID] = []
    private var selectedHelperPIDs: [pid_t] = []
    private var captureGeneration: UInt64 = 0
    /// Un seul rafraîchissement du plan est tenté pendant l'attente du premier
    /// buffer : un helper audio peut apparaître au moment où la lecture
    /// démarre. Une fois consommé, aucun autre tap n'est créé.
    private var didRetryForAudioHelper = false
    private var helperRefreshTask: Task<Void, Never>?
    /// Génération acceptée par le callback audio. Verrou court : le callback
    /// ne prend jamais lifecycleQueue en synchrone. Un buffer d'un tap
    /// remplacé porte une autre génération et ne peut ni établir la réception
    /// ni écrire dans le writer.
    private let activeGeneration = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    /// Jeton du cycle qui a livré son premier buffer non vide. Un buffer
    /// retardé d'un cycle précédent porte un autre jeton et ne peut pas
    /// établir la réception du suivant.
    private let firstBufferGeneration = OSAllocatedUnfairLock<UInt64?>(initialState: nil)

    /// Fenêtre bornée de recherche d'un helper audio apparu après le démarrage.
    private static let helperRefreshWindow: TimeInterval = 8
    private static let helperRefreshInterval: UInt64 = 500_000_000

    deinit {
        helperRefreshTask?.cancel()
    }

    /// Chemin application seule, utilisé par la sonde : aucune permission
    /// microphone n'est demandée et aucune entrée audio n'est ouverte.
    func start(application: SourceApplication, writer: MP3FileWriter) async throws {
        try await startCapture(
            application: application,
            microphone: .none,
            writer: writer
        )
    }

    /// Démarre l'application choisie, le microphone choisi, ou les deux.
    ///
    /// La permission microphone n'est demandée qu'ici, au moment de l'appel,
    /// donc après le clic sur Enregistrer. Un refus échoue le démarrage et
    /// annule le fichier : aucun MP3 vide n'est laissé.
    func start(
        application: SourceApplication?,
        microphone: MicrophoneChoice,
        writer: MP3FileWriter
    ) async throws {
        guard application != nil || microphone != .none else {
            writer.cancel()
            throw AudioCaptureEngineError.noSourceSelected
        }
        try await startCapture(
            application: application,
            microphone: microphone,
            writer: writer
        )
    }

    private func startCapture(
        application: SourceApplication?,
        microphone: MicrophoneChoice,
        writer: MP3FileWriter
    ) async throws {
        let canStart = lifecycleQueue.sync { () -> UInt64? in
            let available = tapID == nil
                && aggregateID == nil
                && ioProcID == nil
            guard available, lifecycle.beginStart() else { return nil }
            unexpectedStopError = nil
            requestedRootPID = nil
            rootIsTranslated = false
            tappedPIDs = []
            untranslatedPIDs = []
            selectedApplicationName = nil
            selectedProcessObjectIDs = []
            selectedHelperPIDs = []
            didRetryForAudioHelper = false
            helperRefreshTask?.cancel()
            helperRefreshTask = nil
            activeGeneration.withLock { $0 = 0 }
            microphoneCycleGeneration.withLock { $0 = 0 }
            captureGeneration &+= 1
            return captureGeneration
        }

        guard let generation = canStart else {
            writer.cancel()
            throw AudioCaptureEngineError.captureAlreadyRunning
        }

        do {
            guard #available(macOS 14.2, *) else {
                throw AudioCaptureEngineError.unsupportedSystemVersion
            }

            // Permission et préparation du micro : uniquement sur ce chemin,
            // donc au moment du clic sur Enregistrer. Le chemin application
            // seule n'y entre jamais.
            var preparedMicrophone: MicrophoneCapture?
            if microphone != .none {
                try await Self.requestMicrophonePermission()
                let prepared = try makeMicrophoneCapture(choice: microphone)
                preparedMicrophone = prepared
                audioQueue.sync {
                    self.microphoneCapture = prepared
                }
            }
            let usesMicrophone = preparedMicrophone != nil

            var resources: CaptureResources?
            var selection: ApplicationAudioTapSelection?
            if let application {
                guard let pid = application.pid, pid > 0 else {
                    throw AudioCaptureEngineError.sourceApplicationNotFound(application.name)
                }

                // Le plan est recalculé à chaque démarrage : le PID choisi
                // reste la racine, seuls ses descendants audio vérifiés sont
                // ajoutés. Aucun bundle ID, aucun helper trouvé hors de
                // l'arbre, aucun repli.
                let plan = ApplicationAudioProcesses.plan(
                    rootPID: pid,
                    processes: LiveProcessTable.snapshot()
                )
                let tapSelection = ApplicationAudioTapSelection(
                    plan: plan,
                    translatedObjectIDs: Self.translatedObjectIDs(for: plan)
                )
                guard tapSelection.isUsable else {
                    throw AudioCaptureEngineError.sourceApplicationNotFound(application.name)
                }
                let constraints = tapSelection.constraints

                do {
                    try constraints.validate()
                } catch let error as ProcessTapConstraintError {
                    throw AudioCaptureEngineError.invalidTapConfiguration(error.violations)
                }

                let created = try await createResources(
                    applicationName: application.name,
                    constraints: constraints,
                    helperPIDs: tapSelection.translatedHelpers.map(\.process.pid),
                    generation: generation
                )
                resources = created
                selection = tapSelection
            }

            let installed = lifecycleQueue.sync { () -> Bool in
                guard captureGeneration == generation, lifecycle.isStarting else {
                    return false
                }
                if let resources, let selection {
                    installLocked(resources, selection: selection)
                }
                selectedApplicationName = application?.name
                activeGeneration.withLock { $0 = generation }
                microphoneCycleGeneration.withLock {
                    $0 = usesMicrophone ? generation : 0
                }
                return true
            }
            guard installed else {
                if let resources {
                    Self.destroy(resources)
                }
                throw AudioCaptureEngineError.notRecording
            }

            // Le writer est installé avant tout démarrage matériel, mais
            // uniquement sur la file audio sérialisée.
            audioQueue.sync {
                self.writer = writer
                self.reportedAudioError = false
                self.lastAudioLevelSentAt = 0
                self.isMicrophoneCaptureActive = usesMicrophone
                self.mixingEnabled = usesMicrophone && application != nil
                self.applicationPendingSamples.removeAll()
                self.microphonePendingSamples.removeAll()
            }

            if let preparedMicrophone {
                try preparedMicrophone.start()
            }

            if let resources {
                // Sans `tapautostart`, AudioDeviceStart ne bloque jamais en
                // attendant le premier son : il rend la main et l'IOProc est
                // appelé lorsque le processus tapé produit réellement de
                // l'audio.
                let startStatus = AudioDeviceStart(
                    resources.aggregateID,
                    resources.ioProcID
                )
                guard startStatus == noErr else {
                    throw AudioCaptureEngineError.captureStartFailed(startStatus)
                }
            }

            let startupError: Error? = lifecycleQueue.sync {
                guard lifecycle.isStarting, unexpectedStopError == nil else {
                    return unexpectedStopError ?? AudioCaptureEngineError.notRecording
                }
                // Le démarrage matériel ne prouve pas la réception : l'état
                // reste en attente tant qu'aucun buffer non vide n'est arrivé.
                lifecycle.markCaptureStarted()
                return nil
            }
            if let startupError {
                throw startupError
            }

            if application != nil {
                startHelperRefresh(generation: generation)
            }
        } catch {
            await teardownFailedStart(writer: writer)
            throw error
        }
    }

    /// Demande la permission micro, au moment du démarrage explicite.
    ///
    /// Appelé uniquement quand un microphone est choisi : le chemin
    /// application seule n'atteint jamais `AVCaptureDevice`. Aucune sortie
    /// par défaut n'est lue ni modifiée, et l'écran n'est jamais demandé.
    private static func requestMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw AudioCaptureEngineError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw AudioCaptureEngineError.microphonePermissionDenied
        @unknown default:
            throw AudioCaptureEngineError.microphonePermissionDenied
        }
    }

    /// Prépare l'entrée micro, sans la démarrer. Les buffers convertis sont
    /// remis à `audioQueue`, seule file qui écrit dans le fichier.
    private func makeMicrophoneCapture(
        choice: MicrophoneChoice
    ) throws -> MicrophoneCapture {
        try MicrophoneCapture(
            choice: choice,
            onSamples: { [weak self] samples in
                guard let self else { return }
                self.audioQueue.async { [weak self] in
                    self?.handleMicrophoneInput(samples)
                }
            },
            onFailure: { [weak self] error in
                guard let self else { return }
                self.audioQueue.async { [weak self] in
                    self?.reportAudioError(error)
                }
            }
        )
    }

    /// Traduit chaque PID du plan. Un PID sans objet processus Core Audio est
    /// absent du dictionnaire ; la sélection le classe alors en
    /// `untranslatedPIDs` au lieu de le présenter comme tapé.
    private static func translatedObjectIDs(
        for plan: ApplicationAudioProcessPlan
    ) -> [pid_t: UInt32] {
        var translated: [pid_t: UInt32] = [:]
        for pid in plan.selectedPIDs where pid > 0 {
            if let objectID = translatePID(pid) {
                translated[pid] = objectID
            }
        }
        return translated
    }

    /// Crée le tap, l'agrégat et l'IOProc, sans démarrer le périphérique.
    /// En cas d'échec partiel, tout ce qui a été créé est détruit avant de
    /// relancer l'erreur : aucun tap orphelin ne survit au démarrage.
    @available(macOS 14.2, *)
    private func createResources(
        applicationName: String,
        constraints: ProcessTapConstraints,
        helperPIDs: [pid_t],
        generation: UInt64
    ) async throws -> CaptureResources {
        let tapDescription = CATapDescription(
            stereoMixdownOfProcesses: constraints.processObjectIDs
        )
        tapDescription.uuid = UUID()
        tapDescription.name = "Naada — \(applicationName)"
        tapDescription.isPrivate = constraints.isPrivate
        tapDescription.isExclusive = constraints.isExclusive
        tapDescription.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var ioProcID: AudioDeviceIOProcID?

        do {
            let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
            guard tapStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
                throw AudioCaptureEngineError.tapCreationFailed(tapStatus)
            }

            let tapFormat = try Self.readTapFormat(tapID)

            // Les valeurs numériques de l'agrégat sont des CFNumber, jamais
            // des CFBoolean : `private`, `stacked` et `tapautostart` sont lus
            // par le HAL via CFNumberGetValue.
            let composition = TapAggregateComposition(
                name: "Naada — \(applicationName)",
                uid: UUID().uuidString,
                tapUID: tapDescription.uuid.uuidString
            )
            let aggregateStatus = AudioHardwareCreateAggregateDevice(
                composition.dictionary as CFDictionary,
                &aggregateID
            )
            guard
                aggregateStatus == noErr,
                aggregateID != AudioObjectID(kAudioObjectUnknown)
            else {
                throw AudioCaptureEngineError.aggregateCreationFailed(aggregateStatus)
            }

            // L'IOProc reçoit les buffers au format d'entrée de l'agrégat.
            // Ce format peut différer de celui du tap ; il est lu après
            // création, avec une attente bornée, puis le tap sert de repli.
            let aggregateFormat = await Self.readAggregateInputFormat(
                aggregateID,
                timeout: 1.0
            ) ?? tapFormat
            let converter = try AudioSampleConverter(
                streamDescription: aggregateFormat
            )

            let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID,
                aggregateID,
                audioQueue
            ) { [weak self] _, inputData, _, _, _ in
                guard let self else { return }
                self.handleAudioInput(
                    inputData,
                    generation: generation,
                    converter: converter
                )
            }
            guard ioProcStatus == noErr, let ioProcID else {
                throw AudioCaptureEngineError.ioProcCreationFailed(ioProcStatus)
            }

            return CaptureResources(
                tapID: tapID,
                aggregateID: aggregateID,
                ioProcID: ioProcID,
                processObjectIDs: constraints.processObjectIDs,
                helperPIDs: helperPIDs
            )
        } catch {
            if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
                _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            if aggregateID != AudioObjectID(kAudioObjectUnknown) {
                _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != AudioObjectID(kAudioObjectUnknown) {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            throw error
        }
    }

    /// Traduit un PID en objet processus Core Audio. Le HAL ne renvoie pas
    /// d'erreur pour un PID sans processus audio : il rend
    /// `kAudioObjectUnknown`, traduit ici par `nil` pour que le moteur omette
    /// ce PID du tap plutôt que d'inventer un autre processus.
    private static func translatePID(_ pid: pid_t) -> AudioObjectID? {
        var pidValue = pid
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pidValue,
            &size,
            &processObjectID
        )

        guard
            status == noErr,
            processObjectID != AudioObjectID(kAudioObjectUnknown),
            size == UInt32(MemoryLayout<AudioObjectID>.size)
        else {
            return nil
        }

        return processObjectID
    }

    /// Lit le format des données que le tap expose à l'agrégat. Ce format est
    /// interprété par `AudioSampleConverter` dans le callback de l'IOProc.
    @available(macOS 14.2, *)
    private static func readTapFormat(
        _ tapID: AudioObjectID
    ) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &size,
            &format
        )

        guard
            status == noErr,
            size == UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            format.mSampleRate > 0,
            format.mChannelsPerFrame > 0
        else {
            throw AudioCaptureEngineError.tapFormatUnavailable(status)
        }

        return format
    }

    /// Métadonnée HAL du processus choisi : produit-il de l'audio à cet
    /// instant ? Lecture seule, aucun tap ni périphérique n'est ouvert.
    private static func processIsProducingOutput(
        _ processObjectID: AudioObjectID
    ) -> Bool? {
        var value: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            processObjectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr, size == UInt32(MemoryLayout<UInt32>.size) else {
            return nil
        }
        return value != 0
    }

    /// Lit le format effectif de l'entrée de l'agrégat, avec une attente
    /// bornée. Les buffers de l'IOProc sont dans ce format, pas forcément
    /// dans celui du tap.
    @available(macOS 14.2, *)
    private static func readAggregateInputFormat(
        _ aggregateID: AudioObjectID,
        timeout: TimeInterval
    ) async -> AudioStreamBasicDescription? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if Task.isCancelled { return nil }
            if let format = readFirstInputFormat(aggregateID) {
                return format
            }
            if Date() >= deadline { return nil }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while true
    }

    @available(macOS 14.2, *)
    private static func readFirstInputFormat(
        _ aggregateID: AudioObjectID
    ) -> AudioStreamBasicDescription? {
        // Certains agrégats exposent directement leur format d'entrée avant
        // que la liste des flux ne soit complète.
        if let format = readDeviceInputFormat(aggregateID) {
            return format
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &size) == noErr,
            size >= UInt32(MemoryLayout<AudioStreamID>.size)
        else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioStreamID>.size
        var streams = [AudioStreamID](repeating: 0, count: count)
        guard
            AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &streams) == noErr
        else {
            return nil
        }

        for stream in streams {
            if let format = readStreamFormat(stream) {
                return format
            }
        }
        return nil
    }

    @available(macOS 14.2, *)
    private static func readDeviceInputFormat(
        _ aggregateID: AudioObjectID
    ) -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            aggregateID,
            &address,
            0,
            nil,
            &size,
            &format
        )
        return validatedFormat(status: status, size: size, format: format)
    }

    @available(macOS 14.2, *)
    private static func readStreamFormat(
        _ streamID: AudioStreamID
    ) -> AudioStreamBasicDescription? {
        for selector in [
            kAudioStreamPropertyVirtualFormat,
            kAudioStreamPropertyPhysicalFormat,
        ] {
            var format = AudioStreamBasicDescription()
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let status = AudioObjectGetPropertyData(
                streamID,
                &address,
                0,
                nil,
                &size,
                &format
            )
            if let valid = validatedFormat(status: status, size: size, format: format) {
                return valid
            }
        }
        return nil
    }

    private static func validatedFormat(
        status: OSStatus,
        size: UInt32,
        format: AudioStreamBasicDescription
    ) -> AudioStreamBasicDescription? {
        guard
            status == noErr,
            size == UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            format.mSampleRate > 0,
            format.mChannelsPerFrame > 0,
            format.mBitsPerChannel > 0
        else {
            return nil
        }
        return format
    }

    /// Installe des ressources déjà démarrées. Appelé uniquement sous
    /// lifecycleQueue, après vérification de la génération.
    private func installLocked(
        _ resources: CaptureResources,
        selection: ApplicationAudioTapSelection
    ) {
        tapID = resources.tapID
        aggregateID = resources.aggregateID
        ioProcID = resources.ioProcID
        requestedRootPID = selection.requestedRootPID
        rootIsTranslated = selection.rootIsTranslated
        tappedPIDs = selection.tappedPIDs
        untranslatedPIDs = selection.untranslatedPIDs
        selectedProcessObjectIDs = selection.processObjectIDs
        selectedHelperPIDs = selection.translatedHelpers.map(\.process.pid)
    }

    /// Retire les identifiants courants. Appelé uniquement sous lifecycleQueue.
    private func takeEndpointsLocked() -> CaptureEndpoints? {
        guard let ioProcID, let aggregateID, let tapID else {
            self.ioProcID = nil
            self.aggregateID = nil
            self.tapID = nil
            return nil
        }
        self.ioProcID = nil
        self.aggregateID = nil
        self.tapID = nil
        return CaptureEndpoints(
            tapID: tapID,
            aggregateID: aggregateID,
            ioProcID: ioProcID
        )
    }

    /// Échoue proprement une capture déjà démarrée, uniquement si la
    /// génération attendue est encore celle de l'attente. La vérification et
    /// la transition sont atomiques : un arrêt concurrent ne peut pas être
    /// écrasé par une erreur de reprise.
    @available(macOS 14.2, *)
    private func failCapture(_ error: Error, expectedGeneration: UInt64) {
        let failure: (didFail: Bool, endpoints: CaptureEndpoints?) =
            lifecycleQueue.sync {
                guard
                    captureGeneration == expectedGeneration,
                    lifecycle.isWaitingForAudio
                else {
                    return (false, nil)
                }

                helperRefreshTask?.cancel()
                helperRefreshTask = nil
                activeGeneration.withLock { $0 = 0 }
                captureGeneration &+= 1
                let current = takeEndpointsLocked()
                unexpectedStopError = error
                lifecycle.finishTeardown()
                didRetryForAudioHelper = false
                return (true, current)
            }

        guard failure.didFail else { return }

        if let endpoints = failure.endpoints {
            Self.destroy(endpoints)
        }

        var outputURL: URL?
        audioQueue.sync {
            self.stopMicrophoneEngineLocked()
            if let writer = self.writer {
                // L'arrêt conserve ce qui a déjà été reçu, micro compris.
                _ = try? self.drainMixedSamples(flushRemainder: true)
                outputURL = try? writer.finish()
            }
            self.resetMixStateLocked()
            self.writer = nil
            self.reportedAudioError = false
            self.lastAudioLevelSentAt = 0
        }

        onUnexpectedStop?(error, outputURL)
    }

    /// N'échoue que si la génération est encore celle de la reprise.
    @available(macOS 14.2, *)
    private func failIfCurrent(_ generation: UInt64, error: Error) {
        failCapture(error, expectedGeneration: generation)
    }

    /// Arrêt d'un démarrage qui n'a jamais abouti. Tout passe par audioQueue
    /// pour laisser les callbacks déjà en file se terminer avant de fermer.
    private func teardownFailedStart(writer: MP3FileWriter) async {
        lifecycleQueue.sync {
            helperRefreshTask?.cancel()
            helperRefreshTask = nil
        }

        if #available(macOS 14.2, *) {
            destroyCaptureResources()
        }

        audioQueue.sync {
            self.stopMicrophoneLocked()
            let installed = self.writer
            installed?.cancel()
            if installed !== writer {
                writer.cancel()
            }
            self.writer = nil
            self.reportedAudioError = false
            self.lastAudioLevelSentAt = 0
        }

        // Le teardown n'est terminé qu'après la libération des ressources et
        // le drainage du writer : l'automate redevient alors réutilisable.
        lifecycleQueue.sync {
            self.requestedRootPID = nil
            self.rootIsTranslated = false
            self.tappedPIDs = []
            self.untranslatedPIDs = []
            self.selectedApplicationName = nil
            self.selectedProcessObjectIDs = []
            self.selectedHelperPIDs = []
            self.didRetryForAudioHelper = false
            self.activeGeneration.withLock { $0 = 0 }
            self.captureGeneration &+= 1
            lifecycle.finishTeardown()
        }
    }

    /// Détruit l'IOProc, l'agrégat puis le tap, dans cet ordre. Les erreurs
    /// sont ignorées : un démarrage échoué ne doit pas masquer sa cause.
    @available(macOS 14.2, *)
    private func destroyCaptureResources() {
        let endpoints: CaptureEndpoints? = lifecycleQueue.sync {
            takeEndpointsLocked()
        }

        if let endpoints {
            Self.destroy(endpoints)
        }
    }

    /// Détruit des ressources déjà retirées de l'état du moteur.
    @available(macOS 14.2, *)
    private static func destroy(_ resources: CaptureResources) {
        destroy(
            CaptureEndpoints(
                tapID: resources.tapID,
                aggregateID: resources.aggregateID,
                ioProcID: resources.ioProcID
            )
        )
    }

    @available(macOS 14.2, *)
    private static func destroy(_ endpoints: CaptureEndpoints) {
        _ = AudioDeviceStop(endpoints.aggregateID, endpoints.ioProcID)
        _ = AudioDeviceDestroyIOProcID(
            endpoints.aggregateID,
            endpoints.ioProcID
        )
        _ = AudioHardwareDestroyAggregateDevice(endpoints.aggregateID)
        _ = AudioHardwareDestroyProcessTap(endpoints.tapID)
    }

    /// Vérification synchrone utilisée par la vue après le démarrage.
    /// Empêche de proclamer « enregistrement » si la capture s'est déjà arrêtée.
    var isCaptureActive: Bool {
        lifecycleQueue.sync {
            lifecycle.isCaptureActive && unexpectedStopError == nil
        }
    }

    var startupStopMessage: String? {
        lifecycleQueue.sync {
            unexpectedStopError?.localizedDescription
        }
    }

    /// Vrai entre le démarrage matériel et le premier buffer non vide.
    var isWaitingForAudio: Bool {
        lifecycleQueue.sync { lifecycle.isWaitingForAudio }
    }

    /// Vrai dès qu'un buffer non vide a été converti pendant ce cycle.
    var isReceivingAudio: Bool {
        lifecycleQueue.sync { lifecycle.isReceivingAudio }
    }


    /// Interroge à nouveau le HAL, sans créer ni lire de tap. Sert au message
    /// « source muette » ; n'interroge que les objets réellement tapés et ne
    /// tente aucun autre processus.
    /// `nil` si aucun objet processus n'est lisible ; `true` dès qu'une des
    /// cibles tapées produit du son.
    func selectedProcessIsProducingOutput() -> Bool? {
        let processObjectIDs = lifecycleQueue.sync { selectedProcessObjectIDs }
        guard !processObjectIDs.isEmpty else { return nil }

        var readable = false
        for processObjectID in processObjectIDs {
            guard let producing = Self.processIsProducingOutput(processObjectID) else {
                continue
            }
            readable = true
            if producing {
                return true
            }
        }
        return readable ? false : nil
    }

    /// Cibles retenues pour la dernière capture. La racine demandée est
    /// distincte de la racine traduite ; `tappedPIDs` ne contient que les PID
    /// réellement présents dans le tap, `untranslatedPIDs` ceux qui ont été
    /// omis faute d'objet processus Core Audio.
    var captureDiagnostics: (
        requestedRootPID: pid_t?,
        rootIsTranslated: Bool,
        tappedPIDs: [pid_t],
        untranslatedPIDs: [pid_t],
        processObjectIDs: [AudioObjectID]
    ) {
        lifecycleQueue.sync {
            (
                requestedRootPID,
                rootIsTranslated,
                tappedPIDs,
                untranslatedPIDs,
                selectedProcessObjectIDs
            )
        }
    }

    func stop() async throws -> CaptureStopResult {
        guard #available(macOS 14.2, *) else {
            throw AudioCaptureEngineError.unsupportedSystemVersion
        }

        if let failure = lifecycleQueue.sync(execute: { unexpectedStopError }) {
            throw failure
        }

        let stopState: (didBegin: Bool, endpoints: CaptureEndpoints?) =
            lifecycleQueue.sync {
                guard lifecycle.beginStop() else { return (false, nil) }
                helperRefreshTask?.cancel()
                helperRefreshTask = nil
                activeGeneration.withLock { $0 = 0 }
                captureGeneration &+= 1
                return (true, takeEndpointsLocked())
            }

        guard stopState.didBegin else {
            throw AudioCaptureEngineError.notRecording
        }

        // Pendant une reprise, l'ancien tap a déjà été détruit avant la
        // création du nouveau : il peut n'y avoir aucun endpoint à arrêter.
        // Le writer reste drainé et l'arrêt reste valide.
        var warning: String?
        if let resources = stopState.endpoints {
            let stopStatus = AudioDeviceStop(
                resources.aggregateID,
                resources.ioProcID
            )
            if stopStatus != noErr {
                warning = String(
                    format: NSLocalizedString(
                        "Stopping the audio aggregate failed (error %d).",
                        comment: "Audio aggregate stop warning"
                    ),
                    stopStatus
                )
            }

            let ioProcStatus = AudioDeviceDestroyIOProcID(
                resources.aggregateID,
                resources.ioProcID
            )
            if ioProcStatus != noErr, warning == nil {
                warning = String(
                    format: NSLocalizedString(
                        "Releasing the audio listener failed (error %d).",
                        comment: "Audio IOProc release warning"
                    ),
                    ioProcStatus
                )
            }

            let aggregateStatus = AudioHardwareDestroyAggregateDevice(
                resources.aggregateID
            )
            if aggregateStatus != noErr, warning == nil {
                warning = String(
                    format: NSLocalizedString(
                        "Destroying the audio aggregate failed (error %d).",
                        comment: "Audio aggregate destruction warning"
                    ),
                    aggregateStatus
                )
            }

            let tapStatus = AudioHardwareDestroyProcessTap(resources.tapID)
            if tapStatus != noErr, warning == nil {
                warning = String(
                    format: NSLocalizedString(
                        "Destroying the audio tap failed (error %d).",
                        comment: "Audio tap destruction warning"
                    ),
                    tapStatus
                )
            }
        }

        // Laisse la file audio se vider, arrête le micro, écrit le reliquat du
        // mélange, puis ferme le writer dans le même bloc sérialisé : aucun
        // callback ne peut plus l'utiliser après.
        var outputURL: URL?
        var finishError: Error?
        audioQueue.sync {
            self.stopMicrophoneEngineLocked()
            do {
                try self.drainMixedSamples(flushRemainder: true)
            } catch {
                finishError = error
            }
            let writer = self.writer
            if let writer {
                do {
                    outputURL = try writer.finish()
                } catch {
                    finishError = finishError ?? error
                }
            }
            self.resetMixStateLocked()
            self.writer = nil
            self.reportedAudioError = false
            self.lastAudioLevelSentAt = 0
        }

        // Resources détruites et writer drainé : le moteur peut être réutilisé
        // même si la fermeture du MP3 signale ensuite une erreur.
        lifecycleQueue.sync {
            self.requestedRootPID = nil
            self.rootIsTranslated = false
            self.tappedPIDs = []
            self.untranslatedPIDs = []
            self.selectedApplicationName = nil
            self.selectedProcessObjectIDs = []
            self.selectedHelperPIDs = []
            self.didRetryForAudioHelper = false
            self.captureGeneration &+= 1
            lifecycle.finishTeardown()
        }

        if let finishError {
            throw finishError
        }
        guard let outputURL else {
            throw AudioCaptureEngineError.missingWriter
        }
        return CaptureStopResult(url: outputURL, warning: warning)
    }

    // MARK: - Helper audio apparu pendant l'attente

    /// Surveille, pendant une fenêtre bornée, l'apparition d'un helper audio
    /// descendant. Un seul remplacement de tap est tenté, sur le même writer,
    /// sans repasser par `start` ni lever `captureAlreadyRunning`.
    private func startHelperRefresh(generation: UInt64) {
        lifecycleQueue.sync {
            helperRefreshTask?.cancel()
        }

        let task = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(Self.helperRefreshWindow)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: Self.helperRefreshInterval)
                if Task.isCancelled { return }
                guard await self.refreshAudioHelpersIfNeeded(
                    generation: generation
                ) else {
                    return
                }
            }
        }

        lifecycleQueue.sync {
            helperRefreshTask = task
        }
    }

    /// Retourne `true` pour continuer à surveiller, `false` quand la tentative
    /// est consommée ou que la capture n'attend plus le premier buffer.
    private func refreshAudioHelpersIfNeeded(generation: UInt64) async -> Bool {
        let state: (pid: pid_t, applicationName: String, tappedPIDs: [pid_t])? =
            lifecycleQueue.sync {
                guard
                    captureGeneration == generation,
                    lifecycle.isWaitingForAudio,
                    !didRetryForAudioHelper,
                    let requestedRootPID,
                    let selectedApplicationName
                else {
                    return nil
                }
                return (requestedRootPID, selectedApplicationName, tappedPIDs)
            }
        guard let state else { return false }

        let plan = ApplicationAudioProcesses.plan(
            rootPID: state.pid,
            processes: LiveProcessTable.snapshot()
        )
        let selection = ApplicationAudioTapSelection(
            plan: plan,
            translatedObjectIDs: Self.translatedObjectIDs(for: plan)
        )
        let newHelpers = selection.translatedHelpers.filter {
            !state.tappedPIDs.contains($0.process.pid)
        }
        guard !newHelpers.isEmpty else { return true }

        guard #available(macOS 14.2, *) else { return false }

        do {
            try selection.constraints.validate()
        } catch {
            failIfCurrent(generation, error: error)
            return false
        }

        // Retire et détruit l'ancien tap AVANT d'en créer un nouveau : un seul
        // tap existe à la fois, sans chevauchement. La génération est
        // invalidée et les callbacks de l'ancien IOProc sont rejetés.
        let retry: (generation: UInt64, endpoints: CaptureEndpoints?)? =
            lifecycleQueue.sync {
                guard
                    captureGeneration == generation,
                    lifecycle.isWaitingForAudio,
                    !didRetryForAudioHelper
                else {
                    return nil
                }
                didRetryForAudioHelper = true
                captureGeneration &+= 1
                activeGeneration.withLock { $0 = 0 }
                return (captureGeneration, takeEndpointsLocked())
            }
        guard let retry else { return false }

        // Le micro n'appartient pas au tap : seul son jeton de premier buffer
        // suit la nouvelle génération du cycle.
        microphoneCycleGeneration.withLock { token in
            if token != 0 {
                token = retry.generation
            }
        }

        if let endpoints = retry.endpoints {
            Self.destroy(endpoints)
        }

        do {
            let resources = try await createResources(
                applicationName: state.applicationName,
                constraints: selection.constraints,
                helperPIDs: selection.translatedHelpers.map(\.process.pid),
                generation: retry.generation
            )

            let stillWaiting = lifecycleQueue.sync {
                captureGeneration == retry.generation
                    && lifecycle.isWaitingForAudio
            }
            guard stillWaiting else {
                Self.destroy(resources)
                return false
            }

            let startStatus = AudioDeviceStart(
                resources.aggregateID,
                resources.ioProcID
            )
            guard startStatus == noErr else {
                Self.destroy(resources)
                failIfCurrent(
                    retry.generation,
                    error: AudioCaptureEngineError.captureStartFailed(startStatus)
                )
                return false
            }

            let installed = lifecycleQueue.sync { () -> Bool in
                guard
                    captureGeneration == retry.generation,
                    lifecycle.isWaitingForAudio
                else {
                    return false
                }
                installLocked(resources, selection: selection)
                activeGeneration.withLock { $0 = retry.generation }
                return true
            }
            if !installed {
                Self.destroy(resources)
            }
        } catch {
            failIfCurrent(retry.generation, error: error)
            return false
        }

        return false
    }

    // MARK: - IOProc et mélange

    /// Appelé par AudioDevice sur `audioQueue`, avec les données d'entrée de
    /// l'agrégat et le convertisseur propre à cet IOProc. Tout l'état du
    /// pipeline est déjà confiné à cette file.
    private func handleAudioInput(
        _ bufferList: UnsafePointer<AudioBufferList>,
        generation: UInt64,
        converter: AudioSampleConverter
    ) {
        // Un buffer d'un tap remplacé ne doit ni établir la réception ni
        // écrire dans le writer du cycle courant.
        guard activeGeneration.withLock({ $0 }) == generation else { return }
        guard writer != nil else { return }

        do {
            guard let samples = try converter.convert(bufferList), !samples.isEmpty else {
                return
            }
            noteFirstBuffer(generation: generation)
            if mixingEnabled {
                applicationPendingSamples.append(contentsOf: samples)
                try drainMixedSamples(flushRemainder: false)
            } else {
                try writeSamples(samples)
            }
        } catch {
            reportAudioError(error)
        }
    }

    /// Appelé sur `audioQueue` avec les échantillons micro déjà convertis en
    /// PCM 16 bits stéréo 48 kHz. Le micro ne dépend pas du tap : un
    /// remplacement de tap ne l'interrompt pas.
    private func handleMicrophoneInput(_ samples: [Int16]) {
        guard isMicrophoneCaptureActive, writer != nil else { return }
        noteMicrophoneFirstBuffer()
        do {
            if mixingEnabled {
                microphonePendingSamples.append(contentsOf: samples)
                try drainMixedSamples(flushRemainder: false)
            } else {
                try writeSamples(samples)
            }
        } catch {
            reportAudioError(error)
        }
    }

    private func noteMicrophoneFirstBuffer() {
        let generation = microphoneCycleGeneration.withLock { $0 }
        guard generation != 0 else { return }
        noteFirstBuffer(generation: generation)
    }

    /// Écrit le mélange des deux flux. Tant que les deux côtés ont des
    /// échantillons, ils sont additionnés au plus court par `PCMMix` ; si un
    /// seul côté attend au-delà de la fenêtre, il est écrit avec du silence
    /// pour borner la latence sans perdre de son. `flushRemainder` vide tout
    /// à l'arrêt.
    private func drainMixedSamples(flushRemainder: Bool) throws {
        guard mixingEnabled, writer != nil else { return }

        while true {
            let applicationCount = applicationPendingSamples.count
            let microphoneCount = microphonePendingSamples.count

            let mixed: [Int16]
            if applicationCount > 0 && microphoneCount > 0 {
                let count = min(applicationCount, microphoneCount)
                let application = Array(applicationPendingSamples.prefix(count))
                let microphone = Array(microphonePendingSamples.prefix(count))
                applicationPendingSamples.removeFirst(count)
                microphonePendingSamples.removeFirst(count)
                mixed = PCMMix.mix(application, microphone)
            } else if applicationCount > 0,
                flushRemainder || applicationCount >= Self.maximumUnpairedSamples
            {
                mixed = PCMMix.mix(applicationPendingSamples, nil)
                applicationPendingSamples.removeAll()
            } else if microphoneCount > 0,
                flushRemainder || microphoneCount >= Self.maximumUnpairedSamples
            {
                mixed = PCMMix.mix(microphonePendingSamples, nil)
                microphonePendingSamples.removeAll()
            } else {
                break
            }

            try writeSamples(mixed)
        }
    }

    /// Unique porte d'écriture : le niveau publié est celui des échantillons
    /// réellement écrits, jamais celui d'une source avant mélange.
    private func writeSamples(_ samples: [Int16]) throws {
        guard !samples.isEmpty, let writer else { return }
        try writer.append(samples)
        publishAudioLevel(for: samples)
    }

    private func reportAudioError(_ error: Error) {
        guard !reportedAudioError else { return }
        reportedAudioError = true
        onAudioError?(error)
    }

    // MARK: - Arrêt du microphone et du mélange

    /// Arrête la lecture micro sans toucher aux tampons déjà reçus.
    /// Appelé uniquement sur `audioQueue`.
    private func stopMicrophoneEngineLocked() {
        microphoneCapture?.stop()
        microphoneCapture = nil
        isMicrophoneCaptureActive = false
        microphoneCycleGeneration.withLock { $0 = 0 }
    }

    /// Arrête le micro et abandonne le mélange sans rien écrire.
    private func stopMicrophoneLocked() {
        stopMicrophoneEngineLocked()
        resetMixStateLocked()
    }

    private func resetMixStateLocked() {
        mixingEnabled = false
        applicationPendingSamples.removeAll()
        microphonePendingSamples.removeAll()
    }

    /// Marque la première réception sans prendre `lifecycleQueue` en
    /// synchrone depuis le callback audio : un simple drapeau sous verrou,
    /// puis une transition asynchrone portant le jeton du cycle.
    private func noteFirstBuffer(generation: UInt64) {
        let isFirst = firstBufferGeneration.withLock { seen -> Bool in
            guard seen != generation else { return false }
            seen = generation
            return true
        }
        guard isFirst else { return }

        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureGeneration == generation else { return }
            self.lifecycle.markFirstBufferReceived()
        }
    }

    /// Mesure et publie le niveau au plus 10 fois par seconde. Appelé
    /// uniquement sur `audioQueue`, avec les échantillons PCM déjà convertis.
    private func publishAudioLevel(for samples: [Int16]) {
        guard let onAudioLevel else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAudioLevelSentAt >= Self.audioLevelInterval else { return }

        lastAudioLevelSentAt = now
        onAudioLevel(AudioLevel.normalizedRMS(samples))
    }
}

/// Convertit les échantillons de l'entrée de l'agrégat en PCM 16 bits
/// entrelacé, au format attendu par l'encodeur MP3. Le format et la
/// disposition réelle des buffers sont vérifiés avant toute copie : une
/// incohérence lève une erreur visible plutôt que de produire du silence.
private final class AudioSampleConverter {
    private let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let layout: AudioStreamFormat

    init(streamDescription: AudioStreamBasicDescription) throws {
        var description = streamDescription

        guard
            description.mSampleRate > 0,
            description.mChannelsPerFrame > 0,
            description.mBitsPerChannel > 0,
            let sourceFormat = AVAudioFormat(streamDescription: &description),
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(MP3FileWriter.sampleRate),
                channels: AVAudioChannelCount(MP3FileWriter.channelCount),
                interleaved: true
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
            let layout = AudioStreamFormat(
                sampleRate: streamDescription.mSampleRate,
                channelsPerFrame: Int(streamDescription.mChannelsPerFrame),
                bitsPerChannel: Int(streamDescription.mBitsPerChannel),
                bytesPerFrame: Int(streamDescription.mBytesPerFrame),
                isInterleaved: (streamDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            )
        else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        self.converter = converter
        self.layout = layout
    }

    func convert(_ bufferList: UnsafePointer<AudioBufferList>) throws -> [Int16]? {
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard !sourceBuffers.isEmpty else { return nil }

        let descriptors = sourceBuffers.map {
            AudioBufferLayout.Buffer(
                channelCount: Int($0.mNumberChannels),
                byteSize: Int($0.mDataByteSize)
            )
        }
        let summary = AudioBufferLayout.analyze(
            format: layout,
            buffers: descriptors
        )
        guard summary.isCompatible else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        guard !summary.isEmpty else { return nil }

        // Un seul buffer entrelacé est traité comme tel. Pour une voie, les
        // deux dispositions sont identiques. Toute autre combinaison est
        // refusée explicitement.
        if layout.channelsPerFrame > 1 {
            guard (summary.kind == .interleaved) == sourceFormat.isInterleaved else {
                throw AudioCaptureEngineError.audioConversionFailed
            }
        }

        let frameCount = summary.frameCount
        guard frameCount > 0 else { return nil }
        guard let input = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        input.frameLength = AVAudioFrameCount(frameCount)

        let destinationBuffers = UnsafeMutableAudioBufferListPointer(
            input.mutableAudioBufferList
        )

        switch summary.kind {
        case .interleaved:
            guard
                let source = sourceBuffers.first,
                let sourceData = source.mData,
                let destination = destinationBuffers.first,
                let destinationData = destination.mData
            else {
                throw AudioCaptureEngineError.audioConversionFailed
            }
            let byteCount = frameCount
                * layout.channelsPerFrame
                * layout.bytesPerSample
            guard
                byteCount <= Int(source.mDataByteSize),
                byteCount <= Int(destination.mDataByteSize)
            else {
                throw AudioCaptureEngineError.audioConversionFailed
            }
            destinationData.copyMemory(
                from: UnsafeRawPointer(sourceData),
                byteCount: byteCount
            )
        case .deinterleaved:
            guard destinationBuffers.count >= layout.channelsPerFrame else {
                throw AudioCaptureEngineError.audioConversionFailed
            }
            for channel in 0..<layout.channelsPerFrame {
                guard
                    let sourceData = sourceBuffers[channel].mData,
                    let destinationData = destinationBuffers[channel].mData
                else {
                    throw AudioCaptureEngineError.audioConversionFailed
                }
                let byteCount = frameCount * layout.bytesPerSample
                guard
                    byteCount <= Int(sourceBuffers[channel].mDataByteSize),
                    byteCount <= Int(destinationBuffers[channel].mDataByteSize)
                else {
                    throw AudioCaptureEngineError.audioConversionFailed
                }
                destinationData.copyMemory(
                    from: UnsafeRawPointer(sourceData),
                    byteCount: byteCount
                )
            }
        case .incompatible:
            throw AudioCaptureEngineError.audioConversionFailed
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frameCount) * ratio) + 64
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: output,
            error: &conversionError
        ) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }

        guard conversionError == nil else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        guard status == .haveData || status == .inputRanDry else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        guard output.frameLength > 0 else { return nil }
        guard let raw = output.audioBufferList.pointee.mBuffers.mData else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        let sampleCount = Int(output.frameLength) * MP3FileWriter.channelCount
        let pointer = raw.assumingMemoryBound(to: Int16.self)
        return Array(UnsafeBufferPointer(start: pointer, count: sampleCount))
    }
}

/// Entrée microphone préparée : permission déjà accordée, périphérique choisi,
/// tap installé et conversion en PCM 16 bits stéréo 48 kHz.
///
/// Tant que `start()` n'est pas appelé, aucun échantillon n'est lu. La classe
/// ne connaît ni le writer ni le mélange : elle remet ses échantillons
/// convertis au moteur, qui seul décide de l'écriture.
private final class MicrophoneCapture {
    private let engine: AVAudioEngine
    private var isTapInstalled = true

    init(
        choice: MicrophoneChoice,
        onSamples: @escaping ([Int16]) -> Void,
        onFailure: @escaping (Error) -> Void
    ) throws {
        guard choice != .none else {
            throw AudioCaptureEngineError.noSourceSelected
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode

        if case let .selected(uid, _) = choice {
            guard let deviceID = Self.inputDeviceID(forUID: uid) else {
                throw AudioCaptureEngineError.selectedMicrophoneUnavailable
            }
            guard let audioUnit = input.audioUnit else {
                throw AudioCaptureEngineError.microphoneOpenFailed
            }
            var device = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw AudioCaptureEngineError.microphoneOpenFailed
            }
        }

        // Format réel de l'entrée après choix du périphérique. Un format nul
        // signifie que l'entrée n'est pas exploitable : erreur distincte,
        // jamais du silence présenté comme une capture.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureEngineError.microphoneFormatUnavailable
        }

        let converter = try MicrophoneSampleConverter(sourceFormat: format)
        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { buffer, _ in
            do {
                guard let samples = try converter.convert(buffer), !samples.isEmpty else {
                    return
                }
                onSamples(samples)
            } catch {
                onFailure(error)
            }
        }

        self.engine = engine
    }

    func start() throws {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioCaptureEngineError.microphoneStartFailed
        }
    }

    func stop() {
        guard isTapInstalled else { return }
        isTapInstalled = false
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Traduit l'UID Core Audio choisi en périphérique d'entrée. Un UID
    /// inconnu ou un périphérique sans entrée valent « introuvable ».
    private static func inputDeviceID(forUID uid: String) -> AudioDeviceID? {
        let cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &size,
                &deviceID
            )
        }

        guard
            status == noErr,
            deviceID != AudioDeviceID(kAudioObjectUnknown),
            size == UInt32(MemoryLayout<AudioDeviceID>.size),
            deviceHasInputStreams(deviceID)
        else {
            return nil
        }
        return deviceID
    }

    private static func deviceHasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        )
        return status == noErr && size > 0
    }
}

/// Convertit les buffers de l'entrée micro en PCM 16 bits entrelacé stéréo
/// 48 kHz, sans gain. Une entrée mono est dupliquée sur les deux voies ; au-delà
/// de deux voies, les deux premières sont retenues.
private final class MicrophoneSampleConverter {
    private let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(sourceFormat: AVAudioFormat) throws {
        let sourceChannels = Int(sourceFormat.channelCount)
        guard sourceChannels > 0 else {
            throw AudioCaptureEngineError.microphoneFormatUnavailable
        }

        let targetChannels = AVAudioChannelCount(min(sourceChannels, 2))
        guard
            sourceFormat.sampleRate > 0,
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(MP3FileWriter.sampleRate),
                channels: targetChannels,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            throw AudioCaptureEngineError.microphoneFormatUnavailable
        }

        if sourceChannels > 2 {
            converter.channelMap = [
                NSNumber(value: 0),
                NSNumber(value: 1),
            ]
        }

        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Int16]? {
        guard buffer.frameLength > 0 else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: output,
            error: &conversionError
        ) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        guard status == .haveData || status == .inputRanDry else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        guard output.frameLength > 0 else { return nil }

        let channelCount = Int(targetFormat.channelCount)
        let sampleCount = Int(output.frameLength) * channelCount
        let outputBuffer = output.audioBufferList.pointee.mBuffers
        guard
            let raw = outputBuffer.mData,
            Int(outputBuffer.mDataByteSize) >= sampleCount * MemoryLayout<Int16>.size
        else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        let pointer = raw.assumingMemoryBound(to: Int16.self)
        let samples = Array(
            UnsafeBufferPointer(start: pointer, count: sampleCount)
        )

        guard channelCount == 1 else { return samples }

        var stereo: [Int16] = []
        stereo.reserveCapacity(samples.count * 2)
        for sample in samples {
            stereo.append(sample)
            stereo.append(sample)
        }
        return stereo
    }
}

/// Lecture seule de la table des processus, sans Core Audio ni privilège.
///
/// `KERN_PROC_ALL` fournit le couple PID/parent ; `KERN_PROCARGS2` fournit la
/// ligne de commande complète. Un processus dont les arguments sont
/// illisibles reste présent avec une commande vide : il ne peut donc jamais
/// être retenu comme helper audio.
private enum LiveProcessTable {
    static func snapshot() -> [ApplicationAudioProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        let capacity = size / MemoryLayout<kinfo_proc>.stride
        guard capacity > 0 else { return [] }
        var entries = [kinfo_proc](
            repeating: kinfo_proc(),
            count: capacity
        )
        guard sysctl(&mib, 4, &entries, &size, nil, 0) == 0 else {
            return []
        }

        let count = min(capacity, size / MemoryLayout<kinfo_proc>.stride)
        return entries.prefix(count).compactMap { entry in
            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { return nil }
            return ApplicationAudioProcess(
                pid: pid,
                parentPID: entry.kp_eproc.e_ppid,
                command: arguments(for: pid)
            )
        }
    }

    private static func arguments(for pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard
            sysctl(&mib, 3, nil, &size, nil, 0) == 0,
            size > MemoryLayout<Int32>.size
        else {
            return ""
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else {
            return ""
        }

        let argc = buffer.withUnsafeBytes { raw in
            raw.load(as: Int32.self)
        }
        guard argc > 0 else { return "" }

        var strings: [String] = []
        var start = MemoryLayout<Int32>.size
        var index = start
        while index < size {
            if buffer[index] == 0 {
                if index > start,
                   let value = String(
                       bytes: buffer[start..<index],
                       encoding: .utf8
                   ) {
                    strings.append(value)
                }
                start = index + 1
            }
            index += 1
        }

        guard !strings.isEmpty else { return "" }
        let command = strings
            .dropFirst()
            .prefix(Int(argc))
            .joined(separator: " ")
        return command
    }
}
