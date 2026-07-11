import Foundation

struct TimelineFilterDraft {
    var title = ""
    var symbolName = "tag.fill"
    var colorID = "custom"
    var source = "custom"
    var nameEquals = ""
    var nameContains = ""
    var metadataKey = ""
    var metadataValue = ""

    var canCreate: Bool {
        !title.trimmed.isEmpty && match.hasCriteria
    }

    var match: TimelineFilterMatch {
        TimelineFilterMatch(
            source: source.trimmed,
            nameEquals: nameEquals.trimmed,
            nameContains: nameContains.trimmed,
            metadataKey: metadataKey.trimmed,
            metadataValue: metadataValue.trimmed
        )
    }

    func makeFilter() -> TimelineFilterDefinition {
        TimelineFilterDraftFactory().makeFilter(from: self)
    }
}

extension TimelineFilterDraft {
    static let audioTemplate = TimelineFilterDraftCatalog.audioTemplate
    static let iconPresets = TimelineFilterDraftCatalog.iconPresets
    static let colorPresets = TimelineFilterDraftCatalog.colorPresets
}

struct TimelineFilterColorPreset: Identifiable, Sendable {
    var id: String
    var title: String
    var color: TimelineFilterColor
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
