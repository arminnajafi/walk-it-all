import Foundation

public struct RouteProcessor: Sendable {
    public let chunker: RouteChunker
    public let simplifier: RouteSimplifier

    public init(
        chunker: RouteChunker = RouteChunker(),
        simplifier: RouteSimplifier = RouteSimplifier(toleranceMeters: 3)
    ) {
        self.chunker = chunker
        self.simplifier = simplifier
    }

    public func process(_ route: WorkoutRoute) -> WorkoutRouteRecord? {
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
            routeParts: parts
        )
    }
}
