import SwiftUI

@main
struct WalkItAllApp: App {
    @State private var model: AppModel

    init() {
        do {
            _model = State(initialValue: AppModel(dependencies: try .live()))
        } catch {
            fatalError("Could not create the protected local store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

