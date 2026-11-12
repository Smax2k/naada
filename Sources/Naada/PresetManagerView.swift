import AppKit
import NaadaCore
import SwiftUI

/// Gestion compacte des presets, ouverte depuis l'en-tête de la fenêtre.
///
/// Le panneau ne démarre jamais de capture : il ne fait que lire et modifier
/// les trois réglages (source, titre, dossier) de la fenêtre principale.
struct PresetManagerView: View {
    @ObservedObject var model: RecorderViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var newPresetName = ""
    @State private var renamingPresetID: UUID?
    @State private var renameDraft = ""
    @State private var presetPendingDeletion: RecordingPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if model.presets.isEmpty {
                emptyState
            } else {
                presetList
            }

            Divider()
            creationSection
        }
        .padding(16)
        .frame(width: 380)
        .confirmationDialog(
            "Supprimer « \(presetPendingDeletion?.name ?? "") » ?",
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let preset = presetPendingDeletion {
                    model.deletePreset(id: preset.id)
                }
                presetPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) {
                presetPendingDeletion = nil
            }
        } message: {
            Text("Le preset sera retiré. Les réglages courants et le dossier ne sont pas modifiés.")
        }
        .accessibilityIdentifier("presetManager")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Presets")
                    .font(.headline)
                Text("Source, titre et dossier en un clic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(model.presets.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Fermer les presets")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Aucun preset enregistré", systemImage: "bookmark.slash")
                .font(.callout.weight(.semibold))
            Text("Votre source, votre titre et votre dossier actuels restent inchangés. Créez un premier preset ci-dessous.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(panelBackground)
    }

    private var presetList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.presets) { preset in
                    presetRow(preset)

                    if preset.id != model.presets.last?.id {
                        Divider().padding(.leading, 28)
                    }
                }
            }
        }
        .frame(maxHeight: 252)
        .background(panelBackground)
    }

    @ViewBuilder
    private func presetRow(_ preset: RecordingPreset) -> some View {
        if renamingPresetID == preset.id {
            renameRow(preset)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Label(preset.source.name, systemImage: "app")
                    Label(preset.title.isEmpty ? "Sans titre" : preset.title, systemImage: "textformat")
                    Label(folderLabel(for: preset), systemImage: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Button("Appliquer") {
                        model.applyPreset(preset)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isBusy)
                    .help("Remplacer la source, le titre et le dossier par ce preset")

                    Menu {
                        Button("Renommer") {
                            beginRename(preset)
                        }

                        Button("Mettre à jour depuis la configuration actuelle") {
                            model.updatePreset(id: preset.id)
                        }
                        .disabled(!model.canSavePreset)

                        Divider()

                        Button("Supprimer…", role: .destructive) {
                            presetPendingDeletion = preset
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                    .disabled(model.isBusy)
                    .help("Renommer, mettre à jour ou supprimer ce preset")
                }
            }
            .padding(10)
        }
    }

    private func renameRow(_ preset: RecordingPreset) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Renommer « \(preset.name) »")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Nom du preset", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename() }

                Button("Enregistrer") {
                    commitRename()
                }
                .disabled(trimmedRenameDraft.isEmpty)

                Button("Annuler") {
                    cancelRename()
                }
            }
        }
        .padding(10)
    }

    private var creationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Créer depuis la configuration actuelle")
                .font(.callout.weight(.semibold))
            Text("Le preset mémorise la source sélectionnée, le titre et le dossier visibles dans la fenêtre principale.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Nom du preset", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createPreset() }

                Button("Créer") {
                    createPreset()
                }
                .disabled(trimmedNewPresetName.isEmpty || !model.canSavePreset)
            }

            if !model.canSavePreset {
                Text("Choisissez d'abord une application source, hors enregistrement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { presetPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    presetPendingDeletion = nil
                }
            }
        )
    }

    private var trimmedNewPresetName: String {
        newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRenameDraft: String {
        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createPreset() {
        guard !trimmedNewPresetName.isEmpty else { return }
        guard model.createPreset(named: newPresetName) != nil else { return }
        newPresetName = ""
    }

    private func beginRename(_ preset: RecordingPreset) {
        renamingPresetID = preset.id
        renameDraft = preset.name
    }

    private func commitRename() {
        guard let id = renamingPresetID, !trimmedRenameDraft.isEmpty else { return }
        guard model.renamePreset(id: id, to: renameDraft) else { return }
        cancelRename()
    }

    private func cancelRename() {
        renamingPresetID = nil
        renameDraft = ""
    }

    private func folderLabel(for preset: RecordingPreset) -> String {
        guard let path = preset.folderPath else {
            return "Dossier actuel conservé"
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45))
            )
    }
}
