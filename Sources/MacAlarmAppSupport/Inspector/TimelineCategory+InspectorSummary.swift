extension TimelineCategory {
    var inspectorSummaryInsight: String {
        switch self {
        case .unlock:
            "A screen unlock is a high-signal access event."
        case .lock:
            "The session moved back into a protected state."
        case .sleepWake:
            "Sleep and wake events explain gaps and physical access windows."
        case .app:
            "App focus helps reconstruct what happened after access."
        case .file:
            "Watched file changes can indicate persistence or configuration tampering."
        case .notification:
            "Delivery records prove whether MacAlarm attempted to alert you."
        case .agent:
            "Agent lifecycle and heartbeat events prove monitoring continuity."
        case .log:
            "Unified log matches can surface system or security signals."
        case .ledger:
            "Ledger events relate to proof-of-history integrity."
        case .custom:
            "Custom events let scripts and trusted apps add domain-specific context."
        case .other:
            "This event was recorded in the local tamper-evident ledger."
        }
    }
}
