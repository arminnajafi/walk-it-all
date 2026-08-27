import Foundation
import SwiftData

enum ProtectedModelContainer {
    static func make() throws -> ModelContainer {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("WalkItAll", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(resourceValues)

        let schema = Schema([
            PersistedWorkoutCoverage.self,
            PersistedAppState.self,
            PersistedWorkoutImportState.self,
        ])
        let configuration = ModelConfiguration(
            "WalkItAllLocalCache",
            schema: schema,
            url: directory.appendingPathComponent("coverage.store"),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
