import Foundation
import Observation
import OSLog
import WalkItAllCore

enum AppSheet: Identifiable, Hashable {
    case details
    case healthAccess

    var id: String {
        switch self {
        case .details: "details"
        case .healthAccess: "health-access"
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
    case matching(completed: Int, total: Int)
    case calculating
    case complete(imported: Int, unmatched: Int)
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .requestingHealthAccess, .findingWorkouts, .readingRoutes, .matching, .calculating:
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
        case let .matching(completed, total): "Matching walks \(completed) of \(total)…"
        case .calculating: "Calculating coverage…"
        case let .complete(imported, _): "Updated \(imported) workout\(imported == 1 ? "" : "s")"
        case .failed: "Import needs attention"
        }
    }
}

private struct ProcessedWorkoutRoute: Sendable {
    let record: WorkoutCoverageRecord
    let unmatchedPortionCount: Int
}

#if DEBUG
enum DebugInspectionState {
    case idle
    case loading
    case loaded(route: WorkoutRoute, match: MatchResult, nearbySegmentIDs: Set<SegmentID>)
    case failed(String)
}
#endif

@MainActor
@Observable
final class AppModel {
    private static let onboardingKey = "didCompleteOnboarding"
    private static let connectedHealthKey = "didConnectAppleHealth"
    private static let automaticRefreshInterval: TimeInterval = 5 * 60
    private let logger = Logger(subsystem: "com.arminnajafi.walkitall", category: "AppModel")

    var launchState: AppLaunchState = .loading
    var importPhase: ImportPhase = .idle
    var coverage: CoverageSnapshot?
    var workoutRecords: [WorkoutCoverageRecord] = []
    var selectedWorkoutID: UUID?
    var presentedSheet: AppSheet?
    var lastSuccessfulImport: Date?
    var coverageRenderRevision = 0
    var mapViewportCommand = MapViewportCommand(revision: 0, target: .manhattan)
    #if DEBUG
    var debugInspectionState: DebugInspectionState = .idle
    #endif
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    @ObservationIgnored private let routeSource: any WorkoutRouteSource
    @ObservationIgnored private let repository: any CoverageRepository
    @ObservationIgnored private let cityPackLoader: SQLiteCityPackLoader
    @ObservationIgnored private let matcher: any MapMatcher
    @ObservationIgnored private let coverageCalculator: CoverageCalculator
    @ObservationIgnored private let routeSimplifier: RouteSimplifier
    @ObservationIgnored private let routeChunker: RouteChunker
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = 0
    @ObservationIgnored private var shouldImportAfterOnboardingDismisses = false
    @ObservationIgnored private var lastAutomaticRefreshAttempt: Date?
    #if DEBUG
    @ObservationIgnored private var hasExportedRequestedDiagnostic = false
    @ObservationIgnored private var debugInspectionGeneration = 0
    #endif

    private(set) var cityPack: (any CityCoveragePack)?

    init(dependencies: AppDependencies) {
        routeSource = dependencies.routeSource
        repository = dependencies.repository
        cityPackLoader = dependencies.cityPackLoader
        matcher = dependencies.matcher
        coverageCalculator = dependencies.coverageCalculator
        routeSimplifier = dependencies.routeSimplifier
        routeChunker = dependencies.routeChunker
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: Self.onboardingKey)
            UserDefaults.standard.removeObject(forKey: Self.connectedHealthKey)
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
            || arguments.contains("-skipOnboarding")
    }

    var selectedWorkout: WorkoutCoverageRecord? {
        workoutRecords.first { $0.id == selectedWorkoutID }
    }

    var workoutsWithCoverageCount: Int {
        workoutRecords.lazy.filter {
            $0.contribution.uniqueCoveredDistanceMeters > 0
        }.count
    }

    var hasMappedWorkouts: Bool {
        workoutsWithCoverageCount > 0
    }

    var hasConnectedHealth: Bool {
        UserDefaults.standard.bool(forKey: Self.connectedHealthKey)
    }

    func bootstrap() async {
        guard launchState == .loading || isFailure(launchState) else { return }
        launchState = .loading
        do {
            let pack = try await cityPackLoader.loadBundledManhattan()
            cityPack = pack
            try await repository.prepareForPack(
                identifier: pack.metadata.identifier,
                version: pack.metadata.version
            )

            workoutRecords = try await repository.loadWorkoutRecords(
                packIdentifier: pack.metadata.identifier,
                packVersion: pack.metadata.version
            )
            coverage = await Self.calculateCoverage(
                calculator: coverageCalculator,
                pack: pack,
                contributions: workoutRecords.map(\.contribution)
            )
            lastSuccessfulImport = try await repository.loadLastSuccessfulImport()
            coverageRenderRevision &+= 1
            launchState = .ready
            #if DEBUG
            await exportRequestedDiagnosticIfNeeded()
            #endif
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
        guard !importPhase.isWorking else { return }
        beginAuthorizedImport(resetFirst: true, isAutomatic: false)
    }

    func refreshIfNeeded(now: Date = Date()) {
        guard launchState == .ready,
              hasConnectedHealth,
              !importPhase.isWorking,
              lastSuccessfulImport.map({ now.timeIntervalSince($0) >= Self.automaticRefreshInterval }) ?? true,
              lastAutomaticRefreshAttempt.map({ now.timeIntervalSince($0) >= Self.automaticRefreshInterval }) ?? true
        else { return }

        lastAutomaticRefreshAttempt = now
        beginAuthorizedImport(resetFirst: false, isAutomatic: true)
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
                    try await repository.resetDerivedCoverage()
                    workoutRecords = []
                    selectedWorkoutID = nil
                    showAllManhattan()
                    lastSuccessfulImport = nil
                    if let cityPack { coverage = .empty(pack: cityPack) }
                    coverageRenderRevision &+= 1
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

    func cancelImport() {
        importGeneration &+= 1
        importTask?.cancel()
        importTask = nil
        importPhase = .idle
    }

    func selectWorkout(_ id: UUID) {
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

    private func performImport(generation: Int) async {
        guard let pack = cityPack else { return }
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
            var unmatched = 0

            for try await batch in batches {
                try Task.checkCancellation()
                if !batch.deletedWorkoutIDs.isEmpty {
                    try await repository.remove(workoutIDs: batch.deletedWorkoutIDs)
                    let deleted = Set(batch.deletedWorkoutIDs)
                    workoutRecords.removeAll { deleted.contains($0.id) }
                    if let selectedWorkoutID, deleted.contains(selectedWorkoutID) {
                        clearSelectedWorkout()
                    }
                }
                if !batch.routeInvalidatedWorkoutIDs.isEmpty {
                    try await repository.removeCoverage(workoutIDs: batch.routeInvalidatedWorkoutIDs)
                    let invalidated = Set(batch.routeInvalidatedWorkoutIDs)
                    workoutRecords.removeAll { invalidated.contains($0.id) }
                    if let selectedWorkoutID, invalidated.contains(selectedWorkoutID) {
                        clearSelectedWorkout()
                    }
                }

                importPhase = .readingRoutes(completed: batch.completedCount, total: batch.totalCount)
                for route in batch.routes {
                    try Task.checkCancellation()
                    importPhase = .matching(completed: batch.completedCount, total: batch.totalCount)
                    let processed = try await Self.process(
                        route: route,
                        matcher: matcher,
                        pack: pack,
                        routeChunker: routeChunker,
                        routeSimplifier: routeSimplifier
                    )
                    let record = processed.record
                    try await repository.save(
                        record: record,
                        packIdentifier: pack.metadata.identifier,
                        packVersion: pack.metadata.version
                    )
                    workoutRecords.removeAll { $0.id == record.id }
                    workoutRecords.append(record)
                    workoutRecords.sort { $0.start > $1.start }
                    imported += 1
                    unmatched += processed.unmatchedPortionCount
                }
                for processed in batch.processedWorkouts {
                    try await repository.markWorkoutProcessed(id: processed.id, end: processed.end)
                }
                if let checkpoint = batch.checkpoint {
                    try await repository.saveCheckpoint(checkpoint)
                }
            }

            importPhase = .calculating
            let calculatedCoverage = await Self.calculateCoverage(
                calculator: coverageCalculator,
                pack: pack,
                contributions: workoutRecords.map(\.contribution)
            )
            try Task.checkCancellation()
            guard generation == importGeneration else { return }
            coverage = calculatedCoverage
            let successfulRefreshDate = Date()
            try await repository.saveLastSuccessfulImport(successfulRefreshDate)
            lastSuccessfulImport = successfulRefreshDate
            coverageRenderRevision &+= 1
            importPhase = .complete(imported: imported, unmatched: unmatched)
            #if DEBUG
            await exportRequestedDiagnosticIfNeeded()
            #endif
        } catch is CancellationError {
            guard generation == importGeneration else { return }
            coverage = await Self.calculateCoverage(
                calculator: coverageCalculator,
                pack: pack,
                contributions: workoutRecords.map(\.contribution)
            )
            coverageRenderRevision &+= 1
            importPhase = .idle
        } catch {
            guard generation == importGeneration else { return }
            coverage = await Self.calculateCoverage(
                calculator: coverageCalculator,
                pack: pack,
                contributions: workoutRecords.map(\.contribution)
            )
            coverageRenderRevision &+= 1
            logger.error("Import failed: \(error.localizedDescription, privacy: .private)")
            importPhase = .failed(error.localizedDescription)
        }
    }

    private func isFailure(_ state: AppLaunchState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    #if DEBUG
    func loadDebugInspection(workoutID: UUID) async {
        debugInspectionGeneration &+= 1
        let generation = debugInspectionGeneration
        debugInspectionState = .loading
        do {
            guard let pack = cityPack else {
                debugInspectionState = .failed("The offline Manhattan map is not loaded.")
                return
            }
            guard let route = try await routeSource.route(for: workoutID) else {
                guard generation == debugInspectionGeneration else { return }
                debugInspectionState = .failed(
                    "Apple Health no longer has a readable route for this workout."
                )
                return
            }
            try Task.checkCancellation()
            guard generation == debugInspectionGeneration else { return }
            let match = try await matcher.match(points: route.points, in: pack)
            let nearbySegmentIDs = await Task.detached(priority: .userInitiated) {
                let strideLength = max(1, route.points.count / 500)
                var ids = Set<SegmentID>()
                for index in stride(from: 0, to: route.points.count, by: strideLength) {
                    ids.formUnion(
                        pack.segments(near: route.points[index].coordinate, radiusMeters: 75).map(\.id)
                    )
                }
                return ids
            }.value
            try Task.checkCancellation()
            guard generation == debugInspectionGeneration else { return }
            debugInspectionState = .loaded(
                route: route,
                match: match,
                nearbySegmentIDs: nearbySegmentIDs
            )
        } catch is CancellationError {
            guard generation == debugInspectionGeneration else { return }
            debugInspectionState = .idle
        } catch {
            guard generation == debugInspectionGeneration else { return }
            logger.error("Debug route inspection failed: \(error.localizedDescription, privacy: .private)")
            debugInspectionState = .failed(error.localizedDescription)
        }
    }

    func clearDebugInspection() {
        debugInspectionGeneration &+= 1
        debugInspectionState = .idle
    }

    private func exportRequestedDiagnosticIfNeeded() async {
        guard !hasExportedRequestedDiagnostic,
              let rawIndex = ProcessInfo.processInfo.environment["WALK_IT_ALL_DIAGNOSTIC_WORKOUT_INDEX"],
              let index = Int(rawIndex),
              workoutRecords.indices.contains(index),
              let pack = cityPack
        else { return }

        do {
            let record = workoutRecords[index]
            guard let route = try await routeSource.route(for: record.id) else { return }
            let match = try await matcher.match(points: route.points, in: pack)
            let fixture = PrivateRouteDiagnosticFixture(
                schemaVersion: 2,
                createdAt: Date(),
                packIdentifier: pack.metadata.identifier,
                packVersion: pack.metadata.version,
                route: route,
                match: match
            )
            _ = try await DebugRouteFixtureStore.saveDiagnostic(fixture)
            hasExportedRequestedDiagnostic = true
        } catch {
            logger.error("Private debug diagnostic export failed: \(error.localizedDescription, privacy: .private)")
        }
    }
    #endif

    private nonisolated static func calculateCoverage(
        calculator: CoverageCalculator,
        pack: any CityCoveragePack,
        contributions: [WorkoutCoverageContribution]
    ) async -> CoverageSnapshot {
        await Task.detached(priority: .userInitiated) {
            calculator.snapshot(pack: pack, contributions: contributions)
        }.value
    }

    /// Matching, chunking, and route simplification must all stay off the main
    /// actor. A long Health route can contain thousands of locations even when
    /// its final stored representation is small.
    private nonisolated static func process(
        route: WorkoutRoute,
        matcher: any MapMatcher,
        pack: any CityCoveragePack,
        routeChunker: RouteChunker,
        routeSimplifier: RouteSimplifier
    ) async throws -> ProcessedWorkoutRoute {
        let result = try await matcher.match(points: route.points, in: pack)
        try Task.checkCancellation()
        let contribution = WorkoutCoverageContribution(
            workoutID: route.id,
            intervals: result.intervals,
            confidence: result.averageConfidence
        )
        let routeParts = routeChunker.chunks(from: route.points).map {
            routeSimplifier.simplify($0.map(\.coordinate))
        }
        try Task.checkCancellation()
        return ProcessedWorkoutRoute(
            record: WorkoutCoverageRecord(
                id: route.id,
                start: route.start,
                end: route.end,
                sourceName: route.sourceName,
                simplifiedRouteParts: routeParts,
                contribution: contribution,
                unmatchedPortions: result.unmatchedPortions
            ),
            unmatchedPortionCount: result.unmatchedPortions.count
        )
    }
}
