import Foundation
import WalkItAllCore

actor ProtectedLiveTrailRepository: LiveTrailRepository {
    static let directoryName = "WalkItAllLiveTrail"
    static let fileName = "session.json"

    private let fileURL: URL
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        directoryURL = fileURL.deletingLastPathComponent()
    }

    static func live() throws -> ProtectedLiveTrailRepository {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        return ProtectedLiveTrailRepository(
            fileURL: directory.appendingPathComponent(fileName, isDirectory: false)
        )
    }

    func load() throws -> LiveTrailSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let session = try decoder.decode(LiveTrailSession.self, from: data)
            try protectFiles()
            return session
        } catch is DecodingError {
            // Health remains the permanent source. A malformed temporary file
            // is unusable and deleting this exact file is safer than retrying it.
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    func save(_ session: LiveTrailSession) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try ProtectedModelContainer.protectAndExcludeFromBackup(directoryURL)
        try encoder.encode(session).write(to: fileURL, options: .atomic)
        try protectFiles()
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func protectFiles() throws {
        try ProtectedModelContainer.protectAndExcludeFromBackup(directoryURL)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try ProtectedModelContainer.protectAndExcludeFromBackup(fileURL)
        }
    }
}
