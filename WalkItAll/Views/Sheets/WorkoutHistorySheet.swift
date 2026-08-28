import SwiftUI
import WalkItAllCore

struct WorkoutHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel

    var body: some View {
        Group {
            if model.routeRecords.isEmpty {
                ContentUnavailableView(
                    "No workout routes",
                    systemImage: "figure.walk",
                    description: Text("Outdoor walking and hiking routes imported from Apple Health will appear here.")
                )
            } else {
                List(model.routeRecords) { record in
                    Button {
                        model.selectWorkout(record.id)
                        dismiss()
                    } label: {
                        WorkoutRow(
                            record: record,
                            isSelected: model.selectedWorkoutID == record.id
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("workout-history-row")
                }
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkoutRow: View {
    let record: WorkoutRouteRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "figure.walk.circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .indigo : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.semibold))
                Text(record.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(duration(record.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(
            .time(pattern: interval >= 3_600 ? .hourMinute : .minuteSecond)
        )
    }
}
