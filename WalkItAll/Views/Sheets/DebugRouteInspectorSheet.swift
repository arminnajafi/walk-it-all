#if DEBUG
import MapKit
import SwiftUI
import WalkItAllCore

struct DebugRouteInspectorSheet: View {
    let model: AppModel
    let workoutID: UUID

    @State private var showRawTrace = true
    @State private var showNearbyNetwork = false
    @State private var showCandidates = true
    @State private var showCredited = true
    @State private var showRejected = true
    @State private var incorrectCredited = Set<SegmentID>()
    @State private var clearlyWalkedMissed = Set<SegmentID>()
    @State private var saveStatus: String?

    var body: some View {
        Group {
            switch model.debugInspectionState {
            case .idle, .loading:
                ProgressView("Reading route from Apple Health…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView(
                    "Route unavailable",
                    systemImage: "ladybug",
                    description: Text(message)
                )
            case let .loaded(route, match, nearbySegmentIDs):
                if let pack = model.cityPack {
                    inspector(
                        route: route,
                        match: match,
                        nearbySegmentIDs: nearbySegmentIDs,
                        pack: pack
                    )
                }
            }
        }
        .navigationTitle("Route Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Layers", systemImage: "square.3.layers.3d") {
                    Toggle("Raw Health GPS", isOn: $showRawTrace)
                    Toggle("Nearby eligible network", isOn: $showNearbyNetwork)
                    Toggle("Matcher candidates", isOn: $showCandidates)
                    Toggle("Credited intervals", isOn: $showCredited)
                    Toggle("Rejected trace", isOn: $showRejected)
                }
            }
        }
        .task(id: workoutID) {
            await model.loadDebugInspection(workoutID: workoutID)
        }
        .onDisappear(perform: model.clearDebugInspection)
    }

    private func inspector(
        route: WorkoutRoute,
        match: MatchResult,
        nearbySegmentIDs: Set<SegmentID>,
        pack: any CityCoveragePack
    ) -> some View {
        let creditedIDs = Set(match.intervals.map(\.segmentID))
        let missedCandidates = match.candidateSegmentIDs.subtracting(creditedIDs)
        let clearlyWalkedIDs = creditedIDs
            .subtracting(incorrectCredited)
            .union(clearlyWalkedMissed)
        let measurement = MatchAccuracyEvaluator().evaluate(
            contribution: WorkoutCoverageContribution(
                workoutID: route.id,
                intervals: match.intervals,
                confidence: match.averageConfidence
            ),
            clearlyWalkedSegmentIDs: clearlyWalkedIDs,
            in: pack
        )

        return VStack(spacing: 0) {
            Map(initialPosition: .region(region(for: route))) {
                if showNearbyNetwork {
                    segmentPolylines(
                        ids: nearbySegmentIDs,
                        pack: pack,
                        color: .gray.opacity(0.3),
                        lineWidth: 1
                    )
                }

                if showCandidates {
                    segmentPolylines(
                        ids: match.candidateSegmentIDs,
                        pack: pack,
                        color: .yellow.opacity(0.75),
                        lineWidth: 2
                    )
                }

                if showRawTrace {
                    ForEach(Array(RouteChunker().chunks(from: route.points).enumerated()), id: \.offset) { _, chunk in
                        MapPolyline(coordinates: coordinates(chunk))
                            .stroke(.purple.opacity(0.7), lineWidth: 3)
                    }
                }

                if showCredited {
                    ForEach(Array(match.intervals.enumerated()), id: \.offset) { _, interval in
                        if let segment = pack.segment(id: interval.segmentID) {
                            MapPolyline(coordinates: GeoMath.slice(
                                polyline: segment.coordinates,
                                from: interval.lowerBoundMeters,
                                to: interval.upperBoundMeters
                            ).map(coordinate))
                            .stroke(.indigo, lineWidth: 5)
                        }
                    }
                }

                if showRejected {
                    ForEach(Array(match.unmatchedPortions.enumerated()), id: \.offset) { _, portion in
                        let rejected = route.points.filter {
                            $0.timestamp >= portion.start && $0.timestamp <= portion.end
                        }
                        if rejected.count >= 2 {
                            MapPolyline(coordinates: coordinates(rejected))
                                .stroke(
                                    .red,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [7, 5])
                                )
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .frame(minHeight: 260)

            legend

            List {
                Section("Matcher summary") {
                    LabeledContent("Accepted GPS points", value: match.acceptedPointCount.formatted())
                    LabeledContent("Rejected GPS points", value: match.rejectedPointCount.formatted())
                    LabeledContent("Candidate segments", value: match.candidateSegmentIDs.count.formatted())
                    LabeledContent("Credited distance", value: distance(
                        WorkoutCoverageContribution(
                            workoutID: route.id,
                            intervals: match.intervals,
                            confidence: match.averageConfidence
                        ).uniqueCoveredDistanceMeters
                    ))
                    if let precision = measurement.precision {
                        LabeledContent("Reviewed precision") {
                            Text(precision, format: .percent.precision(.fractionLength(1)))
                        }
                    }
                    if let recall = measurement.recall {
                        LabeledContent("Reviewed recall") {
                            Text(recall, format: .percent.precision(.fractionLength(1)))
                        }
                    }
                }

                Section("Review credited streets") {
                    Text("Turn on any credited street that the route did not actually traverse.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(sorted(creditedIDs), id: \.self) { segmentID in
                        Toggle(isOn: binding(for: segmentID, in: $incorrectCredited)) {
                            segmentLabel(segmentID, pack: pack)
                        }
                    }
                }

                Section("Review missed streets") {
                    Text("Turn on a nearby candidate only when the route clearly walked it but the matcher gave no credit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(sorted(missedCandidates), id: \.self) { segmentID in
                        Toggle(isOn: binding(for: segmentID, in: $clearlyWalkedMissed)) {
                            segmentLabel(segmentID, pack: pack)
                        }
                    }
                }

                Section("Rejected portions") {
                    if match.unmatchedPortions.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(match.unmatchedPortions.enumerated()), id: \.offset) { _, portion in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason(portion.reason))
                                .font(.subheadline.weight(.semibold))
                            Text("\(portion.start.formatted(date: .omitted, time: .standard))–\(portion.end.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Save local review fixture", systemImage: "square.and.arrow.down") {
                        saveReview(route: route, match: match, pack: pack)
                    }
                    if let saveStatus {
                        Text(saveStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("The fixture stays in this debug app’s protected, backup-excluded storage. It contains segment IDs and the Health workout ID, but no coordinates.")
                }
            }
            .frame(minHeight: 300)
        }
    }

    @MapContentBuilder
    private func segmentPolylines(
        ids: Set<SegmentID>,
        pack: any CityCoveragePack,
        color: Color,
        lineWidth: CGFloat
    ) -> some MapContent {
        ForEach(sorted(ids), id: \.self) { segmentID in
            if let segment = pack.segment(id: segmentID) {
                MapPolyline(coordinates: segment.coordinates.map(coordinate))
                    .stroke(color, lineWidth: lineWidth)
            }
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                legendItem("Raw GPS", color: .purple)
                legendItem("Candidates", color: .yellow)
                legendItem("Credited", color: .indigo)
                legendItem("Rejected", color: .red)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        Label(title, systemImage: "line.diagonal")
            .foregroundStyle(color)
    }

    private func binding(for id: SegmentID, in selection: Binding<Set<SegmentID>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(id)
                } else {
                    selection.wrappedValue.remove(id)
                }
            }
        )
    }

    private func segmentLabel(_ id: SegmentID, pack: any CityCoveragePack) -> some View {
        let segment = pack.segment(id: id)
        return VStack(alignment: .leading, spacing: 2) {
            Text(segment?.name ?? "Unnamed \(segment?.kind.rawValue ?? "segment")")
            Text("\(id.rawValue) · \(distance(segment?.lengthMeters ?? 0))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func saveReview(
        route: WorkoutRoute,
        match: MatchResult,
        pack: any CityCoveragePack
    ) {
        let fixture = ReviewFixture(
            schemaVersion: 1,
            createdAt: Date(),
            workoutID: route.id,
            packIdentifier: pack.metadata.identifier,
            packVersion: pack.metadata.version,
            creditedSegmentIDs: sorted(Set(match.intervals.map(\.segmentID))).map(\.rawValue),
            clearlyWalkedSegmentIDs: sorted(
                Set(match.intervals.map(\.segmentID))
                    .subtracting(incorrectCredited)
                    .union(clearlyWalkedMissed)
            ).map(\.rawValue),
            incorrectCreditedSegmentIDs: sorted(incorrectCredited).map(\.rawValue),
            clearlyWalkedMissedSegmentIDs: sorted(clearlyWalkedMissed).map(\.rawValue)
        )
        Task {
            do {
                let url = try await ReviewFixtureStore.save(fixture)
                saveStatus = "Saved \(url.lastPathComponent) locally."
            } catch {
                saveStatus = "Couldn’t save the review: \(error.localizedDescription)"
            }
        }
    }

    private func sorted(_ ids: Set<SegmentID>) -> [SegmentID] {
        ids.sorted { $0.rawValue < $1.rawValue }
    }

    private func reason(_ reason: UnmatchedPortion.Reason) -> String {
        reason.rawValue
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }

    private func distance(_ meters: Double) -> String {
        let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles)
        return "\(miles.value.formatted(.number.precision(.fractionLength(2)))) mi"
    }

    private func coordinates(_ points: [RoutePoint]) -> [CLLocationCoordinate2D] {
        points.map { coordinate($0.coordinate) }
    }

    private func coordinate(_ coordinate: GeoCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
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

private struct ReviewFixture: Codable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let workoutID: UUID
    let packIdentifier: String
    let packVersion: Int
    let creditedSegmentIDs: [String]
    let clearlyWalkedSegmentIDs: [String]
    let incorrectCreditedSegmentIDs: [String]
    let clearlyWalkedMissedSegmentIDs: [String]
}

private enum ReviewFixtureStore {
    static func save(_ fixture: ReviewFixture) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport
                .appendingPathComponent("WalkItAll", isDirectory: true)
                .appendingPathComponent("LocalRouteFixtures", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedDirectory = directory
            try protectedDirectory.setResourceValues(values)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = directory.appendingPathComponent("review-\(UUID().uuidString).json")
            try encoder.encode(fixture).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }.value
    }
}
#endif
