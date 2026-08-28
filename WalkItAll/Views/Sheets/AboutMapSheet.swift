import SwiftUI

struct AboutMapSheet: View {
    var body: some View {
        List {
            Section("What appears") {
                Text("Walk It All shows outdoor walking and hiking workouts that include a GPS route in Apple Health. Routes can be anywhere in the world.")
                Text("The map opens on Manhattan because that is the first personal focus, not because walks are limited to New York.")
            }
            Section("How routes are prepared") {
                Text("Locations with poor accuracy are omitted. A route is separated at long pauses, GPS outages, large jumps, or implausible walking speeds so the map does not draw an artificial line between them.")
                Text("The remaining shape is simplified slightly for smooth map performance. Repeated walks deepen the indigo line subtly.")
            }
            Section("Limitations") {
                Text("This is a map of recorded workout routes—not proof that every street, sidewalk, or physical walk was covered. Ordinary steps, indoor workouts, and activities without a saved route do not appear.")
                Text("GPS can drift near tall buildings, trees, or tunnels. Walk It All preserves the recorded path instead of guessing a street.")
            }
        }
        .navigationTitle("About This Map")
        .navigationBarTitleDisplayMode(.inline)
    }
}
