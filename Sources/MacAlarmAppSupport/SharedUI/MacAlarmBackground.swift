import SwiftUI

struct MacAlarmBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 0) {
                Color(nsColor: .controlBackgroundColor).opacity(0.45)
                    .frame(height: 210)
                Spacer()
            }
        }
    }
}
