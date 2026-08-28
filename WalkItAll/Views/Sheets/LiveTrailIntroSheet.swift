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
                    Text("See this walk as you go")
                        .font(.title2.bold())
                    Text("Live Trail draws your current path immediately while Apple Health records the permanent workout.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    instruction(
                        "Start an Outdoor Walk on Apple Watch",
                        detail: "That workout remains your permanent history.",
                        symbol: "applewatch"
                    )
                    instruction(
                        "Then start Live Trail here",
                        detail: "It is a temporary, on-device guide—not another workout.",
                        symbol: "location.fill"
                    )
                    instruction(
                        "Pause briefly, or Finish when done",
                        detail: "Pause turns location off and can be resumed. Finish is final and waits for the Apple Health route.",
                        symbol: "pause.circle"
                    )
                }

                Text("While active, location continues when the screen locks with Apple’s visible indicator. Walk It All requests When In Use access only, never tracks passively, and deletes the temporary trail after Apple Health supplies the workout route—or after seven days.")
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
