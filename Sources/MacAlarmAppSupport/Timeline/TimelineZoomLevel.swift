enum TimelineZoomLevel {
    static let values: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]

    static func nearest(to value: Double) -> Double {
        values.min { abs($0 - value) < abs($1 - value) } ?? 1
    }

    static func next(after value: Double) -> Double {
        let current = nearest(to: value)
        return values.first { $0 > current } ?? values.last ?? current
    }

    static func previous(before value: Double) -> Double {
        let current = nearest(to: value)
        return values.last { $0 < current } ?? values.first ?? current
    }

    static func normalizedIndex(for value: Double) -> Double {
        Double(values.firstIndex(of: nearest(to: value)) ?? 2)
    }

    static func value(forNormalizedIndex index: Double) -> Double {
        let rounded = Int(index.rounded())
        let clamped = min(max(rounded, 0), values.count - 1)
        return values[clamped]
    }

    static func title(for value: Double) -> String {
        let zoom = nearest(to: value)
        if zoom == 1 {
            return "1x"
        }
        return "\(zoom)x"
    }
}
