import SwiftUI

struct PrivacySheet: View {
    var body: some View {
        List {
            Section {
                Label("No account", systemImage: "person.crop.circle.badge.xmark")
                Label("No advertising or analytics", systemImage: "eye.slash.fill")
                Label("No passive background tracking", systemImage: "location.slash.fill")
                Label("No route uploads", systemImage: "icloud.slash.fill")
            }
            Section("On this iPhone") {
                Text("Walk It All keeps only a simplified copy of each mapped workout route in a protected local cache. Full-resolution Health locations are discarded after processing.")
                Text("Location runs in the background only while you explicitly have a Live Trail active. Pause or Finish stops background trail tracking immediately; Resume starts it again only after you tap it.")
                Text("Filtered Live Trail coordinates stay on this iPhone in protected storage. A finished trail remains until you clear it or start a new one.")
                Text("Finished Live Trails survive an ordinary relaunch, but they are excluded from backup and cannot be recovered after reinstalling or changing phones.")
                Text("The cache is excluded from device backup. If you reinstall or change phones, the app can rebuild from whatever route history Apple Health has synchronized and you authorize.")
            }
            Section("Apple Health") {
                Text("The app requests read-only access to walking, hiking, running, and cycling workouts and their routes. It never writes data to Health.")
                Text("Apple does not tell apps whether Health read access was denied, so an empty map can also mean there are no recorded outdoor routes or access is limited.")
            }
        }
        .navigationTitle("Privacy and Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}
