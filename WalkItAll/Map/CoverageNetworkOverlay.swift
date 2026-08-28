import MapKit
import UIKit
import WalkItAllCore

final class CoverageNetworkOverlay: NSObject, MKOverlay, @unchecked Sendable {
    struct Polyline: Sendable {
        let points: [MKMapPoint]
        let boundingMapRect: MKMapRect

        init(coordinates: [GeoCoordinate]) {
            points = coordinates.map {
                MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            let exactBounds = points.reduce(MKMapRect.null) { rect, point in
                rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            // Perfectly vertical or horizontal streets otherwise have an empty
            // dimension and can disappear from MapKit intersection tests.
            boundingMapRect = exactBounds.insetBy(dx: -1, dy: -1)
        }
    }

    private struct GridKey: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    private struct PolylineStore: Sendable {
        let values: [Polyline]
        let grid: [GridKey: [Int]]
        let cellSize: Double

        init(_ values: [Polyline], cellSize: Double = 8_192) {
            self.values = values
            self.cellSize = cellSize
            var mutableGrid: [GridKey: [Int]] = [:]
            for (index, polyline) in values.enumerated() {
                let bounds = polyline.boundingMapRect
                guard !bounds.isNull else { continue }
                let minX = Int(floor(bounds.minX / cellSize))
                let maxX = Int(floor(bounds.maxX / cellSize))
                let minY = Int(floor(bounds.minY / cellSize))
                let maxY = Int(floor(bounds.maxY / cellSize))
                for x in minX ... maxX {
                    for y in minY ... maxY {
                        mutableGrid[GridKey(x: x, y: y), default: []].append(index)
                    }
                }
            }
            grid = mutableGrid
        }

        func intersecting(_ mapRect: MKMapRect) -> [Polyline] {
            guard !mapRect.isNull else { return [] }
            let minX = Int(floor(mapRect.minX / cellSize))
            let maxX = Int(floor(mapRect.maxX / cellSize))
            let minY = Int(floor(mapRect.minY / cellSize))
            let maxY = Int(floor(mapRect.maxY / cellSize))
            var indices = Set<Int>()
            for x in minX ... maxX {
                for y in minY ... maxY {
                    indices.formUnion(grid[GridKey(x: x, y: y)] ?? [])
                }
            }
            return indices.sorted().compactMap { index in
                let polyline = values[index]
                return polyline.boundingMapRect.intersects(mapRect) ? polyline : nil
            }
        }
    }

    private let covered: PolylineStore
    private let remaining: PolylineStore
    let coveredPolylineCount: Int
    let remainingPolylineCount: Int
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(pack: any CityCoveragePack, coverage: CoverageSnapshot?) {
        var covered: [Polyline] = []
        var remaining: [Polyline] = []

        for segment in pack.segments {
            guard segment.countsTowardCoverage else { continue }
            let coveredIntervals = coverage?.coveredIntervalsBySegment[segment.id] ?? []
            if coveredIntervals.isEmpty {
                remaining.append(Polyline(coordinates: segment.coordinates))
                continue
            }
            for interval in coveredIntervals {
                let coordinates = GeoMath.slice(
                    polyline: segment.coordinates,
                    from: interval.lowerBoundMeters,
                    to: interval.upperBoundMeters
                )
                if coordinates.count >= 2 { covered.append(Polyline(coordinates: coordinates)) }
            }

            var cursor = 0.0
            for interval in coveredIntervals.sorted(by: { $0.lowerBoundMeters < $1.lowerBoundMeters }) {
                if interval.lowerBoundMeters > cursor {
                    let coordinates = GeoMath.slice(
                        polyline: segment.coordinates,
                        from: cursor,
                        to: interval.lowerBoundMeters
                    )
                    if coordinates.count >= 2 { remaining.append(Polyline(coordinates: coordinates)) }
                }
                cursor = max(cursor, interval.upperBoundMeters)
            }
            if cursor < segment.lengthMeters {
                let coordinates = GeoMath.slice(
                    polyline: segment.coordinates,
                    from: cursor,
                    to: segment.lengthMeters
                )
                if coordinates.count >= 2 { remaining.append(Polyline(coordinates: coordinates)) }
            }
        }

        self.covered = PolylineStore(covered)
        self.remaining = PolylineStore(remaining)
        coveredPolylineCount = covered.count
        remainingPolylineCount = remaining.count
        let all = covered + remaining
        boundingMapRect = all.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        coordinate = MKCoordinateRegion(boundingMapRect).center
        super.init()
    }

    func covered(intersecting mapRect: MKMapRect) -> [Polyline] {
        covered.intersecting(mapRect)
    }

    func remaining(intersecting mapRect: MKMapRect) -> [Polyline] {
        remaining.intersecting(mapRect)
    }
}

final class CoverageNetworkRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? CoverageNetworkOverlay else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect(for: mapRect))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if zoomScale > 0.002 {
            let alpha: CGFloat
            if zoomScale > 0.018 {
                alpha = 0.42
            } else if zoomScale > 0.0075 {
                alpha = 0.18
            } else {
                alpha = 0.11
            }
            context.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(max(1 / zoomScale, MKRoadWidthAtZoomScale(zoomScale) * 0.18))
            context.setLineDash(
                phase: 0,
                lengths: [max(4 / zoomScale, 2), max(5 / zoomScale, 2)]
            )
            draw(overlay.remaining(intersecting: mapRect), in: context)
        }

        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(max(2.5 / zoomScale, MKRoadWidthAtZoomScale(zoomScale) * 0.48))
        draw(overlay.covered(intersecting: mapRect), in: context)
    }

    private func draw(
        _ polylines: [CoverageNetworkOverlay.Polyline],
        in context: CGContext
    ) {
        context.beginPath()
        for polyline in polylines {
            guard let first = polyline.points.first else { continue }
            let firstPoint = point(for: first)
            context.move(to: firstPoint)
            for mapPoint in polyline.points.dropFirst() {
                context.addLine(to: point(for: mapPoint))
            }
        }
        context.strokePath()
    }
}
