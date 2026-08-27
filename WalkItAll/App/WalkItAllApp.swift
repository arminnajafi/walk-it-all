import SwiftUI

@main
struct WalkItAllApp: App {
    @State private var model: AppModel?
    private let startupError: String?

    init() {
        do {
            _model = State(initialValue: AppModel(dependencies: try .live()))
            startupError = nil
        } catch {
            _model = State(initialValue: nil)
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model: model)
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open local data", systemImage: "lock.trianglebadge.exclamationmark")
                } description: {
                    Text(startupError ?? "Walk It All could not create its protected local cache.")
                }
            }
        }
    }
}
