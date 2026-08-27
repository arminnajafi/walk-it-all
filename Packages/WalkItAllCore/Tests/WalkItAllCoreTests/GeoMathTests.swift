import XCTest
@testable import WalkItAllCore

final class GeoMathTests: XCTestCase {
    func testProjectsPointOntoSegmentAndReportsOffset() throws {
        let start = GeoCoordinate(latitude: 40.7500, longitude: -73.9900)
        let end = GeoCoordinate(latitude: 40.7510, longitude: -73.9900)
        let point = GeoCoordinate(latitude: 40.7505, longitude: -73.9899)

        let projection = try XCTUnwrap(GeoMath.project(point, onto: [start, end]))

        XCTAssertGreaterThan(projection.distanceMeters, 7)
        XCTAssertLessThan(projection.distanceMeters, 10)
        XCTAssertGreaterThan(projection.offsetMeters, 50)
        XCTAssertLessThan(projection.offsetMeters, 62)
    }

    func testTreatsOppositeHeadingsAsTheSameCorridor() {
        XCTAssertEqual(GeoMath.undirectedHeadingDifference(5, 185), 0, accuracy: 0.001)
        XCTAssertEqual(GeoMath.undirectedHeadingDifference(10, 100), 90, accuracy: 0.001)
    }
}

