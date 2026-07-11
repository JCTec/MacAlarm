import Foundation

public enum TimelineCSVExporter {
    public static let header = "timestamp,source,event,severity,category,title,subtitle,hash,previousHash"

    public static func export(records: [TimelineRecord]) -> String {
        let rows = records.map { record in
            [
                record.timestamp.ISO8601Format(),
                record.event.source,
                record.event.name,
                record.event.severity.rawValue,
                record.category.rawValue,
                record.title,
                record.subtitle,
                record.record.hash,
                record.record.previousHash,
            ].map(csvEscape).joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    public static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
