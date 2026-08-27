import Foundation

public struct RouteSimplifier: Sendable {
    public let toleranceMeters: Double

    public init(toleranceMeters: Double = 3) {
        self.toleranceMeters = toleranceMeters
    }

    public func simplify(_ coordinates: [GeoCoordinate]) -> [GeoCoordinate] {
        guard coordinates.count > 2 else { return coordinates }
        var keep = Set([0, coordinates.count - 1])
        var pending = [(0, coordinates.count - 1)]

        while let (start, end) = pending.popLast() {
            guard end - start > 1 else { continue }
            let baseline = [coordinates[start], coordinates[end]]
            var largestDistance = 0.0
            var largestIndex: Int?

            for index in (start + 1) ..< end {
                guard let projection = GeoMath.project(coordinates[index], onto: baseline) else { continue }
                if projection.distanceMeters > largestDistance {
                    largestDistance = projection.distanceMeters
                    largestIndex = index
                }
            }

            guard largestDistance > toleranceMeters, let largestIndex else { continue }
            keep.insert(largestIndex)
            pending.append((start, largestIndex))
            pending.append((largestIndex, end))
        }
        return keep.sorted().map { coordinates[$0] }
    }
}
