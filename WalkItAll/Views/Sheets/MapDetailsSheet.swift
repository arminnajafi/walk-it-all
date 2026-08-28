import SwiftUI

struct MapDetailsSheet: View {
    let model: AppModel
    @State private var confirmRebuild = false

    var body: some View {
        List {
            Section("Apple Health") {
                LabeledContent("Status", value: model.importPhase.title)
                LabeledContent("Walks mapped", value: model.mappedWorkoutCount.formatted())
                if let date = model.lastSuccessfulImport {
                    LabeledContent(
                        "Last refreshed",
                        value: date.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                if model.importPhase.isWorking {
                    Button("Cancel refresh", systemImage: "xmark.circle", action: model.cancelImport)
                } else {
                    Button("Refresh from Apple Health", systemImage: "arrow.clockwise", action: model.refresh)
                    Button("Rebuild full history", systemImage: "arrow.triangle.2.circlepath") {
                        confirmRebuild = true
                    }
                }

                NavigationLink {
                    HealthAccessHelpSheet(model: model)
                } label: {
                    Label("Review Health access", systemImage: "heart.text.square")
                }
            }

            Section {
                NavigationLink {
                    WorkoutHistorySheet(model: model)
                } label: {
                    Label("Workout history", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink {
                    AboutMapSheet()
                } label: {
                    Label("About this map", systemImage: "map")
                }
                NavigationLink {
                    PrivacySheet()
                } label: {
                    Label("Privacy and recovery", systemImage: "hand.raised.fill")
                }
            }

            if !model.hasMappedWorkouts {
                Section("No routes found") {
                    Label {
                        Text("There may be no recorded outdoor routes, access may be limited, or Health history may still be syncing.")
                    } icon: {
                        Image(systemName: "figure.walk")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Walk It All")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseButton() }
        .confirmationDialog(
            "Rebuild from Apple Health?",
            isPresented: $confirmRebuild,
            titleVisibility: .visible
        ) {
            Button("Rebuild history", role: .destructive, action: model.rebuildFromHealth)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the rebuildable local map and imports your authorized walking routes again.")
        }
    }
}
