import Foundation
import SwiftData
import WalkItAllCore

@ModelActor
actor SwiftDataCoverageRepository: CoverageRepository {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadWorkoutRecords(
        packIdentifier: String,
        packVersion: Int
    ) async throws -> [WorkoutCoverageRecord] {
        let descriptor = FetchDescriptor<PersistedWorkoutCoverage>(
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.packIdentifier == packIdentifier && $0.packVersion == packVersion }
            .compactMap(decode)
    }

    func save(
        record: WorkoutCoverageRecord,
        packIdentifier: String,
        packVersion: Int
    ) async throws {
        let routeData = try encoder.encode(record.simplifiedRoute)
        let contributionData = try encoder.encode(record.contribution)
        let unmatchedData = try encoder.encode(record.unmatchedPortions)
        let descriptor = FetchDescriptor<PersistedWorkoutCoverage>()
        let existing = try modelContext.fetch(descriptor).first { $0.workoutID == record.id }

        if let existing {
            existing.start = record.start
            existing.end = record.end
            existing.sourceName = record.sourceName
            existing.packIdentifier = packIdentifier
            existing.packVersion = packVersion
            existing.routeData = routeData
            existing.contributionData = contributionData
            existing.unmatchedData = unmatchedData
        } else {
            modelContext.insert(PersistedWorkoutCoverage(
                workoutID: record.id,
                start: record.start,
                end: record.end,
                sourceName: record.sourceName,
                packIdentifier: packIdentifier,
                packVersion: packVersion,
                routeData: routeData,
                contributionData: contributionData,
                unmatchedData: unmatchedData
            ))
        }
        try modelContext.save()
    }

    func remove(workoutIDs: [UUID]) async throws {
        guard !workoutIDs.isEmpty else { return }
        let ids = Set(workoutIDs)
        for record in try modelContext.fetch(FetchDescriptor<PersistedWorkoutCoverage>())
            where ids.contains(record.workoutID)
        {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    func replaceSnapshot(_ snapshot: CoverageSnapshot) async throws {
        let state = try primaryState()
        state.snapshotData = try encoder.encode(snapshot)
        state.lastSuccessfulImport = Date()
        try modelContext.save()
    }

    func loadSnapshot() async throws -> CoverageSnapshot? {
        guard let data = try primaryState().snapshotData else { return nil }
        return try? decoder.decode(CoverageSnapshot.self, from: data)
    }

    func loadCheckpoint() async throws -> Data? {
        try primaryState().checkpoint
    }

    func saveCheckpoint(_ checkpoint: Data?) async throws {
        let state = try primaryState()
        state.checkpoint = checkpoint
        try modelContext.save()
    }

    func resetDerivedCoverage() async throws {
        for record in try modelContext.fetch(FetchDescriptor<PersistedWorkoutCoverage>()) {
            modelContext.delete(record)
        }
        let state = try primaryState()
        state.snapshotData = nil
        state.checkpoint = nil
        state.lastSuccessfulImport = nil
        try modelContext.save()
    }

    private func primaryState() throws -> PersistedAppState {
        if let existing = try modelContext.fetch(FetchDescriptor<PersistedAppState>()).first {
            return existing
        }
        let state = PersistedAppState()
        modelContext.insert(state)
        return state
    }

    private func decode(_ persisted: PersistedWorkoutCoverage) -> WorkoutCoverageRecord? {
        guard let route = try? decoder.decode([GeoCoordinate].self, from: persisted.routeData),
              let contribution = try? decoder.decode(
                  WorkoutCoverageContribution.self,
                  from: persisted.contributionData
              ),
              let unmatched = try? decoder.decode(
                  [UnmatchedPortion].self,
                  from: persisted.unmatchedData
              )
        else { return nil }

        return WorkoutCoverageRecord(
            id: persisted.workoutID,
            start: persisted.start,
            end: persisted.end,
            sourceName: persisted.sourceName,
            simplifiedRoute: route,
            contribution: contribution,
            unmatchedPortions: unmatched
        )
    }
}

