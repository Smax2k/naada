import Foundation

/// Format PCM pur d'un flux, sans dépendance à Core Audio.
///
/// Le format du tap et celui de l'entrée de l'agrégat ne sont pas supposés
/// identiques : le moteur lit le format effectif de l'agrégat et construit ce
/// descripteur, qui sert à découper les buffers reçus.
public struct AudioStreamFormat: Equatable {
    public let sampleRate: Double
    public let channelsPerFrame: Int
    public let bitsPerChannel: Int
    /// Taille d'une frame déclarée par le flux, en octets. Pour un flux non
    /// entrelacé, cette valeur peut décrire une seule voie.
    public let declaredBytesPerFrame: Int
    public let isInterleaved: Bool

    public init?(
        sampleRate: Double,
        channelsPerFrame: Int,
        bitsPerChannel: Int,
        bytesPerFrame: Int,
        isInterleaved: Bool
    ) {
        guard
            sampleRate > 0,
            channelsPerFrame > 0,
            bitsPerChannel > 0,
            bytesPerFrame >= 0
        else {
            return nil
        }

        self.sampleRate = sampleRate
        self.channelsPerFrame = channelsPerFrame
        self.bitsPerChannel = bitsPerChannel
        self.declaredBytesPerFrame = bytesPerFrame
        self.isInterleaved = isInterleaved
    }

    /// Largeur d'un échantillon d'une voie, en octets.
    public var bytesPerSample: Int { max(1, bitsPerChannel / 8) }

    /// Octets d'une frame complète pour un flux entrelacé, ou d'une voie pour
    /// un flux non entrelacé.
    public var bytesPerFrame: Int {
        let computed = channelsPerFrame * bytesPerSample
        guard isInterleaved else { return bytesPerSample }
        guard declaredBytesPerFrame > 0 else { return computed }
        return max(declaredBytesPerFrame, computed)
    }
}

/// Découpage réel d'une liste de buffers audio, vérifié contre le format
/// annoncé. Un buffer de silence reste un buffer valide : il transmet des
/// frames, seulement à amplitude nulle.
public struct AudioBufferLayout: Equatable {
    public struct Buffer: Equatable {
        public let channelCount: Int
        public let byteSize: Int

        public init(channelCount: Int, byteSize: Int) {
            self.channelCount = channelCount
            self.byteSize = byteSize
        }
    }

    public enum Kind: String, Equatable {
        case interleaved
        case deinterleaved
        case incompatible
    }

    public let kind: Kind
    public let frameCount: Int
    public let byteCount: Int

    public var isCompatible: Bool { kind != .incompatible }

    /// Vrai pour une liste vide ou une frame nulle : le callback n'a livré
    /// aucun échantillon exploitable, ce qui ne doit pas être compté comme
    /// une réception.
    public var isEmpty: Bool { frameCount == 0 || byteCount == 0 }

    /// Analyse la liste effectivement livrée par l'IOProc. La disposition des
    /// buffers fait foi : un seul buffer portant toutes les voies est
    /// entrelacé, une voie par buffer est non entrelacé.
    public static func analyze(
        format: AudioStreamFormat,
        buffers: [Buffer]
    ) -> AudioBufferLayout {
        let totalBytes = buffers.reduce(0) { $0 + max(0, $1.byteSize) }
        let channels = format.channelsPerFrame
        let sampleWidth = format.bytesPerSample
        let frameBytes = channels * sampleWidth

        guard !buffers.isEmpty else {
            return AudioBufferLayout(
                kind: .incompatible,
                frameCount: 0,
                byteCount: totalBytes
            )
        }

        if buffers.count == 1 {
            let buffer = buffers[0]
            let byteSize = buffer.byteSize
            let looksInterleaved = byteSize > 0
                && byteSize % frameBytes == 0
                && (
                    buffer.channelCount == channels
                        || buffer.channelCount == 0
                        || buffer.channelCount == 1
                )
            guard looksInterleaved else {
                return AudioBufferLayout(
                    kind: .incompatible,
                    frameCount: 0,
                    byteCount: totalBytes
                )
            }
            return AudioBufferLayout(
                kind: .interleaved,
                frameCount: byteSize / frameBytes,
                byteCount: totalBytes
            )
        }

        let oneChannelPerBuffer = buffers.allSatisfy {
            $0.channelCount == 1 && $0.byteSize > 0 && $0.byteSize % sampleWidth == 0
        }
        guard buffers.count == channels, oneChannelPerBuffer else {
            return AudioBufferLayout(
                kind: .incompatible,
                frameCount: 0,
                byteCount: totalBytes
            )
        }

        let frames = buffers.map { $0.byteSize / sampleWidth }.min() ?? 0
        return AudioBufferLayout(
            kind: .deinterleaved,
            frameCount: frames,
            byteCount: totalBytes
        )
    }
}
