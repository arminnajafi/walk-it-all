import Foundation
import WalkItAllCore

struct AppDependencies {
    let routeSource: any WorkoutRouteSource
    let repository: any WalkHistoryRepository
    let routeProcessor: RouteProcessor
    let liveTrailRepository: any LiveTrailRepository
    let liveTrailProcessor: LiveTrailProcessor
    let protectStorage: @Sendable () throws -> Void

    static func live() throws -> AppDependencies {
        return AppDependencies(
            routeSource: HealthKitWorkoutRouteSource(),
            repository: ProtectedWalkHistoryRepository(),
            routeProcessor: RouteProcessor(),
            liveTrailRepository: try ProtectedLiveTrailRepository.live(),
            liveTrailProcessor: LiveTrailProcessor(),
            protectStorage: ProtectedModelContainer.protectHistoryStoreFiles
        )
    }
}
