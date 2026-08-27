import SwiftUI

struct RootView: View {
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
        .fullScreenCover(isPresented: Binding(
            get: { model.launchState == .ready && !model.hasCompletedOnboarding },
            set: { _ in }
        )) {
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
                ProgressView("Opening Manhattan…")
            }
        }
    }
}

