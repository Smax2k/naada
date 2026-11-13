import NaadaCore
import SwiftUI

/// Jauge du son réellement capté par le moteur, dessinée en segments.
///
/// Elle n'a aucun mouvement propre : ses segments s'allument selon les mesures
/// RMS publiées par `RecorderViewModel` pendant l'enregistrement, et la jauge
/// retombe vide à l'arrêt. Au repos, aucun segment n'est allumé.
struct AudioLevelView: View {
    let level: Float
    let isActive: Bool

    /// Nombre de segments de la jauge ; le remplissage suit toujours la même
    /// mesure RMS publiée par `RecorderViewModel`.
    private let segmentCount = 38

    private var hasSignal: Bool {
        isActive && !AudioLevel.isSilent(level)
    }

    private var fraction: CGFloat {
        isActive ? CGFloat(AudioLevel.meterFraction(level)) : 0
    }

    private var litSegments: Int {
        guard fraction > 0 else { return 0 }
        return min(segmentCount, Int((fraction * CGFloat(segmentCount)).rounded(.up)))
    }

    private var decibels: Int {
        guard level > 0 else { return Int(AudioLevel.meterFloorDecibels) }
        let value = 20 * log10(min(1, level))
        return max(Int(AudioLevel.meterFloorDecibels), Int(value.rounded()))
    }

    private var accessibilityValue: String {
        guard isActive else {
            return NSLocalizedString("Idle, no capture in progress", comment: "Audio level accessibility idle value")
        }
        guard hasSignal else {
            return NSLocalizedString("Silence, no sound detected", comment: "Audio level accessibility silent value")
        }
        return String(
            format: NSLocalizedString(
                "Sound received, level %lld decibels",
                comment: "Audio level accessibility value with decibels"
            ),
            decibels
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        index < litSegments
                            ? AnyShapeStyle(Color.red)
                            : AnyShapeStyle(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 22)
        .accessibilityRepresentation {
            ProgressView(value: Double(fraction), total: 1) {
                Text(String(
                    format: NSLocalizedString(
                        "Captured sound level: %@",
                        comment: "Audio level accessibility label"
                    ),
                    accessibilityValue
                ))
            }
        }
        .accessibilityHint(
            NSLocalizedString(
                "The meter follows the sound written to the MP3 file while recording.",
                comment: "Audio level accessibility hint"
            )
        )
    }
}
