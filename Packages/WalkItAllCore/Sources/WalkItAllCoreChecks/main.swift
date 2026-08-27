import Foundation
import WalkItAllCore

@main
enum CoreChecks {
    static func main() async throws {
        try checkProjection()
        checkRouteGaps()
        checkCoverageUnion()
        try await checkParallelStreetMatching()
        try await checkDisconnectedNetworkSplit()
        print("WalkItAllCore checks passed")
    }

    private static func checkProjection() throws {
        let start = GeoCoordinate(latitude: 40.7500, longitude: -73.9900)
        let end = GeoCoordinate(latitude: 40.7510, longitude: -73.9900)
        let point = GeoCoordinate(latitude: 40.7505, longitude: -73.9899)
        guard let projection = GeoMath.project(point, onto: [start, end]),
              (7 ..< 10).contains(projection.distanceMeters),
              (50 ..< 62).contains(projection.offsetMeters)
        else {
            throw CheckFailure("Polyline projection")
        }
    }

    private static func checkRouteGaps() {
        let start = Date(timeIntervalSince1970: 1_000)
        let points = [
            routePoint(40.75, -73.99, start),
            routePoint(40.7501, -73.99, start.addingTimeInterval(10)),
            routePoint(40.76, -73.98, start.addingTimeInterval(400)),
            routePoint(40.7601, -73.98, start.addingTimeInterval(410)),
        ]
        precondition(RouteChunker().chunks(from: points).count == 2, "Route gap was bridged")
    }

    private static func checkCoverageUnion() {
        let segment = WalkableSegment(
            id: "coverage",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ],
            lengthMeters: 100,
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: metadata, segments: [segment])
        let contributions = [
            WorkoutCoverageContribution(
                workoutID: UUID(),
                intervals: [SegmentInterval(segmentID: segment.id, lowerBoundMeters: 0, upperBoundMeters: 55, confidence: 1)],
                confidence: 1
            ),
            WorkoutCoverageContribution(
                workoutID: UUID(),
                intervals: [SegmentInterval(segmentID: segment.id, lowerBoundMeters: 40, upperBoundMeters: 80, confidence: 1)],
                confidence: 1
            ),
        ]
        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: contributions)
        precondition(abs(snapshot.coveredDistanceMeters - 80) < 0.001, "Coverage was double-counted")
        precondition(snapshot.completedSegmentIDs.contains(segment.id), "Completion threshold was not applied")
    }

    private static func checkParallelStreetMatching() async throws {
        let west = WalkableSegment(
            id: "west",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
                GeoCoordinate(latitude: 40.7520, longitude: -73.9900),
            ],
            kind: .street
        )
        let east = WalkableSegment(
            id: "east",
            startNode: NodeID(3),
            endNode: NodeID(4),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.98975),
                GeoCoordinate(latitude: 40.7520, longitude: -73.98975),
            ],
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: metadata, segments: [west, east])
        let start = Date(timeIntervalSince1970: 2_000)
        let points = (0 ... 4).map { index in
            routePoint(
                40.7502 + Double(index) * 0.00035,
                -73.9900,
                start.addingTimeInterval(Double(index) * 20)
            )
        }
        let result = try await ContinuityMapMatcher().match(points: points, in: pack)
        guard !result.intervals.isEmpty,
              result.intervals.allSatisfy({ $0.segmentID == west.id })
        else {
            throw CheckFailure("Parallel-street matcher")
        }
    }

    private static func checkDisconnectedNetworkSplit() async throws {
        let first = WalkableSegment(
            id: "first-component",
            startNode: NodeID(10),
            endNode: NodeID(11),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9910),
                GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
            ],
            kind: .parkPath
        )
        let second = WalkableSegment(
            id: "second-component",
            startNode: NodeID(20),
            endNode: NodeID(21),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9893),
                GeoCoordinate(latitude: 40.7500, longitude: -73.9883),
            ],
            kind: .parkPath
        )
        let pack = InMemoryCityCoveragePack(metadata: metadata, segments: [first, second])
        let start = Date(timeIntervalSince1970: 3_000)
        let points = [
            routePoint(40.7500, -73.9908, start),
            routePoint(40.7500, -73.9901, start.addingTimeInterval(20)),
            routePoint(40.7500, -73.9892, start.addingTimeInterval(45)),
            routePoint(40.7500, -73.9885, start.addingTimeInterval(65)),
        ]
        let result = try await ContinuityMapMatcher().match(points: points, in: pack)
        let matchedIDs = Set(result.intervals.map(\.segmentID))
        guard matchedIDs.contains(first.id),
              matchedIDs.contains(second.id),
              result.unmatchedPortions.contains(where: { $0.reason == .implausibleTransition })
        else {
            throw CheckFailure(
                "Disconnected-network split ids=\(matchedIDs.map(\.rawValue)) unmatched=\(result.unmatchedPortions.map(\.reason.rawValue)) accepted=\(result.acceptedPointCount) rejected=\(result.rejectedPointCount) chunks=\(RouteChunker().chunks(from: points).map(\.count))"
            )
        }
    }

    private static func routePoint(_ latitude: Double, _ longitude: Double, _ timestamp: Date) -> RoutePoint {
        RoutePoint(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: timestamp,
            horizontalAccuracy: 5
        )
    }

    private static var metadata: MapPackMetadata {
        MapPackMetadata(
            identifier: "checks",
            displayName: "Checks",
            version: 1,
            sourceDate: Date(timeIntervalSince1970: 0),
            sourceURL: nil,
            attribution: "Synthetic"
        )
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
