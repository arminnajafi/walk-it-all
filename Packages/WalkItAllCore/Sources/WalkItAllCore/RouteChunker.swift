import Foundation

public struct RouteChunkingResult: Sendable {
    public let chunks: [[RoutePoint]]
    public let discardedPointCount: Int

    public init(chunks: [[RoutePoint]], discardedPointCount: Int) {
        self.chunks = chunks
        self.discardedPointCount = discardedPointCount
    }
}

/// Filters unreliable samples and separates continuous route portions. A
/// break always ends the current part; the processor never draws across it.
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
        let ordered = points.enumerated().sorted {
            if $0.element.timestamp == $1.element.timestamp { return $0.offset < $1.offset }
            return $0.element.timestamp < $1.element.timestamp
        }.map(\.element)

        var chunks: [[RoutePoint]] = []
        var current: [RoutePoint] = []
        var discardedPointCount = 0

        func finishCurrent() {
            if current.count >= 2 {
                chunks.append(current)
            } else {
                discardedPointCount += current.count
            }
            current.removeAll(keepingCapacity: true)
        }

        for point in ordered {
            guard accepts(point) else {
                finishCurrent()
                discardedPointCount += 1
                continue
            }

            if let previous = current.last {
                if isExactDuplicate(previous, point) {
                    discardedPointCount += 1
                    continue
                }

                if requiresSplit(previous, point) {
                    finishCurrent()
                }
            }
            current.append(point)
        }

        finishCurrent()
        return RouteChunkingResult(chunks: chunks, discardedPointCount: discardedPointCount)
    }

    public func accepts(_ point: RoutePoint) -> Bool {
        point.coordinate.isValid
            && point.horizontalAccuracy.isFinite
            && point.horizontalAccuracy >= 0
            && point.horizontalAccuracy <= maximumHorizontalAccuracyMeters
    }

    public func isExactDuplicate(_ previous: RoutePoint, _ point: RoutePoint) -> Bool {
        previous.timestamp == point.timestamp && previous.coordinate == point.coordinate
    }

    public func requiresSplit(_ previous: RoutePoint, _ point: RoutePoint) -> Bool {
        let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
        let distance = GeoMath.distance(previous.coordinate, point.coordinate)
        let speed = elapsed > 0 ? distance / elapsed : .greatestFiniteMagnitude
        return elapsed <= 0
            || elapsed > maximumTimeGap
            || distance > maximumDistanceGapMeters
            || speed > maximumImpliedSpeedMetersPerSecond
    }
}
