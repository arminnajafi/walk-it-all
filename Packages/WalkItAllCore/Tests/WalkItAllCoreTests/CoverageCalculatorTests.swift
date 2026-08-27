import Foundation
import XCTest
@testable import WalkItAllCore

final class CoverageCalculatorTests: XCTestCase {
    func testUnionsRepeatedIntervalsInsteadOfDoubleCountingDistance() {
        let segment = WalkableSegment(
            id: "street-a",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ],
            lengthMeters: 100,
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [segment])
        let contributions = [
            WorkoutCoverageContribution(
                workoutID: UUID(),
                intervals: [SegmentInterval(segmentID: segment.id, lowerBoundMeters: 0, upperBoundMeters: 55, confidence: 0.9)],
                confidence: 0.9
            ),
            WorkoutCoverageContribution(
                workoutID: UUID(),
                intervals: [SegmentInterval(segmentID: segment.id, lowerBoundMeters: 40, upperBoundMeters: 80, confidence: 0.8)],
                confidence: 0.8
            ),
        ]

        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: contributions)

        XCTAssertEqual(snapshot.coveredDistanceMeters, 80, accuracy: 0.001)
        XCTAssertTrue(snapshot.completedSegmentIDs.contains(segment.id))
        XCTAssertEqual(snapshot.completionFraction, 0.8, accuracy: 0.001)
    }
}

