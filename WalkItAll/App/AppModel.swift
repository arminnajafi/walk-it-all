import Foundation
import Observation
import OSLog
import WalkItAllCore

enum AppSheet: Identifiable, Hashable {
    case details
    case workouts
    case methodology
    case privacy
    #if DEBUG
    case debugInspector
    #endif

    var id: String {
        switch self {
        case .details: "details"
        case .workouts: "workouts"
        case .methodology: "methodology"
        case .privacy: "privacy"
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
    @ObservationIgnored private var importTask: Task<Void, Never>?

    private(set) var cityPack: (any CityCoveragePack)?

    init(dependencies: AppDependencies) {
        routeSource = dependencies.routeSource
        repository = dependencies.repository
        cityPackLoader = dependencies.cityPackLoader
        matcher = dependencies.matcher
        coverageCalculator = dependencies.coverageCalculator
        routeSimplifier = dependencies.routeSimplifier
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
            || ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
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
            launchState = .ready
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
            launchState = .failed(error.localizedDescription)
        }
    }

    func connectHealthAndImport() {
        guard !importPhase.isWorking else { return }
        hasCompletedOnboarding = true
        importTask = Task { [weak self] in
            guard let self else { return }
            importPhase = .requestingHealthAccess
            do {
                try await routeSource.requestReadAuthorization()
                await performImport()
            } catch is CancellationError {
                importPhase = .idle
            } catch {
                logger.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
                importPhase = .failed(error.localizedDescription)
            }
        }
    }

    func refresh() {
        guard !importPhase.isWorking else { return }
        importTask = Task { [weak self] in
            await self?.performImport()
        }
    }

    func rebuildFromHealth() {
        guard !importPhase.isWorking else { return }
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.resetDerivedCoverage()
                workoutRecords = []
                if let cityPack { coverage = .empty(pack: cityPack) }
                await performImport()
            } catch {
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
            let batches = await routeSource.routeBatches(since: checkpoint)
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
                        simplifiedRoute: routeSimplifier.simplify(route.points.map(\.coordinate)),
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
            importPhase = .complete(imported: imported, unmatched: unmatched)
        } catch is CancellationError {
            importPhase = .idle
        } catch {
            logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            importPhase = .failed(error.localizedDescription)
        }
    }

    private func isFailure(_ state: AppLaunchState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
