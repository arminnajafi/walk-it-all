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
                Text("Filtered Live Trail coordinates stay on this iPhone. Its temporary protected file can update while the screen is locked after you have unlocked the phone once since restarting it. The file is deleted after Health replaces it or after seven days.")
                Text("The cache is excluded from device backup. If you reinstall or change phones, the app can rebuild from whatever route history Apple Health has synchronized and you authorize.")
            }
            Section("Apple Health") {
                Text("The app requests read-only access to walking and hiking workouts and their routes. It never writes data to Health.")
                Text("Apple does not tell apps whether Health read access was denied, so an empty map can also mean there are no recorded outdoor routes or access is limited.")
            }
        }
        .navigationTitle("Privacy and Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}
