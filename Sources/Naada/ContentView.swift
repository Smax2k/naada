import NaadaCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model: RecorderViewModel
    @State private var isPresetManagerPresented = false
    private let settingActionWidth: CGFloat = 88
    private let refreshActionWidth: CGFloat = 26
    private let recordButtonWidth: CGFloat = 300

    @MainActor
    init(model: RecorderViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? RecorderViewModel.shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator

            sourcesSection
            separator

            recorderSection
            separator

            sessionSection
            separator

            actionSection

            if let error = model.errorMessage {
                errorCard(error)
                    .padding(.top, 14)
            }

            if let url = model.lastOutputURL {
                outputCard(url)
                    .padding(.top, 14)
            }

            separator
                .padding(.top, 16)

            footer
                .padding(.top, 14)
        }
        .padding(24)
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            (NSApp.delegate as? AppDelegate)?.model = model
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.6))
            .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 14) {
            NaadaMark()

            VStack(alignment: .leading, spacing: 2) {
                Text("Naada")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(NSLocalizedString("Session audio recorder", comment: "Window subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
        }
        .padding(.bottom, 14)
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(model.phase.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
        .foregroundStyle(statusColor)
        .accessibilityIdentifier("statusBadge")
    }

    private var presetControl: some View {
        Button {
            isPresetManagerPresented.toggle()
        } label: {
            Label("Presets", systemImage: "bookmark")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.isBusy)
        .help(NSLocalizedString("Manage source, title and folder presets", comment: "Preset button tooltip"))
        .accessibilityIdentifier("presetManagerButton")
        .popover(isPresented: $isPresetManagerPresented, arrowEdge: .bottom) {
            PresetManagerView(model: model)
        }
    }

    /// Console à deux entrées : l'application et le microphone forment un seul
    /// bloc, reliés par une accolade purement décorative (aucun contrôle inerte).
    private var sourcesSection: some View {
        VStack(spacing: 0) {
            settingRow(icon: "app", title: NSLocalizedString("Source application", comment: "Source picker row title")) {
                applicationPicker
            }

            settingRow(icon: "mic", title: NSLocalizedString("Microphone", comment: "Microphone picker row title")) {
                microphonePicker
            }
        }
        .padding(.trailing, 18)
        .overlay(alignment: .trailing) {
            SourceListBrace()
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.9),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
                .frame(width: 9)
                .padding(.vertical, 10)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
    }

    private var applicationPicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.selectedApplicationID) {
                Text(NSLocalizedString("No application", comment: "Source picker no application"))
                    .tag(RememberedSource?.none)
                ForEach(model.applications) { application in
                    Text(application.name)
                        .tag(RememberedSource?.some(application.rememberedSource))
                }
            }
            .labelsHidden()
            .accessibilityLabel(Text(NSLocalizedString("Source application", comment: "Source picker row title")))
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isBusy)

            Button {
                model.refreshApplications()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(NSLocalizedString("Refresh the list of open applications", comment: "Refresh applications tooltip"))
            .frame(width: refreshActionWidth, alignment: .trailing)
            .disabled(model.isBusy)
        }
    }

    private var microphonePicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.selectedMicrophone) {
                Text(NSLocalizedString("No microphone", comment: "No microphone choice"))
                    .tag(MicrophoneChoice.none)
                Text(model.systemDefaultMicrophoneLabel)
                    .tag(MicrophoneChoice.systemDefault)
                ForEach(model.microphones) { microphone in
                    Text(microphoneLabel(microphone))
                        .tag(microphone.choice)
                }
            }
            .labelsHidden()
            .accessibilityLabel(Text(NSLocalizedString("Microphone", comment: "Microphone picker row title")))
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isBusy)

            Button {
                model.refreshMicrophones()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(NSLocalizedString("Refresh the list of microphones", comment: "Refresh microphones tooltip"))
            .frame(width: refreshActionWidth, alignment: .trailing)
            .disabled(model.isBusy)
        }
    }

    /// Minuterie dominante et centrée, puis la phrase d'état et la jauge : la
    /// capture se lit avant les réglages de session.
    private var recorderSection: some View {
        VStack(spacing: 9) {
            Text(model.elapsedText)
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityIdentifier("elapsedTime")

            HStack(spacing: 8) {
                if model.phase.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                }
                Text(recordingHeadline)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(statusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            AudioLevelView(level: model.audioLevel, isActive: model.phase.isRecording)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var sessionSection: some View {
        VStack(spacing: 0) {
            settingRow(icon: nil, title: NSLocalizedString("Session title", comment: "Session title row title")) {
                TextField(NSLocalizedString("Meeting, class, call…", comment: "Session title placeholder"), text: $model.sessionTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isBusy)
            }

            settingRow(icon: nil, title: NSLocalizedString("Output folder", comment: "Output folder row title")) {
                HStack(spacing: 8) {
                    Text(folderDisplay)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(model.outputFolder == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.7))
                        )

                    Button(NSLocalizedString("Choose…", comment: "Choose output folder button")) {
                        model.chooseOutputFolder()
                    }
                    .frame(width: settingActionWidth, alignment: .trailing)
                    .disabled(model.isBusy)
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// Rangée d'action : les presets à gauche, l'enregistrement au centre, et
    /// l'aide au repos juste dessous.
    private var actionSection: some View {
        VStack(spacing: 9) {
            ZStack {
                recordControl

                HStack(spacing: 0) {
                    presetControl
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)

            Text(recorderHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var recordControl: some View {
        if model.canStop {
            Button {
                model.stopRecording()
            } label: {
                Label(NSLocalizedString("Stop", comment: "Stop recording button"), systemImage: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .frame(width: recordButtonWidth)
        } else if model.isBusy {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(model.phase == .stopping
                    ? NSLocalizedString("Finalizing…", comment: "Stop in progress")
                    : NSLocalizedString("Preparing…", comment: "Start in progress"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: recordButtonWidth)
        } else {
            Button {
                model.startRecording()
            } label: {
                Label(NSLocalizedString("Record", comment: "Start recording button"), systemImage: "record.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .frame(width: recordButtonWidth)
            .disabled(!model.canStart)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                model.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(NSLocalizedString("Hide this message", comment: "Dismiss error tooltip"))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.25))
        )
    }

    private func outputCard(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Last recorded file", comment: "Last output file title"))
                    .font(.callout.weight(.semibold))
                Text(url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(NSLocalizedString("Show in Finder", comment: "Reveal last file button")) {
                model.revealLastOutput()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(cardBackground)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                NSLocalizedString(
                    "Audio only · no images · no automatic start.",
                    comment: "Audio-only footer"
                ),
                systemImage: "speaker.wave.2"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(NSLocalizedString(
                "Microphone access is requested only when a microphone is selected, and only after you click Record. macOS may also ask for permission to record system audio. No images are captured, sound stays audible, and no capture starts before your click.",
                comment: "Audio-only authorization note"
            ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recorderHint: String {
        if model.canStop {
            return NSLocalizedString("The file will be finalized when you stop.", comment: "Recorder hint while recording")
        }
        if model.isBusy {
            return NSLocalizedString("Please wait.", comment: "Recorder hint while busy")
        }
        return NSLocalizedString("No automatic start.", comment: "Recorder hint at rest")
    }

    private var recordingHeadline: String {
        let applicationName = model.selectedApplicationID?.name
        let microphoneName = model.selectedMicrophoneName

        switch (applicationName, microphoneName) {
        case let (application?, microphone?):
            let key = model.phase.isRecording
                ? "Recording %@ and the microphone “%@”"
                : "%@ and the microphone “%@”"
            return String(
                format: NSLocalizedString(
                    key,
                    comment: "Recording headline with application and microphone"
                ),
                application,
                microphone
            )
        case let (application?, nil):
            return model.phase.isRecording
                ? String(
                    format: NSLocalizedString(
                        "Recording %@",
                        comment: "Recording headline with source name"
                    ),
                    application
                )
                : application
        case let (nil, microphone?):
            let key = model.phase.isRecording
                ? "Recording the microphone “%@”"
                : "Microphone “%@”"
            return String(
                format: NSLocalizedString(
                    key,
                    comment: "Recording headline with microphone name"
                ),
                microphone
            )
        case (nil, nil):
            return NSLocalizedString("No source selected", comment: "Recording headline without source")
        }
    }

    private var statusDetail: String {
        switch model.phase {
        case .idle:
            return idleStatusDetail
        case let .failed(message):
            return message
        case .preparing, .recording, .stopping:
            return model.phase.detail
        }
    }

    /// Nomme la source qui bloque ou les sources réellement actives : jamais
    /// de repli silencieux sur l'autre source.
    private var idleStatusDetail: String {
        let applicationName = model.selectedApplicationID?.name
        let microphoneName = model.selectedMicrophoneName

        switch model.startDecision {
        case .noSourceSelected:
            return NSLocalizedString(
                "Choose an application, a microphone, or both.",
                comment: "Idle status without any source"
            )
        case let .applicationUnavailable(application):
            return String(
                format: NSLocalizedString(
                    "%@ is not open. Open it to record.",
                    comment: "Idle status when source application is closed"
                ),
                application.name
            )
        case let .microphoneUnavailable(microphone):
            return String(
                format: NSLocalizedString(
                    "The selected microphone “%@” is not available. Choose another microphone.",
                    comment: "Idle status when the selected microphone is missing"
                ),
                microphone.rememberedDisplayName
            )
        case .outputFolderMissing:
            return folderMissingDetail(
                applicationName: applicationName,
                microphoneName: microphoneName
            )
        case .allowed:
            return readyDetail(
                applicationName: applicationName,
                microphoneName: microphoneName
            )
        }
    }

    private func folderMissingDetail(
        applicationName: String?,
        microphoneName: String?
    ) -> String {
        switch (applicationName, microphoneName) {
        case let (application?, microphone?):
            return String(
                format: NSLocalizedString(
                    "Choose an output folder for %@ and the microphone “%@”.",
                    comment: "Idle status without output folder for application and microphone"
                ),
                application,
                microphone
            )
        case let (application?, nil):
            return String(
                format: NSLocalizedString(
                    "Choose an output folder for %@.",
                    comment: "Idle status without output folder"
                ),
                application
            )
        case let (nil, microphone?):
            return String(
                format: NSLocalizedString(
                    "Choose an output folder for the microphone “%@”.",
                    comment: "Idle status without output folder for microphone"
                ),
                microphone
            )
        case (nil, nil):
            return NSLocalizedString("No folder chosen", comment: "Output folder placeholder")
        }
    }

    private func readyDetail(
        applicationName: String?,
        microphoneName: String?
    ) -> String {
        switch (applicationName, microphoneName) {
        case let (application?, microphone?):
            return String(
                format: NSLocalizedString(
                    "Ready to record audio from %@ and the microphone “%@”.",
                    comment: "Idle status ready to record from application and microphone"
                ),
                application,
                microphone
            )
        case let (application?, nil):
            return String(
                format: NSLocalizedString(
                    "Ready to record audio from %@.",
                    comment: "Idle status ready to record"
                ),
                application
            )
        case let (nil, microphone?):
            return String(
                format: NSLocalizedString(
                    "Ready to record audio from the microphone “%@”.",
                    comment: "Idle status ready to record from microphone"
                ),
                microphone
            )
        case (nil, nil):
            return NSLocalizedString("No source selected", comment: "Recording headline without source")
        }
    }

    private var folderDisplay: String {
        guard let folder = model.outputFolder else {
            return NSLocalizedString("No folder chosen", comment: "Output folder placeholder")
        }
        return (folder.path as NSString).abbreviatingWithTildeInPath
    }

    private func microphoneLabel(_ microphone: MicrophoneOption) -> String {
        guard !microphone.isAvailable else { return microphone.name }
        return String(
            format: NSLocalizedString(
                "%@ (unavailable)",
                comment: "Unavailable microphone entry"
            ),
            microphone.name
        )
    }

    private var statusColor: Color {
        switch model.phase {
        case .idle:
            return .secondary
        case .preparing, .stopping:
            return .orange
        case .recording:
            return .red
        case .failed:
            return .orange
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55))
            )
    }

    private func settingRow<Content: View>(
        icon: String?,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            } else {
                Color.clear
                    .frame(width: 20, height: 1)
            }
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
    }
}

/// Accolade discrète reliant les deux listes d'entrée. Purement décorative :
/// aucun clic, aucune cible, rien qui promette une action inexistante.
private struct SourceListBrace: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let spineX = width * 0.62
        let curl: CGFloat = 5
        let middle = rect.midY

        var path = Path()
        guard height > 24 else {
            path.move(to: CGPoint(x: spineX, y: rect.minY))
            path.addLine(to: CGPoint(x: spineX, y: rect.maxY))
            return path
        }

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: spineX, y: rect.minY + curl),
            control: CGPoint(x: spineX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: spineX, y: middle - curl))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: middle),
            control: CGPoint(x: rect.maxX, y: middle - curl + 1)
        )
        path.addQuadCurve(
            to: CGPoint(x: spineX, y: middle + curl),
            control: CGPoint(x: rect.maxX, y: middle + curl - 1)
        )
        path.addLine(to: CGPoint(x: spineX, y: rect.maxY - curl))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: spineX, y: rect.maxY)
        )
        return path
    }
}
