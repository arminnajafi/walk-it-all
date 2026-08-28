import Foundation

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90 ... 90).contains(latitude)
            && (-180 ... 180).contains(longitude)
    }
}

public struct GeoBounds: Codable, Hashable, Sendable {
    public let minimumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLatitude: Double
    public let maximumLongitude: Double

    public init(
        minimumLatitude: Double,
        minimumLongitude: Double,
        maximumLatitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLatitude = maximumLatitude
        self.maximumLongitude = maximumLongitude
    }

    public init?(coordinates: some Sequence<GeoCoordinate>) {
        var iterator = coordinates.makeIterator()
        var firstValid: GeoCoordinate?
        while let coordinate = iterator.next() {
            if coordinate.isValid {
                firstValid = coordinate
                break
            }
        }
        guard let first = firstValid else { return nil }
        var minimumLatitude = first.latitude
        var minimumLongitude = first.longitude
        var maximumLatitude = first.latitude
        var maximumLongitude = first.longitude
        while let coordinate = iterator.next() {
            guard coordinate.isValid else { continue }
            minimumLatitude = min(minimumLatitude, coordinate.latitude)
            minimumLongitude = min(minimumLongitude, coordinate.longitude)
            maximumLatitude = max(maximumLatitude, coordinate.latitude)
            maximumLongitude = max(maximumLongitude, coordinate.longitude)
        }
        self.init(
            minimumLatitude: minimumLatitude,
            minimumLongitude: minimumLongitude,
            maximumLatitude: maximumLatitude,
            maximumLongitude: maximumLongitude
        )
    }
}

public struct RoutePoint: Codable, Hashable, Sendable {
    public let coordinate: GeoCoordinate
    public let timestamp: Date
    public let horizontalAccuracy: Double

    public init(
        coordinate: GeoCoordinate,
        timestamp: Date,
        horizontalAccuracy: Double
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }
}

/// A transient, full-resolution route read from Apple Health. The app discards
/// these points as soon as `RouteProcessor` creates a simplified record.
public struct WorkoutRoute: Codable, Sendable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let sourceName: String
    public let points: [RoutePoint]

    public init(id: UUID, start: Date, end: Date, sourceName: String, points: [RoutePoint]) {
        self.id = id
        self.start = start
        self.end = end
        self.sourceName = sourceName
        self.points = points
    }
}

/// The durable, privacy-minimized representation shown on the lifetime map.
public struct WorkoutRouteRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let sourceName: String
    public let routeParts: [[GeoCoordinate]]

    public init(
        id: UUID,
        start: Date,
        end: Date,
        sourceName: String,
        routeParts: [[GeoCoordinate]]
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.sourceName = sourceName
        self.routeParts = routeParts.filter {
            $0.count >= 2 && $0.allSatisfy(\.isValid)
        }
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    public var geographicBounds: GeoBounds? {
        GeoBounds(coordinates: routeParts.joined())
    }
}

public struct WorkoutRouteBatch: Sendable {
    public struct ProcessedWorkout: Sendable {
        public let id: UUID
        public let end: Date

        public init(id: UUID, end: Date) {
            self.id = id
            self.end = end
        }
    }

    public let routes: [WorkoutRoute]
    public let deletedWorkoutIDs: [UUID]
    public let routeInvalidatedWorkoutIDs: [UUID]
    public let processedWorkouts: [ProcessedWorkout]
    public let checkpoint: Data?
    public let completedCount: Int
    public let totalCount: Int

    public init(
        routes: [WorkoutRoute],
        deletedWorkoutIDs: [UUID] = [],
        routeInvalidatedWorkoutIDs: [UUID] = [],
        processedWorkouts: [ProcessedWorkout] = [],
        checkpoint: Data? = nil,
        completedCount: Int = 0,
        totalCount: Int = 0
    ) {
        self.routes = routes
        self.deletedWorkoutIDs = deletedWorkoutIDs
        self.routeInvalidatedWorkoutIDs = routeInvalidatedWorkoutIDs
        self.processedWorkouts = processedWorkouts
        self.checkpoint = checkpoint
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

public protocol WorkoutRouteSource: Sendable {
    func requestReadAuthorization() async throws
    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error>
}

/// A rebuildable local projection. Apple Health remains the source of truth.
public protocol WalkHistoryRepository: Sendable {
    func loadRecords() async throws -> [WorkoutRouteRecord]
    func save(record: WorkoutRouteRecord) async throws
    func removeRouteRecords(workoutIDs: [UUID]) async throws
    func removeWorkouts(workoutIDs: [UUID]) async throws
    func loadProcessedWorkoutIDs() async throws -> Set<UUID>
    func markWorkoutProcessed(id: UUID, end: Date) async throws
    func loadCheckpoint() async throws -> Data?
    func saveCheckpoint(_ checkpoint: Data?) async throws
    func loadLastSuccessfulImport() async throws -> Date?
    func saveLastSuccessfulImport(_ date: Date) async throws
    func reset() async throws
}

public enum LiveTrailState: String, Codable, Hashable, Sendable {
    case active
    case waitingForHealth
}

/// The sole temporary route owned by Walk It All. It exists only while a user
/// is explicitly tracking or waiting for the corresponding Health workout.
public struct LiveTrailSession: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let state: LiveTrailState
    public let start: Date
    public let end: Date?
    public let routeParts: [[RoutePoint]]
    public let lastUpdate: Date

    public init(
        id: UUID = UUID(),
        state: LiveTrailState,
        start: Date,
        end: Date? = nil,
        routeParts: [[RoutePoint]] = [],
        lastUpdate: Date
    ) {
        self.id = id
        self.state = state
        self.start = start
        self.end = end
        self.routeParts = routeParts.compactMap { part in
            let valid = part.filter { $0.coordinate.isValid }
            return valid.isEmpty ? nil : valid
        }
        self.lastUpdate = lastUpdate
    }

    public var coordinateParts: [[GeoCoordinate]] {
        routeParts.compactMap { part in
            let coordinates = part.map(\.coordinate)
            return coordinates.count >= 2 ? coordinates : nil
        }
    }

    public var duration: TimeInterval {
        max(0, (end ?? lastUpdate).timeIntervalSince(start))
    }
}

public protocol LiveTrailRepository: Sendable {
    func load() async throws -> LiveTrailSession?
    func save(_ session: LiveTrailSession) async throws
    func delete() async throws
}
