import SwiftUI

struct ToolbarIconButton: View {
    let symbolName: String
    let helpText: String
    var isActive = false
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .frame(width: 32, height: 30)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control)
                        .strokeBorder(borderColor, lineWidth: isActive ? 1.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(helpText)
        .accessibilityLabel(Text(helpText))
    }

    private var backgroundColor: Color {
        isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        isActive ? Color.accentColor.opacity(0.72) : Color(nsColor: .separatorColor).opacity(0.45)
    }
}
