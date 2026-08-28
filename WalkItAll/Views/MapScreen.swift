import SwiftUI
import WalkItAllCore

struct MapScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: AppModel
    @State private var showHealthWaitHelp = false
    @State private var bottomOverlayHeight: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let pack = model.cityPack {
                    CoverageMapView(
                        pack: pack,
                        coverage: model.coverage,
                        selectedWorkout: model.selectedWorkout,
                        coverageRevision: model.coverageRenderRevision,
                        viewportCommand: model.mapViewportCommand,
                        mapOrnamentBottomInset: bottomOverlayHeight
                            + geometry.safeAreaInsets.bottom
                            + 8
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
                .onPreferenceChange(BottomOverlayHeightPreferenceKey.self) { height in
                    guard height > 0 else { return }
                    bottomOverlayHeight = height
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
        .task(id: model.importPhase) {
            guard model.importPhase == .requestingHealthAccess else { return }
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard model.importPhase == .requestingHealthAccess else { return }
            showHealthWaitHelp = true
        }
        .alert("Still waiting for Apple Health?", isPresented: $showHealthWaitHelp) {
            Button("Review Access") {
                model.cancelImport()
                model.presentedSheet = .healthAccess
            }
            Button("Keep Waiting", role: .cancel) {}
        } message: {
            Text("If the Apple Health permission sheet is not visible, review the access steps or try the request again.")
        }
    }

    @ViewBuilder
    private var topControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack {
                    areaButton
                        .buttonStyle(.glass)
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
                areaButton
                    .buttonStyle(.plain)
                    .walkItAllControlSurface()
                Spacer()
                Button {
                    model.presentedSheet = .details
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .walkItAllControlSurface()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Walk It All")
            }
        }
    }

    private var areaButton: some View {
        Button(action: model.showAllManhattan) {
            Group {
                if dynamicTypeSize >= .accessibility4 {
                    Image(systemName: "map.fill")
                        .frame(width: 44, height: 44)
                } else {
                    Label("Manhattan", systemImage: "map.fill")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel("Show all Manhattan")
        .accessibilityHint("Recenters the map on the full completion area")
        .accessibilityIdentifier("current-completion-area")
    }

    @ViewBuilder
    private func progressCard(_ coverage: CoverageSnapshot, availableHeight: CGFloat) -> some View {
        let card = Group {
            if let workout = model.selectedWorkout {
                SelectedWorkoutCard(workout: workout, clear: model.clearSelectedWorkout)
            } else {
                ProgressCard(
                    coverage: coverage,
                    phase: model.importPhase,
                    lastSuccessfulImport: model.lastSuccessfulImport,
                    hasMappedWorkouts: model.hasMappedWorkouts,
                    refresh: model.refresh,
                    cancel: model.cancelImport,
                    showDetails: { model.presentedSheet = .details }
                )
            }
        }

        Group {
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
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BottomOverlayHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

}

private struct BottomOverlayHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
