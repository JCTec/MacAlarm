import SwiftUI

struct EmptyTimelineState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No events in this range")
                .font(.headline)
            Text("Change the time window or category filters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))
    }
}

struct LiveEdge: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.green.opacity(0.8))
                .frame(width: 4, height: 34)
            Rectangle()
                .fill(Color.green.opacity(0.42))
                .frame(width: 2)
            Capsule()
                .fill(Color.green.opacity(0.8))
                .frame(width: 4, height: 34)
        }
        .padding(.vertical, 22)
        .padding(.trailing, 10)
        .help("Live edge")
    }
}
