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
    let finish: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
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
                Button("Finish", systemImage: "stop.fill", action: finish)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("finish-live-trail")
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

struct WaitingForHealthCard: View {
    let showDetails: () -> Void

    var body: some View {
        Button(action: showDetails) {
            HStack(spacing: 11) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for Apple Health")
                        .font(.subheadline.weight(.semibold))
                    Text("The dashed trail is temporary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .walkItAllContentSurface(cornerRadius: 20)
        }
        .buttonStyle(.plain)
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
