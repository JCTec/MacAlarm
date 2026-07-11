import SwiftUI

extension AgentHealthLevel {
    var tintColor: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
