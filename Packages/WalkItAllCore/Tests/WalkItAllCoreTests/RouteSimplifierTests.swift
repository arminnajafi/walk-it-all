import XCTest
@testable import WalkItAllCore

final class RouteSimplifierTests: XCTestCase {
    func testLargeTracePreservesEndpointsWithoutRecursiveStackGrowth() {
        let coordinates = (0 ..< 20_000).map { index in
            GeoCoordinate(
                latitude: 40.70 + Double(index) * 0.000001,
                longitude: -74.00 + (index.isMultiple(of: 2) ? 0.00001 : -0.00001)
            )
        }

        let simplified = RouteSimplifier(toleranceMeters: 2).simplify(coordinates)

        XCTAssertEqual(simplified.first, coordinates.first)
        XCTAssertEqual(simplified.last, coordinates.last)
        XCTAssertLessThanOrEqual(simplified.count, coordinates.count)
    }
}
