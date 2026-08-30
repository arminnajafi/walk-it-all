import SwiftUI

struct LiveTrailIntroSheet: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("See where you go now")
                        .font(.title2.bold())
                    Text("Live Trail draws one temporary path that you control independently from Apple Health.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    instruction(
                        "Start Live Trail here",
                        detail: "The green line appears immediately and stays only on this iPhone.",
                        symbol: "location.fill"
                    )
                    instruction(
                        "Pause and resume when needed",
                        detail: "Pausing turns location off. Resuming starts a new trail part without bridging the break.",
                        symbol: "pause.circle"
                    )
                    instruction(
                        "Finish when you are done",
                        detail: "Tracking stops, and the trail stays until you clear it or start a new one.",
                        symbol: "stop.circle"
                    )
                }

                Text("While active, location continues when the screen locks with Apple’s visible indicator. Walk It All requests When In Use access only and never tracks passively. If you want this route in your permanent map, separately record a supported outdoor workout that saves a GPS route to Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
        }
        .navigationTitle("Live Trail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseButton() }
    }

    private func instruction(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
        }
    }

    @ViewBuilder
    private var startButton: some View {
        let button = Button(action: model.confirmStartLiveTrail) {
            Label("Start Live Trail", systemImage: "location.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityIdentifier("confirm-start-live-trail")

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }
}
