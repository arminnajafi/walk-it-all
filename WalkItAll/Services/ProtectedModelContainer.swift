import Foundation
import SwiftData

enum ProtectedModelContainer {
    static let historyDirectoryName = "WalkItAllHistory"
    static let historyStoreName = "history.store"
    static let cacheProtection = FileProtectionType.complete

    static func make() throws -> ModelContainer {
        let directory = try historyDirectory(create: true)
        try protectAndExcludeFromBackup(directory)
        do {
            let container = try makeContainer(at: directory)
            try protectHistoryStoreFiles()
            return container
        } catch {
            // This new cache is derived entirely from Health. Remove only its
            // exact store and sidecars when SwiftData reports corruption.
            try removeHistoryStoreFiles()
            let container = try makeContainer(at: directory)
            try protectHistoryStoreFiles()
            return container
        }
    }

    static func protectHistoryStoreFiles() throws {
        let directory = try historyDirectory(create: false)
        try protectAndExcludeFromBackup(directory)
        for url in exactStoreFiles(in: directory, baseName: historyStoreName)
            where FileManager.default.fileExists(atPath: url.path)
        {
            try protectAndExcludeFromBackup(url)
        }
    }

    static func removeHistoryStoreFiles() throws {
        let directory = try historyDirectory(create: false)
        for url in exactStoreFiles(in: directory, baseName: historyStoreName)
            where FileManager.default.fileExists(atPath: url.path)
        {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func makeContainer(at directory: URL) throws -> ModelContainer {
        let schema = Schema([
            PersistedWorkoutRouteRecord.self,
            PersistedHistoryState.self,
            PersistedWorkoutImportState.self,
        ])
        let configuration = ModelConfiguration(
            "WalkItAllHistory",
            schema: schema,
            url: directory.appendingPathComponent(historyStoreName),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func historyDirectory(create: Bool) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directory = applicationSupport.appendingPathComponent(historyDirectoryName, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    fileprivate static func exactStoreFiles(in directory: URL, baseName: String) -> [URL] {
        [baseName, "\(baseName)-wal", "\(baseName)-shm"].map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
    }

    static func protectAndExcludeFromBackup(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: cacheProtection],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(values)
    }
}

struct LegacyCoverageStore: Sendable {
    let files: [URL]

    static func live() throws -> LegacyCoverageStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("WalkItAll", isDirectory: true)
        return LegacyCoverageStore(files: ProtectedModelContainer.exactStoreFiles(
            in: directory,
            baseName: "coverage.store"
        ))
    }

    var exists: Bool {
        files.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func removeAfterSuccessfulRebuild() throws {
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
