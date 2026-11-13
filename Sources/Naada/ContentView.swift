import NaadaCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model: RecorderViewModel
    @State private var isPresetManagerPresented = false
    private let settingActionWidth: CGFloat = 88

    @MainActor
    init(model: RecorderViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? RecorderViewModel.shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            settingsCard
            recorderCard

            if let error = model.errorMessage {
                errorCard(error)
            }

            if let url = model.lastOutputURL {
                outputCard(url)
            }

            footer
        }
        .padding(24)
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            (NSApp.delegate as? AppDelegate)?.model = model
        }
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

            HStack(spacing: 8) {
                statusPill
                presetControl
            }
        }
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

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "app", title: NSLocalizedString("Source application", comment: "Source picker row title")) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.isBusy)

                    Button {
                        model.refreshApplications()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("Refresh the list of open applications", comment: "Refresh applications tooltip"))
                    .frame(width: settingActionWidth, alignment: .trailing)
                    .disabled(model.isBusy)
                }
            }

            Divider().padding(.leading, 42)

            settingRow(icon: "mic", title: NSLocalizedString("Microphone", comment: "Microphone picker row title")) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.isBusy)

                    Button {
                        model.refreshMicrophones()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("Refresh the list of microphones", comment: "Refresh microphones tooltip"))
                    .frame(width: settingActionWidth, alignment: .trailing)
                    .disabled(model.isBusy)
                }
            }

            Divider().padding(.leading, 42)

            settingRow(icon: "folder", title: NSLocalizedString("Output folder", comment: "Output folder row title")) {
                HStack(spacing: 8) {
                    Text(folderDisplay)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(model.outputFolder == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(NSLocalizedString("Choose…", comment: "Choose output folder button")) {
                        model.chooseOutputFolder()
                    }
                    .frame(width: settingActionWidth, alignment: .trailing)
                    .disabled(model.isBusy)
                }
            }

            Divider().padding(.leading, 42)

            settingRow(icon: "textformat", title: NSLocalizedString("Session title", comment: "Session title row title")) {
                TextField(NSLocalizedString("Meeting, class, call…", comment: "Session title placeholder"), text: $model.sessionTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(cardBackground)
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.elapsedText)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    if model.canStop {
                        Button {
                            model.stopRecording()
                        } label: {
                            Label(NSLocalizedString("Stop", comment: "Stop recording button"), systemImage: "stop.fill")
                                .frame(minWidth: 126)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
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
                        .frame(minWidth: 126)
                    } else {
                        Button {
                            model.startRecording()
                        } label: {
                            Label(NSLocalizedString("Record", comment: "Start recording button"), systemImage: "record.circle")
                                .frame(minWidth: 126)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                        .disabled(!model.canStart)
                    }

                    Text(recorderHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            AudioLevelView(level: model.audioLevel, isActive: model.phase.isRecording)
        }
        .padding(18)
        .background(cardBackground)
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
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
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
