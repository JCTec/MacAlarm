import Foundation

struct TimeRangePreset: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let menuTitle: String
    let seconds: TimeInterval

    func isSelected(_ timeRange: TimeInterval, tolerance: TimeInterval = 0.5) -> Bool {
        abs(timeRange - seconds) < tolerance
    }
}

extension TimeRangePreset {
    static let last15Minutes = TimeRangePreset(
        id: "15m",
        title: "15m",
        menuTitle: "Last 15 Minutes",
        seconds: 15 * 60
    )

    static let lastHour = TimeRangePreset(
        id: "1h",
        title: "1h",
        menuTitle: "Last 1 Hour",
        seconds: 60 * 60
    )

    static let last6Hours = TimeRangePreset(
        id: "6h",
        title: "6h",
        menuTitle: "Last 6 Hours",
        seconds: 6 * 60 * 60
    )

    static let last24Hours = TimeRangePreset(
        id: "24h",
        title: "24h",
        menuTitle: "Last 24 Hours",
        seconds: 24 * 60 * 60
    )

    static let last7Days = TimeRangePreset(
        id: "7d",
        title: "7d",
        menuTitle: "Last 7 Days",
        seconds: 7 * 24 * 60 * 60
    )

    static let toolbarPresets = [
        last15Minutes,
        lastHour,
        last6Hours,
        last24Hours,
        last7Days,
    ]
}
