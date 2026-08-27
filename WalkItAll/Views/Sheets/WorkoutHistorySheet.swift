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
                    Button {
                        model.selectWorkout(record.id)
                        dismiss()
                    } label: {
                        WorkoutRow(record: record, isSelected: model.selectedWorkoutID == record.id)
                    }
                    .buttonStyle(.plain)
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
                Text("\(record.sourceName) · \(record.contribution.intervals.count) matched portions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !record.unmatchedPortions.isEmpty {
                    Text("\(record.unmatchedPortions.count) uncertain portion\(record.unmatchedPortions.count == 1 ? "" : "s") skipped")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(record.contribution.confidence, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Average match confidence")
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}
