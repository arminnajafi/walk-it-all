import Foundation
import XCTest
@testable import WalkItAllCore

final class RouteChunkerTests: XCTestCase {
    func testSplitsRatherThanBridgingLargeRouteGap() {
        let start = Date(timeIntervalSince1970: 1_000)
        let points = [
            point(40.75, -73.99, at: start),
            point(40.7501, -73.99, at: start.addingTimeInterval(10)),
            point(40.76, -73.98, at: start.addingTimeInterval(400)),
            point(40.7601, -73.98, at: start.addingTimeInterval(410)),
        ]

        let chunks = RouteChunker().chunks(from: points)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { $0.count == 2 })
    }

    func testRejectsPointsLessAccurateThanFiftyMeters() {
        let start = Date(timeIntervalSince1970: 1_000)
        let points = [
            point(40.75, -73.99, at: start),
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.7501, longitude: -73.99),
                timestamp: start.addingTimeInterval(10),
                horizontalAccuracy: 70
            ),
            point(40.7502, -73.99, at: start.addingTimeInterval(20)),
        ]

        XCTAssertTrue(RouteChunker().chunks(from: points).isEmpty)
    }

    private func point(_ latitude: Double, _ longitude: Double, at date: Date) -> RoutePoint {
        RoutePoint(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: date,
            horizontalAccuracy: 5
        )
    }
}

