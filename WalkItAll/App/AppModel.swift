import Foundation
import Observation
import OSLog
import WalkItAllCore

enum AppSheet: Identifiable, Hashable {
    case details
    #if DEBUG
    case debugInspector
    #endif

    var id: String {
        switch self {
        case .details: "details"
        #if DEBUG
        case .debugInspector: "debug-inspector"
        #endif
        }
    }
}

enum AppLaunchState: Equatable {
    case loading
    case ready
    case failed(String)
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

@MainActor
@Observable
final class AppModel {
    private static let onboardingKey = "didCompleteOnboarding"
    private let logger = Logger(subsystem: "com.arminnajafi.walkitall", category: "AppModel")

    var launchState: AppLaunchState = .loading
    var importPhase: ImportPhase = .idle
    var coverage: CoverageSnapshot?
    var workoutRecords: [WorkoutCoverageRecord] = []
    var selectedWorkoutID: UUID?
    var presentedSheet: AppSheet?
    var lastSuccessfulImport: Date?
    var coverageRenderRevision = 0
    #if DEBUG
    var debugLastRoute: WorkoutRoute?
    var debugLastMatch: MatchResult?
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
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
            || arguments.contains("-skipOnboarding")
    }

    var selectedWorkout: WorkoutCoverageRecord? {
        workoutRecords.first { $0.id == selectedWorkoutID }
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

            if let cached = try await repository.loadSnapshot(),
               cached.packIdentifier == pack.metadata.identifier,
               cached.packVersion == pack.metadata.version
            {
                coverage = cached
            } else {
                coverage = .empty(pack: pack)
            }

            workoutRecords = try await repository.loadWorkoutRecords(
                packIdentifier: pack.metadata.identifier,
                packVersion: pack.metadata.version
            )
            if !workoutRecords.isEmpty {
                coverage = coverageCalculator.snapshot(
                    pack: pack,
                    contributions: workoutRecords.map(\.contribution)
                )
            }
            lastSuccessfulImport = try await repository.loadLastSuccessfulImport()
            coverageRenderRevision &+= 1
            launchState = .ready
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .private)")
            launchState = .failed(error.localizedDescription)
        }
    }

    func connectHealthAndImport() {
        guard !importPhase.isWorking else { return }
        hasCompletedOnboarding = true
        beginAuthorizedImport(resetFirst: false)
    }

    func refresh() {
        guard !importPhase.isWorking else { return }
        beginAuthorizedImport(resetFirst: false)
    }

    func rebuildFromHealth() {
        guard !importPhase.isWorking else { return }
        beginAuthorizedImport(resetFirst: true)
    }

    private func beginAuthorizedImport(resetFirst: Bool) {
        importTask = Task { [weak self] in
            guard let self else { return }
            importPhase = .requestingHealthAccess
            do {
                try await routeSource.requestReadAuthorization()
                if resetFirst {
                    try await repository.resetDerivedCoverage()
                    workoutRecords = []
                    selectedWorkoutID = nil
                    lastSuccessfulImport = nil
                    if let cityPack { coverage = .empty(pack: cityPack) }
                    coverageRenderRevision &+= 1
                }
                await performImport()
            } catch is CancellationError {
                importPhase = .idle
            } catch {
                logger.error("Health import setup failed: \(error.localizedDescription, privacy: .private)")
                importPhase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importPhase = .idle
    }

    func selectWorkout(_ id: UUID) {
        selectedWorkoutID = id
        presentedSheet = nil
    }

    func clearSelectedWorkout() {
        selectedWorkoutID = nil
    }

    private func performImport() async {
        guard let pack = cityPack else { return }
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
                }

                importPhase = .readingRoutes(completed: batch.completedCount, total: batch.totalCount)
                for route in batch.routes {
                    try Task.checkCancellation()
                    importPhase = .matching(completed: batch.completedCount, total: batch.totalCount)
                    let result = try await matcher.match(points: route.points, in: pack)
                    #if DEBUG
                    debugLastRoute = route
                    debugLastMatch = result
                    #endif
                    let contribution = WorkoutCoverageContribution(
                        workoutID: route.id,
                        intervals: result.intervals,
                        confidence: result.averageConfidence
                    )
                    let record = WorkoutCoverageRecord(
                        id: route.id,
                        start: route.start,
                        end: route.end,
                        sourceName: route.sourceName,
                        simplifiedRouteParts: routeChunker.chunks(from: route.points).map {
                            routeSimplifier.simplify($0.map(\.coordinate))
                        },
                        contribution: contribution,
                        unmatchedPortions: result.unmatchedPortions
                    )
                    try await repository.save(
                        record: record,
                        packIdentifier: pack.metadata.identifier,
                        packVersion: pack.metadata.version
                    )
                    workoutRecords.removeAll { $0.id == record.id }
                    workoutRecords.append(record)
                    workoutRecords.sort { $0.start > $1.start }
                    imported += 1
                    unmatched += result.unmatchedPortions.count
                }
                for processed in batch.processedWorkouts {
                    try await repository.markWorkoutProcessed(id: processed.id, end: processed.end)
                }
                if let checkpoint = batch.checkpoint {
                    try await repository.saveCheckpoint(checkpoint)
                }
            }

            importPhase = .calculating
            coverage = coverageCalculator.snapshot(
                pack: pack,
                contributions: workoutRecords.map(\.contribution)
            )
            if let coverage { try await repository.replaceSnapshot(coverage) }
            lastSuccessfulImport = Date()
            coverageRenderRevision &+= 1
            importPhase = .complete(imported: imported, unmatched: unmatched)
        } catch is CancellationError {
            coverage = coverageCalculator.snapshot(
                pack: pack,
                contributions: workoutRecords.map(\.contribution)
            )
            coverageRenderRevision &+= 1
            importPhase = .idle
        } catch {
            coverage = coverageCalculator.snapshot(
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
}
