@preconcurrency import CoreLocation
import Foundation
@preconcurrency import HealthKit
import WalkItAllCore

enum HealthRouteSourceError: LocalizedError {
    case healthDataUnavailable
    case unexpectedSample

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "Apple Health data is not available on this device."
        case .unexpectedSample:
            "Apple Health returned an unexpected workout record."
        }
    }
}

/// HealthKit anchors are deliberately opaque to WalkItAllCore. This cursor owns
/// the two independently mutable Health streams and their parent association.
struct HealthImportCursor: Codable, Sendable {
    static let currentVersion = 2

    var version: Int
    var workoutAnchorData: Data?
    var routeAnchorData: Data?
    var routeToWorkout: [UUID: UUID]

    init(
        version: Int = Self.currentVersion,
        workoutAnchorData: Data? = nil,
        routeAnchorData: Data? = nil,
        routeToWorkout: [UUID: UUID] = [:]
    ) {
        self.version = version
        self.workoutAnchorData = workoutAnchorData
        self.routeAnchorData = routeAnchorData
        self.routeToWorkout = routeToWorkout
    }
}

struct HealthRouteAssociationUpdate: Sendable {
    let routeToWorkout: [UUID: UUID]
    let affectedWorkoutIDs: Set<UUID>
}

enum HealthRouteAssociationReconciler {
    static func applying(
        deletedRouteIDs: [UUID],
        addedAssociations: [UUID: UUID],
        deletedWorkoutIDs: Set<UUID>,
        to existing: [UUID: UUID]
    ) -> HealthRouteAssociationUpdate {
        var associations = existing
        var affected = Set<UUID>()
        for routeID in deletedRouteIDs {
            if let workoutID = associations.removeValue(forKey: routeID),
               !deletedWorkoutIDs.contains(workoutID)
            {
                affected.insert(workoutID)
            }
        }
        associations = associations.filter { !deletedWorkoutIDs.contains($0.value) }
        for (routeID, workoutID) in addedAssociations where !deletedWorkoutIDs.contains(workoutID) {
            associations[routeID] = workoutID
            affected.insert(workoutID)
        }
        return HealthRouteAssociationUpdate(
            routeToWorkout: associations,
            affectedWorkoutIDs: affected
        )
    }
}

enum HealthImportCursorCodec {
    static func decode(_ data: Data?) -> HealthImportCursor {
        guard let data else { return HealthImportCursor() }
        if let cursor = try? JSONDecoder().decode(HealthImportCursor.self, from: data) {
            return cursor
        }
        if (try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)) != nil {
            return HealthImportCursor(workoutAnchorData: data)
        }
        return HealthImportCursor()
    }

    static func encode(_ cursor: HealthImportCursor) throws -> Data {
        try JSONEncoder().encode(cursor)
    }
}

actor HealthKitWorkoutRouteSource: WorkoutRouteSource {
    private struct WorkoutChanges {
        let workouts: [HKWorkout]
        let deletedIDs: [UUID]
        let anchor: HKQueryAnchor
    }

    private struct RouteChanges {
        let routes: [HKWorkoutRoute]
        let deletedIDs: [UUID]
        let anchor: HKQueryAnchor
    }

    private struct LoadedRoute {
        let route: WorkoutRoute?
        let sampleIDs: Set<UUID>
    }

    private let healthStore: HKHealthStore
    private let recentReconciliationDays = 7

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func requestReadAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthRouteSourceError.healthDataUnavailable
        }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let status = try await healthStore.statusForAuthorizationRequest(
            toShare: [],
            read: readTypes
        )
        guard status != .unnecessary else { return }
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func route(for workoutID: UUID) async throws -> WorkoutRoute? {
        guard let workout = try await workout(id: workoutID) else { return nil }
        return try await loadWorkoutRoute(workout).route
    }

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    var cursor = HealthImportCursorCodec.decode(checkpoint)
                    let workoutChanges = try await queryWorkoutChanges(
                        anchor: decodeAnchor(cursor.workoutAnchorData)
                    )
                    let routeChanges = try await queryRouteChanges(
                        anchor: decodeAnchor(cursor.routeAnchorData)
                    )

                    let deletedWorkoutIDs = Set(workoutChanges.deletedIDs)
                    var addedAssociations: [UUID: UUID] = [:]
                    for routeSample in routeChanges.routes {
                        try Task.checkCancellation()
                        guard let parent = try await parentWorkout(for: routeSample) else {
                            // Routes for activities other than walking and hiking are
                            // intentionally outside this app's completion history.
                            continue
                        }
                        addedAssociations[routeSample.uuid] = parent.uuid
                    }
                    let associationUpdate = HealthRouteAssociationReconciler.applying(
                        deletedRouteIDs: routeChanges.deletedIDs,
                        addedAssociations: addedAssociations,
                        deletedWorkoutIDs: deletedWorkoutIDs,
                        to: cursor.routeToWorkout
                    )
                    cursor.routeToWorkout = associationUpdate.routeToWorkout
                    let routeAffectedWorkoutIDs = associationUpdate.affectedWorkoutIDs

                    var candidates = Dictionary(
                        uniqueKeysWithValues: workoutChanges.workouts.map { ($0.uuid, $0) }
                    )
                    if checkpoint != nil {
                        for recent in try await queryRecentWorkouts(days: recentReconciliationDays) {
                            candidates[recent.uuid] = recent
                        }
                    }
                    for workoutID in routeAffectedWorkoutIDs where candidates[workoutID] == nil {
                        if let affected = try await workout(id: workoutID) {
                            candidates[workoutID] = affected
                        }
                    }

                    let changedWorkoutIDs = Set(workoutChanges.workouts.map(\.uuid))
                    let recentCutoff = Calendar.current.date(
                        byAdding: .day,
                        value: -recentReconciliationDays,
                        to: Date()
                    ) ?? .distantPast
                    let workouts = candidates.values
                        .filter {
                            !deletedWorkoutIDs.contains($0.uuid)
                                && (changedWorkoutIDs.contains($0.uuid)
                                    || routeAffectedWorkoutIDs.contains($0.uuid)
                                    || !workoutIDs.contains($0.uuid)
                                    || $0.endDate >= recentCutoff)
                        }
                        .sorted { $0.startDate < $1.startDate }

                    cursor.version = HealthImportCursor.currentVersion
                    cursor.workoutAnchorData = try encodeAnchor(workoutChanges.anchor)
                    cursor.routeAnchorData = try encodeAnchor(routeChanges.anchor)

                    if workouts.isEmpty {
                        continuation.yield(WorkoutRouteBatch(
                            routes: [],
                            deletedWorkoutIDs: workoutChanges.deletedIDs,
                            routeInvalidatedWorkoutIDs: [],
                            processedWorkouts: [],
                            checkpoint: try HealthImportCursorCodec.encode(cursor),
                            completedCount: 0,
                            totalCount: 0
                        ))
                    }

                    for (index, workout) in workouts.enumerated() {
                        try Task.checkCancellation()
                        let loaded = try await loadWorkoutRoute(workout)
                        let previousSampleIDs = Set(cursor.routeToWorkout.compactMap {
                            $0.value == workout.uuid ? $0.key : nil
                        })
                        for removedSampleID in previousSampleIDs.subtracting(loaded.sampleIDs) {
                            cursor.routeToWorkout.removeValue(forKey: removedSampleID)
                        }
                        for sampleID in loaded.sampleIDs {
                            cursor.routeToWorkout[sampleID] = workout.uuid
                        }

                        let routeWasInvalidated = routeAffectedWorkoutIDs.contains(workout.uuid)
                            && loaded.route == nil
                        let isLast = index == workouts.count - 1
                        continuation.yield(WorkoutRouteBatch(
                            routes: loaded.route.map { [$0] } ?? [],
                            deletedWorkoutIDs: index == 0 ? workoutChanges.deletedIDs : [],
                            routeInvalidatedWorkoutIDs: routeWasInvalidated ? [workout.uuid] : [],
                            processedWorkouts: [.init(id: workout.uuid, end: workout.endDate)],
                            checkpoint: isLast ? try HealthImportCursorCodec.encode(cursor) : nil,
                            completedCount: index + 1,
                            totalCount: workouts.count
                        ))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func queryWorkoutChanges(anchor: HKQueryAnchor?) async throws -> WorkoutChanges {
        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkout>(
            predicates: [.workout(walkingOrHikingPredicate())],
            anchor: anchor,
            limit: nil
        )
        let result = try await descriptor.result(for: healthStore)
        return WorkoutChanges(
            workouts: result.addedSamples,
            deletedIDs: result.deletedObjects.map(\.uuid),
            anchor: result.newAnchor
        )
    }

    private func queryRouteChanges(anchor: HKQueryAnchor?) async throws -> RouteChanges {
        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkoutRoute>(
            predicates: [.workoutRoute()],
            anchor: anchor,
            limit: nil
        )
        let result = try await descriptor.result(for: healthStore)
        return RouteChanges(
            routes: result.addedSamples,
            deletedIDs: result.deletedObjects.map(\.uuid),
            anchor: result.newAnchor
        )
    }

    private func queryRecentWorkouts(days: Int) async throws -> [HKWorkout] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let dates = HKQuery.predicateForSamples(withStart: cutoff, end: nil)
        return try await queryWorkouts(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [walkingOrHikingPredicate(), dates]),
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
    }

    private func workout(id: UUID) async throws -> HKWorkout? {
        let identifier = HKQuery.predicateForObject(with: id)
        return try await queryWorkouts(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [walkingOrHikingPredicate(), identifier]),
            sortDescriptors: [],
            limit: 1
        ).first
    }

    private func parentWorkout(for route: HKWorkoutRoute) async throws -> HKWorkout? {
        let margin: TimeInterval = 5 * 60
        let dates = HKQuery.predicateForSamples(
            withStart: route.startDate.addingTimeInterval(-margin),
            end: route.endDate.addingTimeInterval(margin),
            options: []
        )
        let candidates = try await queryWorkouts(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [walkingOrHikingPredicate(), dates]),
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        for candidate in candidates {
            try Task.checkCancellation()
            if try await routeSamples(for: candidate).contains(where: { $0.uuid == route.uuid }) {
                return candidate
            }
        }
        return nil
    }

    private func queryWorkouts(
        predicate: NSPredicate,
        sortDescriptors: [SortDescriptor<HKWorkout>],
        limit: Int? = nil
    ) async throws -> [HKWorkout] {
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            sortDescriptors: sortDescriptors,
            limit: limit
        )
        return try await descriptor.result(for: healthStore)
    }

    private func walkingOrHikingPredicate() -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .walking),
            HKQuery.predicateForWorkouts(with: .hiking),
        ])
    }

    private func loadWorkoutRoute(_ workout: HKWorkout) async throws -> LoadedRoute {
        let routes = try await routeSamples(for: workout)
        guard !routes.isEmpty else { return LoadedRoute(route: nil, sampleIDs: []) }
        var allLocations: [CLLocation] = []
        for route in routes {
            allLocations.append(contentsOf: try await locations(for: route))
        }
        let sorted = allLocations.sorted { $0.timestamp < $1.timestamp }
        var deduplicated: [CLLocation] = []
        deduplicated.reserveCapacity(sorted.count)
        for location in sorted {
            if let previous = deduplicated.last,
               previous.timestamp == location.timestamp,
               previous.coordinate.latitude == location.coordinate.latitude,
               previous.coordinate.longitude == location.coordinate.longitude
            {
                continue
            }
            deduplicated.append(location)
        }
        guard deduplicated.count >= 2 else {
            return LoadedRoute(route: nil, sampleIDs: Set(routes.map(\.uuid)))
        }

        return LoadedRoute(
            route: WorkoutRoute(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                sourceName: workout.sourceRevision.source.name,
                points: deduplicated.map {
                    RoutePoint(
                        coordinate: GeoCoordinate(
                            latitude: $0.coordinate.latitude,
                            longitude: $0.coordinate.longitude
                        ),
                        timestamp: $0.timestamp,
                        horizontalAccuracy: $0.horizontalAccuracy
                    )
                }
            ),
            sampleIDs: Set(routes.map(\.uuid))
        )
    }

    private func routeSamples(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkoutRoute>(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            anchor: nil,
            limit: nil
        )
        return try await descriptor.result(for: healthStore).addedSamples
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        var locations: [CLLocation] = []
        let descriptor = HKWorkoutRouteQueryDescriptor(route)
        for try await location in descriptor.results(for: healthStore) {
            try Task.checkCancellation()
            locations.append(location)
        }
        return locations
    }

    private func decodeAnchor(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func encodeAnchor(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }
}
