import Foundation
import UIKit
import WalkItAllCore

enum ProtectedHistoryError: LocalizedError {
    case dataUnavailable

    var errorDescription: String? {
        switch self {
        case .dataUnavailable:
            "Your protected walking history is unavailable while this iPhone is locked. Unlock it and try again."
        }
    }
}

/// Defers opening the `.complete` SwiftData store until protected data is
/// available. This lets an explicitly active Live Trail recover during a
/// locked background relaunch without weakening lifetime-route protection.
actor ProtectedWalkHistoryRepository: WalkHistoryRepository {
    typealias Availability = @Sendable () async -> Bool
    typealias Factory = @Sendable () throws -> any WalkHistoryRepository

    private let isProtectedDataAvailable: Availability
    private let factory: Factory
    private var resolvedRepository: (any WalkHistoryRepository)?

    init(
        isProtectedDataAvailable: @escaping Availability = {
            await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        },
        factory: @escaping Factory = {
            let container = try ProtectedModelContainer.make()
            return SwiftDataWalkHistoryRepository(modelContainer: container)
        }
    ) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.factory = factory
    }

    func loadRecords() async throws -> [WorkoutRouteRecord] {
        try await repository().loadRecords()
    }

    func save(record: WorkoutRouteRecord) async throws {
        try await repository().save(record: record)
    }

    func removeRouteRecords(workoutIDs: [UUID]) async throws {
        try await repository().removeRouteRecords(workoutIDs: workoutIDs)
    }

    func removeWorkouts(workoutIDs: [UUID]) async throws {
        try await repository().removeWorkouts(workoutIDs: workoutIDs)
    }

    func loadProcessedWorkoutIDs() async throws -> Set<UUID> {
        try await repository().loadProcessedWorkoutIDs()
    }

    func markWorkoutProcessed(id: UUID, end: Date) async throws {
        try await repository().markWorkoutProcessed(id: id, end: end)
    }

    func loadCheckpoint() async throws -> Data? {
        try await repository().loadCheckpoint()
    }

    func saveCheckpoint(_ checkpoint: Data?) async throws {
        try await repository().saveCheckpoint(checkpoint)
    }

    func loadLastSuccessfulImport() async throws -> Date? {
        try await repository().loadLastSuccessfulImport()
    }

    func saveLastSuccessfulImport(_ date: Date) async throws {
        try await repository().saveLastSuccessfulImport(date)
    }

    func reset() async throws {
        try await repository().reset()
    }

    private func repository() async throws -> any WalkHistoryRepository {
        if let resolvedRepository { return resolvedRepository }
        guard await isProtectedDataAvailable() else {
            throw ProtectedHistoryError.dataUnavailable
        }
        let repository = try factory()
        resolvedRepository = repository
        return repository
    }
}
