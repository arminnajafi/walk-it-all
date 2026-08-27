import Foundation

public struct CoverageCalculator: Sendable {
    public let completedSegmentThreshold: Double

    public init(completedSegmentThreshold: Double = 0.70) {
        self.completedSegmentThreshold = completedSegmentThreshold
    }

    public func snapshot(
        pack: any CityCoveragePack,
        contributions: [WorkoutCoverageContribution]
    ) -> CoverageSnapshot {
        let allIntervals = contributions.flatMap(\.intervals)
        let grouped = Dictionary(grouping: allIntervals, by: \.segmentID)
        var coveredBySegment: [SegmentID: Double] = [:]
        var coveredIntervalsBySegment: [SegmentID: [SegmentInterval]] = [:]
        var completed = Set<SegmentID>()

        for (segmentID, intervals) in grouped {
            guard let segment = pack.segment(id: segmentID), segment.countsTowardCoverage else { continue }
            let normalized = intervals.map {
                (
                    min(segment.lengthMeters, max(0, $0.lowerBoundMeters)),
                    min(segment.lengthMeters, max(0, $0.upperBoundMeters))
                )
            }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }

            var merged: [(Double, Double)] = []
            for interval in normalized {
                if let last = merged.last, interval.0 <= last.1 {
                    merged[merged.count - 1] = (last.0, max(last.1, interval.1))
                } else {
                    merged.append(interval)
                }
            }

            let covered = min(segment.lengthMeters, merged.reduce(0) { $0 + ($1.1 - $1.0) })
            coveredBySegment[segmentID] = covered
            coveredIntervalsBySegment[segmentID] = merged.map {
                SegmentInterval(
                    segmentID: segmentID,
                    lowerBoundMeters: $0.0,
                    upperBoundMeters: $0.1,
                    confidence: 1
                )
            }
            if segment.lengthMeters > 0,
               covered / segment.lengthMeters >= completedSegmentThreshold
            {
                completed.insert(segmentID)
            }
        }

        let coveredDistance = coveredBySegment.values.reduce(0, +)
        let averageConfidence: Double
        let confidenceWeights = contributions.map { contribution in
            contribution.intervals.reduce(0) { $0 + $1.lengthMeters }
        }
        let confidenceWeight = confidenceWeights.reduce(0, +)
        if confidenceWeight > 0 {
            averageConfidence = zip(contributions, confidenceWeights).reduce(0) { partial, pair in
                partial + pair.0.confidence * pair.1
            } / confidenceWeight
        } else if contributions.isEmpty {
            averageConfidence = 0
        } else {
            averageConfidence = contributions.reduce(0) { $0 + $1.confidence }
                / Double(contributions.count)
        }

        return CoverageSnapshot(
            packIdentifier: pack.metadata.identifier,
            packVersion: pack.metadata.version,
            totalDistanceMeters: pack.totalLengthMeters,
            coveredDistanceMeters: coveredDistance,
            completedSegmentIDs: completed,
            coveredMetersBySegment: coveredBySegment,
            coveredIntervalsBySegment: coveredIntervalsBySegment,
            averageConfidence: averageConfidence
        )
    }
}
