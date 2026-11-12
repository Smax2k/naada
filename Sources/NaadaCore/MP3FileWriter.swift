import CShine
import Foundation

/// Encode en MP3 (MPEG-1 Layer III, 48 kHz, stéréo, 192 kbit/s) les échantillons
/// PCM 16 bits entrelacés fournis par la capture.
///
/// L'encodeur Shine est compilé dans l'application : aucun binaire externe,
/// aucun service réseau. Le fichier de sortie est créé exclusivement et n'est
/// jamais écrasé.
public final class MP3FileWriter {
    public static let sampleRate: Int = 48_000
    public static let channelCount: Int = 2
    public static let bitrate: Int = 192

    public let url: URL
    public private(set) var framesSubmitted: Int = 0
    public private(set) var bytesWritten: Int = 0

    private let handle: FileHandle
    private var encoder: OpaquePointer?
    private var pending: [Int16] = []
    private let samplesPerPass: Int
    private let frameSampleCount: Int
    private var finished = false
    private var cancelled = false
    private let lock = NSLock()

    public init(
        folder: URL,
        date: Date,
        title: String,
        timeZone: TimeZone = .current
    ) throws {
        var config = shine_config_t()
        shine_set_config_mpeg_defaults(&config.mpeg)
        config.wave.channels = PCM_STEREO
        config.wave.samplerate = Int32(Self.sampleRate)
        config.mpeg.bitr = Int32(Self.bitrate)
        config.mpeg.mode = STEREO
        config.mpeg.emph = NONE

        guard shine_check_config(config.wave.samplerate, config.mpeg.bitr) >= 0 else {
            throw MP3FileWriterError.unsupportedConfiguration
        }
        guard let encoder = shine_initialise(&config) else {
            throw MP3FileWriterError.encoderInitialisationFailed
        }

        let created: CreatedRecordingFile
        do {
            created = try RecordingFile.create(
                in: folder,
                date: date,
                title: title,
                timeZone: timeZone
            )
        } catch {
            shine_close(encoder)
            throw error
        }

        self.encoder = encoder
        self.url = created.url
        self.handle = created.handle
        self.samplesPerPass = Int(shine_samples_per_pass(encoder))
        self.frameSampleCount = self.samplesPerPass * Self.channelCount
    }

    deinit {
        if let encoder {
            shine_close(encoder)
        }
        if !finished && !cancelled {
            try? handle.close()
        }
    }

    /// Ajoute des échantillons entrelacés. Les frames MP3 complètes sont
    /// écrites au fur et à mesure ; le reliquat reste en mémoire.
    public func append(_ samples: UnsafeBufferPointer<Int16>) throws {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        guard !finished, !cancelled, let encoder else { return }
        pending.append(contentsOf: samples)
        framesSubmitted += samples.count / Self.channelCount
        try drainCompleteFrames(encoder: encoder)
    }

    public func append(_ samples: [Int16]) throws {
        try samples.withUnsafeBufferPointer { buffer in
            try append(buffer)
        }
    }

    private func drainCompleteFrames(encoder: OpaquePointer) throws {
        while pending.count >= frameSampleCount {
            let chunk = Array(pending.prefix(frameSampleCount))
            pending.removeFirst(frameSampleCount)
            try encode(chunk, encoder: encoder)
        }
    }

    private func encode(_ interleaved: [Int16], encoder: OpaquePointer) throws {
        guard !interleaved.isEmpty else { return }
        var written: Int32 = 0
        var samples = interleaved
        let data = samples.withUnsafeMutableBufferPointer { buffer -> UnsafeMutablePointer<UInt8>? in
            shine_encode_buffer_interleaved(encoder, buffer.baseAddress, &written)
        }
        guard let data, written > 0 else { return }
        let payload = Data(bytes: data, count: Int(written))
        try handle.write(contentsOf: payload)
        bytesWritten += payload.count
    }

    /// Vide le reliquat (complété par du silence), écrit la dernière frame,
    /// synchronise puis ferme le fichier. L'URL finale est retournée.
    @discardableResult
    public func finish() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        guard !cancelled else { return url }
        guard !finished else { return url }
        finished = true

        var firstError: Error?
        if let encoder {
            if pending.isEmpty && framesSubmitted == 0 {
                // Arrêt immédiat avant tout buffer : une frame de silence
                // garantit un MP3 valide plutôt qu'un fichier vide.
                pending = Array(repeating: 0, count: frameSampleCount)
            }
            if !pending.isEmpty {
                var tail = pending
                let missing = frameSampleCount - tail.count
                if missing > 0 {
                    tail.append(contentsOf: repeatElement(0, count: missing))
                }
                pending.removeAll()
                do {
                    try encode(tail, encoder: encoder)
                } catch {
                    firstError = firstError ?? error
                }
            }

            var written: Int32 = 0
            if let data = shine_flush(encoder, &written), written > 0 {
                let payload = Data(bytes: data, count: Int(written))
                do {
                    try handle.write(contentsOf: payload)
                    bytesWritten += payload.count
                } catch {
                    firstError = firstError ?? error
                }
            }

            shine_close(encoder)
            self.encoder = nil
        }

        do {
            try handle.synchronize()
        } catch {
            firstError = firstError ?? error
        }
        do {
            try handle.close()
        } catch {
            firstError = firstError ?? error
        }

        if let firstError {
            throw firstError
        }
        return url
    }

    /// Ferme l'encodeur et supprime le fichier partiel. Utilisé quand le
    /// démarrage de la capture échoue avant toute donnée utile.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }

        guard !cancelled, !finished else { return }
        cancelled = true
        finished = true

        if let encoder {
            shine_close(encoder)
            self.encoder = nil
        }
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }
}

public enum MP3FileWriterError: Error, LocalizedError {
    case unsupportedConfiguration
    case encoderInitialisationFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedConfiguration:
            return "Configuration MP3 non prise en charge par l'encodeur intégré."
        case .encoderInitialisationFailed:
            return "L'encodeur MP3 intégré n'a pas pu démarrer."
        }
    }
}
