import SwiftUI
import WalkItAllCore

struct MapScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: AppModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let pack = model.cityPack {
                    CoverageMapView(
                        pack: pack,
                        coverage: model.coverage,
                        selectedWorkout: model.selectedWorkout,
                        coverageRevision: model.coverageRenderRevision,
                        bottomMapInset: dynamicTypeSize.isAccessibilitySize ? 520 : 300
                    )
                    .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    topControls
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Spacer()

                    if let coverage = model.coverage {
                        progressCard(coverage, availableHeight: geometry.size.height)
                    }
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

    @ViewBuilder
    private var topControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack {
                    areaLabel
                    Spacer()
                    Button {
                        model.presentedSheet = .details
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("About Walk It All")
                }
            }
        } else {
            HStack {
                areaLabel
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
        }
    }

    private var areaLabel: some View {
        Group {
            if dynamicTypeSize >= .accessibility4 {
                Image(systemName: "map.fill")
                    .frame(width: 44, height: 44)
            } else {
                Label("Manhattan", systemImage: "map.fill")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .walkItAllFloatingSurface(cornerRadius: 18)
        .accessibilityLabel("Current completion area: Manhattan Island")
        .accessibilityIdentifier("current-completion-area")
    }

    @ViewBuilder
    private func progressCard(_ coverage: CoverageSnapshot, availableHeight: CGFloat) -> some View {
        let card = ProgressCard(
            coverage: coverage,
            phase: model.importPhase,
            selectedWorkoutName: model.selectedWorkout.map {
                $0.start.formatted(date: .abbreviated, time: .shortened)
            },
            lastSuccessfulImport: model.lastSuccessfulImport,
            hasMappedWorkouts: !model.workoutRecords.isEmpty,
            refresh: model.refresh,
            cancel: model.cancelImport,
            showDetails: { model.presentedSheet = .details },
            clearSelection: model.clearSelectedWorkout
        )

        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                card
                    .padding(.vertical, 12)
            }
            .frame(maxHeight: availableHeight * 0.78)
            .padding(.horizontal, 16)
        } else {
            card
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }
}
