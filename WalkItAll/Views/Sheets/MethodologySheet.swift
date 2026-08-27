import SwiftUI

struct MethodologySheet: View {
    let model: AppModel

    var body: some View {
        List {
            Section("What counts") {
                Label("Public street blocks and pedestrian streets", systemImage: "road.lanes")
                Label("Meaningful park, waterfront, and greenway paths", systemImage: "leaf.fill")
                Label("Public stairs and walking connectors", systemImage: "stairs")
            }
            Section("What does not count") {
                Text("Private access, parking aisles, service drives, construction, decorative micro-paths, indoor walking, subways, and ferries.")
            }
            Section("How a walk is matched") {
                Text("Walk It All considers GPS accuracy, direction, nearby streets, and continuity through the walking network. Uncertain portions are skipped instead of being assigned to a likely but unproven street.")
                Text("Progress is unique matched distance divided by total eligible walkable distance. A map segment becomes complete after 70% of its length has been covered.")
            }
            Section("Offline map") {
                if let metadata = model.cityPack?.metadata {
                    LabeledContent("Version", value: metadata.version.formatted())
                    LabeledContent("Source date", value: metadata.sourceDate.formatted(date: .abbreviated, time: .omitted))
                    Text(metadata.attribution)
                    if let sourceURL = metadata.sourceURL {
                        Link("OpenStreetMap source", destination: sourceURL)
                    }
                }
            }
        }
        .navigationTitle("How Coverage Works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
