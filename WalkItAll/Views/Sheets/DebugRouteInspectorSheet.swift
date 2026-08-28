#if DEBUG
import MapKit
import SwiftUI
import WalkItAllCore

struct DebugRouteInspectorSheet: View {
    let model: AppModel
    @State private var selectedWorkoutID: UUID

    @State private var showRawTrace = true
    @State private var showNearbyNetwork = false
    @State private var showCandidates = true
    @State private var showCredited = true
    @State private var showRejected = true
    @State private var incorrectCredited = Set<SegmentID>()
    @State private var clearlyWalkedMissed = Set<SegmentID>()
    @State private var isReviewComplete = false
    @State private var saveStatus: String?
    @State private var diagnosticSaveStatus: String?

    init(model: AppModel, workoutID: UUID) {
        self.model = model
        _selectedWorkoutID = State(initialValue: workoutID)
    }

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
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Newer", systemImage: "chevron.up") {
                    moveWorkout(by: -1)
                }
                .disabled(workoutIndex == nil || workoutIndex == 0)

                Spacer()

                if let workoutIndex {
                    Text("\((workoutIndex + 1).formatted()) of \(model.workoutRecords.count.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Older", systemImage: "chevron.down") {
                    moveWorkout(by: 1)
                }
                .disabled(
                    workoutIndex == nil ||
                        workoutIndex == model.workoutRecords.index(before: model.workoutRecords.endIndex)
                )
            }
        }
        .task(id: selectedWorkoutID) {
            await model.loadDebugInspection(workoutID: selectedWorkoutID)
        }
        .onDisappear(perform: model.clearDebugInspection)
    }

    private var workoutIndex: Int? {
        model.workoutRecords.firstIndex { $0.id == selectedWorkoutID }
    }

    private func moveWorkout(by offset: Int) {
        guard let workoutIndex else { return }
        let targetIndex = workoutIndex + offset
        guard model.workoutRecords.indices.contains(targetIndex) else { return }
        incorrectCredited.removeAll()
        clearlyWalkedMissed.removeAll()
        isReviewComplete = false
        saveStatus = nil
        diagnosticSaveStatus = nil
        selectedWorkoutID = model.workoutRecords[targetIndex].id
    }

    private func inspector(
        route: WorkoutRoute,
        match: MatchResult,
        nearbySegmentIDs: Set<SegmentID>,
        pack: any CityCoveragePack
    ) -> some View {
        let reviewContribution = WorkoutCoverageContribution(
            workoutID: route.id,
            intervals: match.intervals,
            confidence: match.averageConfidence
        )
        let creditedIDs = Set(reviewContribution.intervals.map(\.segmentID))
        // Include the wider review network as well as matcher candidates. A
        // segment that never became a candidate is exactly the kind of recall
        // failure this screen needs to make reviewable.
        let missedCandidates = nearbySegmentIDs
            .union(match.candidateSegmentIDs)
            .subtracting(creditedIDs)
        let displayRejections = UnmatchedPortion.coalesced(match.unmatchedPortions)
        let measurement = MatchAccuracyEvaluator().evaluate(
            contribution: reviewContribution,
            incorrectCreditedSegmentIDs: incorrectCredited,
            clearlyWalkedMissedSegmentIDs: clearlyWalkedMissed,
            in: pack
        )

        return VStack(spacing: 0) {
            Map(initialPosition: .region(region(for: route, pack: pack))) {
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
                    ForEach(Array(reviewContribution.intervals.enumerated()), id: \.offset) { _, interval in
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
                    ForEach(Array(displayRejections.enumerated()), id: \.offset) { _, portion in
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
                    LabeledContent(
                        "Credited distance",
                        value: distance(reviewContribution.uniqueCoveredDistanceMeters)
                    )
                    if !isReviewComplete {
                        LabeledContent("Accuracy review", value: "Not completed")
                    }
                    if isReviewComplete, let precision = measurement.precision {
                        LabeledContent("Reviewed precision") {
                            Text(precision, format: .percent.precision(.fractionLength(1)))
                        }
                    }
                    if isReviewComplete, let recall = measurement.recall {
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
                    if displayRejections.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rejectionGroups(displayRejections)) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason(group.reason))
                                .font(.subheadline.weight(.semibold))
                            Text(rejectionSummary(group))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Mark review complete", systemImage: "checkmark.seal") {
                        isReviewComplete = true
                        saveStatus = nil
                    }
                    .disabled(isReviewComplete)

                    Button("Save local review fixture", systemImage: "square.and.arrow.down") {
                        saveReview(
                            route: route,
                            match: match,
                            measurement: measurement,
                            pack: pack
                        )
                    }
                    .disabled(!isReviewComplete)
                    if let saveStatus {
                        Text(saveStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save private diagnostic route", systemImage: "lock.doc") {
                        saveDiagnostic(route: route, match: match, pack: pack)
                    }
                    .foregroundStyle(.orange)
                    if let diagnosticSaveStatus {
                        Text(diagnosticSaveStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Complete the visual review before saving accuracy. Changing a review choice marks it incomplete again. The review fixture has no coordinates. The private diagnostic includes the full Health route and is only for investigating a failed match. Both stay in this debug app’s protected, backup-excluded storage; never share or commit them.")
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
                isReviewComplete = false
                saveStatus = nil
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
        measurement: MatchAccuracyMeasurement,
        pack: any CityCoveragePack
    ) {
        let fixture = RouteReviewFixture(
            schemaVersion: 4,
            createdAt: Date(),
            reviewCompleted: true,
            packIdentifier: pack.metadata.identifier,
            packVersion: pack.metadata.version,
            acceptedPointCount: match.acceptedPointCount,
            rejectedPointCount: match.rejectedPointCount,
            correctlyCreditedMeters: measurement.correctlyCreditedMeters,
            creditedMeters: measurement.creditedMeters,
            clearlyWalkedMeters: measurement.clearlyWalkedMeters,
            rejectionReasonCounts: Dictionary(
                uniqueKeysWithValues: rejectionGroups(
                    UnmatchedPortion.coalesced(match.unmatchedPortions)
                ).map {
                    ($0.reason.rawValue, $0.portions.count)
                }
            ),
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
                let url = try await DebugRouteFixtureStore.saveReview(fixture)
                saveStatus = "Saved \(url.lastPathComponent) locally."
            } catch {
                saveStatus = "Couldn’t save the review: \(error.localizedDescription)"
            }
        }
    }

    private func saveDiagnostic(
        route: WorkoutRoute,
        match: MatchResult,
        pack: any CityCoveragePack
    ) {
        let fixture = PrivateRouteDiagnosticFixture(
            schemaVersion: 2,
            createdAt: Date(),
            packIdentifier: pack.metadata.identifier,
            packVersion: pack.metadata.version,
            route: route,
            match: match
        )
        Task {
            do {
                let url = try await DebugRouteFixtureStore.saveDiagnostic(fixture)
                diagnosticSaveStatus = "Saved \(url.lastPathComponent) privately."
            } catch {
                diagnosticSaveStatus = "Couldn’t save the diagnostic: \(error.localizedDescription)"
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

    private func rejectionGroups(_ portions: [UnmatchedPortion]) -> [RejectionGroup] {
        Dictionary(grouping: portions, by: \.reason)
            .map { RejectionGroup(reason: $0.key, portions: $0.value) }
            .sorted { $0.reason.rawValue < $1.reason.rawValue }
    }

    private func rejectionSummary(_ group: RejectionGroup) -> String {
        let totalSeconds = group.portions.reduce(0) {
            $0 + max(0, $1.end.timeIntervalSince($1.start))
        }
        let portionLabel = group.portions.count == 1 ? "portion" : "portions"
        return "\(group.portions.count.formatted()) \(portionLabel) · \(Duration.seconds(totalSeconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))) total"
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

    private func region(
        for route: WorkoutRoute,
        pack: any CityCoveragePack
    ) -> MKCoordinateRegion {
        let validPoints = route.points.filter {
            $0.coordinate.isValid
                && $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= 50
        }
        let focusedPoints: [RoutePoint]
        if let bounds = pack.geographicBounds {
            let margin = 0.01
            let inArea = validPoints.filter {
                $0.coordinate.latitude >= bounds.minimumLatitude - margin
                    && $0.coordinate.latitude <= bounds.maximumLatitude + margin
                    && $0.coordinate.longitude >= bounds.minimumLongitude - margin
                    && $0.coordinate.longitude <= bounds.maximumLongitude + margin
            }
            focusedPoints = inArea.count >= 2 ? inArea : validPoints
        } else {
            focusedPoints = validPoints
        }
        let regionPoints = focusedPoints.count >= 2 ? focusedPoints : route.points
        let latitudes = regionPoints.map(\.coordinate.latitude)
        let longitudes = regionPoints.map(\.coordinate.longitude)
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

private struct RejectionGroup: Identifiable {
    let reason: UnmatchedPortion.Reason
    let portions: [UnmatchedPortion]

    var id: UnmatchedPortion.Reason { reason }
}

#endif
