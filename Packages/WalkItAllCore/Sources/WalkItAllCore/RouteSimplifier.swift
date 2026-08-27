import Foundation

public struct RouteSimplifier: Sendable {
    public let toleranceMeters: Double

    public init(toleranceMeters: Double = 3) {
        self.toleranceMeters = toleranceMeters
    }

    public func simplify(_ coordinates: [GeoCoordinate]) -> [GeoCoordinate] {
        guard coordinates.count > 2 else { return coordinates }
        var keep = Set([0, coordinates.count - 1])
        simplifyRange(0, coordinates.count - 1, coordinates, &keep)
        return keep.sorted().map { coordinates[$0] }
    }

    private func simplifyRange(
        _ start: Int,
        _ end: Int,
        _ coordinates: [GeoCoordinate],
        _ keep: inout Set<Int>
    ) {
        guard end - start > 1 else { return }
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

        guard largestDistance > toleranceMeters, let largestIndex else { return }
        keep.insert(largestIndex)
        simplifyRange(start, largestIndex, coordinates, &keep)
        simplifyRange(largestIndex, end, coordinates, &keep)
    }
}

