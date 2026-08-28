import Foundation
import XCTest
@testable import WalkItAllCore

final class RouteChunkerTests: XCTestCase {
    func testSortsTimestampsAndDiscardsExactDuplicates() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = point(40.7500, -73.9900, at: start)
        let second = point(40.7501, -73.9900, at: start.addingTimeInterval(10))
        let result = RouteChunker().process([second, first, first])

        XCTAssertEqual(result.chunks, [[first, second]])
        XCTAssertEqual(result.discardedPointCount, 1)
    }

    func testInvalidAndInaccurateLocationsSeparateParts() {
        let start = Date(timeIntervalSince1970: 1_000)
        let result = RouteChunker().process([
            point(40.7500, -73.9900, at: start),
            point(40.7501, -73.9900, at: start.addingTimeInterval(10)),
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 95, longitude: -73.99),
                timestamp: start.addingTimeInterval(20),
                horizontalAccuracy: 5
            ),
            RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.7600, longitude: -73.98),
                timestamp: start.addingTimeInterval(30),
                horizontalAccuracy: 51
            ),
            point(40.7601, -73.9800, at: start.addingTimeInterval(40)),
            point(40.7602, -73.9800, at: start.addingTimeInterval(50)),
        ])

        XCTAssertEqual(result.chunks.count, 2)
        XCTAssertEqual(result.discardedPointCount, 2)
    }

    func testSplitsAtTimeDistanceAndSpeedGapsWithoutBridging() {
        let start = Date(timeIntervalSince1970: 2_000)
        let result = RouteChunker().process([
            point(40.7500, -73.9900, at: start),
            point(40.7501, -73.9900, at: start.addingTimeInterval(10)),
            point(40.7502, -73.9900, at: start.addingTimeInterval(80)),
            point(40.7503, -73.9900, at: start.addingTimeInterval(90)),
            point(40.7600, -73.9800, at: start.addingTimeInterval(100)),
            point(40.7601, -73.9800, at: start.addingTimeInterval(110)),
            point(40.7610, -73.9800, at: start.addingTimeInterval(111)),
            point(40.7611, -73.9800, at: start.addingTimeInterval(121)),
        ])

        XCTAssertEqual(result.chunks.count, 4)
        XCTAssertTrue(result.chunks.allSatisfy { $0.count == 2 })
        XCTAssertNotEqual(result.chunks[0].last?.coordinate, result.chunks[1].first?.coordinate)
    }

    func testNonpositiveTimeSeparatesInsteadOfConnecting() {
        let start = Date(timeIntervalSince1970: 3_000)
        let result = RouteChunker().process([
            point(40.7500, -73.9900, at: start),
            point(40.7501, -73.9900, at: start),
            point(40.7502, -73.9900, at: start.addingTimeInterval(10)),
        ])

        XCTAssertEqual(result.chunks.count, 1)
        XCTAssertEqual(result.chunks[0].first?.coordinate.latitude, 40.7501)
        XCTAssertEqual(result.discardedPointCount, 1)
    }

    func testEmptyAndSinglePointRoutesProduceNoParts() {
        XCTAssertTrue(RouteChunker().chunks(from: []).isEmpty)
        XCTAssertTrue(RouteChunker().chunks(from: [
            point(40.75, -73.99, at: Date())
        ]).isEmpty)
    }

    private func point(_ latitude: Double, _ longitude: Double, at date: Date) -> RoutePoint {
        RoutePoint(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: date,
            horizontalAccuracy: 5
        )
    }
}
