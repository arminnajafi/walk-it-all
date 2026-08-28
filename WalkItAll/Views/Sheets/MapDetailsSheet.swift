import SwiftUI

struct MapDetailsSheet: View {
    let model: AppModel
    @State private var confirmRebuild = false

    var body: some View {
        List {
            Section("Live Trail") {
                switch model.liveTrail.session?.state {
                case .active:
                    Label("Active", systemImage: "location.fill")
                        .foregroundStyle(.green)
                    Text("Location continues while the screen is locked until you tap Finish. Start an Outdoor Walk on Apple Watch for permanent history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .paused:
                    Label("Paused — trail tracking is off", systemImage: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Resume from the map after a short break. Finish instead if the walk is over or you are switching to transit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .waitingForHealth:
                    Label("Finished — syncing from Apple Health", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Background trail tracking is no longer running. The dashed green trail is temporary and will disappear when the finished workout route imports, or after seven days.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case nil:
                    Text("Start Live Trail from the map when you want an immediate, temporary guide during a walk.")
                        .foregroundStyle(.secondary)
                }

                if let date = model.liveTrail.lastExpiredTrailDate {
                    Label {
                        Text("A Live Trail from \(date.formatted(date: .abbreviated, time: .omitted)) expired because its Health route was not found. No coordinates were retained.")
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

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
                    .disabled(model.liveTrail.hasInProgressSession)
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
