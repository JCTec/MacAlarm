import SwiftUI

struct TimelineFilterList: View {
    let filters: [TimelineFilterDefinition]
    let state: (TimelineFilterDefinition) -> CategoryDisplayState
    let setEnabled: (TimelineFilterDefinition, Bool) -> Void
    let cycle: (TimelineFilterDefinition) -> Void
    let delete: (TimelineFilterDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Buttons")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filters) { filter in
                        FilterDefinitionRow(
                            filter: filter,
                            state: state(filter),
                            setEnabled: { setEnabled(filter, $0) },
                            cycle: { cycle(filter) },
                            delete: { delete(filter) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }
}
