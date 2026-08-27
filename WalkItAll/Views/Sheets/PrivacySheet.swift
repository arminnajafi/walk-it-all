import SwiftUI

struct PrivacySheet: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                Label("No account", systemImage: "person.crop.circle.badge.xmark")
                Label("No advertising or analytics", systemImage: "eye.slash.fill")
                Label("No background location tracking", systemImage: "location.slash.fill")
                Label("No route uploads", systemImage: "icloud.slash.fill")
            }
            Section("On this iPhone") {
                Text("The app keeps a simplified route, matched map portions, and aggregate progress in a protected local cache. Full-resolution Health route points are discarded after matching.")
                Text("The cache is excluded from backup. If you reinstall or change phones, Walk It All rebuilds coverage from whatever route history Apple Health has synchronized and you authorize.")
            }
            Section("Apple Health") {
                Text("Walk It All requests read-only access to walking and hiking workouts and their routes. It never writes workouts or other data to Health.")
                Text("Apple does not tell apps whether Health read access was denied, so an empty result can also mean that there are no recorded outdoor routes or that access is limited.")
            }
        }
        .navigationTitle("Privacy and Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
