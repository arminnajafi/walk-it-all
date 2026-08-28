import Foundation
import SwiftData

enum ProtectedModelContainer {
    static let historyDirectoryName = "WalkItAllHistory"
    static let historyStoreName = "history.store"
    static let cacheProtection = FileProtectionType.complete

    static func make() throws -> ModelContainer {
        let directory = try historyDirectory(create: true)
        try protectAndExcludeFromBackup(directory)
        let container: ModelContainer
        do {
            container = try makeContainer(at: directory)
        } catch {
            // This new cache is derived entirely from Health. Remove only its
            // exact store and sidecars when SwiftData reports corruption.
            try removeHistoryStoreFiles()
            container = try makeContainer(at: directory)
        }
        // A transient attribute error must not be mistaken for store
        // corruption and trigger deletion of otherwise valid history.
        try protectHistoryStoreFiles()
        return container
    }

    static func protectHistoryStoreFiles() throws {
        let directory = try historyDirectory(create: false)
        try protectAndExcludeFromBackup(directory)
        for url in exactStoreFiles(in: directory, baseName: historyStoreName)
            where FileManager.default.fileExists(atPath: url.path)
        {
            try protectAndExcludeFromBackup(url)
        }
        for url in exactStoreSupportDirectories(in: directory, baseName: historyStoreName)
            where FileManager.default.fileExists(atPath: url.path)
        {
            try protectTreeAndExcludeFromBackup(url)
        }
    }

    static func removeHistoryStoreFiles() throws {
        let directory = try historyDirectory(create: false)
        for url in exactStoreFiles(in: directory, baseName: historyStoreName)
            where FileManager.default.fileExists(atPath: url.path)
        {
            try FileManager.default.removeItem(at: url)
        }
        for url in exactStoreSupportDirectories(in: directory, baseName: historyStoreName)
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

    static func exactStoreSupportDirectories(in directory: URL, baseName: String) -> [URL] {
        let stem = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
        return [directory.appendingPathComponent(".\(stem)_SUPPORT", isDirectory: true)]
    }

    static func protectTreeAndExcludeFromBackup(
        _ root: URL,
        protection: FileProtectionType = cacheProtection
    ) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try protectAndExcludeFromBackup(root, protection: protection)
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else { return }
        for case let child as URL in enumerator {
            try protectAndExcludeFromBackup(child, protection: protection)
        }
        if let enumerationError { throw enumerationError }
    }

    static func protectAndExcludeFromBackup(
        _ url: URL,
        protection: FileProtectionType = cacheProtection
    ) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: protection],
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
    let directories: [URL]

    init(files: [URL], directories: [URL] = []) {
        self.files = files
        self.directories = directories
    }

    static func live() throws -> LegacyCoverageStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("WalkItAll", isDirectory: true)
        return LegacyCoverageStore(
            files: ProtectedModelContainer.exactStoreFiles(
                in: directory,
                baseName: "coverage.store"
            ),
            directories: ProtectedModelContainer.exactStoreSupportDirectories(
                in: directory,
                baseName: "coverage.store"
            )
        )
    }

    var exists: Bool {
        files.contains { FileManager.default.fileExists(atPath: $0.path) }
            || directories.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func removeAfterSuccessfulRebuild() throws {
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
