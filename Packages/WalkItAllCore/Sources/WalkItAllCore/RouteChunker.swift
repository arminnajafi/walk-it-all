import Foundation

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
        let ordered = points.sorted { $0.timestamp < $1.timestamp }
        var result: [[RoutePoint]] = []
        var current: [RoutePoint] = []

        for point in ordered {
            guard point.coordinate.isValid,
                  point.horizontalAccuracy >= 0,
                  point.horizontalAccuracy <= maximumHorizontalAccuracyMeters
            else {
                finish(&current, into: &result)
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
                    finish(&current, into: &result)
                }
            }
            current.append(point)
        }

        finish(&current, into: &result)
        return result
    }

    private func finish(_ current: inout [RoutePoint], into result: inout [[RoutePoint]]) {
        if current.count >= 2 {
            result.append(current)
        }
        current.removeAll(keepingCapacity: true)
    }
}

