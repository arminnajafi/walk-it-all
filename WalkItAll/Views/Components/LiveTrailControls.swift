import SwiftUI
import WalkItAllCore

struct StartLiveTrailButton: View {
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                button.buttonStyle(.glassProminent)
            } else {
                button
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .walkItAllControlSurface()
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var button: some View {
        Button(action: action) {
            Label("Start Live Trail", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
        }
        .accessibilityHint("Temporarily draws this walk while you move")
        .accessibilityIdentifier("start-live-trail")
    }
}

struct ActiveLiveTrailCard: View {
    let session: LiveTrailSession
    let pause: () -> Void
    let finish: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Trail")
                            .font(.subheadline.weight(.semibold))
                        Text(elapsed(at: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }

                HStack(spacing: 10) {
                    Button("Pause", systemImage: "pause.fill", action: pause)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .accessibilityHint("Stops location until you resume")
                        .accessibilityIdentifier("pause-live-trail")
                    Button("Finish", systemImage: "stop.fill", action: finish)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityHint("Ends this Live Trail and waits for Apple Health")
                        .accessibilityIdentifier("finish-live-trail")
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .walkItAllContentSurface(cornerRadius: 20)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("active-live-trail")
        }
    }

    private func elapsed(at date: Date) -> String {
        Duration.seconds(max(0, date.timeIntervalSince(session.start))).formatted(
            .time(pattern: .hourMinuteSecond)
        )
    }
}

struct PausedLiveTrailCard: View {
    let resume: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Trail paused")
                        .font(.subheadline.weight(.semibold))
                    Text("Live Trail tracking is off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button("Resume", systemImage: "play.fill", action: resume)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityHint("Starts location again in a new trail part")
                    .accessibilityIdentifier("resume-live-trail")
                Button("Finish", systemImage: "stop.fill", action: finish)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityHint("Ends this Live Trail and waits for Apple Health")
                    .accessibilityIdentifier("finish-paused-live-trail")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .walkItAllContentSurface(cornerRadius: 20)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paused-live-trail")
    }
}

struct WaitingForHealthCard: View {
    let refresh: () -> Void
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Trail finished")
                        .font(.subheadline.weight(.semibold))
                    Text("Trail tracking is off. You can close the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: showDetails) {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Health sync")
            }

            Text("The dashed trail stays until your finished workout route syncs into the permanent map.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Check Apple Health Now", systemImage: "arrow.clockwise", action: refresh)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .walkItAllContentSurface(cornerRadius: 20)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        .accessibilityIdentifier("waiting-for-health")
    }
}

struct CompactImportCard: View {
    let phase: ImportPhase
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(phase.title).font(.footnote)
            Spacer()
            Button("Cancel", action: cancel)
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .walkItAllContentSurface(cornerRadius: 18)
    }
}

struct CompactErrorCard: View {
    let message: String
    let showDetails: () -> Void

    var body: some View {
        Button(action: showDetails) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.footnote).lineLimit(2)
                Spacer()
                Image(systemName: "chevron.up").foregroundStyle(.secondary)
            }
            .padding(14)
            .walkItAllContentSurface(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
