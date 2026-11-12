import NaadaCore
import SwiftUI

/// Jauge du son réellement capté par le moteur.
///
/// Elle n'a aucun mouvement propre : sa valeur vient des mesures RMS publiées
/// par `RecorderViewModel` pendant l'enregistrement, et retombe à zéro à
/// l'arrêt. Au repos, elle reste vide et affiche « Repos ».
struct AudioLevelView: View {
    let level: Float
    let isActive: Bool

    private var hasSignal: Bool {
        isActive && !AudioLevel.isSilent(level)
    }

    private var fraction: CGFloat {
        isActive ? CGFloat(AudioLevel.meterFraction(level)) : 0
    }

    private var stateLabel: String {
        guard isActive else { return NSLocalizedString("Idle", comment: "Audio level idle state") }
        return hasSignal
            ? NSLocalizedString("Sound received", comment: "Audio level receiving sound")
            : NSLocalizedString("Silence", comment: "Audio level silent state")
    }

    private var stateDetail: String {
        guard isActive else {
            return NSLocalizedString("No capture in progress", comment: "Audio level inactive detail")
        }
        guard hasSignal else {
            return NSLocalizedString("No sound detected", comment: "Audio level silent detail")
        }
        return "\(decibels) dB"
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

    private var tint: Color {
        hasSignal ? .red : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: isActive ? "waveform" : "waveform.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text(stateLabel)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text(stateDetail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.55), Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 9)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.045 : 0.025))
        )
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
                "The meter follows the source application's actual sound during recording.",
                comment: "Audio level accessibility hint"
            )
        )
    }
}
