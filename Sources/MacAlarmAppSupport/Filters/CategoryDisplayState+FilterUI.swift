import SwiftUI

extension CategoryDisplayState {
    var settingsLabel: String {
        switch self {
        case .normal: "Visible"
        case .spotlight: "Priority"
        case .hidden: "Hidden"
        }
    }

    var tipText: String {
        switch self {
        case .normal: "Visible"
        case .spotlight: "Prioritized"
        case .hidden: "Hidden"
        }
    }

    var accessibilityText: String {
        switch self {
        case .normal: "Visible in timeline"
        case .spotlight: "Prioritized in timeline"
        case .hidden: "Hidden from timeline"
        }
    }

    func indicatorColor(for filter: TimelineFilterDefinition) -> Color {
        switch self {
        case .normal: filter.tintColor
        case .spotlight: Color.accentColor
        case .hidden: Color(nsColor: .secondaryLabelColor)
        }
    }
}
