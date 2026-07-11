extension TimelineDisplayRecord {
    var eventNodeAccessibilityLabel: String {
        "\(title), \(event.severity.rawValue), \(timestamp.inspectorDateString)"
    }

    var eventNodeHelpText: String {
        "\(title)\n\(subtitle)\n\(timestamp.inspectorDateString)"
    }
}
