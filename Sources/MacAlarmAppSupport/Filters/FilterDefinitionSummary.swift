import SwiftUI

struct FilterDefinitionSummary: View {
    let filter: TimelineFilterDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(filter.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                if filter.isBuiltIn {
                    TimelineFilterTemplateBadge()
                }
            }

            Text(filter.match.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
