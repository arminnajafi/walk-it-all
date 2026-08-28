import XCTest
import SwiftData
@preconcurrency import HealthKit
import MapKit
import WalkItAllCore
@testable import WalkItAll

final class WalkItAllTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "didCompleteOnboarding")
        UserDefaults.standard.removeObject(forKey: "didConnectAppleHealth")
        UserDefaults.standard.removeObject(forKey: "didBeginLifetimeMapMigration")
    }

    func testHealthCursorRoundTripsBothAnchorsAndAssociations() throws {
        let routeID = UUID()
        let workoutID = UUID()
        let cursor = HealthImportCursor(
            version: 99,
            workoutAnchorData: Data([1, 2]),
            routeAnchorData: Data([3, 4]),
            routeToWorkout: [routeID: workoutID]
        )

        let decoded = HealthImportCursorCodec.decode(try HealthImportCursorCodec.encode(cursor))

        XCTAssertEqual(decoded.version, 99)
        XCTAssertEqual(decoded.workoutAnchorData, Data([1, 2]))
        XCTAssertEqual(decoded.routeAnchorData, Data([3, 4]))
        XCTAssertEqual(decoded.routeToWorkout[routeID], workoutID)
    }

    func testLegacyWorkoutAnchorMigratesWithoutDiscardingIt() throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        let legacy = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )

        let migration = HealthImportCursorCodec.decodeForImport(legacy)

        XCTAssertEqual(migration.cursor.workoutAnchorData, legacy)
        XCTAssertNil(migration.cursor.routeAnchorData)
        XCTAssertTrue(migration.requiresFullRouteReconciliation)
    }

    func testCorruptHealthCursorRequestsRouteReconciliation() {
        let migration = HealthImportCursorCodec.decodeForImport(Data("not a cursor".utf8))
        XCTAssertNil(migration.cursor.workoutAnchorData)
        XCTAssertNil(migration.cursor.routeAnchorData)
        XCTAssertTrue(migration.requiresFullRouteReconciliation)
    }

    func testCurrentHealthCursorAvoidsFullRouteReconciliation() throws {
        let cursor = HealthImportCursor(
            workoutAnchorData: Data([1]),
            routeAnchorData: Data([2])
        )
        let migration = HealthImportCursorCodec.decodeForImport(
            try HealthImportCursorCodec.encode(cursor)
        )
        XCTAssertFalse(migration.requiresFullRouteReconciliation)
    }

    func testRouteAssociationReplacementAndDeletionAffectParentWorkout() {
        let workoutID = UUID()
        let deletedWorkoutID = UUID()
        let oldRouteID = UUID()
        let replacementRouteID = UUID()
        let deletedWorkoutRouteID = UUID()

        let update = HealthRouteAssociationReconciler.applying(
            deletedRouteIDs: [oldRouteID],
            addedAssociations: [replacementRouteID: workoutID],
            deletedWorkoutIDs: [deletedWorkoutID],
            to: [oldRouteID: workoutID, deletedWorkoutRouteID: deletedWorkoutID]
        )

        XCTAssertEqual(update.routeToWorkout, [replacementRouteID: workoutID])
        XCTAssertEqual(update.affectedWorkoutIDs, [workoutID])
    }

    @MainActor
    func testRepositoryRoundTripsReplacesAndDeletesRecordsAndState() async throws {
        let (repository, _) = try makeSwiftDataRepository()
        let id = UUID()
        let first = record(id: id, latitude: 40.75, source: "First")
        let replacement = record(id: id, latitude: 51.5, source: "Replacement")
        let date = Date(timeIntervalSince1970: 500)

        try await repository.save(record: first)
        try await repository.save(record: replacement)
        try await repository.markWorkoutProcessed(id: id, end: replacement.end)
        try await repository.saveCheckpoint(Data([9]))
        try await repository.saveLastSuccessfulImport(date)

        let loaded = try await repository.loadRecords()
        let processed = try await repository.loadProcessedWorkoutIDs()
        let storedCheckpoint = try await repository.loadCheckpoint()
        let storedDate = try await repository.loadLastSuccessfulImport()
        XCTAssertEqual(loaded, [replacement])
        XCTAssertEqual(processed, [id])
        XCTAssertEqual(storedCheckpoint, Data([9]))
        XCTAssertEqual(storedDate, date)

        try await repository.removeRouteRecords(workoutIDs: [id])
        let recordsAfterRouteRemoval = try await repository.loadRecords()
        let processedAfterRouteRemoval = try await repository.loadProcessedWorkoutIDs()
        XCTAssertTrue(recordsAfterRouteRemoval.isEmpty)
        XCTAssertEqual(processedAfterRouteRemoval, [id])

        try await repository.removeWorkouts(workoutIDs: [id])
        let processedAfterWorkoutRemoval = try await repository.loadProcessedWorkoutIDs()
        XCTAssertTrue(processedAfterWorkoutRemoval.isEmpty)
    }

    @MainActor
    func testRepositoryCorruptionClearsProjectionCursorLedgerAndDate() async throws {
        let (repository, container) = try makeSwiftDataRepository()
        let context = ModelContext(container)
        let id = UUID()
        context.insert(PersistedWorkoutRouteRecord(
            workoutID: id,
            start: .distantPast,
            end: .distantFuture,
            sourceName: "Corrupt",
            routePartsData: Data("invalid".utf8)
        ))
        context.insert(PersistedWorkoutImportState(workoutID: id, end: .now))
        context.insert(PersistedHistoryState(
            checkpoint: Data([1]),
            lastSuccessfulImport: .now
        ))
        try context.save()

        let records = try await repository.loadRecords()
        let processed = try await repository.loadProcessedWorkoutIDs()
        let checkpoint = try await repository.loadCheckpoint()
        let date = try await repository.loadLastSuccessfulImport()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(processed.isEmpty)
        XCTAssertNil(checkpoint)
        XCTAssertNil(date)
    }

    @MainActor
    func testRepositoryRejectsStructurallyValidOutOfRangeGeometry() async throws {
        let (repository, container) = try makeSwiftDataRepository()
        let context = ModelContext(container)
        let id = UUID()
        let invalidParts = [[
            GeoCoordinate(latitude: 95, longitude: -73.99),
            GeoCoordinate(latitude: 96, longitude: -73.98),
        ]]
        context.insert(PersistedWorkoutRouteRecord(
            workoutID: id,
            start: .distantPast,
            end: .distantFuture,
            sourceName: "Corrupt",
            routePartsData: try JSONEncoder().encode(invalidParts)
        ))
        context.insert(PersistedWorkoutImportState(workoutID: id, end: .now))
        try context.save()

        let records = try await repository.loadRecords()
        let processed = try await repository.loadProcessedWorkoutIDs()

        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(processed.isEmpty)
    }

    @MainActor
    func testRepositoryFullResetClearsEveryRebuildableValue() async throws {
        let (repository, _) = try makeSwiftDataRepository()
        let item = record(id: UUID(), latitude: 40.75)
        try await repository.save(record: item)
        try await repository.markWorkoutProcessed(id: item.id, end: item.end)
        try await repository.saveCheckpoint(Data([2]))
        try await repository.saveLastSuccessfulImport(.now)

        try await repository.reset()

        let records = try await repository.loadRecords()
        let processed = try await repository.loadProcessedWorkoutIDs()
        let checkpoint = try await repository.loadCheckpoint()
        let date = try await repository.loadLastSuccessfulImport()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(processed.isEmpty)
        XCTAssertNil(checkpoint)
        XCTAssertNil(date)
    }

    func testLegacyCleanupDeletesOnlyExactStoreFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exact = ["coverage.store", "coverage.store-wal", "coverage.store-shm"].map {
            directory.appendingPathComponent($0)
        }
        let unrelated = directory.appendingPathComponent("keep-me")
        for file in exact + [unrelated] {
            FileManager.default.createFile(atPath: file.path, contents: Data([1]))
        }

        try LegacyCoverageStore(files: exact).removeAfterSuccessfulRebuild()

        XCTAssertTrue(exact.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testProtectedCacheUsesCompleteProtectionAndBackupExclusion() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        FileManager.default.createFile(atPath: file.path, contents: Data([1]))
        defer { try? FileManager.default.removeItem(at: file) }

        try ProtectedModelContainer.protectAndExcludeFromBackup(file)

        let resourceValues = try file.resourceValues(forKeys: [
            .fileProtectionKey,
            .isExcludedFromBackupKey,
        ])
        XCTAssertEqual(ProtectedModelContainer.cacheProtection, .complete)
        #if !targetEnvironment(simulator)
        XCTAssertEqual(resourceValues.fileProtection, .complete)
        #endif
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)
    }

    func testLifetimeOverlayContainsEveryValidPartAndWorldwideBounds() {
        let records = [
            WorkoutRouteRecord(
                id: UUID(), start: .now, end: .now, sourceName: "NYC",
                routeParts: [[
                    GeoCoordinate(latitude: 40.75, longitude: -73.99),
                    GeoCoordinate(latitude: 40.76, longitude: -73.98),
                ]]
            ),
            WorkoutRouteRecord(
                id: UUID(), start: .now, end: .now, sourceName: "London",
                routeParts: [[
                    GeoCoordinate(latitude: 51.50, longitude: -0.20),
                    GeoCoordinate(latitude: 51.51, longitude: -0.10),
                ]]
            ),
        ]

        let overlay = LifetimeRouteOverlay(records: records)
        let world = MKMapRect.world

        XCTAssertEqual(overlay.polylineCount, 2)
        XCTAssertEqual(overlay.polylines(intersecting: world).count, 2)
        XCTAssertGreaterThan(MKCoordinateRegion(overlay.boundingMapRect).span.longitudeDelta, 70)
        XCTAssertTrue(LifetimeRouteRenderer.usesDensityPass)
    }

    func testLifetimeOverlaySpatialQueryClipsToVisibleRectangle() throws {
        let nyc = record(id: UUID(), latitude: 40.75)
        let london = record(id: UUID(), latitude: 51.5, longitude: -0.15)
        let overlay = LifetimeRouteOverlay(records: [nyc, london])
        let bounds = try XCTUnwrap(nyc.geographicBounds)
        let northWest = MKMapPoint(CLLocationCoordinate2D(
            latitude: bounds.maximumLatitude + 0.01,
            longitude: bounds.minimumLongitude - 0.01
        ))
        let southEast = MKMapPoint(CLLocationCoordinate2D(
            latitude: bounds.minimumLatitude - 0.01,
            longitude: bounds.maximumLongitude + 0.01
        ))
        let rect = MKMapRect(
            x: min(northWest.x, southEast.x), y: min(northWest.y, southEast.y),
            width: abs(southEast.x - northWest.x), height: abs(southEast.y - northWest.y)
        )

        XCTAssertEqual(overlay.polylines(intersecting: rect).count, 1)
        XCTAssertGreaterThan(LifetimeRouteStyle.selectedCasingWidth, LifetimeRouteStyle.selectedRouteWidth)
    }

    func testLifetimeOverlayBoundsPathologicalLongPartWithoutExpandingEveryGridCell() {
        let record = WorkoutRouteRecord(
            id: UUID(),
            start: .now,
            end: .now,
            sourceName: "Defensive fixture",
            routeParts: [[
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 51.50, longitude: -0.12),
            ]]
        )

        let overlay = LifetimeRouteOverlay(records: [record])

        XCTAssertEqual(overlay.polylineCount, 1)
        XCTAssertEqual(overlay.polylines(intersecting: .world).count, 1)
    }

    @MainActor
    func testInitialImportPublishesMappedRouteAndExactSuccessfulDate() async throws {
        let route = workoutRoute()
        let checkpoint = Data([7])
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [route],
            processedWorkouts: [.init(id: route.id, end: route.end)],
            checkpoint: checkpoint,
            completedCount: 1,
            totalCount: 1
        )])
        let repository = TestHistoryRepository()
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitForImportToFinish(model)

        let processed = try await repository.loadProcessedWorkoutIDs()
        let storedCheckpoint = try await repository.loadCheckpoint()
        let storedDate = try await repository.loadLastSuccessfulImport()
        let authorizationCount = await source.authorizationRequestCount()
        XCTAssertEqual(model.routeRecords.map(\.id), [route.id])
        XCTAssertEqual(processed, [route.id])
        XCTAssertEqual(storedCheckpoint, checkpoint)
        XCTAssertEqual(model.lastSuccessfulImport, storedDate)
        XCTAssertEqual(authorizationCount, 1)
    }

    @MainActor
    func testRouteInvalidationRemovesMapRecordButKeepsProcessedWorkout() async throws {
        let id = UUID()
        let repository = TestHistoryRepository(
            records: [record(id: id, latitude: 40.75)],
            processedIDs: [id]
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            routeInvalidatedWorkoutIDs: [id],
            processedWorkouts: [.init(id: id, end: .now)],
            checkpoint: Data([2])
        )])
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitForImportToFinish(model)

        let processed = try await repository.loadProcessedWorkoutIDs()
        XCTAssertTrue(model.routeRecords.isEmpty)
        XCTAssertEqual(processed, [id])
    }

    @MainActor
    func testWorkoutDeletionRemovesRecordAndLedger() async throws {
        let id = UUID()
        let repository = TestHistoryRepository(
            records: [record(id: id, latitude: 40.75)],
            processedIDs: [id]
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            deletedWorkoutIDs: [id],
            checkpoint: Data([3])
        )])
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitForImportToFinish(model)

        let processed = try await repository.loadProcessedWorkoutIDs()
        XCTAssertTrue(model.routeRecords.isEmpty)
        XCTAssertTrue(processed.isEmpty)
    }

    @MainActor
    func testForegroundRefreshThrottlesFiveMinutesAndManualRefreshBypassesIt() async throws {
        let lastSuccess = Date(timeIntervalSince1970: 10_000)
        UserDefaults.standard.set(true, forKey: "didConnectAppleHealth")
        let source = TestRouteSource(batches: [WorkoutRouteBatch(routes: [])])
        let repository = TestHistoryRepository(lastSuccessfulImport: lastSuccess)
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refreshIfNeeded(now: lastSuccess.addingTimeInterval(299))
        try await Task.sleep(for: .milliseconds(30))
        let throttledCount = await source.authorizationRequestCount()
        XCTAssertEqual(throttledCount, 0)

        model.refresh()
        try await waitForImportToFinish(model)
        let manualCount = await source.authorizationRequestCount()
        XCTAssertEqual(manualCount, 1)

        let secondSource = TestRouteSource(batches: [WorkoutRouteBatch(routes: [])])
        let secondModel = makeModel(source: secondSource, repository: TestHistoryRepository(lastSuccessfulImport: lastSuccess))
        await secondModel.bootstrap()
        secondModel.refreshIfNeeded(now: lastSuccess.addingTimeInterval(301))
        try await waitForImportToFinish(secondModel)
        let automaticCount = await secondSource.authorizationRequestCount()
        XCTAssertEqual(automaticCount, 1)
    }

    @MainActor
    func testCancellationPreventsOldAuthorizationTaskFromPublishing() async throws {
        let source = SuspendingRouteSource()
        let repository = TestHistoryRepository()
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await Task.sleep(for: .milliseconds(30))
        model.cancelImport()
        await source.resumeAuthorization()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.importPhase, .idle)
        XCTAssertTrue(model.routeRecords.isEmpty)
        let successfulDate = try await repository.loadLastSuccessfulImport()
        XCTAssertNil(successfulDate)
    }

    @MainActor
    func testLegacyStoreIsRetainedOnFailureAndDeletedAfterSuccessfulNonemptyImport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyFile = directory.appendingPathComponent("coverage.store")
        FileManager.default.createFile(atPath: legacyFile.path, contents: Data([1]))
        let legacy = LegacyCoverageStore(files: [legacyFile])

        UserDefaults.standard.set(true, forKey: "didConnectAppleHealth")
        let failing = TestRouteSource(batches: [], failure: TestError.failed)
        let failedModel = makeModel(
            source: failing,
            repository: TestHistoryRepository(),
            legacyStore: legacy
        )
        await failedModel.bootstrap()
        failedModel.refresh()
        try await waitForImportToFinish(failedModel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFile.path))

        UserDefaults.standard.removeObject(forKey: "didBeginLifetimeMapMigration")
        let route = workoutRoute()
        let successful = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [route],
            processedWorkouts: [.init(id: route.id, end: route.end)],
            checkpoint: Data([1])
        )])
        let successfulModel = makeModel(
            source: successful,
            repository: TestHistoryRepository(),
            legacyStore: legacy
        )
        await successfulModel.bootstrap()
        successfulModel.refresh()
        try await waitForImportToFinish(successfulModel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFile.path))
    }

    @MainActor
    private func makeSwiftDataRepository() throws -> (SwiftDataWalkHistoryRepository, ModelContainer) {
        let schema = Schema([
            PersistedWorkoutRouteRecord.self,
            PersistedHistoryState.self,
            PersistedWorkoutImportState.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return (SwiftDataWalkHistoryRepository(modelContainer: container), container)
    }

    @MainActor
    private func makeModel(
        source: any WorkoutRouteSource,
        repository: any WalkHistoryRepository,
        legacyStore: LegacyCoverageStore = LegacyCoverageStore(files: [])
    ) -> AppModel {
        AppModel(dependencies: AppDependencies(
            routeSource: source,
            repository: repository,
            routeProcessor: RouteProcessor(),
            legacyStore: legacyStore,
            protectStorage: {}
        ))
    }

    @MainActor
    private func waitForImportToFinish(_ model: AppModel) async throws {
        for _ in 0 ..< 200 {
            if !model.importPhase.isWorking, model.importPhase != .idle { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Import did not finish")
    }

    private func workoutRoute(id: UUID = UUID()) -> WorkoutRoute {
        let start = Date(timeIntervalSince1970: 1_000)
        return WorkoutRoute(
            id: id,
            start: start,
            end: start.addingTimeInterval(20),
            sourceName: "Apple Watch",
            points: [
                RoutePoint(
                    coordinate: GeoCoordinate(latitude: 40.7500, longitude: -73.9900),
                    timestamp: start,
                    horizontalAccuracy: 5
                ),
                RoutePoint(
                    coordinate: GeoCoordinate(latitude: 40.7501, longitude: -73.9900),
                    timestamp: start.addingTimeInterval(10),
                    horizontalAccuracy: 5
                ),
            ]
        )
    }

    private func record(
        id: UUID,
        latitude: Double,
        longitude: Double = -73.99,
        source: String = "Test"
    ) -> WorkoutRouteRecord {
        WorkoutRouteRecord(
            id: id,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200),
            sourceName: source,
            routeParts: [[
                GeoCoordinate(latitude: latitude, longitude: longitude),
                GeoCoordinate(latitude: latitude + 0.001, longitude: longitude + 0.001),
            ]]
        )
    }
}

private enum TestError: Error { case failed }

private actor TestRouteSource: WorkoutRouteSource {
    private let batches: [WorkoutRouteBatch]
    private let failure: (any Error)?
    private var authorizationCount = 0

    init(batches: [WorkoutRouteBatch], failure: (any Error)? = nil) {
        self.batches = batches
        self.failure = failure
    }

    func requestReadAuthorization() async throws {
        authorizationCount += 1
    }

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        let batches = batches
        let failure = failure
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for batch in batches {
                continuation.yield(batch)
            }
            continuation.finish()
        }
    }

    func authorizationRequestCount() -> Int { authorizationCount }
}

private actor SuspendingRouteSource: WorkoutRouteSource {
    private var continuation: CheckedContinuation<Void, Never>?

    func requestReadAuthorization() async throws {
        await withCheckedContinuation { continuation = $0 }
    }

    func resumeAuthorization() {
        continuation?.resume()
        continuation = nil
    }

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor TestHistoryRepository: WalkHistoryRepository {
    private var records: [UUID: WorkoutRouteRecord]
    private var processedIDs: Set<UUID>
    private var checkpoint: Data?
    private var lastSuccessfulImport: Date?

    init(
        records: [WorkoutRouteRecord] = [],
        processedIDs: Set<UUID> = [],
        checkpoint: Data? = nil,
        lastSuccessfulImport: Date? = nil
    ) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        self.processedIDs = processedIDs
        self.checkpoint = checkpoint
        self.lastSuccessfulImport = lastSuccessfulImport
    }

    func loadRecords() async throws -> [WorkoutRouteRecord] {
        records.values.sorted { $0.start > $1.start }
    }

    func save(record: WorkoutRouteRecord) async throws { records[record.id] = record }

    func removeRouteRecords(workoutIDs: [UUID]) async throws {
        workoutIDs.forEach { records.removeValue(forKey: $0) }
    }

    func removeWorkouts(workoutIDs: [UUID]) async throws {
        workoutIDs.forEach {
            records.removeValue(forKey: $0)
            processedIDs.remove($0)
        }
    }

    func loadProcessedWorkoutIDs() async throws -> Set<UUID> { processedIDs }
    func markWorkoutProcessed(id: UUID, end: Date) async throws { processedIDs.insert(id) }
    func loadCheckpoint() async throws -> Data? { checkpoint }
    func saveCheckpoint(_ checkpoint: Data?) async throws { self.checkpoint = checkpoint }
    func loadLastSuccessfulImport() async throws -> Date? { lastSuccessfulImport }
    func saveLastSuccessfulImport(_ date: Date) async throws { lastSuccessfulImport = date }

    func reset() async throws {
        records = [:]
        processedIDs = []
        checkpoint = nil
        lastSuccessfulImport = nil
    }
}
