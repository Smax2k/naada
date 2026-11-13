import AVFoundation
import CoreAudio
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
        }
    }
}

struct CaptureStopResult {
    let url: URL
    let warning: String?
}

/// Capture l'audio d'une seule application avec un tap de processus Core Audio.
///
/// Choix de conception :
/// - un unique `AudioObjectID` de processus, obtenu depuis le PID choisi, est
///   ciblé ; aucun tap global, aucun ciblage par bundle ID ;
/// - le tap est privé et `CATapUnmuted` : le son continue d'aller vers la
///   sortie système, sans coupure ni redirection ;
/// - l'agrégat qui porte le tap est privé et n'est jamais défini comme sortie
///   par défaut ; seule son entrée est lue par un IOProc, comme un micro ;
/// - aucun écran, aucune fenêtre et aucune image ne sont demandés ;
/// - le pipeline MP3, la conversion et la jauge restent inchangés.
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
    private var converter: AudioSampleConverter?
    private var reportedAudioError = false
    private var lastAudioLevelSentAt: TimeInterval = 0

    /// Intervalle minimal entre deux mesures publiées : 10 envois par seconde
    /// au plus, avant tout saut vers le MainActor.
    private static let audioLevelInterval: TimeInterval = 0.1

    // Cycle de vie du tap : accès exclusivement sur lifecycleQueue.
    private var tapID: AudioObjectID?
    private var aggregateID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var lifecycle = CaptureLifecycleState()
    private var unexpectedStopError: Error?
    private var selectedProcessObjectID: AudioObjectID?
    /// Jeton de capture : un premier buffer retardé d'un cycle précédent ne
    /// doit jamais faire passer la capture suivante en réception.
    private var captureGeneration: UInt64 = 0
    /// Jeton du cycle qui a livré son premier buffer non vide. Verrou court,
    /// sans attente de file : le callback audio ne prend jamais
    /// lifecycleQueue en synchrone. Un buffer retardé d'un cycle précédent
    /// porte un autre jeton et ne peut pas établir la réception du suivant.
    private let firstBufferGeneration = OSAllocatedUnfairLock<UInt64?>(initialState: nil)

    func start(application: SourceApplication, writer: MP3FileWriter) async throws {
        let canStart = lifecycleQueue.sync { () -> UInt64? in
            let available = tapID == nil
                && aggregateID == nil
                && ioProcID == nil
            guard available, lifecycle.beginStart() else { return nil }
            unexpectedStopError = nil
            selectedProcessObjectID = nil
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
            guard let pid = application.pid else {
                throw AudioCaptureEngineError.sourceApplicationNotFound(application.name)
            }

            let processObjectID = try Self.translatePID(
                pid,
                applicationName: application.name
            )
            let constraints = ProcessTapConstraints.processOnly(
                processObjectID: processObjectID
            )

            do {
                try constraints.validate()
            } catch let error as ProcessTapConstraintError {
                throw AudioCaptureEngineError.invalidTapConfiguration(error.violations)
            }

            let tapDescription = CATapDescription(
                stereoMixdownOfProcesses: constraints.processObjectIDs
            )
            tapDescription.uuid = UUID()
            tapDescription.name = "Naada — \(application.name)"
            tapDescription.isPrivate = constraints.isPrivate
            tapDescription.isExclusive = constraints.isExclusive
            tapDescription.muteBehavior = .unmuted

            var tapID = AudioObjectID(kAudioObjectUnknown)
            let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
            guard tapStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
                throw AudioCaptureEngineError.tapCreationFailed(tapStatus)
            }
            lifecycleQueue.sync {
                self.tapID = tapID
            }

            let tapFormat = try Self.readTapFormat(tapID)

            // Les valeurs numériques de l'agrégat sont des CFNumber, jamais
            // des CFBoolean : `private`, `stacked` et `tapautostart` sont lus
            // par le HAL via CFNumberGetValue.
            let composition = TapAggregateComposition(
                name: "Naada — \(application.name)",
                uid: UUID().uuidString,
                tapUID: tapDescription.uuid.uuidString
            )
            var aggregateID = AudioObjectID(kAudioObjectUnknown)
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
            lifecycleQueue.sync {
                self.aggregateID = aggregateID
                self.selectedProcessObjectID = processObjectID
            }

            // L'IOProc reçoit les buffers au format d'entrée de l'agrégat.
            // Ce format peut différer de celui du tap ; il est lu après
            // création, avec une attente bornée, puis le tap sert de repli.
            let aggregateFormat = await Self.readAggregateInputFormat(
                aggregateID,
                timeout: 1.0
            ) ?? tapFormat
            let converter = try AudioSampleConverter(streamDescription: aggregateFormat)

            var ioProcID: AudioDeviceIOProcID?
            let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID,
                aggregateID,
                audioQueue
            ) { [weak self] _, inputData, _, _, _ in
                guard let self else { return }
                self.handleAudioInput(inputData, generation: generation)
            }
            guard ioProcStatus == noErr, let ioProcID else {
                throw AudioCaptureEngineError.ioProcCreationFailed(ioProcStatus)
            }
            lifecycleQueue.sync { self.ioProcID = ioProcID }

            // Le writer et le convertisseur sont installés avant le démarrage
            // effectif, mais uniquement sur la file audio sérialisée.
            audioQueue.sync {
                self.writer = writer
                self.converter = converter
                self.reportedAudioError = false
                self.lastAudioLevelSentAt = 0
            }

            // Sans `tapautostart`, AudioDeviceStart ne bloque jamais en
            // attendant le premier son : il rend la main et l'IOProc est
            // appelé lorsque le processus tapé produit réellement de l'audio.
            let startStatus = AudioDeviceStart(aggregateID, ioProcID)
            guard startStatus == noErr else {
                throw AudioCaptureEngineError.captureStartFailed(startStatus)
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
        } catch {
            await teardownFailedStart(writer: writer)
            throw error
        }
    }

    /// Traduit le PID choisi en objet processus Core Audio. Le HAL ne renvoie
    /// pas d'erreur pour un PID sans processus audio : il rend
    /// `kAudioObjectUnknown`, traité ici comme une source indisponible.
    private static func translatePID(
        _ pid: pid_t,
        applicationName: String
    ) throws -> AudioObjectID {
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
            throw AudioCaptureEngineError.sourceApplicationNotFound(applicationName)
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

    /// Arrêt d'un démarrage qui n'a jamais abouti. Tout passe par audioQueue
    /// pour laisser les callbacks déjà en file se terminer avant de fermer.
    private func teardownFailedStart(writer: MP3FileWriter) async {
        if #available(macOS 14.2, *) {
            destroyCaptureResources()
        }

        audioQueue.sync {
            let installed = self.writer
            installed?.cancel()
            if installed !== writer {
                writer.cancel()
            }
            self.writer = nil
            self.converter = nil
            self.reportedAudioError = false
            self.lastAudioLevelSentAt = 0
        }

        // Le teardown n'est terminé qu'après la libération des ressources et
        // le drainage du writer : l'automate redevient alors réutilisable.
        lifecycleQueue.sync {
            self.selectedProcessObjectID = nil
            self.captureGeneration &+= 1
            lifecycle.finishTeardown()
        }
    }

    /// Détruit l'IOProc, l'agrégat puis le tap, dans cet ordre. Les erreurs
    /// sont ignorées : un démarrage échoué ne doit pas masquer sa cause.
    @available(macOS 14.2, *)
    private func destroyCaptureResources() {
        let resources: (
            ioProc: AudioDeviceIOProcID?,
            aggregate: AudioObjectID?,
            tap: AudioObjectID?
        ) = lifecycleQueue.sync {
            let current = (ioProcID, aggregateID, tapID)
            self.ioProcID = nil
            self.aggregateID = nil
            self.tapID = nil
            return current
        }

        if let ioProc = resources.ioProc, let aggregate = resources.aggregate {
            _ = AudioDeviceStop(aggregate, ioProc)
            _ = AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        if let aggregate = resources.aggregate {
            _ = AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if let tap = resources.tap {
            _ = AudioHardwareDestroyProcessTap(tap)
        }
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
    /// « source muette » ; ne déclenche aucun repli global ou helper.
    func selectedProcessIsProducingOutput() -> Bool? {
        let processObjectID = lifecycleQueue.sync { selectedProcessObjectID }
        guard let processObjectID else { return nil }
        return Self.processIsProducingOutput(processObjectID)
    }

    func stop() async throws -> CaptureStopResult {
        guard #available(macOS 14.2, *) else {
            throw AudioCaptureEngineError.unsupportedSystemVersion
        }

        let resources: (
            ioProc: AudioDeviceIOProcID,
            aggregate: AudioObjectID,
            tap: AudioObjectID
        )? = lifecycleQueue.sync {
            guard
                let ioProc = ioProcID,
                let aggregate = aggregateID,
                let tap = tapID,
                lifecycle.beginStop()
            else {
                return nil
            }
            self.ioProcID = nil
            self.aggregateID = nil
            self.tapID = nil
            self.captureGeneration &+= 1
            return (ioProc, aggregate, tap)
        }

        guard let resources else {
            throw AudioCaptureEngineError.notRecording
        }

        var warning: String?
        let stopStatus = AudioDeviceStop(resources.aggregate, resources.ioProc)
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
            resources.aggregate,
            resources.ioProc
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

        let aggregateStatus = AudioHardwareDestroyAggregateDevice(resources.aggregate)
        if aggregateStatus != noErr, warning == nil {
            warning = String(
                format: NSLocalizedString(
                    "Destroying the audio aggregate failed (error %d).",
                    comment: "Audio aggregate destruction warning"
                ),
                aggregateStatus
            )
        }

        let tapStatus = AudioHardwareDestroyProcessTap(resources.tap)
        if tapStatus != noErr, warning == nil {
            warning = String(
                format: NSLocalizedString(
                    "Destroying the audio tap failed (error %d).",
                    comment: "Audio tap destruction warning"
                ),
                tapStatus
            )
        }

        // Laisse la file audio se vider, puis ferme le writer dans le même
        // bloc sérialisé : aucun callback ne peut plus l'utiliser après.
        var outputURL: URL?
        var finishError: Error?
        audioQueue.sync {
            let writer = self.writer
            if let writer {
                do {
                    outputURL = try writer.finish()
                } catch {
                    finishError = error
                }
            }
            self.writer = nil
            self.converter = nil
            self.reportedAudioError = false
            self.lastAudioLevelSentAt = 0
        }

        // Resources détruites et writer drainé : le moteur peut être réutilisé
        // même si la fermeture du MP3 signale ensuite une erreur.
        lifecycleQueue.sync {
            self.selectedProcessObjectID = nil
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

    // MARK: - IOProc

    /// Appelé par AudioDevice sur `audioQueue`, avec les données d'entrée de
    /// l'agrégat. Tout l'état du pipeline est déjà confiné à cette file.
    private func handleAudioInput(
        _ bufferList: UnsafePointer<AudioBufferList>,
        generation: UInt64
    ) {
        guard let writer, let converter else { return }

        do {
            guard let samples = try converter.convert(bufferList), !samples.isEmpty else {
                return
            }
            noteFirstBuffer(generation: generation)
            publishAudioLevel(for: samples)
            try writer.append(samples)
        } catch {
            guard !reportedAudioError else { return }
            reportedAudioError = true
            onAudioError?(error)
        }
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
