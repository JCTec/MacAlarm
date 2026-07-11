import CoreGraphics

struct TimelineEventLabelPositioner: Sendable {
    static func yPosition(
        nodeY: CGFloat,
        direction: CGFloat,
        circleSize: CGFloat,
        canvasHeight: CGFloat
    ) -> CGFloat {
        let rawY =
            direction < 0
            ? nodeY - circleSize / 2 - 30
            : nodeY + circleSize / 2 + 30
        return min(max(rawY, 34), canvasHeight - 34)
    }
}
