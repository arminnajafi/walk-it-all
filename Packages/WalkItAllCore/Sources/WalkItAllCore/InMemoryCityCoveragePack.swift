import Foundation

public final class InMemoryCityCoveragePack: CityCoveragePack, @unchecked Sendable {
    private struct GridKey: Hashable {
        let x: Int
        let y: Int
    }

    private struct Edge: Sendable {
        let destination: NodeID
        let segmentID: SegmentID
        let distanceMeters: Double
    }

    private struct QueueEntry {
        let node: NodeID
        let distance: Double
    }

    public let metadata: MapPackMetadata
    public let segments: [WalkableSegment]
    public let totalLengthMeters: Double
    public let geographicBounds: GeoBounds?

    private let segmentByID: [SegmentID: WalkableSegment]
    private let grid: [GridKey: [SegmentID]]
    private let adjacency: [NodeID: [Edge]]
    private let gridCellMeters: Double

    public init(
        metadata: MapPackMetadata,
        segments: [WalkableSegment],
        gridCellMeters: Double = 100
    ) {
        self.metadata = metadata
        self.segments = segments
        totalLengthMeters = segments.reduce(0) {
            $0 + ($1.countsTowardCoverage ? $1.lengthMeters : 0)
        }
        segmentByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        self.gridCellMeters = gridCellMeters

        var mutableGrid: [GridKey: Set<SegmentID>] = [:]
        var mutableAdjacency: [NodeID: [Edge]] = [:]
        var minimumLatitude = Double.greatestFiniteMagnitude
        var minimumLongitude = Double.greatestFiniteMagnitude
        var maximumLatitude = -Double.greatestFiniteMagnitude
        var maximumLongitude = -Double.greatestFiniteMagnitude

        for segment in segments {
            if segment.countsTowardCoverage {
                for coordinate in segment.coordinates {
                    minimumLatitude = min(minimumLatitude, coordinate.latitude)
                    minimumLongitude = min(minimumLongitude, coordinate.longitude)
                    maximumLatitude = max(maximumLatitude, coordinate.latitude)
                    maximumLongitude = max(maximumLongitude, coordinate.longitude)
                }
            }
            let points = segment.coordinates.map { GeoMath.globalMeters($0) }
            guard let minX = points.map(\.x).min(),
                  let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(),
                  let maxY = points.map(\.y).max()
            else { continue }

            let xRange = Int(floor(minX / gridCellMeters)) ... Int(floor(maxX / gridCellMeters))
            let yRange = Int(floor(minY / gridCellMeters)) ... Int(floor(maxY / gridCellMeters))
            for x in xRange {
                for y in yRange {
                    mutableGrid[GridKey(x: x, y: y), default: []].insert(segment.id)
                }
            }

            mutableAdjacency[segment.startNode, default: []].append(
                Edge(destination: segment.endNode, segmentID: segment.id, distanceMeters: segment.lengthMeters)
            )
            mutableAdjacency[segment.endNode, default: []].append(
                Edge(destination: segment.startNode, segmentID: segment.id, distanceMeters: segment.lengthMeters)
            )
        }

        geographicBounds = minimumLatitude.isFinite && minimumLatitude != .greatestFiniteMagnitude
            ? GeoBounds(
                minimumLatitude: minimumLatitude,
                minimumLongitude: minimumLongitude,
                maximumLatitude: maximumLatitude,
                maximumLongitude: maximumLongitude
            )
            : nil
        grid = mutableGrid.mapValues(Array.init)
        adjacency = mutableAdjacency
    }

    public func segment(id: SegmentID) -> WalkableSegment? {
        segmentByID[id]
    }

    public func segments(near coordinate: GeoCoordinate, radiusMeters: Double) -> [WalkableSegment] {
        let point = GeoMath.globalMeters(coordinate)
        let minX = Int(floor((point.x - radiusMeters) / gridCellMeters))
        let maxX = Int(floor((point.x + radiusMeters) / gridCellMeters))
        let minY = Int(floor((point.y - radiusMeters) / gridCellMeters))
        let maxY = Int(floor((point.y + radiusMeters) / gridCellMeters))

        var ids = Set<SegmentID>()
        for x in minX ... maxX {
            for y in minY ... maxY {
                ids.formUnion(grid[GridKey(x: x, y: y)] ?? [])
            }
        }

        return ids.compactMap { segmentByID[$0] }.filter { segment in
            guard segment.countsTowardCoverage else { return false }
            guard let projection = GeoMath.project(coordinate, onto: segment.coordinates) else { return false }
            return projection.distanceMeters <= radiusMeters
        }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func shortestPath(
        from start: NodeID,
        to destination: NodeID,
        maximumDistanceMeters: Double
    ) -> GraphPath? {
        if start == destination {
            return GraphPath(distanceMeters: 0, segmentIDs: [])
        }

        var heap = MinHeap<QueueEntry> { $0.distance < $1.distance }
        var bestDistance: [NodeID: Double] = [start: 0]
        var predecessor: [NodeID: (node: NodeID, segmentID: SegmentID)] = [:]
        heap.insert(QueueEntry(node: start, distance: 0))

        while let current = heap.removeMinimum() {
            guard current.distance == bestDistance[current.node] else { continue }
            guard current.distance <= maximumDistanceMeters else { continue }
            if current.node == destination { break }

            for edge in adjacency[current.node] ?? [] {
                let proposed = current.distance + edge.distanceMeters
                guard proposed <= maximumDistanceMeters,
                      proposed < bestDistance[edge.destination, default: .greatestFiniteMagnitude]
                else { continue }

                bestDistance[edge.destination] = proposed
                predecessor[edge.destination] = (current.node, edge.segmentID)
                heap.insert(QueueEntry(node: edge.destination, distance: proposed))
            }
        }

        guard let distance = bestDistance[destination] else { return nil }
        var node = destination
        var reversedSegments: [SegmentID] = []
        while node != start {
            guard let previous = predecessor[node] else { return nil }
            reversedSegments.append(previous.segmentID)
            node = previous.node
        }

        return GraphPath(distanceMeters: distance, segmentIDs: reversedSegments.reversed())
    }
}

private struct MinHeap<Element> {
    private var values: [Element] = []
    private let orderedBefore: (Element, Element) -> Bool

    init(orderedBefore: @escaping (Element, Element) -> Bool) {
        self.orderedBefore = orderedBefore
    }

    mutating func insert(_ element: Element) {
        values.append(element)
        var child = values.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard orderedBefore(values[child], values[parent]) else { break }
            values.swapAt(child, parent)
            child = parent
        }
    }

    mutating func removeMinimum() -> Element? {
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return values.removeLast() }
        values.swapAt(0, values.count - 1)
        let result = values.removeLast()
        var parent = 0

        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var candidate = parent
            if left < values.count, orderedBefore(values[left], values[candidate]) {
                candidate = left
            }
            if right < values.count, orderedBefore(values[right], values[candidate]) {
                candidate = right
            }
            guard candidate != parent else { break }
            values.swapAt(parent, candidate)
            parent = candidate
        }
        return result
    }
}
