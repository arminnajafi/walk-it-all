import Foundation
import SwiftData

@Model
final class PersistedWorkoutCoverage {
    @Attribute(.unique) var workoutID: UUID
    var start: Date
    var end: Date
    var sourceName: String
    var packIdentifier: String
    var packVersion: Int
    @Attribute(.externalStorage) var routeData: Data
    @Attribute(.externalStorage) var contributionData: Data
    @Attribute(.externalStorage) var unmatchedData: Data

    init(
        workoutID: UUID,
        start: Date,
        end: Date,
        sourceName: String,
        packIdentifier: String,
        packVersion: Int,
        routeData: Data,
        contributionData: Data,
        unmatchedData: Data
    ) {
        self.workoutID = workoutID
        self.start = start
        self.end = end
        self.sourceName = sourceName
        self.packIdentifier = packIdentifier
        self.packVersion = packVersion
        self.routeData = routeData
        self.contributionData = contributionData
        self.unmatchedData = unmatchedData
    }
}

@Model
final class PersistedAppState {
    @Attribute(.unique) var key: String
    var checkpoint: Data?
    @Attribute(.externalStorage) var snapshotData: Data?
    var lastSuccessfulImport: Date?

    init(
        key: String = "primary",
        checkpoint: Data? = nil,
        snapshotData: Data? = nil,
        lastSuccessfulImport: Date? = nil
    ) {
        self.key = key
        self.checkpoint = checkpoint
        self.snapshotData = snapshotData
        self.lastSuccessfulImport = lastSuccessfulImport
    }
}

