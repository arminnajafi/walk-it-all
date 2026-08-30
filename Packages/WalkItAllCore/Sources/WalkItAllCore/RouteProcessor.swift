import Foundation

public struct RouteProcessor: Sendable {
    public let walkingOrHikingChunker: RouteChunker
    public let runningChunker: RouteChunker
    public let cyclingChunker: RouteChunker
    public let simplifier: RouteSimplifier

    public init(
        chunker: RouteChunker = RouteChunker(),
        simplifier: RouteSimplifier = RouteSimplifier(toleranceMeters: 3)
    ) {
        walkingOrHikingChunker = chunker
        runningChunker = RouteChunker(
            maximumHorizontalAccuracyMeters: 50,
            maximumTimeGap: 60,
            maximumDistanceGapMeters: 300,
            maximumImpliedSpeedMetersPerSecond: 12
        )
        cyclingChunker = RouteChunker(
            maximumHorizontalAccuracyMeters: 50,
            maximumTimeGap: 60,
            maximumDistanceGapMeters: 500,
            maximumImpliedSpeedMetersPerSecond: 25
        )
        self.simplifier = simplifier
    }

    public init(
        walkingOrHikingChunker: RouteChunker,
        runningChunker: RouteChunker,
        cyclingChunker: RouteChunker,
        simplifier: RouteSimplifier = RouteSimplifier(toleranceMeters: 3)
    ) {
        self.walkingOrHikingChunker = walkingOrHikingChunker
        self.runningChunker = runningChunker
        self.cyclingChunker = cyclingChunker
        self.simplifier = simplifier
    }

    public func process(_ route: WorkoutRoute) -> WorkoutRouteRecord? {
        let chunker = switch route.activityKind {
        case .walking, .hiking: walkingOrHikingChunker
        case .running: runningChunker
        case .cycling: cyclingChunker
        }
        let parts = chunker.chunks(from: route.points).compactMap { chunk -> [GeoCoordinate]? in
            let simplified = simplifier.simplify(chunk.map(\.coordinate))
            return simplified.count >= 2 ? simplified : nil
        }
        guard !parts.isEmpty else { return nil }
        return WorkoutRouteRecord(
            id: route.id,
            start: route.start,
            end: route.end,
            sourceName: route.sourceName,
            activityKind: route.activityKind,
            routeParts: parts
        )
    }
}
