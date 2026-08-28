import SwiftUI
import UIKit

struct MapScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: AppModel
    @State private var showHealthWaitHelp = false
    @State private var bottomOverlayHeight: CGFloat = 76

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LifetimeMapView(
                    records: model.routeRecords,
                    selectedWorkout: model.selectedWorkout,
                    routeRevision: model.routeRenderRevision,
                    liveTrailSession: model.liveTrail.session,
                    liveTrailRevision: model.liveTrail.renderRevision,
                    showsUserLocation: model.liveTrail.accessState.canShowLocation,
                    viewportCommand: model.mapViewportCommand,
                    mapOrnamentBottomInset: bottomOverlayHeight
                        + geometry.safeAreaInsets.bottom
                        + 8
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topControls
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    Spacer()
                    bottomCard(availableHeight: geometry.size.height)
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
        ), onDismiss: model.resumePendingLiveTrailStart) { destination in
            AppSheetHost(destination: destination, model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: model.importPhase) {
            guard model.importPhase == .requestingHealthAccess else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
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
            Text("If Apple’s permission sheet is not visible, review the access steps or try again.")
        }
        .alert(
            "Location needs attention",
            isPresented: Binding(
                get: { model.liveTrail.issueMessage != nil },
                set: { if !$0 { model.liveTrail.clearIssue() } }
            )
        ) {
            if model.liveTrail.accessState == .denied {
                Button("Open Settings") {
                    model.liveTrail.clearIssue()
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
            }
            Button("OK", role: .cancel, action: model.liveTrail.clearIssue)
        } message: {
            Text(model.liveTrail.issueMessage ?? "Location is unavailable.")
        }
    }

    @ViewBuilder
    private var topControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack {
                    manhattanButton.buttonStyle(.glass)
                    Spacer()
                    locationButton.buttonStyle(.glass)
                    infoButton.buttonStyle(.glass)
                }
            }
        } else {
            HStack {
                manhattanButton
                    .buttonStyle(.plain)
                    .walkItAllControlSurface()
                Spacer()
                HStack(spacing: 0) {
                    locationButton
                    infoButton
                }
                .buttonStyle(.plain)
                .walkItAllControlSurface()
            }
        }
    }

    private var manhattanButton: some View {
        Button(action: model.showAllManhattan) {
            Label("Manhattan", systemImage: "map.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Show Manhattan")
        .accessibilityHint("Recenters the map on Manhattan")
        .accessibilityIdentifier("manhattan-recenter")
    }

    private var locationButton: some View {
        Button(action: model.showUserLocation) {
            Image(systemName: "location.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Show current location")
        .accessibilityHint("Requests location access if needed and recenters the map")
        .accessibilityIdentifier("current-location")
    }

    private var infoButton: some View {
        Button {
            model.presentedSheet = .details
        } label: {
            Image(systemName: "info.circle")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("About Walk It All")
    }

    @ViewBuilder
    private func bottomCard(availableHeight: CGFloat) -> some View {
        let card = Group {
            if let workout = model.selectedWorkout {
                SelectedWorkoutCard(workout: workout, clear: model.clearSelectedWorkout)
            } else if let session = model.liveTrail.session, session.state == .active {
                ActiveLiveTrailCard(session: session, finish: model.finishLiveTrail)
            } else if model.liveTrail.isWaitingForHealth {
                WaitingForHealthCard(showDetails: { model.presentedSheet = .details })
            } else if model.importPhase.isWorking {
                CompactImportCard(phase: model.importPhase, cancel: model.cancelImport)
            } else if case let .failed(message) = model.importPhase {
                CompactErrorCard(message: message) { model.presentedSheet = .details }
            } else if !model.hasMappedWorkouts {
                LifetimeMapCard(
                    mappedWorkoutCount: 0,
                    phase: model.importPhase,
                    lastSuccessfulImport: model.lastSuccessfulImport,
                    hasConnectedHealth: model.hasConnectedHealth,
                    refresh: model.refresh,
                    cancel: model.cancelImport,
                    showDetails: { model.presentedSheet = .details }
                )
            } else {
                StartLiveTrailButton(action: model.requestStartLiveTrail)
            }
        }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    card.padding(.vertical, 10)
                }
                .frame(maxHeight: availableHeight * 0.5)
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
