import XCTest
import WalkItAllCore
@testable import WalkItAll

final class WalkItAllTests: XCTestCase {
    func testPreviewMapHasAStableCoverageDenominator() {
        let pack = PreviewCityPack.manhattanSample
        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: [])

        XCTAssertGreaterThan(snapshot.totalDistanceMeters, 0)
        XCTAssertEqual(snapshot.coveredDistanceMeters, 0)
        XCTAssertEqual(snapshot.packVersion, pack.metadata.version)
    }

    func testBundledManhattanDatabaseLoads() async throws {
        let pack = try await SQLiteCityPackLoader().loadBundledManhattan()

        XCTAssertEqual(pack.metadata.identifier, "manhattan-island")
        XCTAssertGreaterThan(pack.segments.count, 10_000)
        XCTAssertGreaterThan(pack.totalLengthMeters, 500_000)
    }
}

