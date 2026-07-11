import SwiftUI

public struct TimelineEventPresentation: Equatable, Sendable {
    public var title: String
    public var symbolName: String
    public var color: TimelineFilterColor

    public init(title: String, symbolName: String, color: TimelineFilterColor) {
        self.title = title
        self.symbolName = symbolName
        self.color = color
    }

    public var tintColor: Color {
        color.color
    }
}
