import Foundation

public struct LiveTrailAppendResult: Sendable {
    public let session: LiveTrailSession
    public let accepted: Bool
    public let requiresNewPart: Bool

    public init(session: LiveTrailSession, accepted: Bool, requiresNewPart: Bool) {
        self.session = session
        self.accepted = accepted
        self.requiresNewPart = requiresNewPart
    }
}

/// Incremental form of RouteProcessor used only by an explicitly active Live
/// Trail. Invalid samples create a break, so later data can never bridge them.
public struct LiveTrailProcessor: Sendable {
    public let chunker: RouteChunker
    public let simplifier: RouteSimplifier

    public init(
        chunker: RouteChunker = RouteChunker(
            maximumHorizontalAccuracyMeters: 50,
            maximumTimeGap: 60,
            maximumDistanceGapMeters: 500,
            maximumImpliedSpeedMetersPerSecond: 25
        ),
        simplifier: RouteSimplifier = RouteSimplifier(toleranceMeters: 3)
    ) {
        self.chunker = chunker
        self.simplifier = simplifier
    }

    public func appending(
        _ point: RoutePoint,
        to session: LiveTrailSession,
        forceNewPart: Bool = false
    ) -> LiveTrailAppendResult {
        guard session.state == .active else {
            return LiveTrailAppendResult(session: session, accepted: false, requiresNewPart: true)
        }
        guard chunker.accepts(point) else {
            return LiveTrailAppendResult(session: session, accepted: false, requiresNewPart: true)
        }
        guard point.timestamp >= session.start else {
            return LiveTrailAppendResult(session: session, accepted: false, requiresNewPart: true)
        }

        var parts = session.routeParts
        let previous = parts.last?.last
        if let previous, chunker.isExactDuplicate(previous, point) {
            return LiveTrailAppendResult(
                session: session,
                accepted: false,
                requiresNewPart: forceNewPart
            )
        }

        let startsNewPart = forceNewPart
            || previous.map { chunker.requiresSplit($0, point) } ?? true
        if startsNewPart || parts.isEmpty {
            parts.append([point])
        } else {
            parts[parts.count - 1].append(point)
        }

        return LiveTrailAppendResult(
            session: LiveTrailSession(
                id: session.id,
                state: .active,
                start: session.start,
                routeParts: parts,
                lastUpdate: point.timestamp
            ),
            accepted: true,
            requiresNewPart: false
        )
    }

    public func compacting(_ session: LiveTrailSession) -> LiveTrailSession {
        LiveTrailSession(
            id: session.id,
            state: session.state,
            start: session.start,
            end: session.end,
            routeParts: session.routeParts.map(simplifier.simplify),
            lastUpdate: session.lastUpdate
        )
    }

    public func pausing(_ session: LiveTrailSession, at date: Date) -> LiveTrailSession {
        let compacted = compacting(session)
        return LiveTrailSession(
            id: compacted.id,
            state: .paused,
            start: compacted.start,
            routeParts: compacted.routeParts,
            lastUpdate: max(date, compacted.lastUpdate)
        )
    }

    public func resuming(_ session: LiveTrailSession, at date: Date) -> LiveTrailSession {
        LiveTrailSession(
            id: session.id,
            state: .active,
            start: session.start,
            routeParts: session.routeParts,
            lastUpdate: max(date, session.lastUpdate)
        )
    }

    public func finishing(_ session: LiveTrailSession, at date: Date) -> LiveTrailSession {
        let compacted = compacting(session)
        return LiveTrailSession(
            id: compacted.id,
            state: .finished,
            start: compacted.start,
            end: max(date, compacted.start),
            routeParts: compacted.routeParts,
            lastUpdate: max(date, compacted.lastUpdate)
        )
    }
}
