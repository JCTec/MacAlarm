import CoreGraphics

struct TimelinePlacementCandidate: Sendable {
    let x: CGFloat
    let nodeY: CGFloat
    let direction: CGFloat
    let distance: CGFloat
    let lane: Int
    let preferredDirection: CGFloat
    let size: CGFloat
}

struct TimelinePlacedNode: Sendable {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let direction: CGFloat
}
