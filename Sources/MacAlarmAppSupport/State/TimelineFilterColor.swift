import SwiftUI

public struct TimelineFilterColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    public static let unlock = TimelineFilterColor(red: 0.04, green: 0.55, blue: 0.48)
    public static let lock = TimelineFilterColor(red: 0.22, green: 0.36, blue: 0.74)
    public static let sleepWake = TimelineFilterColor(red: 0.48, green: 0.38, blue: 0.68)
    public static let app = TimelineFilterColor(red: 0.18, green: 0.50, blue: 0.78)
    public static let file = TimelineFilterColor(red: 0.78, green: 0.48, blue: 0.14)
    public static let notification = TimelineFilterColor(red: 0.75, green: 0.24, blue: 0.38)
    public static let agent = TimelineFilterColor(red: 0.39, green: 0.47, blue: 0.53)
    public static let log = TimelineFilterColor(red: 0.12, green: 0.56, blue: 0.62)
    public static let ledger = TimelineFilterColor(red: 0.52, green: 0.40, blue: 0.24)
    public static let custom = TimelineFilterColor(red: 0.58, green: 0.32, blue: 0.72)
    public static let audio = TimelineFilterColor(red: 0.10, green: 0.58, blue: 0.80)
    public static let secondary = TimelineFilterColor(red: 0.45, green: 0.47, blue: 0.50)
}
