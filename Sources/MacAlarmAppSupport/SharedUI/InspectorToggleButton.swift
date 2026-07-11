import SwiftUI

struct InspectorToggleButton: View {
    let isVisible: Bool
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        ToolbarIconButton(
            symbolName: "sidebar.right",
            helpText: isVisible ? "Hide inspector" : "Show inspector",
            isActive: isVisible,
            isEnabled: isEnabled
        ) {
            withAnimation(.easeOut(duration: 0.2)) {
                toggle()
            }
        }
    }
}
