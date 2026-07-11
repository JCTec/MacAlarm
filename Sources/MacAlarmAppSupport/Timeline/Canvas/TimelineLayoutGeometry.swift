import CoreGraphics

struct TimelineLayoutGeometry: Sendable {
    let contentWidth: CGFloat
    let height: CGFloat
    let spineY: CGFloat

    init(signature: TimelineLayoutSignature, recordCount: Int) {
        let baseWidth = max(signature.viewportWidth, CGFloat(max(recordCount, 1)) * 88)
        contentWidth = max(signature.viewportWidth, baseWidth * signature.zoom)
        height = signature.viewportHeight
        spineY = signature.viewportHeight * 0.5
    }
}
