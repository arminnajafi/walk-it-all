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
        .accessibilityHint("Temporarily draws your route while you move")
        .accessibilityIdentifier("start-live-trail")
    }
}

struct ActiveLiveTrailCard: View {
    let pause: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Trail on")
                        .font(.subheadline.weight(.semibold))
                    Text("Tracking continues when the screen locks")
                        .font(.caption)
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
                    .accessibilityHint("Stops tracking and keeps the trail on the map")
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

struct PausedLiveTrailCard: View {
    let resume: () -> Void
    let finish: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Trail paused")
                        .font(.subheadline.weight(.semibold))
                    Text("Tracking is off")
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
                    .accessibilityHint("Stops tracking and keeps the trail on the map")
                    .accessibilityIdentifier("finish-paused-live-trail")
            }
            .font(.subheadline.weight(.semibold))

            Button("Clear Trail", systemImage: "trash", role: .destructive, action: clear)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("clear-paused-live-trail")
        }
        .padding(14)
        .walkItAllContentSurface(cornerRadius: 20)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paused-live-trail")
    }
}

struct FinishedLiveTrailCard: View {
    let startNew: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trail finished")
                        .font(.subheadline.weight(.semibold))
                    Text("Tracking is off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("This temporary trail stays on the map until you clear it or start a new one.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Start New", systemImage: "location.fill", action: startNew)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityIdentifier("start-new-live-trail")
                Button("Clear Trail", systemImage: "trash", role: .destructive, action: clear)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("clear-finished-live-trail")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .walkItAllContentSurface(cornerRadius: 20)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        .accessibilityIdentifier("finished-live-trail")
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
