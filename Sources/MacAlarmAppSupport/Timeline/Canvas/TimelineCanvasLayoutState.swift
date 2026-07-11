struct TimelineCanvasLayoutState: Equatable, Sendable {
    var layout: TimelineLayout

    static let empty = TimelineCanvasLayoutState(
        layout: TimelineLayout.placeholder(
            for: TimelineLayoutRequest(records: [], viewportWidth: 0, viewportHeight: 0, zoom: 1)
        )
    )

    func activeLayout(for request: TimelineLayoutRequest) -> TimelineLayout {
        activeLayout(for: request, signature: request.signature)
    }

    func activeLayout(for request: TimelineLayoutRequest, signature: TimelineLayoutSignature) -> TimelineLayout {
        layout.signature == signature ? layout : TimelineLayout.placeholder(for: request, signature: signature)
    }

    mutating func apply(_ layout: TimelineLayout) {
        self.layout = layout
    }
}
