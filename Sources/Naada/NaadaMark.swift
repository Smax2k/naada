import AppKit
import SwiftUI

/// Affiche la véritable icône de l'application, avec repli sur le symbole waveform.
struct NaadaMark: View {
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let icon = applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "waveform")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @MainActor
    private var applicationIcon: NSImage? {
        NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }
}
