import SwiftUI
import WalkItAllCore

struct StartLiveTrailButton: View {
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                button
                    .buttonStyle(.glassProminent)
                    .tint(.indigo)
            } else {
                button
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.indigo)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var button: some View {
        Button(action: action) {
            Label("Start Live Trail", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
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
        LiveTrailControlCard(
            title: "Live Trail",
            detail: "Active · continues when your screen locks",
            symbol: "location.fill",
            tint: .green
        ) {
            LiveTrailActionRow {
                LiveTrailActionButton(
                    "Pause",
                    symbol: "pause.fill",
                    style: .primary,
                    action: pause
                )
                .accessibilityHint("Stops location until you resume")
                .accessibilityIdentifier("pause-live-trail")
            } secondary: {
                LiveTrailActionButton(
                    "Finish",
                    symbol: "stop.fill",
                    style: .secondary,
                    action: finish
                )
                .accessibilityHint("Stops tracking and keeps the trail on the map")
                .accessibilityIdentifier("finish-live-trail")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-live-trail")
    }
}

struct PausedLiveTrailCard: View {
    let resume: () -> Void
    let finish: () -> Void

    var body: some View {
        LiveTrailControlCard(
            title: "Live Trail",
            detail: "Paused · location is off",
            symbol: "pause.fill",
            tint: .orange
        ) {
            LiveTrailActionRow {
                LiveTrailActionButton(
                    "Resume",
                    symbol: "play.fill",
                    style: .primary,
                    action: resume
                )
                .accessibilityHint("Starts location again in a new trail part")
                .accessibilityIdentifier("resume-live-trail")
            } secondary: {
                LiveTrailActionButton(
                    "Finish",
                    symbol: "stop.fill",
                    style: .secondary,
                    action: finish
                )
                .accessibilityHint("Stops tracking and keeps the trail on the map")
                .accessibilityIdentifier("finish-paused-live-trail")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paused-live-trail")
    }
}

struct FinishedLiveTrailCard: View {
    let startNew: () -> Void
    let clear: () -> Void

    var body: some View {
        LiveTrailControlCard(
            title: "Live Trail",
            detail: "Finished · stays until cleared",
            symbol: "checkmark",
            tint: .green
        ) {
            LiveTrailActionRow {
                LiveTrailActionButton(
                    "Start New",
                    symbol: "location.fill",
                    style: .primary,
                    action: startNew
                )
                .accessibilityIdentifier("start-new-live-trail")
            } secondary: {
                LiveTrailActionButton(
                    "Clear Trail",
                    symbol: "trash",
                    role: .destructive,
                    style: .destructive,
                    action: clear
                )
                .accessibilityIdentifier("clear-finished-live-trail")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("finished-live-trail")
    }
}

private enum LiveTrailControlMetrics {
    static let actionSpacing: CGFloat = 8
    static let cardSpacing: CGFloat = 12
    static let controlHeight: CGFloat = 44
}

private struct LiveTrailControlCard<Actions: View>: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: LiveTrailControlMetrics.cardSpacing) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            actions
        }
        .padding(14)
        .walkItAllContentSurface(cornerRadius: 20)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
    }
}

private struct LiveTrailActionRow<PrimaryAction: View, SecondaryAction: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let primaryAction: PrimaryAction
    let secondaryAction: SecondaryAction

    init(
        @ViewBuilder _ primaryAction: () -> PrimaryAction,
        @ViewBuilder secondary secondaryAction: () -> SecondaryAction
    ) {
        self.primaryAction = primaryAction()
        self.secondaryAction = secondaryAction()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: LiveTrailControlMetrics.actionSpacing) {
                    primaryAction
                    secondaryAction
                }
            } else {
                HStack(spacing: LiveTrailControlMetrics.actionSpacing) {
                    primaryAction
                    secondaryAction
                }
            }
        }
    }
}

private struct LiveTrailActionButton: View {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    let title: String
    let symbol: String
    let role: ButtonRole?
    let style: Style
    let action: () -> Void

    init(
        _ title: String,
        symbol: String,
        role: ButtonRole? = nil,
        style: Style,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.style = style
        self.action = action
    }

    var body: some View {
        Group {
            switch style {
            case .primary:
                button
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            case .secondary:
                button
                    .buttonStyle(.bordered)
                    .tint(.primary)
            case .destructive:
                button
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .buttonBorderShape(.capsule)
    }

    private var button: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: LiveTrailControlMetrics.controlHeight)
        }
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
