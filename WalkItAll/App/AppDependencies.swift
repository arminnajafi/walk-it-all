import Foundation
import SwiftData
import WalkItAllCore

struct AppDependencies {
    let routeSource: any WorkoutRouteSource
    let repository: any CoverageRepository
    let cityPackLoader: SQLiteCityPackLoader
    let matcher: any MapMatcher
    let coverageCalculator: CoverageCalculator
    let routeSimplifier: RouteSimplifier
    let routeChunker: RouteChunker

    static func live() throws -> AppDependencies {
        let container = try ProtectedModelContainer.make()
        return AppDependencies(
            routeSource: HealthKitWorkoutRouteSource(),
            repository: SwiftDataCoverageRepository(modelContainer: container),
            cityPackLoader: SQLiteCityPackLoader(),
            matcher: ContinuityMapMatcher(),
            coverageCalculator: CoverageCalculator(),
            routeSimplifier: RouteSimplifier(),
            routeChunker: RouteChunker()
        )
    }
}
