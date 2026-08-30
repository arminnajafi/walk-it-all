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
    case userLocation(MapUserTrackingMode)
}

enum MapUserTrackingMode: Equatable, Sendable {
    case free
    case followNorthUp
    case followWithHeading
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
    case complete(HealthImportCompletion)
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
        case let .processingRoutes(completed, total): "Preparing routes \(completed) of \(total)…"
        case .preparingMap: "Updating your map…"
        case let .complete(completion): completion.title
        case .failed: "Refresh needs attention"
        }
    }
}

enum HealthImportCompletion: Equatable, Sendable {
    case refreshed(added: Int, updated: Int, removed: Int)
    case rebuilt(Int)

    static func refreshed(
        comparing previousRecords: [WorkoutRouteRecord],
        with currentRecords: [WorkoutRouteRecord]
    ) -> Self {
        let previous = Dictionary(uniqueKeysWithValues: previousRecords.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: currentRecords.map { ($0.id, $0) })
        let previousIDs = Set(previous.keys)
        let currentIDs = Set(current.keys)
        let sharedIDs = previousIDs.intersection(currentIDs)
        return .refreshed(
            added: currentIDs.subtracting(previousIDs).count,
            updated: sharedIDs.count { previous[$0] != current[$0] },
            removed: previousIDs.subtracting(currentIDs).count
        )
    }

    var title: String {
        switch self {
        case let .rebuilt(count):
            return "Rebuilt \(Self.workoutCount(count))"
        case let .refreshed(added, updated, removed):
            let changes = [
                Self.changeDescription(count: added, action: "added"),
                Self.changeDescription(count: updated, action: "updated"),
                Self.changeDescription(count: removed, action: "removed"),
            ].compactMap(\.self)
            return changes.isEmpty
                ? "Apple Health is up to date"
                : changes.joined(separator: " · ")
        }
    }

    private static func workoutCount(_ count: Int) -> String {
        "\(count) workout\(count == 1 ? "" : "s")"
    }

    private static func changeDescription(count: Int, action: String) -> String? {
        guard count > 0 else { return nil }
        return "\(workoutCount(count)) \(action)"
    }
}

enum HealthImportApplicationError: LocalizedError {
    case noReadableWorkouts

    var errorDescription: String? {
        switch self {
        case .noReadableWorkouts:
            "Apple Health returned no readable workouts. Your existing map was kept. Review Health access or try again."
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private static let onboardingKey = "didCompleteOnboarding"
    private static let connectedHealthKey = "didConnectAppleHealth"
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
    var mapUserTrackingMode: MapUserTrackingMode = .free
    @ObservationIgnored let liveTrail: LiveTrailController
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    @ObservationIgnored private let routeSource: any WorkoutRouteSource
    @ObservationIgnored private let repository: any WalkHistoryRepository
    @ObservationIgnored private let routeProcessor: RouteProcessor
    @ObservationIgnored private let protectStorage: @Sendable () throws -> Void
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = 0
    @ObservationIgnored private var shouldImportAfterOnboardingDismisses = false
    @ObservationIgnored private var shouldStartLiveTrailAfterSheetDismisses = false
    @ObservationIgnored private var shouldFollowAfterLocationAuthorization = false
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
        protectStorage = dependencies.protectStorage

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            // Write explicit false values so UI-test resets also override any
            // simulator-level defaults injected during manual visual QA.
            UserDefaults.standard.set(false, forKey: Self.onboardingKey)
            UserDefaults.standard.set(false, forKey: Self.connectedHealthKey)
            UserDefaults.standard.set(false, forKey: Self.liveTrailExplainedKey)
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
            || arguments.contains("-skipOnboarding")
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
            try protectStorage()
            routeRenderRevision &+= 1
            launchState = .ready

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
        beginAuthorizedImport(resetFirst: false, isAutomatic: false)
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
        beginAuthorizedImport(resetFirst: false, isAutomatic: true)
    }

    func cancelImport() {
        importGeneration &+= 1
        importTask?.cancel()
        importTask = nil
        importPhase = .idle
        publishStoredHistory()
    }

    func selectWorkout(_ id: UUID) {
        guard !liveTrail.hasInProgressSession else { return }
        shouldFollowAfterLocationAuthorization = false
        selectedWorkoutID = id
        mapUserTrackingMode = .free
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
        shouldFollowAfterLocationAuthorization = false
        mapUserTrackingMode = .free
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .manhattan
        )
    }

    func showUserLocation() {
        liveTrail.requestCurrentLocation()
        guard liveTrail.accessState.canShowLocation else {
            shouldFollowAfterLocationAuthorization = liveTrail.accessState == .notDetermined
            mapUserTrackingMode = .free
            return
        }
        shouldFollowAfterLocationAuthorization = false
        let mode: MapUserTrackingMode = mapUserTrackingMode == .followNorthUp
            ? .followWithHeading
            : .followNorthUp
        requestUserTracking(mode)
    }

    func locationAccessDidChange(_ accessState: LocationAccessState) {
        guard accessState.canShowLocation else {
            mapUserTrackingMode = .free
            return
        }
        guard shouldFollowAfterLocationAuthorization else { return }
        shouldFollowAfterLocationAuthorization = false
        requestUserTracking(.followNorthUp)
    }

    func mapUserTrackingDidChange(_ mode: MapUserTrackingMode) {
        if mode == .free {
            shouldFollowAfterLocationAuthorization = false
        }
        mapUserTrackingMode = mode
    }

    private func followUserHeading() {
        liveTrail.requestCurrentLocation()
        requestUserTracking(.followWithHeading)
    }

    private func requestUserTracking(_ mode: MapUserTrackingMode) {
        mapUserTrackingMode = mode
        mapViewportCommand = MapViewportCommand(
            revision: mapViewportCommand.revision &+ 1,
            target: .userLocation(mode)
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
        followUserHeading()
    }

    func clearLiveTrail() {
        Task { [weak self] in
            await self?.liveTrail.clear()
        }
    }

    func startNewLiveTrail() {
        selectedWorkoutID = nil
        Task { [weak self] in
            guard let self else { return }
            await liveTrail.startNew()
            followUserHeading()
        }
    }

    private func startLiveTrail() {
        selectedWorkoutID = nil
        liveTrail.start()
        followUserHeading()
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
                    routeRecords = []
                    lastSuccessfulImport = nil
                    clearSelectedWorkout()
                    routeRenderRevision &+= 1
                }
                await performImport(generation: generation, isRebuild: resetFirst)
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

    private func performImport(generation: Int, isRebuild: Bool) async {
        guard generation == importGeneration else { return }
        importPhase = .findingWorkouts
        do {
            let recordsBeforeImport = try await repository.loadRecords()
            let checkpoint = try await repository.loadCheckpoint()
            let processedWorkoutIDs = try await repository.loadProcessedWorkoutIDs()
            let batches = await routeSource.routeBatches(
                since: checkpoint,
                excluding: processedWorkoutIDs
            )
            var pendingCheckpoint: Data?
            var authoritativeWorkoutIDs: Set<UUID>?

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
                    } else {
                        try await repository.removeRouteRecords(workoutIDs: [route.id])
                    }
                }
                for processed in batch.processedWorkouts {
                    try await repository.markWorkoutProcessed(id: processed.id, end: processed.end)
                }
                if let checkpoint = batch.checkpoint { pendingCheckpoint = checkpoint }
                if let authoritative = batch.authoritativeWorkoutIDs {
                    authoritativeWorkoutIDs = authoritative
                }
            }

            try Task.checkCancellation()
            guard generation == importGeneration else { return }

            if let authoritativeWorkoutIDs {
                let existingWorkoutIDs = try await repository.loadProcessedWorkoutIDs()
                if authoritativeWorkoutIDs.isEmpty, !existingWorkoutIDs.isEmpty {
                    throw HealthImportApplicationError.noReadableWorkouts
                }
                let staleWorkoutIDs = existingWorkoutIDs.subtracting(authoritativeWorkoutIDs)
                if !staleWorkoutIDs.isEmpty {
                    try await repository.removeWorkouts(
                        workoutIDs: staleWorkoutIDs.sorted { $0.uuidString < $1.uuidString }
                    )
                }
            }
            if let pendingCheckpoint {
                try await repository.saveCheckpoint(pendingCheckpoint)
            }

            importPhase = .preparingMap
            let records = try await repository.loadRecords()
            try Task.checkCancellation()
            guard generation == importGeneration else { return }
            let successfulRefreshDate = Date()
            try await repository.saveLastSuccessfulImport(successfulRefreshDate)
            try protectStorage()
            routeRecords = records
            lastSuccessfulImport = successfulRefreshDate
            clearSelectionIfMissing()
            routeRenderRevision &+= 1
            importPhase = .complete(
                isRebuild
                    ? .rebuilt(records.count)
                    : .refreshed(comparing: recordsBeforeImport, with: records)
            )

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
                end: start.addingTimeInterval(-81_900),
                sourceName: "Apple Watch",
                activityKind: .cycling,
                routeParts: [[
                    GeoCoordinate(latitude: 40.7040, longitude: -74.0180),
                    GeoCoordinate(latitude: 40.7280, longitude: -74.0120),
                    GeoCoordinate(latitude: 40.7600, longitude: -74.0100),
                    GeoCoordinate(latitude: 40.8030, longitude: -73.9710),
                    GeoCoordinate(latitude: 40.8500, longitude: -73.9360),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                start: start.addingTimeInterval(-172_800),
                end: start.addingTimeInterval(-168_600),
                sourceName: "Apple Watch",
                activityKind: .running,
                routeParts: [[
                    GeoCoordinate(latitude: 40.7040, longitude: -74.0090),
                    GeoCoordinate(latitude: 40.7180, longitude: -73.9970),
                    GeoCoordinate(latitude: 40.7350, longitude: -73.9740),
                    GeoCoordinate(latitude: 40.7560, longitude: -73.9580),
                    GeoCoordinate(latitude: 40.7870, longitude: -73.9380),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                start: start.addingTimeInterval(-259_200),
                end: start.addingTimeInterval(-255_600),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7060, longitude: -74.0110),
                    GeoCoordinate(latitude: 40.7210, longitude: -74.0040),
                    GeoCoordinate(latitude: 40.7420, longitude: -73.9890),
                    GeoCoordinate(latitude: 40.7580, longitude: -73.9850),
                    GeoCoordinate(latitude: 40.7800, longitude: -73.9810),
                    GeoCoordinate(latitude: 40.8090, longitude: -73.9540),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                start: start.addingTimeInterval(-345_600),
                end: start.addingTimeInterval(-342_000),
                sourceName: "iPhone",
                activityKind: .hiking,
                routeParts: [[
                    GeoCoordinate(latitude: 40.7680, longitude: -73.9819),
                    GeoCoordinate(latitude: 40.7810, longitude: -73.9738),
                    GeoCoordinate(latitude: 40.7980, longitude: -73.9495),
                    GeoCoordinate(latitude: 40.7920, longitude: -73.9460),
                    GeoCoordinate(latitude: 40.7740, longitude: -73.9720),
                    GeoCoordinate(latitude: 40.7680, longitude: -73.9819),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                start: start.addingTimeInterval(-432_000),
                end: start.addingTimeInterval(-430_200),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7390, longitude: -74.0090),
                    GeoCoordinate(latitude: 40.7350, longitude: -73.9740),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                start: start.addingTimeInterval(-518_400),
                end: start.addingTimeInterval(-516_600),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7550, longitude: -74.0040),
                    GeoCoordinate(latitude: 40.7440, longitude: -73.9720),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                start: start.addingTimeInterval(-604_800),
                end: start.addingTimeInterval(-603_000),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7710, longitude: -73.9940),
                    GeoCoordinate(latitude: 40.7580, longitude: -73.9590),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                start: start.addingTimeInterval(-691_200),
                end: start.addingTimeInterval(-689_400),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.7900, longitude: -73.9780),
                    GeoCoordinate(latitude: 40.7760, longitude: -73.9470),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                start: start.addingTimeInterval(-777_600),
                end: start.addingTimeInterval(-775_800),
                sourceName: "Apple Watch",
                routeParts: [[
                    GeoCoordinate(latitude: 40.8040, longitude: -73.9650),
                    GeoCoordinate(latitude: 40.7910, longitude: -73.9340),
                ]]
            ),
        ]
    }()
    #endif
}
