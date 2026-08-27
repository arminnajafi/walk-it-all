import SwiftUI
import WalkItAllCore

struct ProgressCard: View {
    let coverage: CoverageSnapshot
    let phase: ImportPhase
    let selectedWorkoutName: String?
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
                }
                Spacer()
                Button(action: showDetails) {
                    Image(systemName: "chevron.up")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show coverage details")
            }

            ProgressView(value: coverage.completionFraction)
                .tint(.indigo)
                .accessibilityLabel("Manhattan walking progress")
                .accessibilityValue(coverage.completionFraction, format: .percent.precision(.fractionLength(1)))

            HStack {
                Label(distance(coverage.coveredDistanceMeters), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.indigo)
                Spacer()
                Text("\(distance(coverage.remainingDistanceMeters)) remaining")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))

            if phase.isWorking {
                HStack(spacing: 10) {
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
                    Label("Refresh from Apple Health", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(phase.isWorking)
            }
        }
        .padding(18)
        .walkItAllFloatingSurface()
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private func distance(_ meters: Double) -> String {
        let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles)
        return miles.formatted(.measurement(width: .abbreviated, usage: .road).precision(.fractionLength(1)))
    }
}

