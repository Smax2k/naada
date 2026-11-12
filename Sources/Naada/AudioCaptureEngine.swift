import AVFoundation
import CoreAudio
import Foundation
import NaadaCore

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
            return "L'application « \(name) » n'expose plus de processus audio capturable. Relancez la sélection."
        case .unsupportedSystemVersion:
            return "La capture audio par tap de processus nécessite macOS 14.2 ou ultérieur."
        case let .invalidTapConfiguration(violations):
            let reasons = violations.map(\.rawValue).joined(separator: ", ")
            return "La configuration du tap audio a été refusée (\(reasons))."
        case let .tapCreationFailed(status):
            return "Le tap audio de l'application n'a pas pu être créé (erreur \(status))."
        case let .aggregateCreationFailed(status):
            return "L'agrégat audio privé n'a pas pu être créé (erreur \(status))."
        case let .tapFormatUnavailable(status):
            return "Le format audio du tap n'a pas pu être lu (erreur \(status))."
        case let .ioProcCreationFailed(status):
            return "L'écoute audio de l'agrégat n'a pas pu être créée (erreur \(status))."
        case let .captureStartFailed(status):
            return "La capture audio n'a pas pu démarrer (erreur \(status))."
        case .notRecording:
            return "Aucune capture n'est en cours."
        case .captureAlreadyRunning:
            return "Une capture est déjà en cours dans ce moteur."
        case .audioConversionFailed:
            return "Un échantillon audio n'a pas pu être converti en PCM."
        case .missingWriter:
            return "Le fichier MP3 de sortie n'est plus disponible."
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

    func start(application: SourceApplication, writer: MP3FileWriter) async throws {
        let canStart = lifecycleQueue.sync { () -> Bool in
            let available = tapID == nil
                && aggregateID == nil
                && ioProcID == nil
            guard available, lifecycle.beginStart() else { return false }
            unexpectedStopError = nil
            return true
        }

        guard canStart else {
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

            let tapEntry: [String: Any] = [
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString
            ]
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Naada — \(application.name)",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapListKey: [tapEntry],
            ]

            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            let aggregateStatus = AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &aggregateID
            )
            guard
                aggregateStatus == noErr,
                aggregateID != AudioObjectID(kAudioObjectUnknown)
            else {
                throw AudioCaptureEngineError.aggregateCreationFailed(aggregateStatus)
            }
            lifecycleQueue.sync { self.aggregateID = aggregateID }

            let converter = try AudioSampleConverter(streamDescription: tapFormat)

            var ioProcID: AudioDeviceIOProcID?
            let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID,
                aggregateID,
                audioQueue
            ) { [weak self] _, inputData, _, _, _ in
                guard let self else { return }
                self.handleAudioInput(inputData)
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

            let startStatus = AudioDeviceStart(aggregateID, ioProcID)
            guard startStatus == noErr else {
                throw AudioCaptureEngineError.captureStartFailed(startStatus)
            }

            let startupError: Error? = lifecycleQueue.sync {
                guard lifecycle.isStarting, unexpectedStopError == nil else {
                    return unexpectedStopError ?? AudioCaptureEngineError.notRecording
                }
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
            return (ioProc, aggregate, tap)
        }

        guard let resources else {
            throw AudioCaptureEngineError.notRecording
        }

        var warning: String?
        let stopStatus = AudioDeviceStop(resources.aggregate, resources.ioProc)
        if stopStatus != noErr {
            warning = "L'arrêt de l'agrégat audio a échoué (erreur \(stopStatus))."
        }

        let ioProcStatus = AudioDeviceDestroyIOProcID(
            resources.aggregate,
            resources.ioProc
        )
        if ioProcStatus != noErr, warning == nil {
            warning = "La libération de l'écoute audio a échoué (erreur \(ioProcStatus))."
        }

        let aggregateStatus = AudioHardwareDestroyAggregateDevice(resources.aggregate)
        if aggregateStatus != noErr, warning == nil {
            warning = "La destruction de l'agrégat audio a échoué (erreur \(aggregateStatus))."
        }

        let tapStatus = AudioHardwareDestroyProcessTap(resources.tap)
        if tapStatus != noErr, warning == nil {
            warning = "La destruction du tap audio a échoué (erreur \(tapStatus))."
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
    private func handleAudioInput(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard let writer, let converter else { return }

        do {
            guard let samples = try converter.convert(bufferList) else { return }
            publishAudioLevel(for: samples)
            try writer.append(samples)
        } catch {
            guard !reportedAudioError else { return }
            reportedAudioError = true
            onAudioError?(error)
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

/// Convertit les échantillons du tap (souvent Float32 planaire) en PCM 16 bits
/// entrelacé, au format attendu par l'encodeur MP3.
private final class AudioSampleConverter {
    private let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let bytesPerSample: Int
    private let sourceBytesPerFrame: Int

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
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        let sourceASBD = sourceFormat.streamDescription.pointee
        let sampleWidth = max(1, Int(sourceASBD.mBitsPerChannel / 8))
        let declaredFrameWidth = Int(sourceASBD.mBytesPerFrame)

        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        self.converter = converter
        self.bytesPerSample = sampleWidth
        self.sourceBytesPerFrame = sourceFormat.isInterleaved
            ? (declaredFrameWidth > 0
                ? declaredFrameWidth
                : Int(sourceASBD.mChannelsPerFrame) * sampleWidth)
            : sampleWidth
    }

    func convert(_ bufferList: UnsafePointer<AudioBufferList>) throws -> [Int16]? {
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard !sourceBuffers.isEmpty, sourceBytesPerFrame > 0 else { return nil }

        let frameCount = sourceBuffers
            .map { Int($0.mDataByteSize) / sourceBytesPerFrame }
            .min() ?? 0
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
        if sourceFormat.isInterleaved {
            guard
                let source = sourceBuffers.first,
                let sourceData = source.mData,
                let destination = destinationBuffers.first,
                let destinationData = destination.mData
            else {
                throw AudioCaptureEngineError.audioConversionFailed
            }
            let byteCount = min(
                Int(source.mDataByteSize),
                Int(destination.mDataByteSize)
            )
            destinationData.copyMemory(
                from: UnsafeRawPointer(sourceData),
                byteCount: byteCount
            )
        } else {
            let channelCount = min(sourceBuffers.count, destinationBuffers.count)
            guard channelCount > 0 else {
                throw AudioCaptureEngineError.audioConversionFailed
            }
            for channel in 0..<channelCount {
                guard
                    let sourceData = sourceBuffers[channel].mData,
                    let destinationData = destinationBuffers[channel].mData
                else {
                    throw AudioCaptureEngineError.audioConversionFailed
                }
                let byteCount = min(
                    Int(sourceBuffers[channel].mDataByteSize),
                    Int(destinationBuffers[channel].mDataByteSize)
                )
                destinationData.copyMemory(
                    from: UnsafeRawPointer(sourceData),
                    byteCount: byteCount
                )
            }
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
