import Foundation
import XCTest
@testable import WalkItAllCore

final class LiveTrailProcessorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testFiltersBreaksAndNeverBridgesInvalidLocations() {
        let processor = LiveTrailProcessor()
        var session = activeSession()
        var needsNewPart = false

        for point in [
            point(40.7500, -73.9900, seconds: 0),
            point(40.7501, -73.9900, seconds: 10),
        ] {
            let result = processor.appending(point, to: session, forceNewPart: needsNewPart)
            session = result.session
            needsNewPart = result.requiresNewPart
        }

        let rejected = processor.appending(
            point(40.7502, -73.9900, seconds: 20, accuracy: 75),
            to: session
        )
        XCTAssertFalse(rejected.accepted)
        XCTAssertTrue(rejected.requiresNewPart)

        let resumed = processor.appending(
            point(40.7503, -73.9900, seconds: 30),
            to: rejected.session,
            forceNewPart: rejected.requiresNewPart
        )
        XCTAssertEqual(resumed.session.routeParts.count, 2)
        XCTAssertEqual(resumed.session.routeParts[0].count, 2)
        XCTAssertEqual(resumed.session.routeParts[1].count, 1)
    }

    func testTimeDistanceAndSpeedGapsStartNewParts() {
        let processor = LiveTrailProcessor()
        var session = activeSession()
        for point in [
            point(40.7500, -73.9900, seconds: 0),
            point(40.7501, -73.9900, seconds: 10),
            point(40.7502, -73.9900, seconds: 80),
            point(40.7503, -73.9900, seconds: 90),
            point(40.7600, -73.9800, seconds: 100),
        ] {
            session = processor.appending(point, to: session).session
        }
        XCTAssertEqual(session.routeParts.count, 3)
    }

    func testCompactionPreservesPointTimesAndEndpoints() {
        let processor = LiveTrailProcessor(simplifier: RouteSimplifier(toleranceMeters: 3))
        let points = (0 ... 100).map {
            point(40.75 + Double($0) * 0.00001, -73.99, seconds: Double($0) * 2)
        }
        let session = LiveTrailSession(
            state: .active,
            start: start,
            routeParts: [points],
            lastUpdate: points.last!.timestamp
        )

        let compacted = processor.compacting(session)

        XCTAssertLessThan(compacted.routeParts[0].count, points.count)
        XCTAssertEqual(compacted.routeParts[0].first, points.first)
        XCTAssertEqual(compacted.routeParts[0].last, points.last)
    }

    func testFinishMakesSessionPendingWithoutLosingGeometry() {
        let processor = LiveTrailProcessor()
        let session = LiveTrailSession(
            state: .active,
            start: start,
            routeParts: [[
                point(40.75, -73.99, seconds: 0),
                point(40.7501, -73.99, seconds: 10),
            ]],
            lastUpdate: start.addingTimeInterval(10)
        )
        let finished = processor.finishing(session, at: start.addingTimeInterval(20))
        XCTAssertEqual(finished.state, .waitingForHealth)
        XCTAssertEqual(finished.end, start.addingTimeInterval(20))
        XCTAssertEqual(finished.coordinateParts.count, 1)
    }

    func testHealthAssociationUsesCoverageThenOverlapThenSmallestExcess() {
        let trail = LiveTrailSession(
            state: .waitingForHealth,
            start: start,
            end: start.addingTimeInterval(1_000),
            routeParts: [[point(40.75, -73.99, seconds: 0)]],
            lastUpdate: start.addingTimeInterval(1_000)
        )
        let poorCoverage = record(start: start.addingTimeInterval(250), end: start.addingTimeInterval(1_000))
        let excess = record(start: start.addingTimeInterval(-100), end: start.addingTimeInterval(1_100))
        let best = record(start: start, end: start.addingTimeInterval(1_000))

        XCTAssertEqual(
            LiveTrailHealthAssociator.matchingWorkoutID(
                for: trail,
                among: [poorCoverage, excess, best]
            ),
            best.id
        )
    }

    private func activeSession() -> LiveTrailSession {
        LiveTrailSession(state: .active, start: start, lastUpdate: start)
    }

    private func point(
        _ latitude: Double,
        _ longitude: Double,
        seconds: TimeInterval,
        accuracy: Double = 5
    ) -> RoutePoint {
        RoutePoint(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: start.addingTimeInterval(seconds),
            horizontalAccuracy: accuracy
        )
    }

    private func record(start: Date, end: Date) -> WorkoutRouteRecord {
        WorkoutRouteRecord(
            id: UUID(),
            start: start,
            end: end,
            sourceName: "Apple Watch",
            routeParts: [[
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ]]
        )
    }
}
