import Foundation
import SQLite3
import WalkItAllCore

enum CityPackLoadError: LocalizedError {
    case missingBundledMap
    case couldNotOpen(String)
    case invalidMetadata
    case invalidSegment(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledMap:
            "The Manhattan offline map is missing from this build."
        case let .couldNotOpen(message):
            "The Manhattan offline map could not be opened: \(message)"
        case .invalidMetadata:
            "The Manhattan offline map has invalid metadata."
        case let .invalidSegment(identifier):
            "The Manhattan offline map contains an invalid segment (\(identifier))."
        }
    }
}

actor SQLiteCityPackLoader {
    func loadBundledManhattan(bundle: Bundle = .main) throws -> InMemoryCityCoveragePack {
        guard let url = bundle.url(
            forResource: "manhattan-v3",
            withExtension: "sqlite",
            subdirectory: "OfflineMaps"
        ) ?? bundle.url(forResource: "manhattan-v3", withExtension: "sqlite")
        else {
            #if DEBUG
            return PreviewCityPack.manhattanSample
            #else
            throw CityPackLoadError.missingBundledMap
            #endif
        }
        return try load(url: url)
    }

    func load(url: URL) throws -> InMemoryCityCoveragePack {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let database { sqlite3_close(database) }
            throw CityPackLoadError.couldNotOpen(message)
        }
        defer { sqlite3_close(database) }

        let metadataValues = try readMetadata(database)
        guard let identifier = metadataValues["identifier"],
              let displayName = metadataValues["display_name"],
              let versionString = metadataValues["version"],
              let version = Int(versionString),
              let sourceDateString = metadataValues["source_date"],
              let sourceDate = ISO8601DateFormatter().date(from: sourceDateString),
              let attribution = metadataValues["attribution"]
        else {
            throw CityPackLoadError.invalidMetadata
        }

        let metadata = MapPackMetadata(
            identifier: identifier,
            displayName: displayName,
            version: version,
            sourceDate: sourceDate,
            sourceURL: metadataValues["source_url"].flatMap(URL.init(string:)),
            attribution: attribution,
            attributionURL: metadataValues["attribution_url"].flatMap(URL.init(string:)),
            licenseURL: metadataValues["license_url"].flatMap(URL.init(string:))
        )
        return InMemoryCityCoveragePack(
            metadata: metadata,
            segments: try readSegments(database)
        )
    }

    private func readMetadata(_ database: OpaquePointer) throws -> [String: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT key, value FROM metadata", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw CityPackLoadError.invalidMetadata
        }
        defer { sqlite3_finalize(statement) }

        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            if let key = string(statement, column: 0), let value = string(statement, column: 1) {
                values[key] = value
            }
        }
        return values
    }

    private func readSegments(_ database: OpaquePointer) throws -> [WalkableSegment] {
        let sql = """
        SELECT id, start_node, end_node, kind, length_meters,
               source_way_id, name, coordinates_json, counts_toward_coverage
        FROM segments
        ORDER BY id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw CityPackLoadError.couldNotOpen(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var segments: [WalkableSegment] = []
        let decoder = JSONDecoder()
        while sqlite3_step(statement) == SQLITE_ROW {
            let identifier = string(statement, column: 0) ?? "unknown"
            guard let kindValue = string(statement, column: 3),
                  let kind = WalkableWayKind(rawValue: kindValue),
                  let coordinateJSON = data(statement, column: 7),
                  let pairs = try? decoder.decode([[Double]].self, from: coordinateJSON),
                  pairs.allSatisfy({ $0.count == 2 })
            else {
                throw CityPackLoadError.invalidSegment(identifier)
            }
            let coordinates = pairs.map {
                GeoCoordinate(latitude: $0[1], longitude: $0[0])
            }
            guard coordinates.count >= 2 else {
                throw CityPackLoadError.invalidSegment(identifier)
            }
            let sourceWayID: Int64? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 5)
            segments.append(WalkableSegment(
                id: SegmentID(identifier),
                startNode: NodeID(sqlite3_column_int64(statement, 1)),
                endNode: NodeID(sqlite3_column_int64(statement, 2)),
                coordinates: coordinates,
                lengthMeters: sqlite3_column_double(statement, 4),
                kind: kind,
                sourceWayID: sourceWayID,
                name: string(statement, column: 6),
                countsTowardCoverage: sqlite3_column_int(statement, 8) != 0
            ))
        }
        return segments
    }

    private func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func data(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

enum PreviewCityPack {
    static let manhattanSample: InMemoryCityCoveragePack = {
        let latitudeLines = [40.742, 40.746, 40.750, 40.754, 40.758]
        let longitudeLines = [-74.000, -73.995, -73.990, -73.985]
        var nodeID: Int64 = 1
        var segments: [WalkableSegment] = []

        for (row, latitude) in latitudeLines.enumerated() {
            for column in 0 ..< (longitudeLines.count - 1) {
                let start = GeoCoordinate(latitude: latitude, longitude: longitudeLines[column])
                let end = GeoCoordinate(latitude: latitude, longitude: longitudeLines[column + 1])
                segments.append(WalkableSegment(
                    id: SegmentID("sample-h-\(row)-\(column)"),
                    startNode: NodeID(nodeID),
                    endNode: NodeID(nodeID + 1),
                    coordinates: [start, end],
                    kind: .street,
                    name: "Sample Street"
                ))
                nodeID += 2
            }
        }
        for (column, longitude) in longitudeLines.enumerated() {
            for row in 0 ..< (latitudeLines.count - 1) {
                let start = GeoCoordinate(latitude: latitudeLines[row], longitude: longitude)
                let end = GeoCoordinate(latitude: latitudeLines[row + 1], longitude: longitude)
                segments.append(WalkableSegment(
                    id: SegmentID("sample-v-\(column)-\(row)"),
                    startNode: NodeID(nodeID),
                    endNode: NodeID(nodeID + 1),
                    coordinates: [start, end],
                    kind: .street,
                    name: "Sample Avenue"
                ))
                nodeID += 2
            }
        }

        return InMemoryCityCoveragePack(
            metadata: MapPackMetadata(
                identifier: "manhattan-preview",
                displayName: "Manhattan Preview",
                version: 1,
                sourceDate: Date(timeIntervalSince1970: 0),
                sourceURL: URL(string: "https://www.openstreetmap.org"),
                attribution: "© OpenStreetMap contributors",
                attributionURL: URL(string: "https://www.openstreetmap.org/copyright"),
                licenseURL: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")
            ),
            segments: segments
        )
    }()
}
