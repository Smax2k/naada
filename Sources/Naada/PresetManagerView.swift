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
            String(
                format: NSLocalizedString("Delete “%@”?", comment: "Preset deletion dialog title"),
                presetPendingDeletion?.name ?? ""
            ),
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Delete", comment: "Confirm preset deletion"), role: .destructive) {
                if let preset = presetPendingDeletion {
                    model.deletePreset(id: preset.id)
                }
                presetPendingDeletion = nil
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel preset deletion"), role: .cancel) {
                presetPendingDeletion = nil
            }
        } message: {
            Text(NSLocalizedString(
                "The preset will be removed. Current settings and folder stay unchanged.",
                comment: "Preset deletion message"
            ))
        }
        .accessibilityIdentifier("presetManager")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Presets")
                    .font(.headline)
                Text(NSLocalizedString("Source, title and folder in one click.", comment: "Preset manager subtitle"))
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
            .help(NSLocalizedString("Close presets", comment: "Close preset manager tooltip"))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(NSLocalizedString("No saved presets", comment: "Empty preset state title"), systemImage: "bookmark.slash")
                .font(.callout.weight(.semibold))
            Text(NSLocalizedString(
                "Your current source, title and folder stay unchanged. Create a first preset below.",
                comment: "Empty preset state explanation"
            ))
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
                    Label(preset.title.isEmpty
                        ? NSLocalizedString("Untitled", comment: "Preset without title")
                        : preset.title, systemImage: "textformat")
                    Label(folderLabel(for: preset), systemImage: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Button(NSLocalizedString("Apply", comment: "Apply preset button")) {
                        model.applyPreset(preset)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isBusy)
                    .help(NSLocalizedString(
                        "Replace the source, title and folder with this preset",
                        comment: "Apply preset tooltip"
                    ))

                    Menu {
                        Button(NSLocalizedString("Rename", comment: "Rename preset action")) {
                            beginRename(preset)
                        }

                        Button(NSLocalizedString(
                            "Update from current configuration",
                            comment: "Update preset action"
                        )) {
                            model.updatePreset(id: preset.id)
                        }
                        .disabled(!model.canSavePreset)

                        Divider()

                        Button(NSLocalizedString("Delete…", comment: "Delete preset action"), role: .destructive) {
                            presetPendingDeletion = preset
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                    .disabled(model.isBusy)
                    .help(NSLocalizedString(
                        "Rename, update or delete this preset",
                        comment: "Preset actions tooltip"
                    ))
                }
            }
            .padding(10)
        }
    }

    private func renameRow(_ preset: RecordingPreset) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(
                format: NSLocalizedString("Rename “%@”", comment: "Rename preset title"),
                preset.name
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(NSLocalizedString("Preset name", comment: "Preset name placeholder"), text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename() }

                Button(NSLocalizedString("Save", comment: "Save renamed preset")) {
                    commitRename()
                }
                .disabled(trimmedRenameDraft.isEmpty)

                Button(NSLocalizedString("Cancel", comment: "Cancel preset rename")) {
                    cancelRename()
                }
            }
        }
        .padding(10)
    }

    private var creationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Create from current configuration", comment: "Preset creation section title"))
                .font(.callout.weight(.semibold))
            Text(NSLocalizedString(
                "The preset remembers the selected source, title and folder shown in the main window.",
                comment: "Preset creation explanation"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField(NSLocalizedString("Preset name", comment: "Preset name placeholder"), text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createPreset() }

                Button(NSLocalizedString("Create", comment: "Create preset button")) {
                    createPreset()
                }
                .disabled(trimmedNewPresetName.isEmpty || !model.canSavePreset)
            }

            if !model.canSavePreset {
                Text(NSLocalizedString(
                    "Choose a source application first, outside recording.",
                    comment: "Preset creation requirement"
                ))
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
            return NSLocalizedString("Current folder kept", comment: "Preset keeping current output folder")
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
