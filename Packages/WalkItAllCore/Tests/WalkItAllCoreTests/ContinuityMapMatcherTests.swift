import Foundation
import XCTest
@testable import WalkItAllCore

final class ContinuityMapMatcherTests: XCTestCase {
    func testClosedLoopUsesShortPathAcrossGeometrySeam() async throws {
        let start = GeoCoordinate(latitude: 40.75, longitude: -73.99)
        let loop = WalkableSegment(
            id: "closed-loop",
            startNode: NodeID(1),
            endNode: NodeID(1),
            coordinates: [
                start,
                GeoCoordinate(latitude: 40.75, longitude: -73.989),
                GeoCoordinate(latitude: 40.751, longitude: -73.989),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
                start,
            ],
            kind: .parkPath
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [loop])
        let points = [
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.7501, longitude: -73.99),
                timestamp: Date(timeIntervalSince1970: 100),
                horizontalAccuracy: 3
            ),
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.75, longitude: -73.9899),
                timestamp: Date(timeIntervalSince1970: 105),
                horizontalAccuracy: 3
            ),
        ]

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)
        let contribution = WorkoutCoverageContribution(
            workoutID: UUID(),
            intervals: result.intervals,
            confidence: result.averageConfidence
        )

        XCTAssertEqual(result.acceptedPointCount, 2)
        XCTAssertEqual(contribution.intervals.count, 2)
        XCTAssertGreaterThan(contribution.uniqueCoveredDistanceMeters, 5)
        XCTAssertLessThan(contribution.uniqueCoveredDistanceMeters, 40)
    }

    func testKeepsRouteOnCorrectParallelStreet() async throws {
        let west = WalkableSegment(
            id: "west-street",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
                GeoCoordinate(latitude: 40.7520, longitude: -73.9900),
            ],
            kind: .street
        )
        let east = WalkableSegment(
            id: "east-street",
            startNode: NodeID(3),
            endNode: NodeID(4),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.98975),
                GeoCoordinate(latitude: 40.7520, longitude: -73.98975),
            ],
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [west, east])
        let start = Date(timeIntervalSince1970: 1_000)
        let points = (0 ... 4).map { index in
            RoutePoint(
                coordinate: GeoCoordinate(
                    latitude: 40.7502 + Double(index) * 0.00035,
                    longitude: -73.9900
                ),
                timestamp: start.addingTimeInterval(Double(index) * 20),
                horizontalAccuracy: 5
            )
        }

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)

        XCTAssertFalse(result.intervals.isEmpty)
        XCTAssertTrue(result.intervals.allSatisfy { $0.segmentID == west.id })
        XCTAssertGreaterThan(result.averageConfidence, 0.9)
    }

    func testLaterPointsResolveAnInitiallyAmbiguousParallelStreet() async throws {
        let west = WalkableSegment(
            id: "resolved-west",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
                GeoCoordinate(latitude: 40.7520, longitude: -73.9900),
            ],
            kind: .street
        )
        let east = WalkableSegment(
            id: "resolved-east",
            startNode: NodeID(3),
            endNode: NodeID(4),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9898),
                GeoCoordinate(latitude: 40.7520, longitude: -73.9898),
            ],
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [west, east])
        let start = Date(timeIntervalSince1970: 1_500)
        let points = [
            routePoint(40.7502, -73.9899, start),
            routePoint(40.7508, -73.9900, start.addingTimeInterval(20)),
            routePoint(40.7514, -73.9900, start.addingTimeInterval(40)),
        ]

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)

        XCTAssertEqual(result.acceptedPointCount, points.count)
        XCTAssertFalse(result.intervals.isEmpty)
        XCTAssertTrue(result.intervals.allSatisfy { $0.segmentID == west.id })
    }

    func testTreatsGraphSplitsFromOneSourceWayAsEquivalentCandidates() async throws {
        let coordinates = [
            GeoCoordinate(latitude: 40.75000, longitude: -73.99000),
            GeoCoordinate(latitude: 40.75005, longitude: -73.99000),
            GeoCoordinate(latitude: 40.75010, longitude: -73.99000),
            GeoCoordinate(latitude: 40.75015, longitude: -73.99000),
        ]
        var segments: [WalkableSegment] = []
        for index in 0 ..< 3 {
            segments.append(WalkableSegment(
                id: SegmentID("source-way-part-\(index)"),
                startNode: NodeID(Int64(index + 1)),
                endNode: NodeID(Int64(index + 2)),
                coordinates: [coordinates[index], coordinates[index + 1]],
                kind: .parkPath,
                sourceWayID: 42
            ))
        }
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: segments)
        let start = Date(timeIntervalSince1970: 2_000)
        let points = (0 ..< coordinates.count).map { index in
            RoutePoint(
                coordinate: coordinates[index],
                timestamp: start.addingTimeInterval(Double(index) * 5),
                horizontalAccuracy: 3
            )
        }

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)
        let contribution = WorkoutCoverageContribution(
            workoutID: UUID(),
            intervals: result.intervals,
            confidence: result.averageConfidence
        )

        XCTAssertEqual(result.acceptedPointCount, points.count)
        let creditedIDs = Set(result.intervals.map { $0.segmentID })
        let expectedIDs = Set(segments.map { $0.id })
        XCTAssertEqual(creditedIDs, expectedIDs)
        XCTAssertGreaterThan(contribution.uniqueCoveredDistanceMeters, 15)
        XCTAssertGreaterThan(result.averageConfidence, 0.7)
    }

    func testKeepsDisconnectedPartsOfOneSourceWayCompeting() async throws {
        let west = WalkableSegment(
            id: "loop-west",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9901),
                GeoCoordinate(latitude: 40.7510, longitude: -73.9901),
            ],
            kind: .parkPath,
            sourceWayID: 84
        )
        let east = WalkableSegment(
            id: "loop-east",
            startNode: NodeID(3),
            endNode: NodeID(4),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9899),
                GeoCoordinate(latitude: 40.7510, longitude: -73.9899),
            ],
            kind: .parkPath,
            sourceWayID: 84
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [west, east])
        let start = Date(timeIntervalSince1970: 2_500)
        let points = [
            routePoint(40.7502, -73.9900, start),
            routePoint(40.7508, -73.9900, start.addingTimeInterval(20)),
        ]

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)

        XCTAssertTrue(result.intervals.isEmpty)
        XCTAssertEqual(result.acceptedPointCount, 0)
        XCTAssertTrue(result.unmatchedPortions.contains { $0.reason == .lowConfidence })
    }

    func testDoesNotCreateCoverageAcrossSubwaySizedGap() async throws {
        let segment = WalkableSegment(
            id: "long-street",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.70, longitude: -74.00),
                GeoCoordinate(latitude: 40.80, longitude: -73.95),
            ],
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [segment])
        let start = Date(timeIntervalSince1970: 1_000)
        let points = [
            routePoint(40.7000, -74.0000, start),
            routePoint(40.7001, -73.99995, start.addingTimeInterval(10)),
            routePoint(40.7900, -73.9550, start.addingTimeInterval(600)),
            routePoint(40.7901, -73.95495, start.addingTimeInterval(610)),
        ]

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)

        let covered = result.intervals.reduce(0) { $0 + $1.lengthMeters }
        XCTAssertLessThan(covered, 100)
    }

    func testPreservesCoverageOnBothSidesOfDisconnectedNetwork() async throws {
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
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [first, second])
        let start = Date(timeIntervalSince1970: 3_000)
        let points = [
            routePoint(40.7500, -73.9908, start),
            routePoint(40.7500, -73.9901, start.addingTimeInterval(20)),
            routePoint(40.7500, -73.9892, start.addingTimeInterval(45)),
            routePoint(40.7500, -73.9885, start.addingTimeInterval(65)),
        ]

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)
        let matchedIDs = Set(result.intervals.map(\.segmentID))

        XCTAssertTrue(matchedIDs.contains(first.id))
        XCTAssertTrue(matchedIDs.contains(second.id))
        XCTAssertTrue(result.unmatchedPortions.contains { $0.reason == .implausibleTransition })
    }

    func testDoesNotCreditGraphOnlyCrossingConnector() async throws {
        let connector = WalkableSegment(
            id: "crossing",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
                GeoCoordinate(latitude: 40.7502, longitude: -73.9900),
            ],
            kind: .connector,
            countsTowardCoverage: false
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [connector])
        let start = Date(timeIntervalSince1970: 4_000)

        let result = try await ContinuityMapMatcher().match(
            points: [
                routePoint(40.7500, -73.9900, start),
                routePoint(40.7502, -73.9900, start.addingTimeInterval(20)),
            ],
            in: pack
        )

        XCTAssertTrue(result.intervals.isEmpty)
        XCTAssertTrue(result.unmatchedPortions.allSatisfy { $0.reason == .noNearbyWalkableWay })
    }

    func testRejectsAOnlyCandidateWhenItIsTooFarFromTheTrace() async throws {
        let street = WalkableSegment(
            id: "distant-street",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
                GeoCoordinate(latitude: 40.7520, longitude: -73.9900),
            ],
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [street])
        let start = Date(timeIntervalSince1970: 5_000)
        let points = [
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.7502, longitude: -73.98965),
                timestamp: start,
                horizontalAccuracy: 20
            ),
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.7505, longitude: -73.98965),
                timestamp: start.addingTimeInterval(20),
                horizontalAccuracy: 20
            ),
        ]

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)

        XCTAssertTrue(result.intervals.isEmpty)
        XCTAssertEqual(result.acceptedPointCount, 0)
        XCTAssertTrue(result.unmatchedPortions.contains { $0.reason == .lowConfidence })
    }

    func testMatchesAndNormalizesARealisticMultiThousandPointRoute() async throws {
        let street = WalkableSegment(
            id: "long-realistic-route",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.7400, longitude: -73.9900),
                GeoCoordinate(latitude: 40.7600, longitude: -73.9900),
            ],
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [street])
        let start = Date(timeIntervalSince1970: 6_000)
        let pointCount = 2_500
        let points = (0 ..< pointCount).map { index in
            let fraction = Double(index) / Double(pointCount - 1)
            return RoutePoint(
                coordinate: GeoCoordinate(
                    latitude: 40.7400 + fraction * 0.0200,
                    longitude: -73.9900 + sin(Double(index) * 0.13) * 0.000005
                ),
                timestamp: start.addingTimeInterval(Double(index)),
                horizontalAccuracy: 5
            )
        }

        let result = try await ContinuityMapMatcher().match(points: points, in: pack)
        let contribution = WorkoutCoverageContribution(
            workoutID: UUID(),
            intervals: result.intervals,
            confidence: result.averageConfidence
        )

        XCTAssertEqual(result.acceptedPointCount, pointCount)
        XCTAssertEqual(contribution.intervals.count, 1)
        XCTAssertGreaterThan(contribution.uniqueCoveredDistanceMeters, street.lengthMeters * 0.98)
        XCTAssertLessThanOrEqual(contribution.uniqueCoveredDistanceMeters, street.lengthMeters)
    }

    private func routePoint(_ latitude: Double, _ longitude: Double, _ timestamp: Date) -> RoutePoint {
        RoutePoint(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: timestamp,
            horizontalAccuracy: 5
        )
    }
}
