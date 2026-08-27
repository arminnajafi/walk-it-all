import SwiftUI
import WalkItAllCore

struct ProgressCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let coverage: CoverageSnapshot
    let phase: ImportPhase
    let selectedWorkoutName: String?
    let lastSuccessfulImport: Date?
    let hasMappedWorkouts: Bool
    let refresh: () -> Void
    let cancel: () -> Void
    let showDetails: () -> Void
    let clearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedWorkoutName {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                    Text(selectedWorkoutName)
                        .lineLimit(1)
                    Spacer()
                    Button("Clear", systemImage: "xmark", action: clearSelection)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Clear selected workout")
                }
                .font(.subheadline.weight(.medium))
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(coverage.completionFraction, format: .percent.precision(.fractionLength(1)))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .contentTransition(.numericText())
                    Text("of Manhattan walked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: showDetails) {
                    Image(systemName: "chevron.up")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show coverage details")
            }

            ProgressView(value: coverage.completionFraction)
                .tint(.indigo)
                .accessibilityLabel("Manhattan walking progress")
                .accessibilityValue(
                    coverage.completionFraction.formatted(.percent.precision(.fractionLength(1)))
                )

            if dynamicTypeSize.isAccessibilitySize {
                distanceSummaryVertical
            } else {
                ViewThatFits(in: .horizontal) {
                    distanceSummaryHorizontal
                    distanceSummaryVertical
                }
            }

            if !hasMappedWorkouts, !phase.isWorking {
                Label("No mappable walking routes yet", systemImage: "figure.walk")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHint("Record an outdoor walk, or review Apple Health access in coverage details.")
            }

            if case let .failed(message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if phase.isWorking {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(phase.title)
                        .font(.footnote)
                    Spacer()
                    Button("Cancel", action: cancel)
                        .font(.footnote.weight(.semibold))
                }
            } else {
                Button(action: refresh) {
                    Label(refreshButtonTitle, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .disabled(phase.isWorking)
                .accessibilityLabel("Refresh from Apple Health")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    refreshText
                    Spacer(minLength: 8)
                    osmAttribution
                }
                VStack(alignment: .leading, spacing: 5) {
                    refreshText
                    osmAttribution
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .walkItAllFloatingSurface()
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private func distance(_ meters: Double) -> String {
        let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles)
        return "\(miles.value.formatted(.number.precision(.fractionLength(1)))) mi"
    }

    private var refreshButtonTitle: String {
        dynamicTypeSize >= .accessibility4 ? "Refresh" : "Refresh from Apple Health"
    }

    private var distanceSummaryHorizontal: some View {
        HStack {
            Label(distance(coverage.coveredDistanceMeters), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.indigo)
            Spacer()
            Text("\(distance(coverage.remainingDistanceMeters)) remaining")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
    }

    private var distanceSummaryVertical: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(distance(coverage.coveredDistanceMeters), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.indigo)
            Text("\(distance(coverage.remainingDistanceMeters)) remaining")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
    }

    @ViewBuilder
    private var refreshText: some View {
        if let lastSuccessfulImport {
            Text("Refreshed \(lastSuccessfulImport.formatted(.relative(presentation: .named)))")
        } else {
            Text("Not refreshed yet")
        }
    }

    private var osmAttribution: some View {
        Link(
            "© OpenStreetMap",
            destination: URL(string: "https://www.openstreetmap.org/copyright")!
        )
        .accessibilityIdentifier("osm-attribution")
    }
}
