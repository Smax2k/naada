import Foundation

/// Mesure de niveau d'un flux PCM 16 bits, sans dépendance à la capture.
///
/// Le niveau est la valeur efficace (RMS) normalisée sur l'échelle pleine des
/// `Int16` : 0 pour le silence numérique, 1 pour une onde à pleine échelle.
/// Aucun lissage, aucune valeur inventée : la jauge ne bouge que lorsqu'un
/// échantillon réel arrive.
public enum AudioLevel {
    /// En dessous de ce niveau normalisé, la source est considérée silencieuse
    /// (≈ −60 dBFS), ce qui évite de faire vibrer la jauge sur le bruit de
    /// quantification.
    public static let silenceThreshold: Float = 0.001

    /// Plancher d'affichage de la jauge, en décibels pleine échelle.
    public static let meterFloorDecibels: Float = -60

    /// RMS normalisé dans [0, 1] d'échantillons PCM 16 bits.
    public static func normalizedRMS(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var sumOfSquares = 0.0
        for sample in samples {
            let value = Double(sample)
            sumOfSquares += value * value
        }
        let rms = (sumOfSquares / Double(samples.count)).squareRoot()
        let normalized = rms / Double(Int16.max)
        return Float(min(1, max(0, normalized)))
    }

    /// `true` pour le silence numérique et pour tout niveau sous le seuil.
    public static func isSilent(_ level: Float) -> Bool {
        !(level > silenceThreshold)
    }

    /// Position de la jauge sur une échelle en décibels : un RMS de 0,1
    /// (−20 dBFS) remplit environ deux tiers de la barre, un RMS de 1 la
    /// remplit entièrement. Le silence reste à 0, sans animation.
    public static func meterFraction(_ level: Float) -> Float {
        guard level > silenceThreshold else { return 0 }

        let clamped = min(1, level)
        let decibels = 20 * log10(clamped)
        let range = -meterFloorDecibels
        return min(1, max(0, (decibels - meterFloorDecibels) / range))
    }
}
