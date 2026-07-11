import SwiftUI

struct BrandMark: View {
    let subtitle: String

    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbolName: "shield.lefthalf.filled", tintColor: .accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("MacAlarm")
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }
}
