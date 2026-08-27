#if DEBUG
import MapKit
import SwiftUI
import WalkItAllCore

struct DebugRouteInspectorSheet: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let route = model.debugLastRoute,
               let match = model.debugLastMatch,
               let pack = model.cityPack
            {
                Map(initialPosition: .region(region(for: route))) {
                    ForEach(Array(match.candidateSegmentIDs).sorted(by: {
                        $0.rawValue < $1.rawValue
                    }), id: \.self) { segmentID in
                        if let segment = pack.segment(id: segmentID) {
                            MapPolyline(coordinates: segment.coordinates.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                            .stroke(.gray.opacity(0.5), lineWidth: 2)
                        }
                    }

                    ForEach(Array(RouteChunker().chunks(from: route.points).enumerated()), id: \.offset) { _, chunk in
                        MapPolyline(coordinates: chunk.map {
                            CLLocationCoordinate2D(
                                latitude: $0.coordinate.latitude,
                                longitude: $0.coordinate.longitude
                            )
                        })
                        .stroke(.purple.opacity(0.65), lineWidth: 3)
                    }

                    ForEach(Array(match.intervals.enumerated()), id: \.offset) { _, interval in
                        if let segment = pack.segment(id: interval.segmentID) {
                            MapPolyline(coordinates: GeoMath.slice(
                                polyline: segment.coordinates,
                                from: interval.lowerBoundMeters,
                                to: interval.upperBoundMeters
                            ).map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                            .stroke(.indigo, lineWidth: 5)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))

                HStack {
                    Label("Raw GPS", systemImage: "line.diagonal")
                        .foregroundStyle(.purple)
                    Spacer()
                    Label("Candidates", systemImage: "line.diagonal")
                        .foregroundStyle(.gray)
                    Spacer()
                    Label("Accepted network", systemImage: "line.diagonal")
                        .foregroundStyle(.indigo)
                }
                .font(.caption.weight(.semibold))
                .padding()

                List {
                    LabeledContent("Accepted points", value: match.acceptedPointCount.formatted())
                    LabeledContent("Rejected points", value: match.rejectedPointCount.formatted())
                    LabeledContent("Confidence") {
                        Text(match.averageConfidence, format: .percent.precision(.fractionLength(0)))
                    }
                    LabeledContent("Unmatched portions", value: match.unmatchedPortions.count.formatted())
                    LabeledContent("Candidate segments", value: match.candidateSegmentIDs.count.formatted())
                    ForEach(Array(match.unmatchedPortions.prefix(20).enumerated()), id: \.offset) { _, portion in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(portion.reason.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized)
                                .font(.caption.weight(.semibold))
                            Text("\(portion.start.formatted(date: .omitted, time: .standard))–\(portion.end.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 220)
            } else {
                ContentUnavailableView(
                    "No debug route yet",
                    systemImage: "ladybug",
                    description: Text("Import a workout in this debug build to inspect its raw and matched paths.")
                )
            }
        }
        .navigationTitle("Route Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseButton() }
    }

    private func region(for route: WorkoutRoute) -> MKCoordinateRegion {
        let latitudes = route.points.map(\.coordinate.latitude)
        let longitudes = route.points.map(\.coordinate.longitude)
        let minLatitude = latitudes.min() ?? 40.70
        let maxLatitude = latitudes.max() ?? 40.88
        let minLongitude = longitudes.min() ?? -74.02
        let maxLongitude = longitudes.max() ?? -73.93
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.005, (maxLatitude - minLatitude) * 1.25),
                longitudeDelta: max(0.005, (maxLongitude - minLongitude) * 1.25)
            )
        )
    }
}
#endif
