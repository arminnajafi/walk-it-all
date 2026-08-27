import SwiftUI
import WalkItAllCore

struct MapScreen: View {
    let model: AppModel

    var body: some View {
        ZStack {
            if let pack = model.cityPack {
                CoverageMapView(
                    pack: pack,
                    coverage: model.coverage,
                    selectedWorkout: model.selectedWorkout
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Label("Manhattan", systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .walkItAllFloatingSurface(cornerRadius: 18)
                        .accessibilityLabel("Current completion area: Manhattan Island")
                        .accessibilityIdentifier("current-completion-area")
                    Spacer()
                    Button {
                        model.presentedSheet = .details
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .walkItAllFloatingSurface(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About Walk It All")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                if let coverage = model.coverage {
                    ProgressCard(
                        coverage: coverage,
                        phase: model.importPhase,
                        selectedWorkoutName: model.selectedWorkout.map {
                            $0.start.formatted(date: .abbreviated, time: .shortened)
                        },
                        refresh: model.refresh,
                        cancel: model.cancelImport,
                        showDetails: { model.presentedSheet = .details },
                        clearSelection: model.clearSelectedWorkout
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .sheet(item: Binding(
            get: { model.presentedSheet },
            set: { model.presentedSheet = $0 }
        )) { destination in
            AppSheetHost(destination: destination, model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
