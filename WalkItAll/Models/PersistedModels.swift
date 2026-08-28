import Foundation
import SwiftData

@Model
final class PersistedWorkoutRouteRecord {
    @Attribute(.unique) var workoutID: UUID
    var start: Date
    var end: Date
    var sourceName: String
    @Attribute(.externalStorage) var routePartsData: Data

    init(
        workoutID: UUID,
        start: Date,
        end: Date,
        sourceName: String,
        routePartsData: Data
    ) {
        self.workoutID = workoutID
        self.start = start
        self.end = end
        self.sourceName = sourceName
        self.routePartsData = routePartsData
    }
}

@Model
final class PersistedHistoryState {
    @Attribute(.unique) var key: String
    var checkpoint: Data?
    var lastSuccessfulImport: Date?

    init(
        key: String = "primary",
        checkpoint: Data? = nil,
        lastSuccessfulImport: Date? = nil
    ) {
        self.key = key
        self.checkpoint = checkpoint
        self.lastSuccessfulImport = lastSuccessfulImport
    }
}

@Model
final class PersistedWorkoutImportState {
    @Attribute(.unique) var workoutID: UUID
    var end: Date

    init(workoutID: UUID, end: Date) {
        self.workoutID = workoutID
        self.end = end
    }
}
