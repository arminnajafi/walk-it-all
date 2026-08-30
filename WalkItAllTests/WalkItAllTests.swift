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
        UserDefaults.standard.removeObject(forKey: "didExplainLiveTrail")
    }

    func testHealthCursorRoundTripsBothAnchorsAndAssociations() throws {
        let routeID = UUID()
        let workoutID = UUID()
        let cursor = HealthImportCursor(
            version: HealthImportCursor.currentVersion,
            workoutAnchorData: Data([1, 2]),
            routeAnchorData: Data([3, 4]),
            routeToWorkout: [routeID: workoutID]
        )

        let decoded = HealthImportCursorCodec.decode(try HealthImportCursorCodec.encode(cursor))

        XCTAssertEqual(decoded.version, HealthImportCursor.currentVersion)
        XCTAssertEqual(decoded.workoutAnchorData, Data([1, 2]))
        XCTAssertEqual(decoded.routeAnchorData, Data([3, 4]))
        XCTAssertEqual(decoded.routeToWorkout[routeID], workoutID)
    }

    func testLegacyWorkoutAnchorResetsForExpandedActivityScope() throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        let legacy = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )

        let migration = HealthImportCursorCodec.decodeForImport(legacy)

        XCTAssertNil(migration.cursor.workoutAnchorData)
        XCTAssertNil(migration.cursor.routeAnchorData)
        XCTAssertTrue(migration.requiresFullRouteReconciliation)
    }

    func testVersionTwoCursorResetsWorkoutScopeButPreservesRouteAnchor() throws {
        let routeID = UUID()
        let workoutID = UUID()
        let oldCursor = HealthImportCursor(
            version: 2,
            workoutAnchorData: Data([1]),
            routeAnchorData: Data([2]),
            routeToWorkout: [routeID: workoutID]
        )

        let migration = HealthImportCursorCodec.decodeForImport(
            try HealthImportCursorCodec.encode(oldCursor)
        )

        XCTAssertNil(migration.cursor.workoutAnchorData)
        XCTAssertEqual(migration.cursor.routeAnchorData, Data([2]))
        XCTAssertTrue(migration.cursor.routeToWorkout.isEmpty)
        XCTAssertTrue(migration.requiresFullRouteReconciliation)
    }

    func testHealthActivityMapperSupportsEveryMVPActivity() {
        XCTAssertEqual(HealthWorkoutActivityMapper.kind(for: .walking), .walking)
        XCTAssertEqual(HealthWorkoutActivityMapper.kind(for: .hiking), .hiking)
        XCTAssertEqual(HealthWorkoutActivityMapper.kind(for: .running), .running)
        XCTAssertEqual(HealthWorkoutActivityMapper.kind(for: .cycling), .cycling)
        XCTAssertNil(HealthWorkoutActivityMapper.kind(for: .swimming))
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

    func testFutureHealthCursorRequestsSafeRouteReconciliation() throws {
        let cursor = HealthImportCursor(
            version: HealthImportCursor.currentVersion + 1,
            workoutAnchorData: Data([1]),
            routeAnchorData: Data([2])
        )

        let migration = HealthImportCursorCodec.decodeForImport(
            try HealthImportCursorCodec.encode(cursor)
        )

        XCTAssertTrue(migration.requiresFullRouteReconciliation)
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

    func testUnresolvedRouteChangeInvalidatesCachedWorkoutWithoutDeletingWorkout() {
        let unresolved = UUID()
        let resolved = UUID()
        let deleted = UUID()

        let invalidations = HealthRouteAssociationReconciler.unresolvedInvalidations(
            affectedWorkoutIDs: [unresolved, resolved, deleted],
            candidateWorkoutIDs: [resolved],
            deletedWorkoutIDs: [deleted]
        )

        XCTAssertEqual(invalidations, [unresolved])
    }

    @MainActor
    func testRepositoryRoundTripsReplacesAndDeletesRecordsAndState() async throws {
        let (repository, _) = try makeSwiftDataRepository()
        let id = UUID()
        let first = record(id: id, latitude: 40.75, source: "First")
        let replacement = record(
            id: id,
            latitude: 51.5,
            source: "Replacement",
            activityKind: .cycling
        )
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
        XCTAssertEqual(loaded.first?.activityKind, .cycling)
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
    func testRepositoryDecodesLegacyGeometryPayloadAsWalking() async throws {
        let (repository, container) = try makeSwiftDataRepository()
        let context = ModelContext(container)
        let id = UUID()
        let legacyParts = [[
            GeoCoordinate(latitude: 40.75, longitude: -73.99),
            GeoCoordinate(latitude: 40.751, longitude: -73.989),
        ]]
        context.insert(PersistedWorkoutRouteRecord(
            workoutID: id,
            start: .distantPast,
            end: .distantFuture,
            sourceName: "Legacy",
            routePartsData: try JSONEncoder().encode(legacyParts)
        ))
        try context.save()

        let loaded = try await repository.loadRecords()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, id)
        XCTAssertEqual(loaded.first?.activityKind, .walking)
        XCTAssertEqual(loaded.first?.routeParts, legacyParts)
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

    func testExternalRouteTreeIsProtectedAndExcludedFromBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        let route = nested.appendingPathComponent("route")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: route.path, contents: Data([1]))
        defer { try? FileManager.default.removeItem(at: root) }

        try ProtectedModelContainer.protectTreeAndExcludeFromBackup(root)

        for url in [root, nested, route] {
            let values = try url.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey,
            ])
            #if !targetEnvironment(simulator)
            XCTAssertEqual(values.fileProtection, .complete)
            #endif
            XCTAssertEqual(values.isExcludedFromBackup, true)
        }
    }

    func testProtectedHistoryDefersStoreCreationUntilDataIsAvailable() async throws {
        let probe = FactoryInvocationProbe()
        let repository = ProtectedWalkHistoryRepository(
            isProtectedDataAvailable: { false },
            factory: {
                probe.recordInvocation()
                return TestHistoryRepository()
            }
        )

        do {
            _ = try await repository.loadRecords()
            XCTFail("Locked protected data should prevent history-store creation")
        } catch ProtectedHistoryError.dataUnavailable {
            // Expected.
        }

        XCTAssertEqual(probe.invocationCount, 0)
    }

    func testProtectedHistoryCreatesAndReusesOneRepositoryAfterUnlock() async throws {
        let probe = FactoryInvocationProbe()
        let repository = ProtectedWalkHistoryRepository(
            isProtectedDataAvailable: { true },
            factory: {
                probe.recordInvocation()
                return TestHistoryRepository()
            }
        )

        _ = try await repository.loadRecords()
        _ = try await repository.loadCheckpoint()

        XCTAssertEqual(probe.invocationCount, 1)
    }

    func testLiveTrailRepositoryRoundTripsAndDeletesExactProtectedFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("session.json")
        let unrelated = directory.appendingPathComponent("keep-me")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProtectedLiveTrailRepository(fileURL: file)
        let session = liveTrailSession(state: .active)

        try await repository.save(session)
        FileManager.default.createFile(atPath: unrelated.path, contents: Data([1]))

        let loaded = try await repository.load()
        XCTAssertEqual(loaded, session)
        let values = try file.resourceValues(forKeys: [
            .fileProtectionKey,
            .isExcludedFromBackupKey,
        ])
        XCTAssertEqual(
            ProtectedLiveTrailRepository.protection,
            .completeUntilFirstUserAuthentication
        )
        #if !targetEnvironment(simulator)
        XCTAssertEqual(values.fileProtection, .completeUntilFirstUserAuthentication)
        #endif
        XCTAssertEqual(values.isExcludedFromBackup, true)

        try await repository.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testCorruptLiveTrailFileIsDiscardedWithoutTouchingHealthHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        try Data("not-json".utf8).write(to: file)
        let repository = ProtectedLiveTrailRepository(fileURL: file)

        let loaded = try await repository.load()
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testStructurallyInvalidLiveTrailFileIsDiscarded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        let start = Date()
        let invalid = LiveTrailSession(
            state: .active,
            start: start,
            routeParts: [[RoutePoint(
                coordinate: GeoCoordinate(latitude: 40.75, longitude: -73.99),
                timestamp: start,
                horizontalAccuracy: 75
            )]],
            lastUpdate: start
        )
        try JSONEncoder().encode(invalid).write(to: file)
        let repository = ProtectedLiveTrailRepository(fileURL: file)

        let loaded = try await repository.load()

        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testFinishedLiveTrailRemainsIndependentWhenHealthHistoryAlreadyExists() async throws {
        let routeRecord = record(id: UUID(), latitude: 40.75)
        let liveRepository = TestLiveTrailRepository(
            session: liveTrailSession(state: .finished)
        )
        let model = makeModel(
            source: TestRouteSource(batches: []),
            repository: TestHistoryRepository(records: [routeRecord]),
            liveTrailRepository: liveRepository
        )

        await model.bootstrap()

        XCTAssertEqual(model.liveTrail.session?.state, .finished)
        let stored = await liveRepository.load()
        XCTAssertEqual(stored?.state, .finished)
    }

    @MainActor
    func testLiveTrailRecoversBeforeLockedHistoryFailure() async throws {
        let now = Date()
        let active = LiveTrailSession(
            state: .active,
            start: now.addingTimeInterval(-60),
            routeParts: [],
            lastUpdate: now
        )
        let model = makeModel(
            source: TestRouteSource(batches: []),
            repository: FailingHistoryRepository(),
            liveTrailRepository: TestLiveTrailRepository(session: active)
        )

        await model.bootstrap()

        XCTAssertEqual(model.liveTrail.session?.id, active.id)
        XCTAssertTrue(model.liveTrail.hasInProgressSession)
        guard case .failed = model.launchState else {
            return XCTFail("Permanent history should remain unavailable while locked")
        }
    }

    @MainActor
    func testFinishedLiveTrailDoesNotExpireAndClearDeletesIt() async throws {
        let session = liveTrailSession(state: .finished)
        let repository = TestLiveTrailRepository(session: session)
        let controller = LiveTrailController(repository: repository)

        await controller.bootstrap(now: session.start.addingTimeInterval(30 * 24 * 60 * 60))

        XCTAssertEqual(controller.session, session)
        await controller.clear()
        XCTAssertNil(controller.session)
        let stored = await repository.load()
        XCTAssertNil(stored)
    }

    @MainActor
    func testStartNewDoesNotDiscardFinishedTrailWhenLocationIsDenied() async throws {
        let session = liveTrailSession(state: .finished)
        let repository = TestLiveTrailRepository(session: session)
        let locationManager = TestLocationManager(authorizationStatus: .denied)
        let controller = LiveTrailController(
            repository: repository,
            locationManager: locationManager
        )
        await controller.bootstrap(now: session.end ?? session.lastUpdate)

        await controller.startNew(now: session.lastUpdate.addingTimeInterval(1))

        XCTAssertEqual(controller.session, session)
        let stored = await repository.load()
        XCTAssertEqual(stored, session)
        XCTAssertNotNil(controller.issueMessage)
    }

    @MainActor
    func testRecoveredActiveTrailAutomaticallyFinishesAtTwelveHours() async throws {
        let start = Date().addingTimeInterval(-(13 * 60 * 60))
        let active = LiveTrailSession(
            state: .active,
            start: start,
            routeParts: [],
            lastUpdate: start.addingTimeInterval(100)
        )
        let repository = TestLiveTrailRepository(session: active)
        let controller = LiveTrailController(repository: repository)

        await controller.bootstrap(now: Date())

        XCTAssertEqual(controller.session?.state, .finished)
        XCTAssertEqual(
            controller.session?.end,
            start.addingTimeInterval(LiveTrailController.maximumSessionDuration)
        )
        let stored = await repository.load()
        XCTAssertEqual(stored?.state, .finished)
    }

    @MainActor
    func testRecoveredPausedTrailAutomaticallyFinishesAtTwelveHours() async throws {
        let start = Date().addingTimeInterval(-(13 * 60 * 60))
        let paused = LiveTrailSession(
            state: .paused,
            start: start,
            routeParts: [],
            lastUpdate: start.addingTimeInterval(100)
        )
        let repository = TestLiveTrailRepository(session: paused)
        let controller = LiveTrailController(repository: repository)

        await controller.bootstrap(now: Date())

        XCTAssertEqual(controller.session?.state, .finished)
        XCTAssertEqual(
            controller.session?.end,
            start.addingTimeInterval(100),
            "Finishing a paused trail must not include unattended paused time"
        )
        let stored = await repository.load()
        XCTAssertEqual(stored?.state, .finished)
    }

    @MainActor
    func testRepeatedBootstrapDoesNotOverwriteRecoveredLiveTrail() async throws {
        let now = Date()
        let paused = LiveTrailSession(
            state: .paused,
            start: now.addingTimeInterval(-300),
            routeParts: [],
            lastUpdate: now.addingTimeInterval(-30)
        )
        let repository = TestLiveTrailRepository(session: paused)
        let controller = LiveTrailController(repository: repository)

        await controller.bootstrap(now: now)
        await repository.save(LiveTrailSession(
            state: .finished,
            start: now.addingTimeInterval(-300),
            end: now,
            lastUpdate: now
        ))
        await controller.bootstrap(now: now.addingTimeInterval(1))

        XCTAssertEqual(controller.session?.id, paused.id)
        XCTAssertEqual(controller.session?.state, .paused)
    }

    @MainActor
    func testFinishingPausedTrailUsesPauseTimeAndIsFinal() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let pauseDate = start.addingTimeInterval(600)
        let paused = LiveTrailSession(
            state: .paused,
            start: start,
            routeParts: [],
            lastUpdate: pauseDate
        )
        let repository = TestLiveTrailRepository(session: paused)
        let controller = LiveTrailController(repository: repository)
        await controller.bootstrap(now: pauseDate)

        await controller.finish(at: start.addingTimeInterval(3_600))

        XCTAssertEqual(controller.session?.state, .finished)
        XCTAssertEqual(controller.session?.end, pauseDate)
        let stored = await repository.load()
        XCTAssertEqual(stored?.end, pauseDate)
    }

    @MainActor
    func testFinishKeepsTerminalRecoveryCheckpointIfCompactedSaveFails() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let paused = LiveTrailSession(
            state: .paused,
            start: start,
            routeParts: [],
            lastUpdate: start.addingTimeInterval(600)
        )
        let repository = FailingLiveTrailRepository(
            session: paused,
            failingSaveCalls: [2]
        )
        let controller = LiveTrailController(repository: repository)
        await controller.bootstrap(now: paused.lastUpdate)

        await controller.finish(at: start.addingTimeInterval(3_600))

        let stored = try await repository.load()
        XCTAssertEqual(stored?.state, .finished)
        XCTAssertEqual(stored?.end, paused.lastUpdate)
        XCTAssertNil(controller.issueMessage)
    }

    @MainActor
    func testFinishDeletesStaleActiveCheckpointWhenTerminalSavesFail() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let active = LiveTrailSession(
            state: .active,
            start: start,
            routeParts: [],
            lastUpdate: start.addingTimeInterval(600)
        )
        let repository = FailingLiveTrailRepository(
            session: active,
            failingSaveCalls: [1, 2]
        )
        let controller = LiveTrailController(repository: repository)
        await controller.bootstrap(now: active.lastUpdate)

        await controller.finish(at: start.addingTimeInterval(900))

        XCTAssertEqual(controller.session?.state, .finished)
        let stored = try await repository.load()
        XCTAssertNil(stored)
        XCTAssertNotNil(controller.issueMessage)
    }

    @MainActor
    func testFinishedTrailRejectsResumeAndRepeatedFinish() async throws {
        let finished = liveTrailSession(state: .finished)
        let repository = TestLiveTrailRepository(session: finished)
        let controller = LiveTrailController(repository: repository)
        await controller.bootstrap(now: finished.lastUpdate)

        controller.resume(now: finished.lastUpdate.addingTimeInterval(10))
        await controller.finish(at: finished.lastUpdate.addingTimeInterval(20))

        let stored = await repository.load()
        XCTAssertEqual(controller.session, finished)
        XCTAssertEqual(stored, finished)
    }

    @MainActor
    func testFinishingLiveTrailDoesNotTriggerHealthRefresh() async throws {
        let source = TestRouteSource(batches: [])
        let paused = liveTrailSession(state: .paused)
        let model = makeModel(
            source: source,
            repository: TestHistoryRepository(),
            liveTrailRepository: TestLiveTrailRepository(session: paused)
        )
        await model.bootstrap()

        model.finishLiveTrail()
        for _ in 0 ..< 100 where !model.liveTrail.isFinished {
            try await Task.sleep(for: .milliseconds(10))
        }

        let authorizationCount = await source.authorizationRequestCount()
        XCTAssertTrue(model.liveTrail.isFinished)
        XCTAssertEqual(authorizationCount, 0)
    }

    @MainActor
    func testFullHealthRebuildIsUnavailableDuringRecoveredActiveTrail() async throws {
        let source = TestRouteSource(batches: [WorkoutRouteBatch(routes: [])])
        let active = LiveTrailSession(
            state: .active,
            start: Date(),
            routeParts: [],
            lastUpdate: Date()
        )
        let model = makeModel(
            source: source,
            repository: TestHistoryRepository(),
            liveTrailRepository: TestLiveTrailRepository(session: active)
        )
        await model.bootstrap()

        model.rebuildFromHealth()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(
            model.liveTrail.hasInProgressSession,
            "A recovered active trail may safely pause if simulator location delivery is unavailable"
        )
        let authorizationCount = await source.authorizationRequestCount()
        XCTAssertEqual(authorizationCount, 0)
    }

    @MainActor
    func testFullHealthRebuildIsUnavailableDuringRecoveredPausedTrail() async throws {
        let source = TestRouteSource(batches: [WorkoutRouteBatch(routes: [])])
        let paused = LiveTrailSession(
            state: .paused,
            start: Date(),
            routeParts: [],
            lastUpdate: Date()
        )
        let model = makeModel(
            source: source,
            repository: TestHistoryRepository(),
            liveTrailRepository: TestLiveTrailRepository(session: paused)
        )
        await model.bootstrap()

        model.rebuildFromHealth()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(model.liveTrail.isPaused)
        let authorizationCount = await source.authorizationRequestCount()
        XCTAssertEqual(authorizationCount, 0)
    }

    func testLifetimeSnapshotContainsEveryValidPartAndWorldwideBounds() {
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

        let snapshot = LifetimeRouteSnapshot(records: records)

        XCTAssertEqual(snapshot.overlays.count, 2)
        XCTAssertEqual(snapshot.polylineCount, 2)
        XCTAssertGreaterThan(MKCoordinateRegion(snapshot.boundingMapRect).span.longitudeDelta, 70)
        XCTAssertTrue(LifetimeRouteRenderer.usesNativeSpatialCulling)
        XCTAssertLessThan(LifetimeRouteRenderer.strokeAlpha, 1)
    }

    @MainActor
    func testSelectingWorkoutPreservesImmutableHistoryOverlays() async throws {
        let workout = record(id: UUID(), latitude: 40.75)
        let mapView = MKMapView()
        let coordinator = LifetimeMapView.Coordinator()
        let viewport = MapViewportCommand(revision: 0, target: .manhattan)

        coordinator.update(
            mapView: mapView,
            records: [workout],
            selectedWorkout: nil,
            routeRevision: 1,
            liveTrailSession: nil,
            liveTrailRevision: 0,
            showsUserLocation: false,
            appIsActive: true,
            viewportCommand: viewport,
            bottomInset: 100,
            onUserTrackingModeChange: { _ in },
            initial: true
        )

        for _ in 0 ..< 50 where !mapView.overlays.contains(where: {
            $0 is LifetimeWorkoutRouteOverlay
        }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let originalHistory = try XCTUnwrap(
            mapView.overlays.first { $0 is LifetimeWorkoutRouteOverlay }
                as? LifetimeWorkoutRouteOverlay
        )

        coordinator.update(
            mapView: mapView,
            records: [workout],
            selectedWorkout: workout,
            routeRevision: 1,
            liveTrailSession: nil,
            liveTrailRevision: 0,
            showsUserLocation: false,
            appIsActive: true,
            viewportCommand: MapViewportCommand(revision: 1, target: .workout(workout.id)),
            bottomInset: 100,
            onUserTrackingModeChange: { _ in },
            initial: false
        )

        XCTAssertTrue(mapView.overlays.contains { $0 === originalHistory })
        XCTAssertEqual(
            mapView.overlays.filter { $0 is LifetimeWorkoutRouteOverlay }.count,
            1
        )
        XCTAssertEqual(mapView.overlays.count, 3, "Selection adds only its casing and route")
    }

    func testLifetimeSnapshotKeepsWorkoutBoundsSeparateForNativeCulling() throws {
        let nyc = record(id: UUID(), latitude: 40.75)
        let london = record(id: UUID(), latitude: 51.5, longitude: -0.15)
        let snapshot = LifetimeRouteSnapshot(records: [nyc, london])
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

        XCTAssertEqual(snapshot.overlays.filter { $0.boundingMapRect.intersects(rect) }.count, 1)
        XCTAssertGreaterThan(LifetimeRouteStyle.selectedCasingWidth, LifetimeRouteStyle.selectedRouteWidth)
    }

    func testLifetimeSnapshotAcceptsAPathologicalLongPartWithoutBuildingAGrid() {
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

        let snapshot = LifetimeRouteSnapshot(records: [record])

        XCTAssertEqual(snapshot.overlays.count, 1)
        XCTAssertEqual(snapshot.polylineCount, 1)
        XCTAssertTrue(snapshot.overlays[0].boundingMapRect.intersects(.world))
    }

    func testLifetimeSnapshotBuildsLargeHistoryAsIndependentlyBoundedOverlays() {
        let records = (0 ..< 1_500).map { index in
            record(
                id: UUID(),
                latitude: 40.60 + Double(index % 300) * 0.001,
                longitude: -74.05 + Double(index % 200) * 0.001
            )
        }

        let snapshot = LifetimeRouteSnapshot(records: records)

        XCTAssertEqual(snapshot.overlays.count, 1_500)
        XCTAssertEqual(snapshot.polylineCount, 1_500)
        XCTAssertTrue(snapshot.overlays.allSatisfy { !$0.boundingMapRect.isNull })
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
    func testAuthoritativeReconciliationRemovesOnlyStaleSupportedWorkouts() async throws {
        let retainedID = UUID()
        let staleID = UUID()
        let repository = TestHistoryRepository(
            records: [
                record(id: retainedID, latitude: 40.75),
                record(id: staleID, latitude: 40.76),
            ],
            processedIDs: [retainedID, staleID]
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            authoritativeWorkoutIDs: [retainedID],
            checkpoint: Data([4])
        )])
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitForImportToFinish(model)

        let processed = try await repository.loadProcessedWorkoutIDs()
        let checkpoint = try await repository.loadCheckpoint()
        XCTAssertEqual(model.routeRecords.map(\.id), [retainedID])
        XCTAssertEqual(processed, [retainedID])
        XCTAssertEqual(checkpoint, Data([4]))
    }

    @MainActor
    func testZeroReadableScopeKeepsExistingCacheAndOldCheckpoint() async throws {
        let id = UUID()
        let oldCheckpoint = Data([3])
        let repository = TestHistoryRepository(
            records: [record(id: id, latitude: 40.75)],
            processedIDs: [id],
            checkpoint: oldCheckpoint
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            authoritativeWorkoutIDs: [],
            checkpoint: Data([9])
        )])
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitForImportToFinish(model)

        let processed = try await repository.loadProcessedWorkoutIDs()
        let checkpoint = try await repository.loadCheckpoint()
        XCTAssertEqual(model.routeRecords.map(\.id), [id])
        XCTAssertEqual(processed, [id])
        XCTAssertEqual(checkpoint, oldCheckpoint)
        guard case .failed = model.importPhase else {
            return XCTFail("An unreadable Health scope should ask for attention")
        }
    }

    @MainActor
    func testLocationButtonRecentersWithoutEnablingHeadingFollow() async {
        let model = makeModel(
            source: TestRouteSource(batches: []),
            repository: TestHistoryRepository()
        )

        XCTAssertEqual(model.mapUserTrackingMode, .free)
        model.showUserLocation()
        XCTAssertEqual(model.mapUserTrackingMode, .follow)
        XCTAssertEqual(model.mapViewportCommand.target, .userLocation)

        let firstRevision = model.mapViewportCommand.revision
        model.mapUserTrackingDidChange(.follow)
        model.showUserLocation()
        XCTAssertEqual(model.mapUserTrackingMode, .follow)
        XCTAssertEqual(model.mapViewportCommand.target, .userLocation)
        XCTAssertGreaterThan(model.mapViewportCommand.revision, firstRevision)

        model.mapUserTrackingDidChange(.free)
        XCTAssertEqual(model.mapUserTrackingMode, .free)
    }

    func testHeadingConeRotatesIndependentlyFromMapCamera() {
        XCTAssertEqual(
            HeadingConeGeometry.rotationRadians(deviceHeading: 90, mapHeading: 0),
            .pi / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            HeadingConeGeometry.rotationRadians(deviceHeading: 90, mapHeading: 30),
            .pi / 3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            HeadingConeGeometry.rotationRadians(deviceHeading: 350, mapHeading: 0),
            -.pi / 18,
            accuracy: 0.0001
        )
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
    func testCancellationBeforeStreamCompletionDoesNotPublishCheckpoint() async throws {
        let route = workoutRoute()
        let oldCheckpoint = Data([1])
        let source = SuspendedAfterBatchRouteSource(batch: WorkoutRouteBatch(
            routes: [route],
            processedWorkouts: [.init(id: route.id, end: route.end)],
            checkpoint: Data([9])
        ))
        let repository = TestHistoryRepository(checkpoint: oldCheckpoint)
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        for _ in 0 ..< 100 where !(await source.didYieldBatch()) {
            try await Task.sleep(for: .milliseconds(10))
        }
        model.cancelImport()
        try await Task.sleep(for: .milliseconds(50))

        let checkpoint = try await repository.loadCheckpoint()
        XCTAssertEqual(checkpoint, oldCheckpoint)
        XCTAssertEqual(model.importPhase, .idle)
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
        liveTrailRepository: any LiveTrailRepository = TestLiveTrailRepository()
    ) -> AppModel {
        AppModel(dependencies: AppDependencies(
            routeSource: source,
            repository: repository,
            routeProcessor: RouteProcessor(),
            liveTrailRepository: liveTrailRepository,
            liveTrailProcessor: LiveTrailProcessor(),
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
        source: String = "Test",
        activityKind: RouteActivityKind = .walking
    ) -> WorkoutRouteRecord {
        WorkoutRouteRecord(
            id: id,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200),
            sourceName: source,
            activityKind: activityKind,
            routeParts: [[
                GeoCoordinate(latitude: latitude, longitude: longitude),
                GeoCoordinate(latitude: latitude + 0.001, longitude: longitude + 0.001),
            ]]
        )
    }

    private func liveTrailSession(state: LiveTrailState) -> LiveTrailSession {
        let start = Date(timeIntervalSince1970: 100)
        return LiveTrailSession(
            state: state,
            start: start,
            end: state == .finished ? start.addingTimeInterval(100) : nil,
            routeParts: [[
                RoutePoint(
                    coordinate: GeoCoordinate(latitude: 40.75, longitude: -73.99),
                    timestamp: start,
                    horizontalAccuracy: 5
                ),
                RoutePoint(
                    coordinate: GeoCoordinate(latitude: 40.751, longitude: -73.99),
                    timestamp: start.addingTimeInterval(100),
                    horizontalAccuracy: 5
                ),
            ]],
            lastUpdate: start.addingTimeInterval(100)
        )
    }
}

private final class FactoryInvocationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.withLock { count }
    }

    func recordInvocation() {
        lock.withLock { count += 1 }
    }
}

private final class TestLocationManager: CLLocationManager {
    private let testAuthorizationStatus: CLAuthorizationStatus

    init(authorizationStatus: CLAuthorizationStatus) {
        testAuthorizationStatus = authorizationStatus
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus {
        testAuthorizationStatus
    }
}

private actor FailingHistoryRepository: WalkHistoryRepository {
    func loadRecords() async throws -> [WorkoutRouteRecord] { throw ProtectedHistoryError.dataUnavailable }
    func save(record: WorkoutRouteRecord) async throws { throw ProtectedHistoryError.dataUnavailable }
    func removeRouteRecords(workoutIDs: [UUID]) async throws { throw ProtectedHistoryError.dataUnavailable }
    func removeWorkouts(workoutIDs: [UUID]) async throws { throw ProtectedHistoryError.dataUnavailable }
    func loadProcessedWorkoutIDs() async throws -> Set<UUID> { throw ProtectedHistoryError.dataUnavailable }
    func markWorkoutProcessed(id: UUID, end: Date) async throws { throw ProtectedHistoryError.dataUnavailable }
    func loadCheckpoint() async throws -> Data? { throw ProtectedHistoryError.dataUnavailable }
    func saveCheckpoint(_ checkpoint: Data?) async throws { throw ProtectedHistoryError.dataUnavailable }
    func loadLastSuccessfulImport() async throws -> Date? { throw ProtectedHistoryError.dataUnavailable }
    func saveLastSuccessfulImport(_ date: Date) async throws { throw ProtectedHistoryError.dataUnavailable }
    func reset() async throws { throw ProtectedHistoryError.dataUnavailable }
}

private actor TestLiveTrailRepository: LiveTrailRepository {
    private var session: LiveTrailSession?

    init(session: LiveTrailSession? = nil) {
        self.session = session
    }

    func load() -> LiveTrailSession? { session }
    func save(_ session: LiveTrailSession) { self.session = session }
    func delete() { session = nil }
}

private actor FailingLiveTrailRepository: LiveTrailRepository {
    private enum Failure: Error { case save }

    private var session: LiveTrailSession?
    private var saveCallCount = 0
    private let failingSaveCalls: Set<Int>

    init(session: LiveTrailSession?, failingSaveCalls: Set<Int>) {
        self.session = session
        self.failingSaveCalls = failingSaveCalls
    }

    func load() throws -> LiveTrailSession? { session }

    func save(_ session: LiveTrailSession) throws {
        saveCallCount += 1
        if failingSaveCalls.contains(saveCallCount) {
            throw Failure.save
        }
        self.session = session
    }

    func delete() { session = nil }
}

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

private actor SuspendedAfterBatchRouteSource: WorkoutRouteSource {
    private let batch: WorkoutRouteBatch
    private var yielded = false

    init(batch: WorkoutRouteBatch) {
        self.batch = batch
    }

    func requestReadAuthorization() async throws {}

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        let batch = batch
        yielded = true
        return AsyncThrowingStream { continuation in
            continuation.yield(batch)
            // Deliberately remain open. Cancelling the consumer must end the
            // import without publishing this batch's deferred checkpoint.
        }
    }

    func didYieldBatch() -> Bool { yielded }
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
