import SwiftUI

struct ContentView: View {
    @StateObject private var model = RecorderViewModel.shared

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
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Naada")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Enregistreur de session audio")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
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
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "app", title: "Application source") {
                HStack(spacing: 8) {
                    Picker("", selection: $model.selectedApplicationPID) {
                        Text("Choisir une application…")
                            .tag(pid_t?.none)
                        ForEach(model.applications) { application in
                            Text(application.name)
                                .tag(Optional(application.pid))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    .disabled(model.isBusy)

                    Button {
                        model.refreshApplications()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Actualiser la liste des applications ouvertes")
                    .disabled(model.isBusy)
                }
            }

            Divider().padding(.leading, 42)

            settingRow(icon: "folder", title: "Dossier de sortie") {
                HStack(spacing: 10) {
                    Text(folderDisplay)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(model.outputFolder == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Choisir…") {
                        model.chooseOutputFolder()
                    }
                    .disabled(model.isBusy)
                }
            }

            Divider().padding(.leading, 42)

            settingRow(icon: "textformat", title: "Titre de session") {
                TextField("Réunion, cours, appel…", text: $model.sessionTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
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
                            Label("Arrêter", systemImage: "stop.fill")
                                .frame(minWidth: 126)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                    } else if model.isBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.phase == .stopping ? "Finalisation…" : "Préparation…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 126)
                    } else {
                        Button {
                            model.startRecording()
                        } label: {
                            Label("Enregistrer", systemImage: "record.circle")
                                .frame(minWidth: 126)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                        .disabled(!model.canStart)
                    }

                    Text(model.canStop ? "Le fichier sera finalisé à l'arrêt." : (model.isBusy ? "Veuillez patienter." : "Aucun démarrage automatique."))
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
            .help("Masquer ce message")
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
                Text("Dernier fichier enregistré")
                    .font(.callout.weight(.semibold))
                Text(url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Afficher dans le Finder") {
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
                "Capture audio de l'application uniquement · aucun micro · le son système reste audible.",
                systemImage: "speaker.wave.2"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("macOS peut demander l'autorisation « Enregistrement de l'écran » au premier démarrage, même si Naada ne capture aucune image. Aucune capture ne démarre avant votre clic.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recordingHeadline: String {
        if let application = model.selectedApplication {
            return model.phase.isRecording
                ? "Enregistrement de \(application.name)"
                : application.name
        }
        return "Aucune source sélectionnée"
    }

    private var statusDetail: String {
        switch model.phase {
        case .idle:
            if let application = model.selectedApplication {
                if model.outputFolder == nil {
                    return "Choisissez un dossier de sortie pour \(application.name)."
                }
                return "Prêt à enregistrer l'audio de \(application.name)."
            }
            return "Choisissez une application source."
        case let .failed(message):
            return message
        case .preparing, .recording, .stopping:
            return model.phase.detail
        }
    }

    private var folderDisplay: String {
        guard let folder = model.outputFolder else {
            return "Aucun dossier choisi"
        }
        return (folder.path as NSString).abbreviatingWithTildeInPath
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
        }
        .padding(.vertical, 11)
    }
}
