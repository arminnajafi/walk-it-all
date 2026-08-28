import SwiftUI
#if DEBUG
import UIKit
#endif

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: AppModel

    var body: some View {
        Group {
            switch model.launchState {
            case .loading:
                LaunchPlaceholder()
            case .ready:
                MapScreen(model: model)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn’t open Walk It All", systemImage: "map.circle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await model.bootstrap() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task { await model.bootstrap() }
        #if DEBUG
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
        }
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            #if DEBUG
            UIApplication.shared.isIdleTimerDisabled = newPhase == .active
            #endif
            guard newPhase == .active else { return }
            model.refreshIfNeeded()
        }
        .onChange(of: model.launchState) { _, newState in
            guard newState == .ready, scenePhase == .active else { return }
            model.refreshIfNeeded()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { model.launchState == .ready && !model.hasCompletedOnboarding },
                set: { _ in }
            ),
            onDismiss: model.resumePendingOnboardingImport
        ) {
            OnboardingView(model: model)
        }
    }
}

private struct LaunchPlaceholder: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.indigo)
                ProgressView("Opening your map…")
            }
        }
    }
}
