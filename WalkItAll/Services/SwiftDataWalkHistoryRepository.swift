import Foundation
import SwiftData
import WalkItAllCore

@ModelActor
actor SwiftDataWalkHistoryRepository: WalkHistoryRepository {
    private struct RoutePayload: Codable {
        static let currentVersion = 2

        let version: Int
        let activityKind: RouteActivityKind
        let routeParts: [[GeoCoordinate]]
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadRecords() async throws -> [WorkoutRouteRecord] {
        let descriptor = FetchDescriptor<PersistedWorkoutRouteRecord>(
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        let persisted = try modelContext.fetch(descriptor)
        let records = persisted.compactMap(decode)
        guard records.count == persisted.count else {
            // Projection and Health anchors must reset together. Otherwise one
            // corrupt row could be skipped forever by the processed ledger.
            try await reset()
            return []
        }
        return records
    }

    func save(record: WorkoutRouteRecord) async throws {
        let data = try encoder.encode(RoutePayload(
            version: RoutePayload.currentVersion,
            activityKind: record.activityKind,
            routeParts: record.routeParts
        ))
        let workoutID = record.id
        let descriptor = FetchDescriptor<PersistedWorkoutRouteRecord>(
            predicate: #Predicate { $0.workoutID == workoutID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.start = record.start
            existing.end = record.end
            existing.sourceName = record.sourceName
            existing.routePartsData = data
        } else {
            modelContext.insert(PersistedWorkoutRouteRecord(
                workoutID: workoutID,
                start: record.start,
                end: record.end,
                sourceName: record.sourceName,
                routePartsData: data
            ))
        }
        try modelContext.save()
    }

    func removeRouteRecords(workoutIDs: [UUID]) async throws {
        guard !workoutIDs.isEmpty else { return }
        for workoutID in workoutIDs {
            try deleteRecord(workoutID: workoutID)
        }
        try modelContext.save()
    }

    func removeWorkouts(workoutIDs: [UUID]) async throws {
        guard !workoutIDs.isEmpty else { return }
        for workoutID in workoutIDs {
            try deleteRecord(workoutID: workoutID)
            let descriptor = FetchDescriptor<PersistedWorkoutImportState>(
                predicate: #Predicate { $0.workoutID == workoutID }
            )
            if let state = try modelContext.fetch(descriptor).first {
                modelContext.delete(state)
            }
        }
        try modelContext.save()
    }

    func loadProcessedWorkoutIDs() async throws -> Set<UUID> {
        Set(try modelContext.fetch(FetchDescriptor<PersistedWorkoutImportState>()).map(\.workoutID))
    }

    func markWorkoutProcessed(id: UUID, end: Date) async throws {
        let descriptor = FetchDescriptor<PersistedWorkoutImportState>(
            predicate: #Predicate { $0.workoutID == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.end = end
        } else {
            modelContext.insert(PersistedWorkoutImportState(workoutID: id, end: end))
        }
        try modelContext.save()
    }

    func loadCheckpoint() async throws -> Data? {
        try primaryState().checkpoint
    }

    func saveCheckpoint(_ checkpoint: Data?) async throws {
        let state = try primaryState()
        state.checkpoint = checkpoint
        try modelContext.save()
    }

    func loadLastSuccessfulImport() async throws -> Date? {
        try primaryState().lastSuccessfulImport
    }

    func saveLastSuccessfulImport(_ date: Date) async throws {
        let state = try primaryState()
        state.lastSuccessfulImport = date
        try modelContext.save()
    }

    func reset() async throws {
        for record in try modelContext.fetch(FetchDescriptor<PersistedWorkoutRouteRecord>()) {
            modelContext.delete(record)
        }
        for state in try modelContext.fetch(FetchDescriptor<PersistedWorkoutImportState>()) {
            modelContext.delete(state)
        }
        let state = try primaryState()
        state.checkpoint = nil
        state.lastSuccessfulImport = nil
        try modelContext.save()
    }

    private func primaryState() throws -> PersistedHistoryState {
        if let existing = try modelContext.fetch(FetchDescriptor<PersistedHistoryState>()).first {
            return existing
        }
        let state = PersistedHistoryState()
        modelContext.insert(state)
        return state
    }

    private func deleteRecord(workoutID: UUID) throws {
        let descriptor = FetchDescriptor<PersistedWorkoutRouteRecord>(
            predicate: #Predicate { $0.workoutID == workoutID }
        )
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
        }
    }

    private func decode(_ persisted: PersistedWorkoutRouteRecord) -> WorkoutRouteRecord? {
        let activityKind: RouteActivityKind
        let routeParts: [[GeoCoordinate]]
        if let payload = try? decoder.decode(RoutePayload.self, from: persisted.routePartsData) {
            guard payload.version <= RoutePayload.currentVersion else { return nil }
            activityKind = payload.activityKind
            routeParts = payload.routeParts
        } else if let legacyParts = try? decoder.decode(
            [[GeoCoordinate]].self,
            from: persisted.routePartsData
        ) {
            activityKind = .walking
            routeParts = legacyParts
        } else {
            return nil
        }
        let record = WorkoutRouteRecord(
            id: persisted.workoutID,
            start: persisted.start,
            end: persisted.end,
            sourceName: persisted.sourceName,
            activityKind: activityKind,
            routeParts: routeParts
        )
        return record.routeParts.isEmpty ? nil : record
    }
}
