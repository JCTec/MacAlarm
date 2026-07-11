import SwiftUI

struct HashProofSection: View {
    let record: TimelineRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hash Chain")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 10, height: 10)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2, height: 22)
                    Circle()
                        .fill(record.tintColor)
                        .frame(width: 14, height: 14)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HashLine(title: "Previous", value: record.record.previousHash)
                    HashLine(title: "Record", value: record.record.hash)
                }
            }
        }
    }
}

struct HashLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(shortHash)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var shortHash: String {
        guard value.count > 20 else { return value }
        return "\(value.prefix(12))...\(value.suffix(12))"
    }
}

struct MetadataSection: View {
    let record: TimelineRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata")
                .font(.headline)

            if record.event.metadata.isEmpty {
                Text("No metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(record.event.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        GridRow {
                            Text(key)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.caption)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
    }
}
