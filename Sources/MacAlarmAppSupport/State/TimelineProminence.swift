import CoreGraphics
import MacAlarmCore

public struct TimelineProminence: Equatable, Sendable {
    public var opacity: Double
    public var circleSize: CGFloat
    public var stemLength: CGFloat
    public var lineWidth: CGFloat
    public var labelVisible: Bool
    public var zIndex: Double

    public static func forState(_ state: CategoryDisplayState, severity: AlarmSeverity) -> TimelineProminence {
        switch state {
        case .hidden:
            TimelineProminence(opacity: 0, circleSize: 0, stemLength: 0, lineWidth: 0, labelVisible: false, zIndex: 0)
        case .normal:
            TimelineProminence(
                opacity: severity >= .warning ? 0.9 : 0.58,
                circleSize: severity >= .warning ? 24 : 18,
                stemLength: severity >= .warning ? 72 : 44,
                lineWidth: severity >= .warning ? 1.5 : 1,
                labelVisible: severity >= .warning,
                zIndex: severity >= .warning ? 20 : 5
            )
        case .spotlight:
            TimelineProminence(
                opacity: 1,
                circleSize: severity >= .warning ? 38 : 30,
                stemLength: severity >= .warning ? 124 : 94,
                lineWidth: 2,
                labelVisible: severity >= .warning,
                zIndex: 50
            )
        }
    }
}
