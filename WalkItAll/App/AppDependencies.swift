import Foundation
import SwiftData
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
        let container = try ProtectedModelContainer.make()
        return AppDependencies(
            routeSource: HealthKitWorkoutRouteSource(),
            repository: SwiftDataWalkHistoryRepository(modelContainer: container),
            routeProcessor: RouteProcessor(),
            liveTrailRepository: try ProtectedLiveTrailRepository.live(),
            liveTrailProcessor: LiveTrailProcessor(),
            legacyStore: try LegacyCoverageStore.live(),
            protectStorage: ProtectedModelContainer.protectHistoryStoreFiles
        )
    }
}
