import Foundation
import XCTest
@testable import WalkItAllCore

final class CoverageCalculatorTests: XCTestCase {
    func testContributionNormalizesOverlappingAndAdjacentIntervals() throws {
        let workoutID = UUID()
        let contribution = WorkoutCoverageContribution(
            workoutID: workoutID,
            intervals: [
                SegmentInterval(segmentID: "b", lowerBoundMeters: 20, upperBoundMeters: 30, confidence: 0.7),
                SegmentInterval(segmentID: "a", lowerBoundMeters: 25, upperBoundMeters: 60, confidence: 0.8),
                SegmentInterval(segmentID: "a", lowerBoundMeters: -10, upperBoundMeters: 25, confidence: 1),
                SegmentInterval(segmentID: "a", lowerBoundMeters: 60.005, upperBoundMeters: 70, confidence: 0.9),
            ],
            confidence: 1.4
        )

        XCTAssertEqual(contribution.workoutID, workoutID)
        XCTAssertEqual(contribution.intervals.map(\.segmentID), ["a", "b"])
        XCTAssertEqual(contribution.intervals[0].lowerBoundMeters, 0, accuracy: 0.001)
        XCTAssertEqual(contribution.intervals[0].upperBoundMeters, 70, accuracy: 0.001)
        XCTAssertEqual(contribution.uniqueCoveredDistanceMeters, 80, accuracy: 0.001)
        XCTAssertEqual(contribution.confidence, 1)

        let decoded = try JSONDecoder().decode(
            WorkoutCoverageContribution.self,
            from: JSONEncoder().encode(contribution)
        )
        XCTAssertEqual(decoded.intervals, contribution.intervals)
    }

    func testUnmatchedPortionsCoalesceOnlyForTheSameReason() {
        let start = Date(timeIntervalSince1970: 100)
        let portions = [
            UnmatchedPortion(start: start, end: start.addingTimeInterval(2), reason: .routeGap),
            UnmatchedPortion(start: start.addingTimeInterval(2.5), end: start.addingTimeInterval(4), reason: .routeGap),
            UnmatchedPortion(start: start.addingTimeInterval(4), end: start.addingTimeInterval(5), reason: .lowConfidence),
        ]

        let result = UnmatchedPortion.coalesced(portions)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].start, start)
        XCTAssertEqual(result[0].end, start.addingTimeInterval(4))
        XCTAssertEqual(result[0].reason, .routeGap)
        XCTAssertEqual(result[1].reason, .lowConfidence)
    }

    func testAccuracyEvaluationUsesReviewedMetersAndCombinesRoutes() {
        let first = WalkableSegment(
            id: "first",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ],
            lengthMeters: 100,
            kind: .street
        )
        let second = WalkableSegment(
            id: "second",
            startNode: NodeID(2),
            endNode: NodeID(3),
            coordinates: [
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
                GeoCoordinate(latitude: 40.752, longitude: -73.99),
            ],
            lengthMeters: 100,
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [first, second])
        let contribution = WorkoutCoverageContribution(
            workoutID: UUID(),
            intervals: [
                SegmentInterval(segmentID: first.id, lowerBoundMeters: 0, upperBoundMeters: 100, confidence: 1),
                SegmentInterval(segmentID: second.id, lowerBoundMeters: 0, upperBoundMeters: 50, confidence: 1),
            ],
            confidence: 1
        )

        let measurement = MatchAccuracyEvaluator().evaluate(
            contribution: contribution,
            incorrectCreditedSegmentIDs: [second.id],
            clearlyWalkedMissedSegmentIDs: [],
            in: pack
        )
        let combined = MatchAccuracyMeasurement.combined([measurement, measurement])

        XCTAssertEqual(try XCTUnwrap(measurement.precision), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(measurement.recall), 1, accuracy: 0.001)
        XCTAssertEqual(combined.precision, measurement.precision)
        XCTAssertEqual(combined.recall, measurement.recall)
    }

    func testAccuracyEvaluationCountsOnlyReviewedMissedMetersAgainstRecall() throws {
        let credited = WalkableSegment(
            id: "credited",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ],
            lengthMeters: 100,
            kind: .street
        )
        let missed = WalkableSegment(
            id: "missed",
            startNode: NodeID(2),
            endNode: NodeID(3),
            coordinates: [
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
                GeoCoordinate(latitude: 40.752, longitude: -73.99),
            ],
            lengthMeters: 50,
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [credited, missed])
        let contribution = WorkoutCoverageContribution(
            workoutID: UUID(),
            intervals: [
                SegmentInterval(
                    segmentID: credited.id,
                    lowerBoundMeters: 20,
                    upperBoundMeters: 80,
                    confidence: 1
                ),
            ],
            confidence: 1
        )

        let withoutMiss = MatchAccuracyEvaluator().evaluate(
            contribution: contribution,
            incorrectCreditedSegmentIDs: [],
            clearlyWalkedMissedSegmentIDs: [],
            in: pack
        )
        let withMiss = MatchAccuracyEvaluator().evaluate(
            contribution: contribution,
            incorrectCreditedSegmentIDs: [],
            clearlyWalkedMissedSegmentIDs: [missed.id],
            in: pack
        )

        XCTAssertEqual(try XCTUnwrap(withoutMiss.recall), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(withMiss.recall), 60.0 / 110.0, accuracy: 0.001)
    }

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

    func testSegmentCompletionThresholdIsInclusiveAtSeventyPercent() {
        let segment = WalkableSegment(
            id: "street-threshold",
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
        let contribution = WorkoutCoverageContribution(
            workoutID: UUID(),
            intervals: [SegmentInterval(
                segmentID: segment.id,
                lowerBoundMeters: 10,
                upperBoundMeters: 80,
                confidence: 0.9
            )],
            confidence: 0.9
        )

        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: [contribution])

        XCTAssertEqual(snapshot.coveredDistanceMeters, 70, accuracy: 0.001)
        XCTAssertTrue(snapshot.completedSegmentIDs.contains(segment.id))
    }

    func testHandlesFifteenHundredOverlappingWorkoutContributions() {
        let segment = WalkableSegment(
            id: "load-street",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.76, longitude: -73.99),
            ],
            lengthMeters: 1_000,
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(metadata: .fixture, segments: [segment])
        let contributions = (0 ..< 1_500).map { index in
            WorkoutCoverageContribution(
                workoutID: UUID(),
                intervals: [SegmentInterval(
                    segmentID: segment.id,
                    lowerBoundMeters: Double(index % 900),
                    upperBoundMeters: Double(index % 900) + 100,
                    confidence: 0.8
                )],
                confidence: 0.8
            )
        }

        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: contributions)

        XCTAssertEqual(snapshot.coveredDistanceMeters, 999, accuracy: 0.001)
        XCTAssertEqual(snapshot.completedSegmentIDs, [segment.id])
    }

    func testAverageConfidenceIsWeightedByMatchedDistance() {
        let segment = WalkableSegment(
            id: "confidence-street",
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
                intervals: [SegmentInterval(
                    segmentID: segment.id,
                    lowerBoundMeters: 0,
                    upperBoundMeters: 90,
                    confidence: 1
                )],
                confidence: 1
            ),
            WorkoutCoverageContribution(
                workoutID: UUID(),
                intervals: [SegmentInterval(
                    segmentID: segment.id,
                    lowerBoundMeters: 90,
                    upperBoundMeters: 100,
                    confidence: 0
                )],
                confidence: 0
            ),
        ]

        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: contributions)

        XCTAssertEqual(snapshot.averageConfidence, 0.9, accuracy: 0.001)
    }
}
