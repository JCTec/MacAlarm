import MacAlarmCore
import SwiftUI

struct PinnedSummaryIcon: View {
    let symbolName: String
    let tintColor: Color
    let severity: AlarmSeverity

    var body: some View {
        ZStack {
            Circle()
                .fill(tintColor)
                .frame(width: 40, height: 40)
            Circle()
                .stroke(
                    severity.timelineColor,
                    lineWidth: severity >= .warning ? 2.4 : 1.1
                )
                .frame(width: 44, height: 44)
            Image(systemName: symbolName)
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}
