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
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func routeBatches(since checkpoint: Data?) async -> AsyncThrowingStream<WorkoutRouteBatch, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let anchor = decodeAnchor(checkpoint)
                    let changes = try await queryWorkoutChanges(anchor: anchor)
                    let encodedAnchor = try encodeAnchor(changes.anchor)
                    let workouts = changes.workouts.sorted { $0.startDate < $1.startDate }

                    if workouts.isEmpty {
                        continuation.yield(WorkoutRouteBatch(
                            routes: [],
                            deletedWorkoutIDs: changes.deletedIDs,
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
        }
    }

    private func queryWorkoutChanges(
        anchor: HKQueryAnchor?
    ) async throws -> (workouts: [HKWorkout], deletedIDs: [UUID], anchor: HKQueryAnchor?) {
        let walking = HKQuery.predicateForWorkouts(with: .walking)
        let hiking = HKQuery.predicateForWorkouts(with: .hiking)
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [walking, hiking])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples ?? []).compactMap { $0 as? HKWorkout }
                continuation.resume(returning: (
                    workouts,
                    (deleted ?? []).map(\.uuid),
                    newAnchor
                ))
            }
            healthStore.execute(query)
        }
    }

    private func loadWorkoutRoute(_ workout: HKWorkout) async throws -> WorkoutRoute? {
        let routes = try await routeSamples(for: workout)
        guard !routes.isEmpty else { return nil }
        var allLocations: [CLLocation] = []
        for route in routes {
            allLocations.append(contentsOf: try await locations(for: route))
        }
        let sorted = allLocations.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        return WorkoutRoute(
            id: workout.uuid,
            start: workout.startDate,
            end: workout.endDate,
            sourceName: workout.sourceRevision.source.name,
            points: sorted.map {
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
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? []).compactMap { $0 as? HKWorkoutRoute })
                }
            }
            healthStore.execute(query)
        }
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        let accumulator = LocationAccumulator()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    accumulator.finishOnce {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                accumulator.append(locations ?? [])
                if done {
                    accumulator.finishOnce {
                        continuation.resume(returning: accumulator.values)
                    }
                }
            }
            healthStore.execute(query)
        }
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

private final class LocationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CLLocation] = []
    private var isFinished = false

    var values: [CLLocation] {
        lock.withLock { storage }
    }

    func append(_ locations: [CLLocation]) {
        lock.withLock {
            guard !isFinished else { return }
            storage.append(contentsOf: locations)
        }
    }

    func finishOnce(_ action: () -> Void) {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        if shouldFinish { action() }
    }
}
