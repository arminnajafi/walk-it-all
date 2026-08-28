import XCTest
@testable import WalkItAllCore

final class GeoMathTests: XCTestCase {
    func testBoundsSkipInvalidCoordinates() throws {
        let bounds = try XCTUnwrap(GeoBounds(coordinates: [
            GeoCoordinate(latitude: .nan, longitude: 0),
            GeoCoordinate(latitude: 40.7, longitude: -74),
            GeoCoordinate(latitude: 40.8, longitude: -73.9),
        ]))

        XCTAssertEqual(bounds.minimumLatitude, 40.7)
        XCTAssertEqual(bounds.maximumLongitude, -73.9)
    }

    func testProjectsPointOntoSegment() throws {
        let start = GeoCoordinate(latitude: 40.7500, longitude: -73.9900)
        let end = GeoCoordinate(latitude: 40.7510, longitude: -73.9900)
        let point = GeoCoordinate(latitude: 40.7505, longitude: -73.9899)

        let projection = try XCTUnwrap(GeoMath.project(point, onto: [start, end]))

        XCTAssertGreaterThan(projection.distanceMeters, 7)
        XCTAssertLessThan(projection.distanceMeters, 10)
    }
}
