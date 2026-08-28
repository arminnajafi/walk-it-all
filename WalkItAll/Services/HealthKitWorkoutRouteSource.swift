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

actor HealthKitWorkoutRouteSource: WorkoutRouteSource {
    private let healthStore: HKHealthStore

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

    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let anchor = decodeAnchor(checkpoint)
                    let changes = try await queryWorkoutChanges(anchor: anchor)
                    let encodedAnchor = try encodeAnchor(changes.anchor)
                    var candidates = Dictionary(
                        uniqueKeysWithValues: changes.workouts.map { ($0.uuid, $0) }
                    )

                    // Workout-route samples can finish after the workout itself.
                    // Rechecking a small recent window catches those updates without
                    // re-reading a lifetime of route-less indoor walks every refresh.
                    if checkpoint != nil {
                        for workout in try await queryRecentWorkouts(days: 7) {
                            candidates[workout.uuid] = workout
                        }
                    }
                    let changedIDs = Set(changes.workouts.map(\.uuid))
                    let recentCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
                    let workouts = candidates.values
                        .filter {
                            changedIDs.contains($0.uuid)
                                || !workoutIDs.contains($0.uuid)
                                || $0.endDate >= recentCutoff
                        }
                        .sorted { $0.startDate < $1.startDate }

                    if workouts.isEmpty {
                        continuation.yield(WorkoutRouteBatch(
                            routes: [],
                            deletedWorkoutIDs: changes.deletedIDs,
                            processedWorkouts: [],
                            checkpoint: encodedAnchor,
                            completedCount: 0,
                            totalCount: 0
                        ))
                    }

                    for (index, workout) in workouts.enumerated() {
                        try Task.checkCancellation()
                        let route = try await loadWorkoutRoute(workout)
                        let isLast = index == workouts.count - 1
                        continuation.yield(WorkoutRouteBatch(
                            routes: route.map { [$0] } ?? [],
                            deletedWorkoutIDs: index == 0 ? changes.deletedIDs : [],
                            processedWorkouts: [.init(id: workout.uuid, end: workout.endDate)],
                            checkpoint: isLast ? encodedAnchor : nil,
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

    private func queryWorkoutChanges(
        anchor: HKQueryAnchor?
    ) async throws -> (workouts: [HKWorkout], deletedIDs: [UUID], anchor: HKQueryAnchor?) {
        let walking = HKQuery.predicateForWorkouts(with: .walking)
        let hiking = HKQuery.predicateForWorkouts(with: .hiking)
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [walking, hiking])

        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            anchor: anchor,
            limit: nil
        )
        let result = try await descriptor.result(for: healthStore)
        return (
            result.addedSamples,
            result.deletedObjects.map(\.uuid),
            result.newAnchor
        )
    }

    private func queryRecentWorkouts(days: Int) async throws -> [HKWorkout] {
        let walking = HKQuery.predicateForWorkouts(with: .walking)
        let hiking = HKQuery.predicateForWorkouts(with: .hiking)
        let activity = NSCompoundPredicate(orPredicateWithSubpredicates: [walking, hiking])
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let dates = HKQuery.predicateForSamples(withStart: cutoff, end: nil)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [activity, dates])
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: nil
        )
        return try await descriptor.result(for: healthStore)
    }

    private func loadWorkoutRoute(_ workout: HKWorkout) async throws -> WorkoutRoute? {
        let routes = try await routeSamples(for: workout)
        guard !routes.isEmpty else { return nil }
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
        guard deduplicated.count >= 2 else { return nil }

        return WorkoutRoute(
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

    private func encodeAnchor(_ anchor: HKQueryAnchor?) throws -> Data? {
        guard let anchor else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }
}
