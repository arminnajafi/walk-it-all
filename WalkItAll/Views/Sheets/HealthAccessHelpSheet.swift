import SwiftUI

struct HealthAccessHelpSheet: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                ContentUnavailableView {
                    Label("Apple Health Access", systemImage: "heart.text.square.fill")
                } description: {
                    Text("Walk It All needs read-only access to Workouts and Workout Routes. Route processing stays on this iPhone.")
                }
            }

            Section("Request access") {
                Button("Request Apple Health Access", systemImage: "heart.fill") {
                    model.refresh()
                }
                .disabled(model.importPhase.isWorking)
                .accessibilityIdentifier("request-health-access")

                Text("If iOS still needs your decision, Apple’s permission sheet appears. Otherwise, review existing access below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Review existing access") {
                accessStep(1, "Open the Health app.")
                accessStep(2, "Tap your picture or initials at the top right.")
                accessStep(3, "Under Privacy, tap Apps, then Walk It All.")
                accessStep(4, "Turn on all available read permissions.")
            }

            Section {
                Text("Apple does not provide apps with a public link directly to this Health permission page. HealthKit also does not reveal whether read access was denied, so Walk It All never guesses about your choice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Health Access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseButton() }
    }

    private func accessStep(_ number: Int, _ text: String) -> some View {
        Label(text, systemImage: "\(number).circle.fill")
            .labelStyle(.titleAndIcon)
    }
}
