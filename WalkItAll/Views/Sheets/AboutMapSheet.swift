import SwiftUI

struct AboutMapSheet: View {
    var body: some View {
        List {
            Section("What appears") {
                Text("Walk It All shows walking, hiking, running, and cycling workouts that include a GPS route in Apple Health. Routes can be anywhere in the world.")
                Text("The map opens on Manhattan because that is the first personal focus, not because walks are limited to New York.")
            }
            Section("How routes are prepared") {
                Text("Locations with poor accuracy are omitted. A route is separated at long pauses, GPS outages, large jumps, or speeds that are implausible for its activity so the map does not draw an artificial line between them.")
                Text("The remaining shape is simplified slightly for smooth map performance. Repeated routes deepen the indigo line subtly.")
            }
            Section("Limitations") {
                Text("This is a map of recorded workout routes—not proof that every street, sidewalk, or physical walk was covered. Ordinary steps, indoor workouts, and activities without a saved route do not appear.")
                Text("GPS can drift near tall buildings, trees, or tunnels. Walk It All preserves the recorded path instead of guessing a street.")
            }
            Section("Live Trail") {
                Text("Live Trail is an optional temporary guide for seeing where you go right now. It is independent from Apple Health and never becomes permanent workout history.")
                Text("Pause stops location and Resume continues in a new part. Finish stops tracking but keeps the green trail until you clear it or start a new one.")
                Text("A supported workout recorded separately may later appear in indigo underneath. It does not change or remove the green trail.")
            }
        }
        .navigationTitle("About This Map")
        .navigationBarTitleDisplayMode(.inline)
    }
}
