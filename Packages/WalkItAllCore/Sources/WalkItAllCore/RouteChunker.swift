import Foundation

public struct RouteChunkingResult: Sendable {
    public let chunks: [[RoutePoint]]
    public let unmatchedPortions: [UnmatchedPortion]
    public let rejectedPointCount: Int

    public init(
        chunks: [[RoutePoint]],
        unmatchedPortions: [UnmatchedPortion],
        rejectedPointCount: Int
    ) {
        self.chunks = chunks
        self.unmatchedPortions = unmatchedPortions
        self.rejectedPointCount = rejectedPointCount
    }
}

public struct RouteChunker: Sendable {
    public let maximumHorizontalAccuracyMeters: Double
    public let maximumTimeGap: TimeInterval
    public let maximumDistanceGapMeters: Double
    public let maximumImpliedSpeedMetersPerSecond: Double

    public init(
        maximumHorizontalAccuracyMeters: Double = 50,
        maximumTimeGap: TimeInterval = 60,
        maximumDistanceGapMeters: Double = 200,
        maximumImpliedSpeedMetersPerSecond: Double = 6
    ) {
        self.maximumHorizontalAccuracyMeters = maximumHorizontalAccuracyMeters
        self.maximumTimeGap = maximumTimeGap
        self.maximumDistanceGapMeters = maximumDistanceGapMeters
        self.maximumImpliedSpeedMetersPerSecond = maximumImpliedSpeedMetersPerSecond
    }

    public func chunks(from points: [RoutePoint]) -> [[RoutePoint]] {
        process(points).chunks
    }

    public func process(_ points: [RoutePoint]) -> RouteChunkingResult {
        let ordered = points.sorted { $0.timestamp < $1.timestamp }
        var result: [[RoutePoint]] = []
        var current: [RoutePoint] = []
        var unmatched: [UnmatchedPortion] = []
        var rejectedPointCount = 0

        for point in ordered {
            guard point.coordinate.isValid,
                  point.horizontalAccuracy >= 0,
                  point.horizontalAccuracy <= maximumHorizontalAccuracyMeters
            else {
                finish(
                    &current,
                    into: &result,
                    unmatched: &unmatched,
                    rejectedPointCount: &rejectedPointCount
                )
                unmatched.append(UnmatchedPortion(
                    start: point.timestamp,
                    end: point.timestamp,
                    reason: .inaccurateLocation
                ))
                rejectedPointCount += 1
                continue
            }

            if let previous = current.last {
                let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
                let distance = GeoMath.distance(previous.coordinate, point.coordinate)
                let impliedSpeed = elapsed > 0 ? distance / elapsed : .greatestFiniteMagnitude
                if elapsed <= 0
                    || elapsed > maximumTimeGap
                    || distance > maximumDistanceGapMeters
                    || impliedSpeed > maximumImpliedSpeedMetersPerSecond
                {
                    unmatched.append(UnmatchedPortion(
                        start: previous.timestamp,
                        end: point.timestamp,
                        reason: .routeGap
                    ))
                    finish(
                        &current,
                        into: &result,
                        unmatched: &unmatched,
                        rejectedPointCount: &rejectedPointCount
                    )
                }
            }
            current.append(point)
        }

        finish(
            &current,
            into: &result,
            unmatched: &unmatched,
            rejectedPointCount: &rejectedPointCount
        )
        return RouteChunkingResult(
            chunks: result,
            unmatchedPortions: unmatched,
            rejectedPointCount: rejectedPointCount
        )
    }

    private func finish(
        _ current: inout [RoutePoint],
        into result: inout [[RoutePoint]],
        unmatched: inout [UnmatchedPortion],
        rejectedPointCount: inout Int
    ) {
        if current.count >= 2 {
            result.append(current)
        } else if let point = current.first {
            unmatched.append(UnmatchedPortion(
                start: point.timestamp,
                end: point.timestamp,
                reason: .lowConfidence
            ))
            rejectedPointCount += 1
        }
        current.removeAll(keepingCapacity: true)
    }
}
