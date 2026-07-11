public enum CategoryDisplayState: String, CaseIterable, Codable, Sendable {
    case normal
    case spotlight
    case hidden

    public mutating func advance() {
        switch self {
        case .normal: self = .spotlight
        case .spotlight: self = .hidden
        case .hidden: self = .normal
        }
    }

    public var systemOverlayName: String? {
        switch self {
        case .normal: nil
        case .spotlight: "circle"
        case .hidden: "slash"
        }
    }
}
