import Foundation
import WalkItAllCore

struct AppDependencies {
    let routeSource: any WorkoutRouteSource
    let repository: any WalkHistoryRepository
    let routeProcessor: RouteProcessor
    let liveTrailRepository: any LiveTrailRepository
    let liveTrailProcessor: LiveTrailProcessor
    let legacyStore: LegacyCoverageStore
    let protectStorage: @Sendable () throws -> Void

    static func live() throws -> AppDependencies {
        return AppDependencies(
            routeSource: HealthKitWorkoutRouteSource(),
            repository: ProtectedWalkHistoryRepository(),
            routeProcessor: RouteProcessor(),
            liveTrailRepository: try ProtectedLiveTrailRepository.live(),
            liveTrailProcessor: LiveTrailProcessor(),
            legacyStore: try LegacyCoverageStore.live(),
            protectStorage: ProtectedModelContainer.protectHistoryStoreFiles
        )
    }
}
