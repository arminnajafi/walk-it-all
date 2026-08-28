import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model: AppModel?
    let startupError: String?

    override init() {
        do {
            model = AppModel(dependencies: try .live())
            startupError = nil
        } catch {
            model = nil
            startupError = error.localizedDescription
        }
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Bootstrap immediately on a Core Location relaunch so an explicitly
        // active session can recreate its background activity and update stream.
        Task { await model?.bootstrap() }
        return true
    }
}

@main
struct WalkItAllApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if let model = appDelegate.model {
                RootView(model: model)
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open local data", systemImage: "lock.trianglebadge.exclamationmark")
                } description: {
                    Text(appDelegate.startupError ?? "Walk It All could not create its protected local cache.")
                }
            }
        }
    }
}
