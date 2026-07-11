import SwiftUI

struct TimelineFilterDraftEditor: View {
    @Binding var draft: TimelineFilterDraft
    let create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Filter")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Display name", text: $draft.title)

                HStack(spacing: 10) {
                    Picker("Icon", selection: $draft.symbolName) {
                        ForEach(TimelineFilterDraft.iconPresets, id: \.self) { symbol in
                            Label(symbol, systemImage: symbol).tag(symbol)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Color", selection: $draft.colorID) {
                        ForEach(TimelineFilterDraft.colorPresets) { preset in
                            Label(preset.title, systemImage: "circle.fill")
                                .foregroundStyle(preset.color.color)
                                .tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                TextField("Source, e.g. custom", text: $draft.source)
                TextField("Event name contains, e.g. audio", text: $draft.nameContains)
                TextField("Event name exactly equals", text: $draft.nameEquals)

                HStack(spacing: 10) {
                    TextField("Metadata key", text: $draft.metadataKey)
                    TextField("Metadata value", text: $draft.metadataValue)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Audio Template") {
                    draft = .audioTemplate
                }
                Button("Clear") {
                    draft = TimelineFilterDraft()
                }
                Spacer()
                Button(action: create) {
                    Label("Create", systemImage: "plus")
                }
                .disabled(!draft.canCreate)
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Match Preview")
                    .font(.subheadline.weight(.semibold))
                Text(draft.match.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding(16)
    }
}
