import Foundation
import MacAlarmCore

public struct TimelineFilterMatch: Codable, Equatable, Sendable {
    public var category: TimelineCategory?
    public var source: String
    public var nameEquals: String
    public var nameContains: String
    public var metadataKey: String
    public var metadataValue: String

    public init(
        category: TimelineCategory? = nil,
        source: String = "",
        nameEquals: String = "",
        nameContains: String = "",
        metadataKey: String = "",
        metadataValue: String = ""
    ) {
        self.category = category
        self.source = source
        self.nameEquals = nameEquals
        self.nameContains = nameContains
        self.metadataKey = metadataKey
        self.metadataValue = metadataValue
    }

    public func matches(event: AlarmEvent, category eventCategory: TimelineCategory) -> Bool {
        if let category, category != eventCategory {
            return false
        }

        if !source.isBlank, event.source != source.trimmed {
            return false
        }

        if !nameEquals.isBlank, event.name != nameEquals.trimmed {
            return false
        }

        if !nameContains.isBlank,
            event.name.range(of: nameContains.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == nil
        {
            return false
        }

        if !metadataKey.isBlank {
            let key = metadataKey.trimmed
            guard let value = event.metadata[key] else {
                return false
            }

            if !metadataValue.isBlank, value != metadataValue.trimmed {
                return false
            }
        }

        return true
    }

    public var summary: String {
        var parts = [String]()
        if let category {
            parts.append("category=\(category.title)")
        }
        if !source.isBlank {
            parts.append("source=\(source.trimmed)")
        }
        if !nameEquals.isBlank {
            parts.append("name=\(nameEquals.trimmed)")
        }
        if !nameContains.isBlank {
            parts.append("name contains \(nameContains.trimmed)")
        }
        if !metadataKey.isBlank {
            parts.append(
                metadataValue.isBlank
                    ? "metadata has \(metadataKey.trimmed)" : "\(metadataKey.trimmed)=\(metadataValue.trimmed)")
        }
        return parts.isEmpty ? "All events" : parts.joined(separator: ", ")
    }

    public var hasCriteria: Bool {
        category != nil
            || !source.isBlank
            || !nameEquals.isBlank
            || !nameContains.isBlank
            || !metadataKey.isBlank
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }
}
