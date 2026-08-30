import SwiftUI
import WalkItAllCore

struct EmptyRouteMapCard: View {
    let phase: ImportPhase
    let lastSuccessfulImport: Date?
    let hasConnectedHealth: Bool
    let refresh: () -> Void
    let cancel: () -> Void
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No outdoor routes mapped yet")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: showDetails) {
                    Image(systemName: "chevron.up")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show map details")
            }

            if !phase.isWorking {
                Text("Ordinary steps and indoor workouts do not include a route. Record a supported outdoor workout, or review Apple Health access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case let .failed(message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if phase.isWorking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(phase.title).font(.footnote)
                    Spacer()
                    Button("Cancel", action: cancel)
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
            } else {
                Button(action: refresh) {
                    Label(
                        hasConnectedHealth ? "Refresh" : "Connect Apple Health",
                        systemImage: hasConnectedHealth ? "arrow.clockwise" : "heart.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel(
                    hasConnectedHealth ? "Refresh from Apple Health" : "Connect Apple Health"
                )
            }
        }
        .padding(17)
        .walkItAllContentSurface()
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityIdentifier("lifetime-map-card")
    }

    private var subtitle: String {
        if phase.isWorking { return phase.title }
        if let lastSuccessfulImport {
            return "Refreshed \(lastSuccessfulImport.formatted(.relative(presentation: .named)))"
        }
        return "Your lifetime route map"
    }
}

struct SelectedWorkoutCard: View {
    let workout: WorkoutRouteRecord
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text(workout.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Clear", systemImage: "xmark", action: clear)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }

            Label(duration(workout.duration), systemImage: "clock")
                .font(.subheadline.weight(.medium))
            Label(workout.activityKind.displayName, systemImage: workout.activityKind.systemImage)
                .font(.subheadline.weight(.medium))
            Label("Orange with a contrasting outline shows this workout", systemImage: "line.diagonal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .walkItAllContentSurface(cornerRadius: 22)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selected-workout-card")
    }

    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(
            .time(pattern: interval >= 3_600 ? .hourMinute : .minuteSecond)
        )
    }
}

#if DEBUG
#Preview("Empty") {
    EmptyRouteMapCard(
        phase: .idle,
        lastSuccessfulImport: .now,
        hasConnectedHealth: true,
        refresh: {},
        cancel: {},
        showDetails: {}
    )
    .padding()
}
#endif
