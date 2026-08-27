import Foundation

public struct ContinuityMapMatcher: MapMatcher {
    public struct Configuration: Sendable {
        public let maximumCandidatesPerPoint: Int
        public let minimumCandidateRadiusMeters: Double
        public let maximumCandidateRadiusMeters: Double
        public let minimumAcceptedConfidence: Double

        public init(
            maximumCandidatesPerPoint: Int = 6,
            minimumCandidateRadiusMeters: Double = 15,
            maximumCandidateRadiusMeters: Double = 50,
            minimumAcceptedConfidence: Double = 0.55
        ) {
            self.maximumCandidatesPerPoint = maximumCandidatesPerPoint
            self.minimumCandidateRadiusMeters = minimumCandidateRadiusMeters
            self.maximumCandidateRadiusMeters = maximumCandidateRadiusMeters
            self.minimumAcceptedConfidence = minimumAcceptedConfidence
        }
    }

    private struct Candidate: Sendable {
        let segment: WalkableSegment
        let projection: GeoMath.Projection
        let emissionScore: Double
    }

    private struct State: Sendable {
        let score: Double
        let previousIndex: Int?
    }

    private struct Travel: Sendable {
        let distanceMeters: Double
        let intervals: [SegmentInterval]
    }

    private struct NodePair: Hashable, Sendable {
        let lower: NodeID
        let upper: NodeID

        init(_ first: NodeID, _ second: NodeID) {
            if first.rawValue <= second.rawValue {
                lower = first
                upper = second
            } else {
                lower = second
                upper = first
            }
        }
    }

    private enum CachedPath: Sendable {
        case found(GraphPath)
        case missing
    }

    public let configuration: Configuration
    public let chunker: RouteChunker

    public init(
        configuration: Configuration = Configuration(),
        chunker: RouteChunker = RouteChunker()
    ) {
        self.configuration = configuration
        self.chunker = chunker
    }

    public func match(points: [RoutePoint], in pack: any CityCoveragePack) async throws -> MatchResult {
        let chunks = chunker.chunks(from: points)
        var intervals: [SegmentInterval] = []
        var unmatched: [UnmatchedPortion] = []
        var acceptedPoints = 0
        var confidenceValues: [Double] = []
        var pathCache: [NodePair: CachedPath] = [:]

        for chunk in chunks {
            try Task.checkCancellation()
            let chunkResult = matchChunk(chunk, in: pack, pathCache: &pathCache)
            intervals.append(contentsOf: chunkResult.intervals)
            unmatched.append(contentsOf: chunkResult.unmatched)
            acceptedPoints += chunkResult.acceptedPoints
            confidenceValues.append(contentsOf: chunkResult.confidences)
        }

        let rejectedByFiltering = max(0, points.count - chunks.reduce(0) { $0 + $1.count })
        let rejectedByMatching = max(0, chunks.reduce(0) { $0 + $1.count } - acceptedPoints)
        let averageConfidence = confidenceValues.isEmpty
            ? 0
            : confidenceValues.reduce(0, +) / Double(confidenceValues.count)

        return MatchResult(
            intervals: intervals,
            unmatchedPortions: unmatched,
            acceptedPointCount: acceptedPoints,
            rejectedPointCount: rejectedByFiltering + rejectedByMatching,
            averageConfidence: averageConfidence
        )
    }

    private func matchChunk(
        _ points: [RoutePoint],
        in pack: any CityCoveragePack,
        pathCache: inout [NodePair: CachedPath]
    ) -> (intervals: [SegmentInterval], unmatched: [UnmatchedPortion], acceptedPoints: Int, confidences: [Double]) {
        let candidateSets = points.map { candidates(for: $0, in: pack) }
        var intervals: [SegmentInterval] = []
        var unmatched: [UnmatchedPortion] = []
        var confidences: [Double] = []
        var acceptedPoints = 0
        var start = 0

        while start < points.count {
            while start < points.count, candidateSets[start].isEmpty {
                unmatched.append(UnmatchedPortion(
                    start: points[start].timestamp,
                    end: points[start].timestamp,
                    reason: .noNearbyWalkableWay
                ))
                start += 1
            }
            guard start < points.count else { break }

            var end = start
            while end < points.count, !candidateSets[end].isEmpty {
                end += 1
            }

            let range = start ..< end
            if range.count >= 2 {
                let result = viterbi(
                    points: Array(points[range]),
                    candidateSets: Array(candidateSets[range]),
                    pack: pack,
                    pathCache: &pathCache
                )
                intervals.append(contentsOf: result.intervals)
                unmatched.append(contentsOf: result.unmatched)
                acceptedPoints += result.acceptedPoints
                confidences.append(contentsOf: result.confidences)
            } else {
                unmatched.append(UnmatchedPortion(
                    start: points[start].timestamp,
                    end: points[start].timestamp,
                    reason: .lowConfidence
                ))
            }
            start = max(end, start + 1)
        }

        return (intervals, unmatched, acceptedPoints, confidences)
    }

    private func candidates(for point: RoutePoint, in pack: any CityCoveragePack) -> [Candidate] {
        let radius = min(
            configuration.maximumCandidateRadiusMeters,
            max(configuration.minimumCandidateRadiusMeters, point.horizontalAccuracy * 2)
        )
        let sigma = max(5, point.horizontalAccuracy)
        return pack.segments(near: point.coordinate, radiusMeters: radius)
            .compactMap { segment -> Candidate? in
                guard let projection = GeoMath.project(point.coordinate, onto: segment.coordinates) else { return nil }
                let normalizedDistance = projection.distanceMeters / sigma
                return Candidate(
                    segment: segment,
                    projection: projection,
                    emissionScore: -0.5 * normalizedDistance * normalizedDistance
                )
            }
            .sorted { $0.projection.distanceMeters < $1.projection.distanceMeters }
            .prefix(configuration.maximumCandidatesPerPoint)
            .map { $0 }
    }

    private func viterbi(
        points: [RoutePoint],
        candidateSets: [[Candidate]],
        pack: any CityCoveragePack,
        pathCache: inout [NodePair: CachedPath]
    ) -> (intervals: [SegmentInterval], unmatched: [UnmatchedPortion], acceptedPoints: Int, confidences: [Double]) {
        var rows: [[State]] = [candidateSets[0].map { State(score: $0.emissionScore, previousIndex: nil) }]

        for pointIndex in 1 ..< points.count {
            let previousCandidates = candidateSets[pointIndex - 1]
            let currentCandidates = candidateSets[pointIndex]
            let observedDistance = GeoMath.distance(points[pointIndex - 1].coordinate, points[pointIndex].coordinate)
            let observedHeading = GeoMath.bearing(
                from: points[pointIndex - 1].coordinate,
                to: points[pointIndex].coordinate
            )
            var row: [State] = []

            for current in currentCandidates {
                var bestScore = -Double.infinity
                var bestPrevious: Int?

                for (previousIndex, previous) in previousCandidates.enumerated() {
                    guard let travel = travel(
                        from: previous,
                        to: current,
                        in: pack,
                        pathCache: &pathCache
                    ) else { continue }
                    let transitionScore = scoreTransition(
                        networkDistance: travel.distanceMeters,
                        observedDistance: observedDistance
                    )
                    guard transitionScore.isFinite else { continue }

                    let headingDifference = GeoMath.undirectedHeadingDifference(
                        observedHeading,
                        current.projection.localBearingDegrees
                    )
                    let headingScore = -pow(headingDifference / 90, 2) * 0.75
                    let proposed = rows[pointIndex - 1][previousIndex].score
                        + transitionScore
                        + current.emissionScore
                        + headingScore
                    if proposed > bestScore {
                        bestScore = proposed
                        bestPrevious = previousIndex
                    }
                }
                row.append(State(score: bestScore, previousIndex: bestPrevious))
            }

            if row.allSatisfy({ !$0.score.isFinite }) {
                var splitIntervals: [SegmentInterval] = []
                var splitUnmatched: [UnmatchedPortion] = [
                    UnmatchedPortion(
                        start: points[pointIndex - 1].timestamp,
                        end: points[pointIndex].timestamp,
                        reason: .implausibleTransition
                    ),
                ]
                var splitAcceptedPoints = 0
                var splitConfidences: [Double] = []

                if pointIndex >= 2 {
                    let left = viterbi(
                        points: Array(points[..<pointIndex]),
                        candidateSets: Array(candidateSets[..<pointIndex]),
                        pack: pack,
                        pathCache: &pathCache
                    )
                    splitIntervals.append(contentsOf: left.intervals)
                    splitUnmatched.append(contentsOf: left.unmatched)
                    splitAcceptedPoints += left.acceptedPoints
                    splitConfidences.append(contentsOf: left.confidences)
                }

                if points.count - pointIndex >= 2 {
                    let right = viterbi(
                        points: Array(points[pointIndex...]),
                        candidateSets: Array(candidateSets[pointIndex...]),
                        pack: pack,
                        pathCache: &pathCache
                    )
                    splitIntervals.append(contentsOf: right.intervals)
                    splitUnmatched.append(contentsOf: right.unmatched)
                    splitAcceptedPoints += right.acceptedPoints
                    splitConfidences.append(contentsOf: right.confidences)
                }

                return (
                    splitIntervals,
                    splitUnmatched,
                    splitAcceptedPoints,
                    splitConfidences
                )
            }
            rows.append(row)
        }

        guard let finalIndex = rows.last?.indices.max(by: { rows.last![$0].score < rows.last![$1].score }),
              rows.last![finalIndex].score.isFinite
        else {
            return (
                [],
                [UnmatchedPortion(start: points[0].timestamp, end: points.last!.timestamp, reason: .implausibleTransition)],
                0,
                []
            )
        }

        var selectedIndices = Array(repeating: 0, count: points.count)
        selectedIndices[points.count - 1] = finalIndex
        if points.count > 1 {
            for index in stride(from: points.count - 1, through: 1, by: -1) {
                guard let previous = rows[index][selectedIndices[index]].previousIndex else {
                    return (
                        [],
                        [UnmatchedPortion(start: points[0].timestamp, end: points.last!.timestamp, reason: .implausibleTransition)],
                        0,
                        []
                    )
                }
                selectedIndices[index - 1] = previous
            }
        }

        let confidenceValues = rows.indices.map { rowIndex in
            confidence(selectedIndex: selectedIndices[rowIndex], states: rows[rowIndex])
        }
        var intervals: [SegmentInterval] = []
        var unmatched: [UnmatchedPortion] = []
        var accepted = Set<Int>()

        for index in 1 ..< points.count {
            let pairConfidence = min(confidenceValues[index - 1], confidenceValues[index])
            guard pairConfidence >= configuration.minimumAcceptedConfidence else {
                unmatched.append(UnmatchedPortion(
                    start: points[index - 1].timestamp,
                    end: points[index].timestamp,
                    reason: .lowConfidence
                ))
                continue
            }
            let previous = candidateSets[index - 1][selectedIndices[index - 1]]
            let current = candidateSets[index][selectedIndices[index]]
            guard let routeTravel = travel(
                from: previous,
                to: current,
                in: pack,
                pathCache: &pathCache
            ) else {
                unmatched.append(UnmatchedPortion(
                    start: points[index - 1].timestamp,
                    end: points[index].timestamp,
                    reason: .implausibleTransition
                ))
                continue
            }
            intervals.append(contentsOf: routeTravel.intervals.map {
                SegmentInterval(
                    segmentID: $0.segmentID,
                    lowerBoundMeters: $0.lowerBoundMeters,
                    upperBoundMeters: $0.upperBoundMeters,
                    confidence: pairConfidence
                )
            })
            accepted.insert(index - 1)
            accepted.insert(index)
        }

        return (intervals, unmatched, accepted.count, confidenceValues)
    }

    private func confidence(selectedIndex: Int, states: [State]) -> Double {
        let selected = states[selectedIndex].score
        let alternative = states.indices
            .filter { $0 != selectedIndex }
            .map { states[$0].score }
            .filter(\.isFinite)
            .max()
        guard let alternative else { return 1 }
        let margin = max(0, selected - alternative)
        return min(1, max(0, 1 - exp(-margin)))
    }

    private func scoreTransition(networkDistance: Double, observedDistance: Double) -> Double {
        guard networkDistance <= observedDistance * 4 + 100 else {
            return -.infinity
        }
        let scale = max(20, observedDistance)
        return -2 * abs(networkDistance - observedDistance) / scale
    }

    private func travel(
        from start: Candidate,
        to end: Candidate,
        in pack: any CityCoveragePack,
        pathCache: inout [NodePair: CachedPath]
    ) -> Travel? {
        if start.segment.id == end.segment.id {
            return Travel(
                distanceMeters: abs(end.projection.offsetMeters - start.projection.offsetMeters),
                intervals: [SegmentInterval(
                    segmentID: start.segment.id,
                    lowerBoundMeters: start.projection.offsetMeters,
                    upperBoundMeters: end.projection.offsetMeters,
                    confidence: 1
                )]
            )
        }

        let startEndpoints: [(NodeID, Double, SegmentInterval)] = [
            (
                start.segment.startNode,
                start.projection.offsetMeters,
                SegmentInterval(
                    segmentID: start.segment.id,
                    lowerBoundMeters: 0,
                    upperBoundMeters: start.projection.offsetMeters,
                    confidence: 1
                )
            ),
            (
                start.segment.endNode,
                start.segment.lengthMeters - start.projection.offsetMeters,
                SegmentInterval(
                    segmentID: start.segment.id,
                    lowerBoundMeters: start.projection.offsetMeters,
                    upperBoundMeters: start.segment.lengthMeters,
                    confidence: 1
                )
            ),
        ]
        let endEndpoints: [(NodeID, Double, SegmentInterval)] = [
            (
                end.segment.startNode,
                end.projection.offsetMeters,
                SegmentInterval(
                    segmentID: end.segment.id,
                    lowerBoundMeters: 0,
                    upperBoundMeters: end.projection.offsetMeters,
                    confidence: 1
                )
            ),
            (
                end.segment.endNode,
                end.segment.lengthMeters - end.projection.offsetMeters,
                SegmentInterval(
                    segmentID: end.segment.id,
                    lowerBoundMeters: end.projection.offsetMeters,
                    upperBoundMeters: end.segment.lengthMeters,
                    confidence: 1
                )
            ),
        ]

        var best: Travel?
        for startEndpoint in startEndpoints {
            for endEndpoint in endEndpoints {
                let directBudget = 2_000.0
                let key = NodePair(startEndpoint.0, endEndpoint.0)
                let graphPath: GraphPath?
                if let cached = pathCache[key] {
                    switch cached {
                    case let .found(path): graphPath = path
                    case .missing: graphPath = nil
                    }
                } else {
                    let resolved = pack.shortestPath(
                        from: startEndpoint.0,
                        to: endEndpoint.0,
                        maximumDistanceMeters: directBudget
                    )
                    pathCache[key] = resolved.map(CachedPath.found) ?? .missing
                    graphPath = resolved
                }
                guard let graphPath else { continue }

                let total = startEndpoint.1 + graphPath.distanceMeters + endEndpoint.1
                var pathIntervals = [startEndpoint.2]
                pathIntervals.append(contentsOf: graphPath.segmentIDs.compactMap { id in
                    guard let segment = pack.segment(id: id) else { return nil }
                    return SegmentInterval(
                        segmentID: id,
                        lowerBoundMeters: 0,
                        upperBoundMeters: segment.lengthMeters,
                        confidence: 1
                    )
                })
                pathIntervals.append(endEndpoint.2)
                if best == nil || total < best!.distanceMeters {
                    best = Travel(distanceMeters: total, intervals: pathIntervals)
                }
            }
        }
        return best
    }
}
