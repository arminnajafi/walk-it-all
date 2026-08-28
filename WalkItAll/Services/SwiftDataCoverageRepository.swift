import Foundation
import SwiftData
import WalkItAllCore

@ModelActor
actor SwiftDataCoverageRepository: CoverageRepository {
    // Increment whenever matcher semantics change so every Health route is
    // deterministically projected again instead of mixing old and new results.
    private static let currentMatchingProjectionVersion = 2
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func prepareForPack(identifier: String, version: Int) async throws {
        let state = try primaryState()
        let hasCoverageRecords = !(try modelContext.fetch(
            FetchDescriptor<PersistedWorkoutCoverage>()
        )).isEmpty
        let hasImportRecords = !(try modelContext.fetch(
            FetchDescriptor<PersistedWorkoutImportState>()
        )).isEmpty
        let hasDerivedState = state.checkpoint != nil
            || state.snapshotData != nil
            || state.lastSuccessfulImport != nil
            || hasCoverageRecords
            || hasImportRecords
        let isCompatible = state.packIdentifier == identifier
            && state.packVersion == version
            && state.matchingProjectionVersion == Self.currentMatchingProjectionVersion

        guard !hasDerivedState || isCompatible else {
            try await resetDerivedCoverage()
            let resetState = try primaryState()
            resetState.packIdentifier = identifier
            resetState.packVersion = version
            resetState.matchingProjectionVersion = Self.currentMatchingProjectionVersion
            try modelContext.save()
            return
        }

        state.packIdentifier = identifier
        state.packVersion = version
        state.matchingProjectionVersion = Self.currentMatchingProjectionVersion
        // Kept in the schema only so existing personal stores migrate cleanly.
        // Aggregate coverage is always derived from per-workout contributions.
        state.snapshotData = nil
        try modelContext.save()
    }

    func loadWorkoutRecords(
        packIdentifier: String,
        packVersion: Int
    ) async throws -> [WorkoutCoverageRecord] {
        let descriptor = FetchDescriptor<PersistedWorkoutCoverage>(
            predicate: #Predicate {
                $0.packIdentifier == packIdentifier && $0.packVersion == packVersion
            },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        let persistedRecords = try modelContext.fetch(descriptor)
        let records = persistedRecords.compactMap(decode)
        guard records.count == persistedRecords.count else {
            // A partial cache cannot be trusted: its processed-workout ledger
            // and Health anchors may otherwise prevent an older workout from
            // being reconstructed. Clear the rebuildable projection so the
            // next foreground refresh performs a complete Health import.
            try await resetDerivedCoverage()
            return []
        }
        return records
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

    func save(
        record: WorkoutCoverageRecord,
        packIdentifier: String,
        packVersion: Int
    ) async throws {
        let routeData = try encoder.encode(record.simplifiedRouteParts)
        let contributionData = try encoder.encode(record.contribution)
        let unmatchedData = try encoder.encode(record.unmatchedPortions)
        let id = record.id
        let descriptor = FetchDescriptor<PersistedWorkoutCoverage>(
            predicate: #Predicate { $0.workoutID == id }
        )
        let existing = try modelContext.fetch(descriptor).first

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
        for id in workoutIDs {
            try deleteCoverage(workoutID: id)
            let importDescriptor = FetchDescriptor<PersistedWorkoutImportState>(
                predicate: #Predicate { $0.workoutID == id }
            )
            if let state = try modelContext.fetch(importDescriptor).first {
                modelContext.delete(state)
            }
        }
        try modelContext.save()
    }

    func removeCoverage(workoutIDs: [UUID]) async throws {
        guard !workoutIDs.isEmpty else { return }
        for id in workoutIDs {
            try deleteCoverage(workoutID: id)
        }
        try modelContext.save()
    }

    func loadCheckpoint() async throws -> Data? {
        try primaryState().checkpoint
    }

    func loadLastSuccessfulImport() async throws -> Date? {
        try primaryState().lastSuccessfulImport
    }

    func saveCheckpoint(_ checkpoint: Data?) async throws {
        let state = try primaryState()
        state.checkpoint = checkpoint
        try modelContext.save()
    }

    func saveLastSuccessfulImport(_ date: Date) async throws {
        let state = try primaryState()
        state.lastSuccessfulImport = date
        try modelContext.save()
    }

    func resetDerivedCoverage() async throws {
        for record in try modelContext.fetch(FetchDescriptor<PersistedWorkoutCoverage>()) {
            modelContext.delete(record)
        }
        for state in try modelContext.fetch(FetchDescriptor<PersistedWorkoutImportState>()) {
            modelContext.delete(state)
        }
        let state = try primaryState()
        state.snapshotData = nil
        state.checkpoint = nil
        state.lastSuccessfulImport = nil
        state.packIdentifier = nil
        state.packVersion = nil
        state.matchingProjectionVersion = nil
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

    private func deleteCoverage(workoutID: UUID) throws {
        let coverageDescriptor = FetchDescriptor<PersistedWorkoutCoverage>(
            predicate: #Predicate { $0.workoutID == workoutID }
        )
        if let record = try modelContext.fetch(coverageDescriptor).first {
            modelContext.delete(record)
        }
    }

    private func decode(_ persisted: PersistedWorkoutCoverage) -> WorkoutCoverageRecord? {
        let routeParts: [[GeoCoordinate]]
        if let decoded = try? decoder.decode([[GeoCoordinate]].self, from: persisted.routeData) {
            routeParts = decoded
        } else if let legacy = try? decoder.decode([GeoCoordinate].self, from: persisted.routeData) {
            routeParts = [legacy]
        } else {
            return nil
        }

        guard let contribution = try? decoder.decode(
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
            simplifiedRouteParts: routeParts,
            contribution: contribution,
            unmatchedPortions: unmatched
        )
    }
}
