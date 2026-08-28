import Foundation

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
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

public struct SegmentID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public var description: String { rawValue }
}

public struct NodeID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int64) {
        self.rawValue = rawValue
    }
}

public enum WalkableWayKind: String, Codable, CaseIterable, Sendable {
    case street
    case pedestrian
    case parkPath
    case greenway
    case steps
    case connector
}

public struct WalkableSegment: Codable, Hashable, Sendable, Identifiable {
    public let id: SegmentID
    public let startNode: NodeID
    public let endNode: NodeID
    public let coordinates: [GeoCoordinate]
    public let lengthMeters: Double
    public let kind: WalkableWayKind
    public let sourceWayID: Int64?
    public let name: String?
    public let countsTowardCoverage: Bool

    public init(
        id: SegmentID,
        startNode: NodeID,
        endNode: NodeID,
        coordinates: [GeoCoordinate],
        lengthMeters: Double? = nil,
        kind: WalkableWayKind,
        sourceWayID: Int64? = nil,
        name: String? = nil,
        countsTowardCoverage: Bool = true
    ) {
        precondition(coordinates.count >= 2, "A segment needs at least two coordinates")
        self.id = id
        self.startNode = startNode
        self.endNode = endNode
        self.coordinates = coordinates
        self.lengthMeters = lengthMeters ?? GeoMath.polylineLength(coordinates)
        self.kind = kind
        self.sourceWayID = sourceWayID
        self.name = name
        self.countsTowardCoverage = countsTowardCoverage
    }
}

public struct SegmentInterval: Codable, Hashable, Sendable {
    public let segmentID: SegmentID
    public let lowerBoundMeters: Double
    public let upperBoundMeters: Double
    public let confidence: Double

    public init(
        segmentID: SegmentID,
        lowerBoundMeters: Double,
        upperBoundMeters: Double,
        confidence: Double
    ) {
        self.segmentID = segmentID
        self.lowerBoundMeters = min(lowerBoundMeters, upperBoundMeters)
        self.upperBoundMeters = max(lowerBoundMeters, upperBoundMeters)
        self.confidence = min(1, max(0, confidence))
    }

    public var lengthMeters: Double {
        max(0, upperBoundMeters - lowerBoundMeters)
    }
}

public struct UnmatchedPortion: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case inaccurateLocation
        case routeGap
        case noNearbyWalkableWay
        case lowConfidence
        case implausibleTransition
    }

    public let start: Date
    public let end: Date
    public let reason: Reason

    public init(start: Date, end: Date, reason: Reason) {
        self.start = min(start, end)
        self.end = max(start, end)
        self.reason = reason
    }

    public static func coalesced(
        _ portions: [UnmatchedPortion],
        maximumGap: TimeInterval = 1
    ) -> [UnmatchedPortion] {
        let sorted = portions.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        var result: [UnmatchedPortion] = []
        for portion in sorted {
            if let last = result.last,
               last.reason == portion.reason,
               portion.start.timeIntervalSince(last.end) <= maximumGap
            {
                result[result.count - 1] = UnmatchedPortion(
                    start: last.start,
                    end: max(last.end, portion.end),
                    reason: last.reason
                )
            } else {
                result.append(portion)
            }
        }
        return result
    }
}

public struct MatchResult: Codable, Sendable {
    public let intervals: [SegmentInterval]
    public let unmatchedPortions: [UnmatchedPortion]
    public let acceptedPointCount: Int
    public let rejectedPointCount: Int
    public let averageConfidence: Double
    public let candidateSegmentIDs: Set<SegmentID>

    public init(
        intervals: [SegmentInterval],
        unmatchedPortions: [UnmatchedPortion],
        acceptedPointCount: Int,
        rejectedPointCount: Int,
        averageConfidence: Double,
        candidateSegmentIDs: Set<SegmentID> = []
    ) {
        self.intervals = intervals
        self.unmatchedPortions = unmatchedPortions
        self.acceptedPointCount = acceptedPointCount
        self.rejectedPointCount = rejectedPointCount
        self.averageConfidence = averageConfidence
        self.candidateSegmentIDs = candidateSegmentIDs
    }
}

public struct MapPackMetadata: Codable, Hashable, Sendable {
    public let identifier: String
    public let displayName: String
    public let version: Int
    public let sourceDate: Date
    public let sourceURL: URL?
    public let attribution: String

    public init(
        identifier: String,
        displayName: String,
        version: Int,
        sourceDate: Date,
        sourceURL: URL?,
        attribution: String
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.version = version
        self.sourceDate = sourceDate
        self.sourceURL = sourceURL
        self.attribution = attribution
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
}

public struct GraphPath: Sendable {
    public let distanceMeters: Double
    public let segmentIDs: [SegmentID]

    public init(distanceMeters: Double, segmentIDs: [SegmentID]) {
        self.distanceMeters = distanceMeters
        self.segmentIDs = segmentIDs
    }
}

public protocol CityCoveragePack: Sendable {
    var metadata: MapPackMetadata { get }
    var segments: [WalkableSegment] { get }
    var totalLengthMeters: Double { get }
    var geographicBounds: GeoBounds? { get }

    func segment(id: SegmentID) -> WalkableSegment?
    func segments(near coordinate: GeoCoordinate, radiusMeters: Double) -> [WalkableSegment]
    func shortestPath(from: NodeID, to: NodeID, maximumDistanceMeters: Double) -> GraphPath?
}

public protocol MapMatcher: Sendable {
    func match(points: [RoutePoint], in pack: any CityCoveragePack) async throws -> MatchResult
}

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
    func route(for workoutID: UUID) async throws -> WorkoutRoute?
    func routeBatches(
        since checkpoint: Data?,
        excluding workoutIDs: Set<UUID>
    ) async -> AsyncThrowingStream<WorkoutRouteBatch, Error>
}

public struct WorkoutCoverageContribution: Codable, Sendable {
    public let workoutID: UUID
    public let intervals: [SegmentInterval]
    public let confidence: Double

    public init(workoutID: UUID, intervals: [SegmentInterval], confidence: Double) {
        self.workoutID = workoutID
        self.intervals = Self.normalized(intervals)
        self.confidence = min(1, max(0, confidence))
    }

    public var uniqueCoveredDistanceMeters: Double {
        intervals.reduce(0) { $0 + $1.lengthMeters }
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID
        case intervals
        case confidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workoutID: try container.decode(UUID.self, forKey: .workoutID),
            intervals: try container.decode([SegmentInterval].self, forKey: .intervals),
            confidence: try container.decode(Double.self, forKey: .confidence)
        )
    }

    private static func normalized(_ intervals: [SegmentInterval]) -> [SegmentInterval] {
        Dictionary(grouping: intervals, by: \.segmentID)
            .flatMap { segmentID, segmentIntervals -> [SegmentInterval] in
                let sorted = segmentIntervals
                    .map {
                        SegmentInterval(
                            segmentID: segmentID,
                            lowerBoundMeters: max(0, $0.lowerBoundMeters),
                            upperBoundMeters: max(0, $0.upperBoundMeters),
                            confidence: $0.confidence
                        )
                    }
                    .filter { $0.lengthMeters > 0 }
                    .sorted {
                        if $0.lowerBoundMeters == $1.lowerBoundMeters {
                            return $0.upperBoundMeters < $1.upperBoundMeters
                        }
                        return $0.lowerBoundMeters < $1.lowerBoundMeters
                    }

                var merged: [SegmentInterval] = []
                for interval in sorted {
                    guard let last = merged.last,
                          interval.lowerBoundMeters <= last.upperBoundMeters + 0.01
                    else {
                        merged.append(interval)
                        continue
                    }
                    let combinedLength = last.lengthMeters + interval.lengthMeters
                    let combinedConfidence = combinedLength > 0
                        ? ((last.confidence * last.lengthMeters)
                            + (interval.confidence * interval.lengthMeters)) / combinedLength
                        : max(last.confidence, interval.confidence)
                    merged[merged.count - 1] = SegmentInterval(
                        segmentID: segmentID,
                        lowerBoundMeters: last.lowerBoundMeters,
                        upperBoundMeters: max(last.upperBoundMeters, interval.upperBoundMeters),
                        confidence: combinedConfidence
                    )
                }
                return merged
            }
            .sorted {
                if $0.segmentID == $1.segmentID {
                    return $0.lowerBoundMeters < $1.lowerBoundMeters
                }
                return $0.segmentID.rawValue < $1.segmentID.rawValue
            }
    }
}

public struct WorkoutCoverageRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let sourceName: String
    public let simplifiedRouteParts: [[GeoCoordinate]]
    public let contribution: WorkoutCoverageContribution
    public let unmatchedPortions: [UnmatchedPortion]

    public init(
        id: UUID,
        start: Date,
        end: Date,
        sourceName: String,
        simplifiedRouteParts: [[GeoCoordinate]],
        contribution: WorkoutCoverageContribution,
        unmatchedPortions: [UnmatchedPortion]
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.sourceName = sourceName
        self.simplifiedRouteParts = simplifiedRouteParts
        self.contribution = contribution
        self.unmatchedPortions = UnmatchedPortion.coalesced(unmatchedPortions)
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case sourceName
        case simplifiedRouteParts
        case contribution
        case unmatchedPortions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            start: try container.decode(Date.self, forKey: .start),
            end: try container.decode(Date.self, forKey: .end),
            sourceName: try container.decode(String.self, forKey: .sourceName),
            simplifiedRouteParts: try container.decode([[GeoCoordinate]].self, forKey: .simplifiedRouteParts),
            contribution: try container.decode(WorkoutCoverageContribution.self, forKey: .contribution),
            unmatchedPortions: try container.decode([UnmatchedPortion].self, forKey: .unmatchedPortions)
        )
    }
}

public struct CoverageSnapshot: Codable, Sendable {
    public let packIdentifier: String
    public let packVersion: Int
    public let totalDistanceMeters: Double
    public let coveredDistanceMeters: Double
    public let completedSegmentIDs: Set<SegmentID>
    public let coveredMetersBySegment: [SegmentID: Double]
    public let coveredIntervalsBySegment: [SegmentID: [SegmentInterval]]
    public let averageConfidence: Double

    public init(
        packIdentifier: String,
        packVersion: Int,
        totalDistanceMeters: Double,
        coveredDistanceMeters: Double,
        completedSegmentIDs: Set<SegmentID>,
        coveredMetersBySegment: [SegmentID: Double],
        coveredIntervalsBySegment: [SegmentID: [SegmentInterval]],
        averageConfidence: Double
    ) {
        self.packIdentifier = packIdentifier
        self.packVersion = packVersion
        self.totalDistanceMeters = totalDistanceMeters
        self.coveredDistanceMeters = coveredDistanceMeters
        self.completedSegmentIDs = completedSegmentIDs
        self.coveredMetersBySegment = coveredMetersBySegment
        self.coveredIntervalsBySegment = coveredIntervalsBySegment
        self.averageConfidence = averageConfidence
    }

    public var completionFraction: Double {
        guard totalDistanceMeters > 0 else { return 0 }
        return min(1, max(0, coveredDistanceMeters / totalDistanceMeters))
    }

    public var remainingDistanceMeters: Double {
        max(0, totalDistanceMeters - coveredDistanceMeters)
    }

    public static func empty(pack: any CityCoveragePack) -> CoverageSnapshot {
        CoverageSnapshot(
            packIdentifier: pack.metadata.identifier,
            packVersion: pack.metadata.version,
            totalDistanceMeters: pack.totalLengthMeters,
            coveredDistanceMeters: 0,
            completedSegmentIDs: [],
            coveredMetersBySegment: [:],
            coveredIntervalsBySegment: [:],
            averageConfidence: 0
        )
    }
}

public protocol CoverageRepository: Sendable {
    func prepareForPack(identifier: String, version: Int) async throws
    func loadWorkoutRecords(packIdentifier: String, packVersion: Int) async throws -> [WorkoutCoverageRecord]
    func loadProcessedWorkoutIDs() async throws -> Set<UUID>
    func markWorkoutProcessed(id: UUID, end: Date) async throws
    func save(record: WorkoutCoverageRecord, packIdentifier: String, packVersion: Int) async throws
    func removeCoverage(workoutIDs: [UUID]) async throws
    func remove(workoutIDs: [UUID]) async throws
    func loadCheckpoint() async throws -> Data?
    func loadLastSuccessfulImport() async throws -> Date?
    func saveCheckpoint(_ checkpoint: Data?) async throws
    func saveLastSuccessfulImport(_ date: Date) async throws
    func resetDerivedCoverage() async throws
}
