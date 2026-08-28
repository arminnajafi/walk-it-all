import SwiftUI
import WalkItAllCore

struct WorkoutHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel

    var body: some View {
        Group {
            if model.workoutRecords.isEmpty {
                ContentUnavailableView(
                    "No mapped workouts",
                    systemImage: "figure.walk",
                    description: Text("Outdoor walking and hiking routes imported from Apple Health will appear here.")
                )
            } else {
                List(model.workoutRecords) { record in
                    HStack(spacing: 8) {
                        Button {
                            model.selectWorkout(record.id)
                            dismiss()
                        } label: {
                            WorkoutRow(record: record, isSelected: model.selectedWorkoutID == record.id)
                        }
                        .buttonStyle(.plain)

                        #if DEBUG
                        NavigationLink {
                            DebugRouteInspectorSheet(model: model, workoutID: record.id)
                        } label: {
                            Image(systemName: "ladybug")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Inspect route matching")
                        #endif
                    }
                }
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkoutRow: View {
    let record: WorkoutCoverageRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "figure.walk.circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .indigo : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.semibold))
                Text("\(record.sourceName) · \(duration(record.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(distance(record.contribution.uniqueCoveredDistanceMeters))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.indigo)
                .accessibilityLabel("Uniquely credited distance")
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private func distance(_ meters: Double) -> String {
        let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles)
        return "\(miles.value.formatted(.number.precision(.fractionLength(2)))) mi"
    }

    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(
            .time(pattern: interval >= 3_600 ? .hourMinute : .minuteSecond)
        )
    }
}
