import XCTest
import SwiftData
@preconcurrency import HealthKit
import MapKit
import WalkItAllCore
@testable import WalkItAll

final class WalkItAllTests: XCTestCase {
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

        let decoded = HealthImportCursorCodec.decode(legacy)
        let migration = HealthImportCursorCodec.decodeForImport(legacy)

        XCTAssertEqual(decoded.version, HealthImportCursor.currentVersion)
        XCTAssertEqual(decoded.workoutAnchorData, legacy)
        XCTAssertNil(decoded.routeAnchorData)
        XCTAssertTrue(decoded.routeToWorkout.isEmpty)
        XCTAssertTrue(migration.requiresFullRouteReconciliation)
    }

    func testCorruptHealthCursorFallsBackToRebuildableEmptyState() {
        let decoded = HealthImportCursorCodec.decode(Data("not a cursor".utf8))
        let migration = HealthImportCursorCodec.decodeForImport(Data("not a cursor".utf8))

        XCTAssertNil(decoded.workoutAnchorData)
        XCTAssertNil(decoded.routeAnchorData)
        XCTAssertTrue(decoded.routeToWorkout.isEmpty)
        XCTAssertTrue(migration.requiresFullRouteReconciliation)
    }

    func testCurrentHealthCursorDoesNotRepeatFullRouteReconciliation() throws {
        let cursor = HealthImportCursor(
            workoutAnchorData: Data([1]),
            routeAnchorData: Data([2])
        )

        let decoding = HealthImportCursorCodec.decodeForImport(
            try HealthImportCursorCodec.encode(cursor)
        )

        XCTAssertFalse(decoding.requiresFullRouteReconciliation)
    }

    func testRouteAssociationReplacementAndDeletionAffectTheParentWorkout() {
        let workoutID = UUID()
        let deletedWorkoutID = UUID()
        let oldRouteID = UUID()
        let replacementRouteID = UUID()
        let deletedWorkoutRouteID = UUID()

        let update = HealthRouteAssociationReconciler.applying(
            deletedRouteIDs: [oldRouteID],
            addedAssociations: [replacementRouteID: workoutID],
            deletedWorkoutIDs: [deletedWorkoutID],
            to: [
                oldRouteID: workoutID,
                deletedWorkoutRouteID: deletedWorkoutID,
            ]
        )

        XCTAssertEqual(update.routeToWorkout, [replacementRouteID: workoutID])
        XCTAssertEqual(update.affectedWorkoutIDs, [workoutID])
    }

    func testCoverageOverlayDrawsExactIntervalsEvenForCompletedSegments() {
        let segment = WalkableSegment(
            id: "exact-interval",
            startNode: NodeID(1),
            endNode: NodeID(2),
            coordinates: [
                GeoCoordinate(latitude: 40.75, longitude: -73.99),
                GeoCoordinate(latitude: 40.751, longitude: -73.99),
            ],
            lengthMeters: 100,
            kind: .street
        )
        let pack = InMemoryCityCoveragePack(
            metadata: MapPackMetadata(
                identifier: "test",
                displayName: "Test",
                version: 1,
                sourceDate: .distantPast,
                sourceURL: nil,
                attribution: "Test"
            ),
            segments: [segment]
        )
        let coverage = CoverageSnapshot(
            packIdentifier: pack.metadata.identifier,
            packVersion: pack.metadata.version,
            totalDistanceMeters: 100,
            coveredDistanceMeters: 70,
            completedSegmentIDs: [segment.id],
            coveredMetersBySegment: [segment.id: 70],
            coveredIntervalsBySegment: [segment.id: [SegmentInterval(
                segmentID: segment.id,
                lowerBoundMeters: 10,
                upperBoundMeters: 80,
                confidence: 1
            )]],
            averageConfidence: 1
        )

        let overlay = CoverageNetworkOverlay(pack: pack, coverage: coverage)

        XCTAssertEqual(overlay.coveredPolylineCount, 1)
        XCTAssertEqual(overlay.remainingPolylineCount, 2)
    }

    func testBundledCoverageOverlayHasManhattanSizedBounds() async throws {
        let pack = try await SQLiteCityPackLoader().loadBundledManhattan()
        let overlay = CoverageNetworkOverlay(pack: pack, coverage: .empty(pack: pack))
        let region = MKCoordinateRegion(overlay.boundingMapRect)

        XCTAssertFalse(overlay.boundingMapRect.isNull)
        XCTAssertGreaterThan(region.center.latitude, 40.7)
        XCTAssertLessThan(region.center.latitude, 40.9)
        XCTAssertLessThan(region.span.latitudeDelta, 0.25)
        XCTAssertLessThan(region.span.longitudeDelta, 0.15)
    }

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
        XCTAssertEqual(pack.metadata.version, 2)
        XCTAssertEqual(
            pack.metadata.attributionURL?.absoluteString,
            "https://www.openstreetmap.org/copyright"
        )
        XCTAssertEqual(
            pack.metadata.licenseURL?.absoluteString,
            "https://opendatacommons.org/licenses/odbl/1-0/"
        )
        XCTAssertEqual(pack.segments.count, 36_827)
        XCTAssertEqual(pack.totalLengthMeters / 1_609.344, 760.8771434590388, accuracy: 0.000_001)
        XCTAssertNotNil(Bundle.main.url(
            forResource: "manhattan-v\(pack.metadata.version)",
            withExtension: "sqlite"
        ))
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
    func testRepositoryClearsLegacyAggregateSnapshotDuringPreparation() async throws {
        let schema = Schema([
            PersistedWorkoutCoverage.self,
            PersistedAppState.self,
            PersistedWorkoutImportState.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.insert(PersistedAppState(
            snapshotData: Data([1, 2, 3]),
            packIdentifier: "manhattan",
            packVersion: 1
        ))
        try context.save()
        let repository = SwiftDataCoverageRepository(modelContainer: container)

        try await repository.prepareForPack(identifier: "manhattan", version: 1)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<PersistedAppState>()).first)
        XCTAssertNil(state.snapshotData)
    }

    @MainActor
    func testRepositoryInvalidatesAnOlderMatchingProjection() async throws {
        let schema = Schema([
            PersistedWorkoutCoverage.self,
            PersistedAppState.self,
            PersistedWorkoutImportState.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let workoutID = UUID()
        context.insert(PersistedAppState(
            checkpoint: Data([1]),
            packIdentifier: "manhattan",
            packVersion: 2,
            matchingProjectionVersion: 0
        ))
        context.insert(PersistedWorkoutImportState(
            workoutID: workoutID,
            end: Date(timeIntervalSince1970: 100)
        ))
        try context.save()
        let repository = SwiftDataCoverageRepository(modelContainer: container)

        try await repository.prepareForPack(identifier: "manhattan", version: 2)

        let checkpoint = try await repository.loadCheckpoint()
        let processedWorkoutIDs = try await repository.loadProcessedWorkoutIDs()
        XCTAssertNil(checkpoint)
        XCTAssertTrue(processedWorkoutIDs.isEmpty)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<PersistedAppState>()).first)
        XCTAssertEqual(state.matchingProjectionVersion, 2)
    }

    @MainActor
    func testRepositoryClearsAllDerivedStateWhenAWorkoutProjectionIsCorrupt() async throws {
        let schema = Schema([
            PersistedWorkoutCoverage.self,
            PersistedAppState.self,
            PersistedWorkoutImportState.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let workoutID = UUID()
        context.insert(PersistedAppState(
            checkpoint: Data([9]),
            lastSuccessfulImport: Date(timeIntervalSince1970: 100),
            packIdentifier: "manhattan",
            packVersion: 2,
            matchingProjectionVersion: 2
        ))
        context.insert(PersistedWorkoutImportState(
            workoutID: workoutID,
            end: Date(timeIntervalSince1970: 100)
        ))
        context.insert(PersistedWorkoutCoverage(
            workoutID: workoutID,
            start: Date(timeIntervalSince1970: 50),
            end: Date(timeIntervalSince1970: 100),
            sourceName: "Test",
            packIdentifier: "manhattan",
            packVersion: 2,
            routeData: Data("invalid".utf8),
            contributionData: Data("invalid".utf8),
            unmatchedData: Data("invalid".utf8)
        ))
        try context.save()
        let repository = SwiftDataCoverageRepository(modelContainer: container)

        let records = try await repository.loadWorkoutRecords(
            packIdentifier: "manhattan",
            packVersion: 2
        )
        let processedWorkoutIDs = try await repository.loadProcessedWorkoutIDs()
        let checkpoint = try await repository.loadCheckpoint()
        let lastSuccessfulImport = try await repository.loadLastSuccessfulImport()

        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(processedWorkoutIDs.isEmpty)
        XCTAssertNil(checkpoint)
        XCTAssertNil(lastSuccessfulImport)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedWorkoutCoverage>()).isEmpty)
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
    func testOnboardingWaitsForCoverDismissalBeforeRequestingHealthAccess() async throws {
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            checkpoint: Data([1]),
            completedCount: 0,
            totalCount: 0
        )])
        let model = makeModel(source: source, repository: TestCoverageRepository())
        await model.bootstrap()

        model.completeOnboarding(requestHealthAccess: true)
        await Task.yield()
        let countBeforeDismissal = await source.currentAuthorizationCount()
        XCTAssertEqual(countBeforeDismissal, 0)

        model.resumePendingOnboardingImport()
        try await waitUntilImportStops(model)

        let countAfterDismissal = await source.currentAuthorizationCount()
        XCTAssertEqual(countAfterDismissal, 1)
    }

    @MainActor
    func testCancelledAuthorizationCannotResumeAnOldImport() async throws {
        let source = TestRouteSource(batches: [], suspendAuthorization: true)
        let model = makeModel(source: source, repository: TestCoverageRepository())
        await model.bootstrap()

        model.refresh()
        try await waitForAuthorizationRequest(source)
        model.cancelImport()
        await source.finishAuthorization()
        try await Task.sleep(for: .milliseconds(50))

        let routeBatchRequestCount = await source.currentRouteBatchRequestCount()
        XCTAssertEqual(routeBatchRequestCount, 0)
        XCTAssertEqual(model.importPhase, .idle)
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
        XCTAssertEqual(prepared?.version, 2)
    }

    @MainActor
    func testMappedWorkoutStateRequiresCreditedManhattanDistance() async throws {
        let pack = try await SQLiteCityPackLoader().loadBundledManhattan()
        let segment = try XCTUnwrap(pack.segments.first(where: \.countsTowardCoverage))
        let uncreditedID = UUID()
        let creditedID = UUID()
        let records = [
            WorkoutCoverageRecord(
                id: uncreditedID,
                start: .distantPast,
                end: .distantPast,
                sourceName: "Outside Manhattan",
                simplifiedRouteParts: [],
                contribution: WorkoutCoverageContribution(
                    workoutID: uncreditedID,
                    intervals: [],
                    confidence: 0
                ),
                unmatchedPortions: []
            ),
            WorkoutCoverageRecord(
                id: creditedID,
                start: .distantPast,
                end: .distantPast,
                sourceName: "Manhattan",
                simplifiedRouteParts: [],
                contribution: WorkoutCoverageContribution(
                    workoutID: creditedID,
                    intervals: [SegmentInterval(
                        segmentID: segment.id,
                        lowerBoundMeters: 0,
                        upperBoundMeters: min(10, segment.lengthMeters),
                        confidence: 1
                    )],
                    confidence: 1
                ),
                unmatchedPortions: []
            ),
        ]
        let repository = TestCoverageRepository(records: [records[0]])
        let model = makeModel(source: TestRouteSource(batches: []), repository: repository)

        await model.bootstrap()

        XCTAssertEqual(model.workoutRecords.count, 1)
        XCTAssertEqual(model.workoutsWithCoverageCount, 0)
        XCTAssertFalse(model.hasMappedWorkouts)

        model.workoutRecords = records

        XCTAssertEqual(model.workoutsWithCoverageCount, 1)
        XCTAssertTrue(model.hasMappedWorkouts)
    }

    @MainActor
    func testDeletedWorkoutIsRemovedDuringRefresh() async throws {
        let id = UUID()
        let bundledPack = try await SQLiteCityPackLoader().loadBundledManhattan()
        let segment = try XCTUnwrap(
            bundledPack.segments.first(where: \.countsTowardCoverage)
        )
        let record = WorkoutCoverageRecord(
            id: id,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200),
            sourceName: "Test",
            simplifiedRouteParts: [],
            contribution: WorkoutCoverageContribution(
                workoutID: id,
                intervals: [SegmentInterval(
                    segmentID: segment.id,
                    lowerBoundMeters: 0,
                    upperBoundMeters: segment.lengthMeters,
                    confidence: 1
                )],
                confidence: 1
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
        XCTAssertGreaterThan(model.coverage?.coveredDistanceMeters ?? 0, 0)

        model.refresh()
        try await waitUntilImportStops(model)

        XCTAssertTrue(model.workoutRecords.isEmpty)
        XCTAssertEqual(model.coverage?.coveredDistanceMeters, 0)
        let repositoryIsEmpty = await repository.isEmpty
        XCTAssertTrue(repositoryIsEmpty)
    }

    @MainActor
    func testRouteInvalidationRemovesCoverageButKeepsProcessedWorkout() async throws {
        let id = UUID()
        let record = WorkoutCoverageRecord(
            id: id,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200),
            sourceName: "Test",
            simplifiedRouteParts: [],
            contribution: WorkoutCoverageContribution(workoutID: id, intervals: [], confidence: 0),
            unmatchedPortions: []
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [],
            routeInvalidatedWorkoutIDs: [id],
            processedWorkouts: [.init(id: id, end: record.end)],
            checkpoint: Data([3])
        )])
        let repository = TestCoverageRepository(records: [record], processedIDs: [id])
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitUntilImportStops(model)

        XCTAssertTrue(model.workoutRecords.isEmpty)
        let processedIDs = await repository.currentProcessedIDs()
        XCTAssertEqual(processedIDs, [id])
    }

    @MainActor
    func testAutomaticRefreshUsesFiveMinuteThrottleAndManualRefreshBypassesIt() async throws {
        let source = TestRouteSource(batches: [WorkoutRouteBatch(routes: [], checkpoint: Data([4]))])
        let repository = TestCoverageRepository()
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitUntilImportStops(model)
        let firstRefresh = try XCTUnwrap(model.lastSuccessfulImport)

        model.refreshIfNeeded(now: firstRefresh.addingTimeInterval(301))
        try await waitForRouteBatchRequestCount(source, count: 2)
        try await waitUntilImportStops(model)

        model.refreshIfNeeded(now: firstRefresh.addingTimeInterval(302))
        try await Task.sleep(for: .milliseconds(30))
        let throttledRequestCount = await source.currentRouteBatchRequestCount()
        XCTAssertEqual(throttledRequestCount, 2)

        model.refresh()
        try await waitForRouteBatchRequestCount(source, count: 3)
        try await waitUntilImportStops(model)
        let manualRequestCount = await source.currentRouteBatchRequestCount()
        XCTAssertEqual(manualRequestCount, 3)
    }

    @MainActor
    func testSuccessfulRefreshPersistsAndPublishesTheSameDate() async throws {
        let source = TestRouteSource(batches: [WorkoutRouteBatch(routes: [], checkpoint: Data([5]))])
        let repository = TestCoverageRepository()
        let model = makeModel(source: source, repository: repository)
        await model.bootstrap()

        model.refresh()
        try await waitUntilImportStops(model)

        let persistedDate = await repository.currentLastSuccessfulImport()
        XCTAssertEqual(model.lastSuccessfulImport, persistedDate)
    }

    @MainActor
    func testInterruptedImportDoesNotPublishItsCheckpoint() async throws {
        let route = WorkoutRoute(
            id: UUID(),
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 120),
            sourceName: "Test",
            points: [
                RoutePoint(
                    coordinate: GeoCoordinate(latitude: 40.75, longitude: -73.99),
                    timestamp: Date(timeIntervalSince1970: 100),
                    horizontalAccuracy: 5
                ),
                RoutePoint(
                    coordinate: GeoCoordinate(latitude: 40.751, longitude: -73.99),
                    timestamp: Date(timeIntervalSince1970: 120),
                    horizontalAccuracy: 5
                ),
            ]
        )
        let source = TestRouteSource(batches: [WorkoutRouteBatch(
            routes: [route],
            processedWorkouts: [.init(id: route.id, end: route.end)],
            checkpoint: Data([42]),
            completedCount: 1,
            totalCount: 1
        )])
        let repository = TestCoverageRepository()
        let matcher = SuspendingMatcher()
        let model = makeModel(source: source, repository: repository, matcher: matcher)
        await model.bootstrap()

        model.refresh()
        try await waitForMatcher(matcher)
        model.cancelImport()
        await matcher.finish()
        try await Task.sleep(for: .milliseconds(30))

        let checkpoint = await repository.currentCheckpoint()
        XCTAssertNil(checkpoint)
        XCTAssertTrue(model.workoutRecords.isEmpty)
    }

    @MainActor
    func testWorkoutSelectionPublishesExplicitViewportCommands() async {
        let model = makeModel(source: TestRouteSource(batches: []), repository: TestCoverageRepository())
        let id = UUID()

        model.selectWorkout(id)
        XCTAssertEqual(model.mapViewportCommand.target, .workout(id))
        let selectedRevision = model.mapViewportCommand.revision

        model.clearSelectedWorkout()
        XCTAssertEqual(model.mapViewportCommand.target, .manhattan)
        XCTAssertGreaterThan(model.mapViewportCommand.revision, selectedRevision)
    }

    #if DEBUG
    @MainActor
    func testOlderInspectorLoadCannotReplaceNewerSelection() async throws {
        let olderID = UUID()
        let newerID = UUID()
        let source = OutOfOrderRouteSource(
            suspendedWorkoutID: olderID,
            immediateRoute: WorkoutRoute(
                id: newerID,
                start: Date(timeIntervalSince1970: 200),
                end: Date(timeIntervalSince1970: 210),
                sourceName: "Test",
                points: []
            )
        )
        let model = makeModel(source: source, repository: TestCoverageRepository())
        await model.bootstrap()

        let olderLoad = Task { await model.loadDebugInspection(workoutID: olderID) }
        try await waitForSuspendedRoute(source)
        await model.loadDebugInspection(workoutID: newerID)
        await source.finishSuspendedRoute()
        await olderLoad.value

        guard case let .loaded(route, _, _) = model.debugInspectionState else {
            return XCTFail("Expected the newer inspector route to remain loaded")
        }
        XCTAssertEqual(route.id, newerID)
    }
    #endif

    @MainActor
    private func makeModel(
        source: any WorkoutRouteSource,
        repository: TestCoverageRepository,
        matcher: any MapMatcher = EmptyMatcher()
    ) -> AppModel {
        AppModel(dependencies: AppDependencies(
            routeSource: source,
            repository: repository,
            cityPackLoader: SQLiteCityPackLoader(),
            matcher: matcher,
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

    @MainActor
    private func waitForAuthorizationRequest(_ source: TestRouteSource) async throws {
        for _ in 0 ..< 200 {
            if await source.currentAuthorizationCount() > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Authorization request did not start")
    }

    @MainActor
    private func waitForRouteBatchRequestCount(_ source: TestRouteSource, count: Int) async throws {
        for _ in 0 ..< 200 {
            if await source.currentRouteBatchRequestCount() >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected \(count) route batch requests")
    }

    @MainActor
    private func waitForMatcher(_ matcher: SuspendingMatcher) async throws {
        for _ in 0 ..< 200 {
            if await matcher.hasStarted() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Matcher did not start")
    }

    #if DEBUG
    @MainActor
    private func waitForSuspendedRoute(_ source: OutOfOrderRouteSource) async throws {
        for _ in 0 ..< 200 {
            if await source.hasSuspendedRouteRequest() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Inspector route request did not suspend")
    }
    #endif
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

private actor SuspendingMatcher: MapMatcher {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func match(points: [RoutePoint], in pack: any CityCoveragePack) async throws -> MatchResult {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        try Task.checkCancellation()
        return MatchResult(
            intervals: [],
            unmatchedPortions: [],
            acceptedPointCount: 0,
            rejectedPointCount: points.count,
            averageConfidence: 0
        )
    }

    func hasStarted() -> Bool { started }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor TestRouteSource: WorkoutRouteSource {
    private(set) var authorizationCount = 0
    private(set) var routeBatchRequestCount = 0
    let batches: [WorkoutRouteBatch]
    let suspendAuthorization: Bool
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    init(batches: [WorkoutRouteBatch], suspendAuthorization: Bool = false) {
        self.batches = batches
        self.suspendAuthorization = suspendAuthorization
    }

    func requestReadAuthorization() async throws {
        authorizationCount += 1
        if suspendAuthorization {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
            }
        }
    }

    func currentAuthorizationCount() -> Int { authorizationCount }
    func currentRouteBatchRequestCount() -> Int { routeBatchRequestCount }

    func finishAuthorization() {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    func route(for workoutID: UUID) async throws -> WorkoutRoute? { nil }

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        routeBatchRequestCount += 1
        let batches = self.batches
        return AsyncThrowingStream { continuation in
            for batch in batches { continuation.yield(batch) }
            continuation.finish()
        }
    }
}

#if DEBUG
private actor OutOfOrderRouteSource: WorkoutRouteSource {
    private let suspendedWorkoutID: UUID
    private let immediateRoute: WorkoutRoute
    private var suspendedRouteRequest = false
    private var suspendedContinuation: CheckedContinuation<WorkoutRoute?, Never>?

    init(suspendedWorkoutID: UUID, immediateRoute: WorkoutRoute) {
        self.suspendedWorkoutID = suspendedWorkoutID
        self.immediateRoute = immediateRoute
    }

    func requestReadAuthorization() async throws {}

    func route(for workoutID: UUID) async throws -> WorkoutRoute? {
        if workoutID == suspendedWorkoutID {
            suspendedRouteRequest = true
            return await withCheckedContinuation { continuation in
                suspendedContinuation = continuation
            }
        }
        return workoutID == immediateRoute.id ? immediateRoute : nil
    }

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func hasSuspendedRouteRequest() -> Bool { suspendedRouteRequest }

    func finishSuspendedRoute() {
        suspendedContinuation?.resume(returning: WorkoutRoute(
            id: suspendedWorkoutID,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 110),
            sourceName: "Test",
            points: []
        ))
        suspendedContinuation = nil
    }
}
#endif

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

    func removeCoverage(workoutIDs: [UUID]) async throws {
        let removed = Set(workoutIDs)
        records.removeAll { removed.contains($0.id) }
    }

    func loadCheckpoint() async throws -> Data? { checkpoint }
    func loadLastSuccessfulImport() async throws -> Date? { lastSuccessfulImport }
    func saveCheckpoint(_ checkpoint: Data?) async throws { self.checkpoint = checkpoint }
    func currentCheckpoint() -> Data? { checkpoint }
    func saveLastSuccessfulImport(_ date: Date) async throws { lastSuccessfulImport = date }
    func currentLastSuccessfulImport() -> Date? { lastSuccessfulImport }
    func currentProcessedIDs() -> Set<UUID> { processedIDs }

    func resetDerivedCoverage() async throws {
        records = []
        snapshot = nil
        checkpoint = nil
        processedIDs = []
        lastSuccessfulImport = nil
    }
}
