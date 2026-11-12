import AVFoundation
import CoreMedia
import Foundation
import NaadaCore
import ScreenCaptureKit

enum AudioCaptureEngineError: Error, LocalizedError {
    case sourceApplicationNotFound(String)
    case noDisplayAvailable
    case notRecording
    case captureAlreadyRunning
    case audioConversionFailed
    case missingWriter

    var errorDescription: String? {
        switch self {
        case let .sourceApplicationNotFound(name):
            return "L'application « \(name) » n'est plus visible pour la capture. Relancez la sélection."
        case .noDisplayAvailable:
            return "Aucun écran disponible pour rattacher la capture audio."
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

/// Capture l'audio d'une seule application avec ScreenCaptureKit.
///
/// Choix de conception :
/// - aucun tap de processus Core Audio, aucun périphérique audio ouvert ;
/// - `capturesAudio` seul, sans sortie écran ajoutée ;
/// - `excludesCurrentProcessAudio` évite de capturer Naada lui-même ;
/// - ScreenCaptureKit est passif : le son continue d'aller vers la sortie
///   système, sans coupure ni redirection.
final class AudioCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onUnexpectedStop: ((Error, URL?) -> Void)?
    var onAudioError: ((Error) -> Void)?

    private let audioQueue = DispatchQueue(
        label: "com.naada.audio-pipeline",
        qos: .userInitiated
    )
    private let lifecycleQueue = DispatchQueue(label: "com.naada.capture-lifecycle")

    // État du pipeline audio : accès exclusivement sur audioQueue.
    private var writer: MP3FileWriter?
    private var converter: AudioSampleConverter?
    private var reportedAudioError = false

    // Cycle de vie du flux : accès exclusivement sur lifecycleQueue.
    private var stream: SCStream?
    private var isStarting = false
    private var isStopping = false
    private var unexpectedStopError: Error?

    func start(application: SourceApplication, writer: MP3FileWriter) async throws {
        let canStart = lifecycleQueue.sync { () -> Bool in
            let available = stream == nil && !isStarting && !isStopping
            if available {
                isStarting = true
            }
            return available
        }

        guard canStart else {
            writer.cancel()
            throw AudioCaptureEngineError.captureAlreadyRunning
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )

            guard let runningApplication = content.applications.first(where: {
                $0.processID == application.pid
            }) else {
                throw AudioCaptureEngineError.sourceApplicationNotFound(application.name)
            }

            let applicationWindows = content.windows.filter {
                $0.owningApplication?.processID == application.pid
            }
            let display = content.displays.first(where: { display in
                applicationWindows.contains { $0.frame.intersects(display.frame) }
            }) ?? content.displays.first

            guard let display else {
                throw AudioCaptureEngineError.noDisplayAvailable
            }

            let filter = SCContentFilter(
                display: display,
                including: [runningApplication],
                exceptingWindows: []
            )

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = MP3FileWriter.sampleRate
            configuration.channelCount = MP3FileWriter.channelCount
            configuration.width = 1280
            configuration.height = 720
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.streamName = "Naada — \(application.name)"

            let stream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: self
            )
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

            lifecycleQueue.sync {
                self.stream = stream
                self.isStopping = false
                self.unexpectedStopError = nil
            }

            // Le writer et le convertisseur sont installés avant le démarrage
            // effectif, mais uniquement sur la file audio sérialisée.
            audioQueue.sync {
                self.writer = writer
                self.converter = AudioSampleConverter()
                self.reportedAudioError = false
            }

            try await stream.startCapture()

            let (startupError, stopped) = lifecycleQueue.sync { () -> (Error?, Bool) in
                let result = (unexpectedStopError, isStopping)
                if result.0 == nil && !result.1 {
                    isStarting = false
                }
                return result
            }

            if let startupError {
                throw startupError
            }
            if stopped {
                throw AudioCaptureEngineError.notRecording
            }
        } catch {
            await teardownFailedStart(writer: writer)
            throw error
        }
    }

    /// Arrêt d'un démarrage qui n'a jamais abouti. Tout passe par audioQueue
    /// pour laisser les callbacks déjà en file se terminer avant de fermer.
    private func teardownFailedStart(writer: MP3FileWriter) async {
        let currentStream: SCStream? = lifecycleQueue.sync {
            let current = stream
            self.stream = nil
            self.isStarting = false
            self.isStopping = true
            return current
        }

        if let currentStream {
            try? await currentStream.stopCapture()
            try? currentStream.removeStreamOutput(self, type: .audio)
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
        }
    }

    /// Vérification synchrone utilisée par la vue après `startCapture`.
    /// Empêche de proclamer « enregistrement » si le flux s'est déjà arrêté.
    var isCaptureActive: Bool {
        lifecycleQueue.sync {
            stream != nil && !isStarting && !isStopping && unexpectedStopError == nil
        }
    }

    var startupStopMessage: String? {
        lifecycleQueue.sync {
            unexpectedStopError?.localizedDescription
        }
    }

    func stop() async throws -> CaptureStopResult {
        let stream: SCStream? = lifecycleQueue.sync {
            guard let current = self.stream, !isStarting, !isStopping else { return nil }
            self.stream = nil
            isStopping = true
            return current
        }

        guard let stream else {
            throw AudioCaptureEngineError.notRecording
        }

        var warning: String?
        do {
            try await stream.stopCapture()
        } catch {
            warning = error.localizedDescription
        }

        do {
            try stream.removeStreamOutput(self, type: .audio)
        } catch {
            if warning == nil {
                warning = error.localizedDescription
            }
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
        }

        if let finishError {
            throw finishError
        }
        guard let outputURL else {
            throw AudioCaptureEngineError.missingWriter
        }
        return CaptureStopResult(url: outputURL, warning: warning)
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let writer, let converter else { return }

        do {
            guard let samples = try converter.convert(sampleBuffer) else { return }
            try writer.append(samples)
        } catch {
            guard !reportedAudioError else { return }
            reportedAudioError = true
            onAudioError?(error)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let shouldHandle = lifecycleQueue.sync { () -> Bool in
            guard !isStopping, let current = self.stream, current === stream else {
                return false
            }
            self.stream = nil
            isStopping = true
            isStarting = false
            unexpectedStopError = error
            return true
        }
        guard shouldHandle else { return }

        // Exécuté après les callbacks déjà en file : on vide puis on ferme
        // le writer sur la même file sérialisée.
        audioQueue.async { [self] in
            let writer = self.writer
            let url = try? writer?.finish()
            self.writer = nil
            self.converter = nil
            self.reportedAudioError = false
            self.onUnexpectedStop?(error, url)
        }
    }
}

/// Convertit les échantillons ScreenCaptureKit (souvent Float32 planaire)
/// en PCM 16 bits entrelacé, au format attendu par l'encodeur MP3.
private final class AudioSampleConverter {
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(MP3FileWriter.sampleRate),
        channels: AVAudioChannelCount(MP3FileWriter.channelCount),
        interleaved: true
    )!

    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    func convert(_ sampleBuffer: CMSampleBuffer) throws -> [Int16]? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
            let format = AVAudioFormat(streamDescription: streamDescription)
        else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        if converter == nil || sourceFormat != format {
            converter = AVAudioConverter(from: format, to: targetFormat)
            sourceFormat = format
        }
        guard let converter else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        guard
            let input = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        else {
            throw AudioCaptureEngineError.audioConversionFailed
        }
        input.frameLength = AVAudioFrameCount(frameCount)

        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: input.mutableAudioBufferList
        )
        guard copyStatus == noErr else {
            throw AudioCaptureEngineError.audioConversionFailed
        }

        let ratio = targetFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(frameCount) * ratio) + 64
        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: capacity
            )
        else {
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
