import SwiftUI

struct TimelineFilterSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TimelineFilterDraft()
    let visibleButtonCount: Int
    let filters: [TimelineFilterDefinition]
    let state: (TimelineFilterDefinition) -> CategoryDisplayState
    let setEnabled: (TimelineFilterDefinition, Bool) -> Void
    let cycle: (TimelineFilterDefinition) -> Void
    let delete: (TimelineFilterDefinition) -> Void
    let create: (TimelineFilterDefinition) -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TimelineFilterSettingsHeader(
                visibleButtonCount: visibleButtonCount,
                close: { dismiss() }
            )
            Divider()

            HStack(spacing: 0) {
                TimelineFilterList(
                    filters: filters,
                    state: state,
                    setEnabled: setEnabled,
                    cycle: cycle,
                    delete: delete
                )
                .frame(width: 390)

                Divider()

                TimelineFilterDraftEditor(
                    draft: $draft,
                    create: {
                        create(draft.makeFilter())
                        draft = TimelineFilterDraft()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Divider()
            footer
        }
        .frame(width: 820, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button {
                reset()
            } label: {
                Label("Restore Defaults", systemImage: "arrow.counterclockwise")
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }
}

private struct TimelineFilterSettingsHeader: View {
    let visibleButtonCount: Int
    let close: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline Filters")
                    .font(.title3.weight(.semibold))
                Text("\(visibleButtonCount) visible buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ToolbarIconButton(symbolName: "xmark", helpText: "Close", action: close)
        }
        .padding(16)
    }
}
