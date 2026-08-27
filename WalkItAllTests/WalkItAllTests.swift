import XCTest
import SwiftData
import WalkItAllCore
@testable import WalkItAll

final class WalkItAllTests: XCTestCase {
    func testPreviewMapHasAStableCoverageDenominator() {
        let pack = PreviewCityPack.manhattanSample
        let snapshot = CoverageCalculator().snapshot(pack: pack, contributions: [])

        XCTAssertGreaterThan(snapshot.totalDistanceMeters, 0)
        XCTAssertEqual(snapshot.coveredDistanceMeters, 0)
        XCTAssertEqual(snapshot.packVersion, pack.metadata.version)
    }

    func testBundledManhattanDatabaseLoads() async throws {
        let pack = try await SQLiteCityPackLoader().loadBundledManhattan()

        XCTAssertEqual(pack.metadata.identifier, "manhattan-island")
        XCTAssertGreaterThan(pack.segments.count, 10_000)
        XCTAssertGreaterThan(pack.totalLengthMeters, 500_000)
    }

    @MainActor
    func testSwiftDataRepositoryRoundTripsRoutePartsAndInvalidatesOldPack() async throws {
        let schema = Schema([
            PersistedWorkoutCoverage.self,
            PersistedAppState.self,
            PersistedWorkoutImportState.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let repository = SwiftDataCoverageRepository(modelContainer: container)
        let id = UUID()
        let end = Date(timeIntervalSince1970: 500)
        let routeParts = [
            [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ],
            [
                GeoCoordinate(latitude: 40.76, longitude: -73.98),
                GeoCoordinate(latitude: 40.761, longitude: -73.98),
            ],
        ]
        let record = WorkoutCoverageRecord(
            id: id,
            start: Date(timeIntervalSince1970: 400),
            end: end,
            sourceName: "Test",
            simplifiedRouteParts: routeParts,
            contribution: WorkoutCoverageContribution(
                workoutID: id,
                intervals: [],
                confidence: 0.8
            ),
            unmatchedPortions: []
        )

        try await repository.prepareForPack(identifier: "manhattan", version: 1)
        try await repository.save(record: record, packIdentifier: "manhattan", packVersion: 1)
        try await repository.markWorkoutProcessed(id: id, end: end)
        try await repository.saveCheckpoint(Data([9]))

        let loaded = try await repository.loadWorkoutRecords(
            packIdentifier: "manhattan",
            packVersion: 1
        )
        XCTAssertEqual(loaded.first?.simplifiedRouteParts, routeParts)
        let processedBeforeInvalidation = try await repository.loadProcessedWorkoutIDs()
        XCTAssertEqual(processedBeforeInvalidation, [id])

        try await repository.prepareForPack(identifier: "manhattan", version: 2)

        let recordsAfterInvalidation = try await repository.loadWorkoutRecords(
            packIdentifier: "manhattan",
            packVersion: 2
        )
        let processedAfterInvalidation = try await repository.loadProcessedWorkoutIDs()
        let checkpointAfterInvalidation = try await repository.loadCheckpoint()
        XCTAssertTrue(recordsAfterInvalidation.isEmpty)
        XCTAssertTrue(processedAfterInvalidation.isEmpty)
        XCTAssertNil(checkpointAfterInvalidation)
    }

    @MainActor
    func testRefreshAlwaysRequestsHealthAuthorization() async throws {
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            checkpoint: Data([1]),
            completedCount: 0,
            totalCount: 0
        )])
        let repository = TestCoverageRepository()
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitUntilImportStops(model)

        let authorizationCount = await source.currentAuthorizationCount()
        XCTAssertEqual(authorizationCount, 1)
        XCTAssertEqual(model.lastSuccessfulImport == nil, false)
    }

    @MainActor
    func testBootstrapRestoresLastRefreshDate() async throws {
        let date = Date(timeIntervalSince1970: 123_456)
        let source = TestRouteSource(batches: [])
        let repository = TestCoverageRepository(lastSuccessfulImport: date)
        let model = makeModel(source: source, repository: repository)

        await model.bootstrap()

        XCTAssertEqual(model.lastSuccessfulImport, date)
        let prepared = await repository.preparedPack
        XCTAssertEqual(prepared?.identifier, "manhattan-island")
        XCTAssertEqual(prepared?.version, 1)
    }

    @MainActor
    func testDeletedWorkoutIsRemovedDuringRefresh() async throws {
        let id = UUID()
        let record = WorkoutCoverageRecord(
            id: id,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200),
            sourceName: "Test",
            simplifiedRouteParts: [],
            contribution: WorkoutCoverageContribution(
                workoutID: id,
                intervals: [],
                confidence: 0
            ),
            unmatchedPortions: []
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            deletedWorkoutIDs: [id],
            checkpoint: Data([2])
        )])
        let repository = TestCoverageRepository(records: [record])
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()
        XCTAssertEqual(model.workoutRecords.map(\.id), [id])

        model.refresh()
        try await waitUntilImportStops(model)

        XCTAssertTrue(model.workoutRecords.isEmpty)
        let repositoryIsEmpty = await repository.isEmpty
        XCTAssertTrue(repositoryIsEmpty)
    }

    @MainActor
    private func makeModel(
        source: TestRouteSource,
        repository: TestCoverageRepository
    ) -> AppModel {
        AppModel(dependencies: AppDependencies(
            routeSource: source,
            repository: repository,
            cityPackLoader: SQLiteCityPackLoader(),
            matcher: EmptyMatcher(),
            coverageCalculator: CoverageCalculator(),
            routeSimplifier: RouteSimplifier(),
            routeChunker: RouteChunker()
        ))
    }

    @MainActor
    private func waitUntilImportStops(_ model: AppModel) async throws {
        for _ in 0 ..< 200 {
            if model.importPhase != .idle, !model.importPhase.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Import did not finish")
    }
}

private struct EmptyMatcher: MapMatcher {
    func match(points: [RoutePoint], in pack: any CityCoveragePack) async throws -> MatchResult {
        MatchResult(
            intervals: [],
            unmatchedPortions: [],
            acceptedPointCount: 0,
            rejectedPointCount: points.count,
            averageConfidence: 0
        )
    }
}

private actor TestRouteSource: WorkoutRouteSource {
    private(set) var authorizationCount = 0
    let batches: [WorkoutRouteBatch]

    init(batches: [WorkoutRouteBatch]) {
        self.batches = batches
    }

    func requestReadAuthorization() async throws {
        authorizationCount += 1
    }

    func currentAuthorizationCount() -> Int { authorizationCount }

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        let batches = self.batches
        return AsyncThrowingStream { continuation in
            for batch in batches { continuation.yield(batch) }
            continuation.finish()
        }
    }
}

private actor TestCoverageRepository: CoverageRepository {
    var records: [WorkoutCoverageRecord]
    var snapshot: CoverageSnapshot?
    var checkpoint: Data?
    var processedIDs: Set<UUID>
    var lastSuccessfulImport: Date?
    private(set) var preparedPack: (identifier: String, version: Int)?
    var isEmpty: Bool { records.isEmpty }

    init(
        records: [WorkoutCoverageRecord] = [],
        snapshot: CoverageSnapshot? = nil,
        checkpoint: Data? = nil,
        processedIDs: Set<UUID> = [],
        lastSuccessfulImport: Date? = nil
    ) {
        self.records = records
        self.snapshot = snapshot
        self.checkpoint = checkpoint
        self.processedIDs = processedIDs
        self.lastSuccessfulImport = lastSuccessfulImport
    }

    func prepareForPack(identifier: String, version: Int) async throws {
        preparedPack = (identifier, version)
    }

    func loadWorkoutRecords(packIdentifier: String, packVersion: Int) async throws -> [WorkoutCoverageRecord] {
        records
    }

    func loadProcessedWorkoutIDs() async throws -> Set<UUID> { processedIDs }

    func markWorkoutProcessed(id: UUID, end: Date) async throws {
        processedIDs.insert(id)
    }

    func save(
        record: WorkoutCoverageRecord,
        packIdentifier: String,
        packVersion: Int
    ) async throws {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func remove(workoutIDs: [UUID]) async throws {
        let removed = Set(workoutIDs)
        records.removeAll { removed.contains($0.id) }
        processedIDs.subtract(removed)
    }

    func replaceSnapshot(_ snapshot: CoverageSnapshot) async throws {
        self.snapshot = snapshot
        lastSuccessfulImport = Date()
    }

    func loadSnapshot() async throws -> CoverageSnapshot? { snapshot }
    func loadCheckpoint() async throws -> Data? { checkpoint }
    func loadLastSuccessfulImport() async throws -> Date? { lastSuccessfulImport }
    func saveCheckpoint(_ checkpoint: Data?) async throws { self.checkpoint = checkpoint }

    func resetDerivedCoverage() async throws {
        records = []
        snapshot = nil
        checkpoint = nil
        processedIDs = []
        lastSuccessfulImport = nil
    }
}
