import Foundation
import XCTest
@testable import WalkItAllCore

final class RouteProcessorTests: XCTestCase {
    func testCreatesOneRecordWithSeparatedPartsAndMetadata() throws {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let route = WorkoutRoute(
            id: id,
            start: start,
            end: start.addingTimeInterval(600),
            sourceName: "Apple Watch",
            points: [
                point(40.7500, -73.9900, at: start),
                point(40.7501, -73.9900, at: start.addingTimeInterval(10)),
                point(40.7600, -73.9800, at: start.addingTimeInterval(500)),
                point(40.7601, -73.9800, at: start.addingTimeInterval(510)),
            ]
        )

        let record = try XCTUnwrap(RouteProcessor().process(route))

        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.sourceName, "Apple Watch")
        XCTAssertEqual(record.duration, 600)
        XCTAssertEqual(record.routeParts.count, 2)
        XCTAssertTrue(record.routeParts.allSatisfy { $0.count == 2 })
    }

    func testReturnsNilWhenFewerThanTwoUsablePointsRemain() {
        let start = Date(timeIntervalSince1970: 2_000)
        let route = WorkoutRoute(
            id: UUID(),
            start: start,
            end: start,
            sourceName: "Test",
            points: [RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.75, longitude: -73.99),
                timestamp: start,
                horizontalAccuracy: 80
            )]
        )

        XCTAssertNil(RouteProcessor().process(route))
    }

    func testSimplificationPreservesEndpointsAndTightTurn() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let coordinates = [
            GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
            GeoCoordinate(latitude: 40.7501, longitude: -73.9900),
            GeoCoordinate(latitude: 40.7502, longitude: -73.9900),
            GeoCoordinate(latitude: 40.7502, longitude: -73.9898),
            GeoCoordinate(latitude: 40.7502, longitude: -73.9896),
        ]
        let route = WorkoutRoute(
            id: UUID(),
            start: start,
            end: start.addingTimeInterval(40),
            sourceName: "Test",
            points: coordinates.enumerated().map { index, coordinate in
                RoutePoint(
                    coordinate: coordinate,
                    timestamp: start.addingTimeInterval(Double(index) * 10),
                    horizontalAccuracy: 4
                )
            }
        )

        let part = try XCTUnwrap(RouteProcessor().process(route)?.routeParts.first)

        XCTAssertEqual(part.first, coordinates.first)
        XCTAssertEqual(part.last, coordinates.last)
        XCTAssertTrue(part.contains(coordinates[2]))
    }

    func testWorldwideBoundsAreComputedFromAllParts() throws {
        let record = WorkoutRouteRecord(
            id: UUID(),
            start: .distantPast,
            end: .distantFuture,
            sourceName: "Test",
            routeParts: [
                [
                    GeoCoordinate(latitude: 40.7, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -73.9),
                ],
                [
                    GeoCoordinate(latitude: 51.5, longitude: -0.2),
                    GeoCoordinate(latitude: 51.6, longitude: -0.1),
                ],
            ]
        )

        let bounds = try XCTUnwrap(record.geographicBounds)
        XCTAssertEqual(bounds.minimumLatitude, 40.7)
        XCTAssertEqual(bounds.maximumLatitude, 51.6)
        XCTAssertEqual(bounds.minimumLongitude, -74.0)
        XCTAssertEqual(bounds.maximumLongitude, -0.1)
    }

    func testProcessesFifteenHundredMultiThousandPointRoutes() {
        let processor = RouteProcessor()
        let base = Date(timeIntervalSince1970: 5_000)
        let points = (0 ..< 2_001).map { index in
            RoutePoint(
                coordinate: GeoCoordinate(
                    latitude: 40.70 + Double(index) * 0.000002,
                    longitude: -74.0 + sin(Double(index) / 100) * 0.00001
                ),
                timestamp: base.addingTimeInterval(Double(index) * 2),
                horizontalAccuracy: 5
            )
        }

        for index in 0 ..< 1_500 {
            let route = WorkoutRoute(
                id: UUID(),
                start: base,
                end: base.addingTimeInterval(4_000),
                sourceName: "Synthetic \(index)",
                points: points
            )
            XCTAssertNotNil(processor.process(route))
        }
    }

    private func point(_ latitude: Double, _ longitude: Double, at date: Date) -> RoutePoint {
        RoutePoint(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: date,
            horizontalAccuracy: 5
        )
    }
}
