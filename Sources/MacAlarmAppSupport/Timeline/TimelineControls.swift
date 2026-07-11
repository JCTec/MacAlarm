import SwiftUI

struct TimeRangeControl: View {
    let timeRange: TimeInterval
    let setTimeRange: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(TimeRangePreset.toolbarPresets) { preset in
                TimePresetButton(preset: preset, timeRange: timeRange, setTimeRange: setTimeRange)
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppRadius.control))
    }
}

struct TimePresetButton: View {
    let preset: TimeRangePreset
    let timeRange: TimeInterval
    let setTimeRange: (TimeInterval) -> Void

    var body: some View {
        let selected = preset.isSelected(timeRange)

        Button {
            setTimeRange(preset.seconds)
        } label: {
            Text(preset.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 34, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("Show \(preset.title)")
    }
}

struct ZoomControl: View {
    @Binding var zoom: Double
    @State private var sliderIndex: Double = TimelineZoomLevel.normalizedIndex(for: 1)

    var body: some View {
        HStack(spacing: 5) {
            Button {
                setZoom(TimelineZoomLevel.previous(before: zoom))
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.caption)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(TimelineZoomLevel.nearest(to: zoom) == TimelineZoomLevel.values.first)

            Slider(
                value: Binding(
                    get: { sliderIndex },
                    set: { newValue in
                        setZoom(TimelineZoomLevel.value(forNormalizedIndex: newValue))
                    }
                ),
                in: 0...Double(TimelineZoomLevel.values.count - 1),
                step: 1
            )
            .frame(width: 74)

            Text(TimelineZoomLevel.title(for: zoom))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30)

            Button {
                setZoom(TimelineZoomLevel.next(after: zoom))
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(TimelineZoomLevel.nearest(to: zoom) == TimelineZoomLevel.values.last)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppRadius.control))
        .help("Timeline zoom: \(TimelineZoomLevel.title(for: zoom))")
        .onAppear {
            sliderIndex = TimelineZoomLevel.normalizedIndex(for: zoom)
            zoom = TimelineZoomLevel.nearest(to: zoom)
        }
        .onChange(of: zoom) { _, newValue in
            sliderIndex = TimelineZoomLevel.normalizedIndex(for: newValue)
        }
    }

    private func setZoom(_ value: Double) {
        let snapped = TimelineZoomLevel.nearest(to: value)
        sliderIndex = TimelineZoomLevel.normalizedIndex(for: snapped)
        zoom = snapped
    }
}
