import Foundation

public struct MatchAccuracyMeasurement: Codable, Hashable, Sendable {
    public let correctlyCreditedMeters: Double
    public let creditedMeters: Double
    public let clearlyWalkedMeters: Double

    public init(
        correctlyCreditedMeters: Double,
        creditedMeters: Double,
        clearlyWalkedMeters: Double
    ) {
        self.correctlyCreditedMeters = max(0, correctlyCreditedMeters)
        self.creditedMeters = max(0, creditedMeters)
        self.clearlyWalkedMeters = max(0, clearlyWalkedMeters)
    }

    public var precision: Double? {
        guard creditedMeters > 0 else { return nil }
        return min(1, correctlyCreditedMeters / creditedMeters)
    }

    public var recall: Double? {
        guard clearlyWalkedMeters > 0 else { return nil }
        return min(1, correctlyCreditedMeters / clearlyWalkedMeters)
    }

    public static func combined(_ measurements: [MatchAccuracyMeasurement]) -> Self {
        MatchAccuracyMeasurement(
            correctlyCreditedMeters: measurements.reduce(0) { $0 + $1.correctlyCreditedMeters },
            creditedMeters: measurements.reduce(0) { $0 + $1.creditedMeters },
            clearlyWalkedMeters: measurements.reduce(0) { $0 + $1.clearlyWalkedMeters }
        )
    }
}

public struct MatchAccuracyEvaluator: Sendable {
    public init() {}

    public func evaluate(
        contribution: WorkoutCoverageContribution,
        clearlyWalkedSegmentIDs: Set<SegmentID>,
        ambiguousSegmentIDs: Set<SegmentID> = [],
        in pack: any CityCoveragePack
    ) -> MatchAccuracyMeasurement {
        let eligibleExpectedIDs = clearlyWalkedSegmentIDs.subtracting(ambiguousSegmentIDs)
        let eligibleIntervals = contribution.intervals.filter {
            !ambiguousSegmentIDs.contains($0.segmentID)
        }
        let creditedMeters = eligibleIntervals.reduce(0) { $0 + $1.lengthMeters }
        let correctlyCreditedMeters = eligibleIntervals.reduce(0) { partial, interval in
            partial + (eligibleExpectedIDs.contains(interval.segmentID) ? interval.lengthMeters : 0)
        }
        let clearlyWalkedMeters = eligibleExpectedIDs.reduce(0) { partial, segmentID in
            guard let segment = pack.segment(id: segmentID), segment.countsTowardCoverage else {
                return partial
            }
            return partial + segment.lengthMeters
        }
        return MatchAccuracyMeasurement(
            correctlyCreditedMeters: correctlyCreditedMeters,
            creditedMeters: creditedMeters,
            clearlyWalkedMeters: clearlyWalkedMeters
        )
    }
}
