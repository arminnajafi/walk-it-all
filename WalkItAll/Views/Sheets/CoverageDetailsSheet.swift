import SwiftUI

struct CoverageDetailsSheet: View {
    let model: AppModel
    @State private var confirmRebuild = false

    var body: some View {
        List {
            if let coverage = model.coverage {
                Section("Manhattan Island") {
                    LabeledContent("Covered") {
                        Text(coverage.completionFraction, format: .percent.precision(.fractionLength(1)))
                    }
                    LabeledContent("Distance walked", value: distance(coverage.coveredDistanceMeters))
                    LabeledContent("Distance remaining", value: distance(coverage.remainingDistanceMeters))
                    LabeledContent("Completed map segments", value: coverage.completedSegmentIDs.count.formatted())
                }
            }

            Section("Apple Health") {
                LabeledContent("Status", value: model.importPhase.title)
                LabeledContent("Mapped workouts", value: model.workoutRecords.count.formatted())
                if let date = model.lastSuccessfulImport {
                    LabeledContent("Last refreshed", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Refresh from Apple Health", systemImage: "arrow.clockwise") {
                    model.refresh()
                }
                .disabled(model.importPhase.isWorking)
                Button("Rebuild all coverage", systemImage: "arrow.triangle.2.circlepath") {
                    confirmRebuild = true
                }
                .disabled(model.importPhase.isWorking)
                NavigationLink {
                    HealthAccessHelpSheet(model: model)
                } label: {
                    Label("Review Health access", systemImage: "heart.text.square")
                }
            }

            if model.workoutRecords.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No mappable routes found",
                        systemImage: "figure.walk",
                        description: Text("You may not have recorded outdoor workouts, Health access may be limited, or older Health history may still be syncing.")
                    )
                }
            }

            Section {
                NavigationLink {
                    WorkoutHistorySheet(model: model)
                } label: {
                    Label("Workout history", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink {
                    MethodologySheet(model: model)
                } label: {
                    Label("How coverage works", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                NavigationLink {
                    PrivacySheet(model: model)
                } label: {
                    Label("Privacy and data", systemImage: "hand.raised.fill")
                }
            }

        }
        .navigationTitle("Coverage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseButton() }
        .confirmationDialog(
            "Rebuild from Apple Health?",
            isPresented: $confirmRebuild,
            titleVisibility: .visible
        ) {
            Button("Rebuild coverage", role: .destructive) {
                model.rebuildFromHealth()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the rebuildable local cache and imports your authorized Apple Health routes again.")
        }
    }

    private func distance(_ meters: Double) -> String {
        let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles)
        return "\(miles.value.formatted(.number.precision(.fractionLength(1)))) miles"
    }
}
