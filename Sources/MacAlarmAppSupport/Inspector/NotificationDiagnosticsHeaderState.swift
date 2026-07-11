import MacAlarmCore
import SwiftUI

enum NotificationDiagnosticsLevel: Equatable, Sendable {
    case ready
    case denied
    case fallback
    case unknown

    var tintColor: Color {
        switch self {
        case .ready:
            return .green
        case .denied:
            return .red
        case .fallback:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}

struct NotificationDiagnosticsHeaderState: Equatable, Sendable {
    var subtitle: String
    var level: NotificationDiagnosticsLevel

    var tintColor: Color {
        level.tintColor
    }

    init(snapshot: NotificationAuthorizationSnapshot?, isLoading: Bool) {
        if isLoading {
            subtitle = "Checking notification path"
            level = .unknown
            return
        }

        guard let snapshot else {
            subtitle = "Waiting for notification status"
            level = .unknown
            return
        }

        subtitle = snapshot.authorizationStatus
        switch snapshot.authorizationStatus {
        case "authorized", "provisional", "ephemeral":
            level = .ready
        case "denied":
            level = .denied
        case "unavailable-unbundled-executable":
            level = .fallback
        default:
            level = .unknown
        }
    }
}
