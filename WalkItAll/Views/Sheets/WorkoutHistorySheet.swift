import SwiftUI
import WalkItAllCore

struct WorkoutHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    #if DEBUG
    @State private var inspectorWorkoutID: UUID?
    @State private var isReviewingMatching = false
    #endif

    var body: some View {
        Group {
            if model.workoutRecords.isEmpty {
                ContentUnavailableView(
                    "No workout routes",
                    systemImage: "figure.walk",
                    description: Text("Outdoor walking and hiking routes imported from Apple Health will appear here.")
                )
            } else {
                List(model.workoutRecords) { record in
                    Button {
                        open(record)
                    } label: {
                        WorkoutRow(
                            record: record,
                            isSelected: model.selectedWorkoutID == record.id,
                            isReviewingMatching: reviewModeIsActive
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    isReviewingMatching ? "Done" : "Review",
                    systemImage: "ladybug"
                ) {
                    isReviewingMatching.toggle()
                }
                .accessibilityHint("Changes workout taps between map selection and route matching review")
            }
        }
        #endif
        #if DEBUG
        .navigationDestination(
            isPresented: Binding(
                get: { inspectorWorkoutID != nil },
                set: { isPresented in
                    if !isPresented {
                        inspectorWorkoutID = nil
                    }
                }
            )
        ) {
            if let inspectorWorkoutID {
                DebugRouteInspectorSheet(model: model, workoutID: inspectorWorkoutID)
            }
        }
        #endif
    }

    private var reviewModeIsActive: Bool {
        #if DEBUG
        isReviewingMatching
        #else
        false
        #endif
    }

    private func open(_ record: WorkoutCoverageRecord) {
        #if DEBUG
        if isReviewingMatching {
            inspectorWorkoutID = record.id
            return
        }
        #endif
        model.selectWorkout(record.id)
        dismiss()
    }
}

private struct WorkoutRow: View {
    let record: WorkoutCoverageRecord
    let isSelected: Bool
    let isReviewingMatching: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(isSelected || isReviewingMatching ? .indigo : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(record.sourceName) · \(duration(record.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(distance(record.contribution.uniqueCoveredDistanceMeters))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.indigo)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Uniquely credited distance")
                .accessibilityValue(distance(record.contribution.uniqueCoveredDistanceMeters))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private var iconName: String {
        if isReviewingMatching {
            return "ladybug"
        }
        return isSelected ? "checkmark.circle.fill" : "figure.walk.circle"
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
