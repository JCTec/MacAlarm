import SwiftUI

public struct TimelineFilterDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var symbolName: String
    public var color: TimelineFilterColor
    public var match: TimelineFilterMatch
    public var defaultState: CategoryDisplayState
    public var isBuiltIn: Bool
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        symbolName: String,
        color: TimelineFilterColor,
        match: TimelineFilterMatch,
        defaultState: CategoryDisplayState = .normal,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.color = color
        self.match = match
        self.defaultState = defaultState
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }

    public var tintColor: Color {
        color.color
    }

    public func matches(_ record: TimelineRecord) -> Bool {
        match.matches(event: record.event, category: record.category)
    }
}
