import SwiftUI

struct FilterDefinitionRow: View {
    let filter: TimelineFilterDefinition
    let state: CategoryDisplayState
    let setEnabled: (Bool) -> Void
    let cycle: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            enabledToggle

            IconTile(
                symbolName: filter.symbolName,
                tintColor: filter.isEnabled ? filter.tintColor : .secondary,
                size: 34,
                opacity: filter.isEnabled ? 0.18 : 0.08
            )

            FilterDefinitionSummary(filter: filter)

            Spacer()

            TimelineFilterStatePill(filter: filter, state: state, action: cycle)

            if !filter.isBuiltIn {
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Delete filter")
            }
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .strokeBorder(filter.tintColor.opacity(filter.isEnabled ? 0.22 : 0.08), lineWidth: 1)
        }
    }

    private var enabledToggle: some View {
        Toggle(
            "",
            isOn: Binding(
                get: { filter.isEnabled },
                set: { newValue in
                    setEnabled(newValue)
                }
            )
        )
        .labelsHidden()
        .toggleStyle(.switch)
    }

    private var rowBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(filter.isEnabled ? 0.70 : 0.32)
    }
}
