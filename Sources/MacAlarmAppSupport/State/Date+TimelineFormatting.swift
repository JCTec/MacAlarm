import Foundation

extension Date {
    var timelineTickString: String {
        formatted(TimelineDateFormats.tick)
    }

    var timelineTimeString: String {
        formatted(TimelineDateFormats.time)
    }

    var inspectorDateString: String {
        formatted(TimelineDateFormats.inspector)
    }
}

private enum TimelineDateFormats {
    static let tick = Date.FormatStyle.dateTime
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)

    static let time = Date.FormatStyle.dateTime
        .hour()
        .minute()
        .second()

    static let inspector = Date.FormatStyle.dateTime
        .day()
        .month(.abbreviated)
        .year()
        .hour()
        .minute()
        .second()
}
