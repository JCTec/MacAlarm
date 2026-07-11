import Foundation

struct TimelineFilterDraftFactory: Sendable {
    func makeFilter(from draft: TimelineFilterDraft) -> TimelineFilterDefinition {
        TimelineFilterDefinition(
            id: "custom.\(UUID().uuidString)",
            title: draft.title.trimmed,
            symbolName: draft.symbolName,
            color: color(for: draft.colorID),
            match: draft.match,
            defaultState: .spotlight,
            isBuiltIn: false,
            isEnabled: true
        )
    }

    private func color(for id: String) -> TimelineFilterColor {
        TimelineFilterDraftCatalog.colorPresets.first { $0.id == id }?.color ?? .custom
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
