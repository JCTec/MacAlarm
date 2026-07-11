extension TimelineFilterDefinition {
    public static let defaultTemplates: [TimelineFilterDefinition] = [
        TimelineFilterDefinition(
            id: "builtin.unlock", title: "Unlock", symbolName: "lock.open.fill", color: .unlock,
            match: TimelineFilterMatch(category: .unlock), defaultState: .spotlight, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.lock", title: "Lock", symbolName: "lock.fill", color: .lock,
            match: TimelineFilterMatch(category: .lock), defaultState: .spotlight, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.sleep-wake", title: "Sleep/Wake", symbolName: "moon.zzz.fill", color: .sleepWake,
            match: TimelineFilterMatch(category: .sleepWake), defaultState: .spotlight, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.apps", title: "Apps", symbolName: "app.fill", color: .app,
            match: TimelineFilterMatch(category: .app), defaultState: .normal, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.files", title: "Files", symbolName: "doc.text.fill", color: .file,
            match: TimelineFilterMatch(category: .file), defaultState: .spotlight, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.notifications", title: "Notify", symbolName: "bell.badge.fill", color: .notification,
            match: TimelineFilterMatch(category: .notification), defaultState: .normal, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.agent", title: "Agent", symbolName: "waveform.path.ecg", color: .agent,
            match: TimelineFilterMatch(category: .agent), defaultState: .hidden, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.logs", title: "Logs", symbolName: "terminal.fill", color: .log,
            match: TimelineFilterMatch(category: .log), defaultState: .normal, isBuiltIn: true),
        TimelineFilterDefinition(
            id: "builtin.ledger", title: "Ledger", symbolName: "link", color: .ledger,
            match: TimelineFilterMatch(category: .ledger), defaultState: .normal, isBuiltIn: true),
    ]
}
