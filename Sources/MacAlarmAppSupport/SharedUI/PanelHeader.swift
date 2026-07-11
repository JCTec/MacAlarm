import SwiftUI

struct PanelHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tintColor: Color
    var iconSize: CGFloat = 34
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            IconTile(
                symbolName: symbolName,
                tintColor: tintColor,
                size: iconSize,
                opacity: 0.15
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.md)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        symbolName: String,
        tintColor: Color,
        iconSize: CGFloat = 34
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tintColor = tintColor
        self.iconSize = iconSize
        self.trailing = { EmptyView() }
    }
}
