import MacAlarmCore
import SwiftUI

struct AgentHealthPill: View {
    let presentation: AgentHealthPresentation
    let snapshot: AgentStatusSnapshot?
    let loadError: String?
    let installAgent: @MainActor @Sendable () -> Void
    let startAgent: @MainActor @Sendable () -> Void
    let showLedgerIntegrity: () -> Void
    @State private var showingDetails = false
    @State private var showsHealthyTitle = true
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(presentation.level.tintColor)
                    .frame(width: 8, height: 8)
                if shouldShowTitle {
                    Text(presentation.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                Text(presentation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: AppRadius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .strokeBorder(presentation.level.tintColor.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeOut(duration: 0.2), value: shouldShowTitle)
        .help("Recorder health: \(presentation.title). \(presentation.detail)")
        .onAppear(perform: scheduleHealthyCollapse)
        .onChange(of: presentation.title) { _, _ in
            scheduleHealthyCollapse()
        }
        .onChange(of: presentation.level) { _, _ in
            scheduleHealthyCollapse()
        }
        .onDisappear {
            collapseTask?.cancel()
            collapseTask = nil
        }
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            AgentHealthPopover(
                presentation: presentation,
                snapshot: snapshot,
                loadError: loadError,
                installAgent: installAgent,
                startAgent: startAgent,
                showLedgerIntegrity: showLedgerIntegrity
            )
        }
    }

    private var shouldShowTitle: Bool {
        presentation.level != .healthy || showsHealthyTitle
    }

    private func scheduleHealthyCollapse() {
        collapseTask?.cancel()

        guard presentation.level == .healthy else {
            showsHealthyTitle = true
            collapseTask = nil
            return
        }

        showsHealthyTitle = true
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.22)) {
                showsHealthyTitle = false
            }
        }
    }
}
