import MacAlarmCore
import SwiftUI

extension AlarmSeverity {
    var timelineColor: Color {
        switch self {
        case .debug: Color(nsColor: .secondaryLabelColor)
        case .info: Color(nsColor: .tertiaryLabelColor)
        case .notice: Color(red: 0.10, green: 0.58, blue: 0.42)
        case .warning: Color(red: 0.88, green: 0.58, blue: 0.16)
        case .critical: Color(red: 0.82, green: 0.18, blue: 0.22)
        }
    }
}
