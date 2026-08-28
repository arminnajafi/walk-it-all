import Foundation
import Observation
import OSLog
import WalkItAllCore

enum AppSheet: Identifiable, Hashable {
    case details
    case healthAccess
    case liveTrailIntro

    var id: String {
        switch self {
        case .details: "details"
        case .healthAccess: "health-access"
        case .liveTrailIntro: "live-trail-intro"
        }
    }
}

enum AppLaunchState: Equatable {
    case loading
    case ready
    case failed(String)
}

enum MapViewportTarget: Equatable, Sendable {
    case manhattan
    case workout(UUID)
    case userLocation
}

struct MapViewportCommand: Equatable, Sendable {
    let revision: Int
    let target: MapViewportTarget
}

enum ImportPhase: Equatable {
    case idle
    case requestingHealthAccess
    case findingWorkouts
    case readingRoutes(completed: Int, total: Int)
    case processingRoutes(completed: Int, total: Int)
    case preparingMap
    case complete(imported: Int)
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .requestingHealthAccess, .findingWorkouts, .readingRoutes, .processingRoutes, .preparingMap:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .idle: "Ready"
        case .requestingHealthAccess: "Connecting to Apple Health…"
        case .findingWorkouts: "Finding workouts…"
        case let .readingRoutes(completed, total): "Reading routes \(completed) of \(total)…"
        case let .processingRoutes(completed, total): "Preparing walks \(completed) of \(total)…"
        case .preparingMap: "Updating your map…"
        case let .complete(imported): "Updated \(imported) walk\(imported == 1 ? "" : "s")"
        case .failed: "Refresh needs attention"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private static let onboardingKey = "didCompleteOnboarding"
    private static let connectedHealthKey = "didConnectAppleHealth"
    private static let migrationStartedKey = "didBeginLifetimeMapMigration"
    private static let liveTrailExplainedKey = "didExplainLiveTrail"
    private static let automaticRefreshInterval: TimeInterval = 5 * 60
    private let logger = Logger(subsystem: "com.arminnajafi.walkitall", category: "AppModel")

    var launchState: AppLaunchState = .loading
    var importPhase: ImportPhase = .idle
    var routeRecords: [WorkoutRouteRecord] = []
    var selectedWorkoutID: UUID?
    var presentedSheet: AppSheet?
    var lastSuccessfulImport: Date?
    var routeRenderRevision = 0
    var mapViewportCommand = MapViewportCommand(revision: 0, target: .manhattan)
    @ObservationIgnored let liveTrail: LiveTrailController
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    @ObservationIgnored private let routeSource: any WorkoutRouteSource
    @ObservationIgnored private let repository: any WalkHistoryRepository
    @ObservationIgnored private let routeProcessor: RouteProcessor
    @ObservationIgnored private let legacyStore: LegacyCoverageStore
    @ObservationIgnored private let protectStorage: @Sendable () throws -> Void
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = 0
    @ObservationIgnored private var shouldImportAfterOnboardingDismisses = false
    @ObservationIgnored private var shouldStartLiveTrailAfterSheetDismisses = false
    @ObservationIgnored private var lastAutomaticRefreshAttempt: Date?
    @ObservationIgnored private var bootstrapInProgress = false

    init(dependencies: AppDependencies) {
        routeSource = dependencies.routeSource
        repository = dependencies.repository
        routeProcessor = dependencies.routeProcessor
        liveTrail = LiveTrailController(
            repository: dependencies.liveTrailRepository,
            processor: dependencies.liveTrailProcessor
        )
        legacyStore = dependencies.legacyStore
        protectStorage = dependencies.protectStorage

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: Self.onboardingKey)
            UserDefaults.standard.removeObject(forKey: Self.connectedHealthKey)
            UserDefaults.standard.removeObject(forKey: Self.liveTrailExplainedKey)
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
            || arguments.contains("-skipOnboarding")
        liveTrail.onDidFinish = { [weak self] in
            guard let self,
                  self.launchState == .ready,
                  self.hasConnectedHealth
            else { return }
            self.refresh()
        }
    }

    var selectedWorkout: WorkoutRouteRecord? {
        routeRecords.first { $0.id == selectedWorkoutID }
    }

    var mappedWorkoutCount: Int { routeRecords.count }
    var hasMappedWorkouts: Bool { !routeRecords.isEmpty }

    var hasConnectedHealth: Bool {
        UserDefaults.standard.bool(forKey: Self.connectedHealthKey) || !routeRecords.isEmpty
    }

    func bootstrap() async {
        guard !bootstrapInProgress,
              launchState == .loading || isFailure(launchState)
        else { return }
        bootstrapInProgress = true
        defer { bootstrapInProgress = false }
        launchState = .loading
        // Recover an explicitly active temporary trail before touching the
        // stronger `.complete` lifetime-history store. iOS may relaunch the
        // app for location delivery while that permanent store is still locked.
        await liveTrail.bootstrap()
        do {
            routeRecords = try await repository.loadRecords()
            #if DEBUG
            if routeRecords.isEmpty,
               ProcessInfo.processInfo.arguments.contains("-uiTestPopulated")
            {
                routeRecords = Self.uiTestRecords
            }
            #endif
            lastSuccessfulImport = try await repository.loadLastSuccessfulImport()
            await liveTrail.reconcile(with: routeRecords)
            try protectStorage()
            routeRenderRevision &+= 1
            launchState = .ready

            // A completed new-store import can outlive a failed legacy-file
            // cleanup. Retry the exact cleanup on a later unlocked launch.
            if legacyStore.exists,
               lastSuccessfulImport != nil,
               !routeRecords.isEmpty
            {
                try? finishLegacyMigration()
            } else if !legacyStore.exists {
                UserDefaults.standard.removeObject(forKey: Self.migrationStartedKey)
            }
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .private)")
            launchState = .failed(error.localizedDescription)
        }
    }

    func completeOnboarding(requestHealthAccess: Bool) {
        shouldImportAfterOnboardingDismisses = requestHealthAccess
        hasCompletedOnboarding = true
    }

    func resumePendingOnboardingImport() {
        guard shouldImportAfterOnboardingDismisses else { return }
        shouldImportAfterOnboardingDismisses = false
        refresh()
    }

    func refresh() {
        guard !importPhase.isWorking else { return }
        beginAuthorizedImport(resetFirst: shouldStartLegacyRebuild, isAutomatic: false)
    }

    func rebuildFromHealth() {
        guard !importPhase.isWorking, !liveTrail.hasInProgressSession else { return }
        beginAuthorizedImport(resetFirst: true, isAutomatic: false)
    }

    func refreshIfNeeded(now: Date = Date()) {
        liveTrail.resumeIfNeeded(now: now)
        #if DEBUG
        // Synthetic records exercise populated UI without opening a real
        // Health authorization sheet in UI tests.
        guard !ProcessInfo.processInfo.arguments.contains("-uiTestPopulated") else { return }
        #endif
        guard launchState == .ready,
              hasConnectedHealth,
              !importPhase.isWorking,
              lastSuccessfulImport.map({ now.timeIntervalSince($0) >= Self.automaticRefreshInterval }) ?? true,
              lastAutomaticRefreshAttempt.map({ now.timeIntervalSince($0) >= Self.automaticRefreshInterval }) ?? true
        else { return }

        lastAutomaticRefreshAttempt = now
        beginAuthorizedImport(resetFirst: shouldStartLegacyRebuild, isAutomatic: true)
    }

    func cancelImport() {
        importGeneration &+= 1
        importTask?.cancel()
        importTask = nil
        importPhase = .idle
        publishStoredHistory()
    }

    func selectWorkout(_ id: UUID) {
        guard liveTrail.session == nil else { return }
        selectedWorkoutID = id
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .workout(id)
        )
        presentedSheet = nil
    }

    func clearSelectedWorkout() {
        selectedWorkoutID = nil
        showAllManhattan()
    }

    func showAllManhattan() {
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .manhattan
        )
    }

    func showUserLocation() {
        liveTrail.requestCurrentLocation()
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .userLocation
        )
    }

    func requestStartLiveTrail() {
        if UserDefaults.standard.bool(forKey: Self.liveTrailExplainedKey) {
            startLiveTrail()
        } else {
            presentedSheet = .liveTrailIntro
        }
    }

    func confirmStartLiveTrail() {
        UserDefaults.standard.set(true, forKey: Self.liveTrailExplainedKey)
        shouldStartLiveTrailAfterSheetDismisses = true
        presentedSheet = nil
    }

    func resumePendingLiveTrailStart() {
        guard shouldStartLiveTrailAfterSheetDismisses else { return }
        shouldStartLiveTrailAfterSheetDismisses = false
        startLiveTrail()
    }

    func finishLiveTrail() {
        Task { [weak self] in
            await self?.liveTrail.finish()
        }
    }

    func pauseLiveTrail() {
        Task { [weak self] in
            await self?.liveTrail.pause()
        }
    }

    func resumeLiveTrail() {
        liveTrail.resume()
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .userLocation
        )
    }

    private func startLiveTrail() {
        selectedWorkoutID = nil
        liveTrail.start()
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .userLocation
        )
    }

    private var shouldStartLegacyRebuild: Bool {
        legacyStore.exists
            && !UserDefaults.standard.bool(forKey: Self.migrationStartedKey)
    }

    private func beginAuthorizedImport(resetFirst: Bool, isAutomatic: Bool) {
        importGeneration &+= 1
        let generation = importGeneration
        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }
            importPhase = .requestingHealthAccess
            do {
                try await routeSource.requestReadAuthorization()
                try Task.checkCancellation()
                guard generation == importGeneration else { return }
                UserDefaults.standard.set(true, forKey: Self.connectedHealthKey)
                if resetFirst {
                    try await repository.reset()
                    if legacyStore.exists {
                        UserDefaults.standard.set(true, forKey: Self.migrationStartedKey)
                    }
                    routeRecords = []
                    lastSuccessfulImport = nil
                    clearSelectedWorkout()
                    routeRenderRevision &+= 1
                }
                await performImport(generation: generation)
            } catch is CancellationError {
                guard generation == importGeneration else { return }
                importPhase = .idle
            } catch {
                guard generation == importGeneration else { return }
                logger.error("Health import setup failed: \(error.localizedDescription, privacy: .private)")
                importPhase = .failed(error.localizedDescription)
                if isAutomatic { lastAutomaticRefreshAttempt = Date() }
            }
        }
    }

    private func performImport(generation: Int) async {
        guard generation == importGeneration else { return }
        importPhase = .findingWorkouts
        do {
            let checkpoint = try await repository.loadCheckpoint()
            let processedWorkoutIDs = try await repository.loadProcessedWorkoutIDs()
            let batches = await routeSource.routeBatches(
                since: checkpoint,
                excluding: processedWorkoutIDs
            )
            var imported = 0

            for try await batch in batches {
                try Task.checkCancellation()
                if !batch.deletedWorkoutIDs.isEmpty {
                    try await repository.removeWorkouts(workoutIDs: batch.deletedWorkoutIDs)
                }
                if !batch.routeInvalidatedWorkoutIDs.isEmpty {
                    try await repository.removeRouteRecords(
                        workoutIDs: batch.routeInvalidatedWorkoutIDs
                    )
                }

                importPhase = .readingRoutes(
                    completed: batch.completedCount,
                    total: batch.totalCount
                )
                for route in batch.routes {
                    try Task.checkCancellation()
                    importPhase = .processingRoutes(
                        completed: batch.completedCount,
                        total: batch.totalCount
                    )
                    if let record = await Self.process(route, with: routeProcessor) {
                        try await repository.save(record: record)
                        imported += 1
                    } else {
                        try await repository.removeRouteRecords(workoutIDs: [route.id])
                    }
                }
                for processed in batch.processedWorkouts {
                    try await repository.markWorkoutProcessed(id: processed.id, end: processed.end)
                }
                if let checkpoint = batch.checkpoint {
                    try await repository.saveCheckpoint(checkpoint)
                }
            }

            importPhase = .preparingMap
            let records = try await repository.loadRecords()
            try Task.checkCancellation()
            guard generation == importGeneration else { return }
            let successfulRefreshDate = Date()
            try await repository.saveLastSuccessfulImport(successfulRefreshDate)
            try protectStorage()
            await liveTrail.reconcile(with: records, now: successfulRefreshDate)
            routeRecords = records
            lastSuccessfulImport = successfulRefreshDate
            clearSelectionIfMissing()
            routeRenderRevision &+= 1
            importPhase = .complete(imported: imported)

            if legacyStore.exists, !records.isEmpty {
                do {
                    try finishLegacyMigration()
                } catch {
                    logger.error("Legacy cache cleanup deferred: \(error.localizedDescription, privacy: .private)")
                }
            }
        } catch is CancellationError {
            guard generation == importGeneration else { return }
            await publishStoredHistory()
            importPhase = .idle
        } catch {
            guard generation == importGeneration else { return }
            await publishStoredHistory()
            logger.error("Health import failed: \(error.localizedDescription, privacy: .private)")
            importPhase = .failed(error.localizedDescription)
        }
    }

    private func publishStoredHistory() {
        Task { [weak self] in
            guard let self else { return }
            await publishStoredHistory()
        }
    }

    private func publishStoredHistory() async {
        do {
            routeRecords = try await repository.loadRecords()
            clearSelectionIfMissing()
            routeRenderRevision &+= 1
            try protectStorage()
        } catch {
            logger.error("Could not publish stored history: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func clearSelectionIfMissing() {
        guard let selectedWorkoutID,
              !routeRecords.contains(where: { $0.id == selectedWorkoutID })
        else { return }
        clearSelectedWorkout()
    }

    private func finishLegacyMigration() throws {
        try legacyStore.removeAfterSuccessfulRebuild()
        UserDefaults.standard.removeObject(forKey: Self.migrationStartedKey)
    }

    private func isFailure(_ state: AppLaunchState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    /// Full-resolution Health locations are processed away from the main actor
    /// and never retained by the app model or repository.
    private nonisolated static func process(
        _ route: WorkoutRoute,
        with processor: RouteProcessor
    ) async -> WorkoutRouteRecord? {
        await Task.detached(priority: .userInitiated) {
            processor.process(route)
        }.value
    }

    #if DEBUG
    private static let uiTestRecords: [WorkoutRouteRecord] = {
        let start = Date(timeIntervalSince1970: 1_782_640_800)
        return [
            WorkoutRouteRecord(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                start: start,
                end: start.addingTimeInterval(2_700),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7680, longitude: -73.9819),
                    GeoCoordinate(latitude: 40.7725, longitude: -73.9760),
                    GeoCoordinate(latitude: 40.7780, longitude: -73.9740),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                start: start.addingTimeInterval(-86_400),
                end: start.addingTimeInterval(-84_600),
                sourceName: "iPhone",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7420, longitude: -74.0060),
                    GeoCoordinate(latitude: 40.7480, longitude: -74.0030),
                ]]
            ),
        ]
    }()
    #endif
}
