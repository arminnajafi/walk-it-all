import Foundation
import WalkItAllCore

actor ProtectedLiveTrailRepository: LiveTrailRepository {
    static let directoryName = "WalkItAllLiveTrail"
    static let fileName = "session.json"
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

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
            guard Self.isValid(session) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
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
        try ProtectedModelContainer.protectAndExcludeFromBackup(
            directoryURL,
            protection: Self.protection
        )
        try encoder.encode(session).write(to: fileURL, options: .atomic)
        try protectFiles()
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func protectFiles() throws {
        try ProtectedModelContainer.protectAndExcludeFromBackup(
            directoryURL,
            protection: Self.protection
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try ProtectedModelContainer.protectAndExcludeFromBackup(
                fileURL,
                protection: Self.protection
            )
        }
    }

    private static func isValid(_ session: LiveTrailSession) -> Bool {
        guard session.start <= session.lastUpdate else { return false }
        switch session.state {
        case .active, .paused:
            guard session.end == nil else { return false }
        case .finished:
            guard let end = session.end, end >= session.start else { return false }
        }

        return session.routeParts.allSatisfy { part in
            zip(part, part.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp }
                && part.allSatisfy {
                    $0.coordinate.isValid
                        && $0.horizontalAccuracy.isFinite
                        && (0 ... 50).contains($0.horizontalAccuracy)
                        && $0.timestamp >= session.start
                        && $0.timestamp <= session.lastUpdate
                }
        }
    }
}
