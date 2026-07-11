enum TimelineFilterDraftCatalog {
    static let audioTemplate = TimelineFilterDraft(
        title: "Audio",
        symbolName: "waveform",
        colorID: "audio",
        source: "custom",
        nameEquals: "",
        nameContains: "audio",
        metadataKey: "",
        metadataValue: ""
    )

    static let iconPresets = [
        "tag.fill",
        "waveform",
        "mic.fill",
        "speaker.wave.2.fill",
        "bolt.fill",
        "antenna.radiowaves.left.and.right",
        "externaldrive.fill",
        "network",
        "eye.fill",
        "exclamationmark.triangle.fill",
    ]

    static let colorPresets = [
        TimelineFilterColorPreset(id: "custom", title: "Purple", color: .custom),
        TimelineFilterColorPreset(id: "audio", title: "Blue", color: .audio),
        TimelineFilterColorPreset(id: "unlock", title: "Teal", color: .unlock),
        TimelineFilterColorPreset(id: "file", title: "Orange", color: .file),
        TimelineFilterColorPreset(id: "notification", title: "Rose", color: .notification),
        TimelineFilterColorPreset(id: "lock", title: "Indigo", color: .lock),
    ]
}
