#if DEBUG
import Foundation
import WalkItAllCore

struct RouteReviewFixture: Codable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let packIdentifier: String
    let packVersion: Int
    let acceptedPointCount: Int
    let rejectedPointCount: Int
    let correctlyCreditedMeters: Double
    let creditedMeters: Double
    let clearlyWalkedMeters: Double
    let rejectionReasonCounts: [String: Int]
    let creditedSegmentIDs: [String]
    let clearlyWalkedSegmentIDs: [String]
    let incorrectCreditedSegmentIDs: [String]
    let clearlyWalkedMissedSegmentIDs: [String]
}

struct PrivateRouteDiagnosticFixture: Codable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let packIdentifier: String
    let packVersion: Int
    let route: WorkoutRoute
    let match: MatchResult
}

enum DebugRouteFixtureStore {
    static func saveReview(_ fixture: RouteReviewFixture) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let directory = try protectedDirectory()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = directory.appendingPathComponent("review-\(UUID().uuidString).json")
            try encoder.encode(fixture).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }.value
    }

    static func saveDiagnostic(_ fixture: PrivateRouteDiagnosticFixture) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let directory = try protectedDirectory()
            let encoder = JSONEncoder()
            // Health locations can contain sub-second timestamps. Milliseconds
            // keep private diagnostics reproducible; second-only ISO-8601 can
            // collapse distinct samples into artificial zero-time route gaps.
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let url = directory.appendingPathComponent("diagnostic-\(UUID().uuidString).json")
            try encoder.encode(fixture).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }.value
    }

    private static func protectedDirectory() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("WalkItAll", isDirectory: true)
            .appendingPathComponent("LocalRouteFixtures", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(values)
        return protectedDirectory
    }
}
#endif
