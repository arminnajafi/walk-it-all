import MapKit
import UIKit
import WalkItAllCore

final class CoverageNetworkOverlay: NSObject, MKOverlay {
    struct Polyline {
        let points: [MKMapPoint]
        let boundingMapRect: MKMapRect

        init(coordinates: [GeoCoordinate]) {
            points = coordinates.map {
                MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            boundingMapRect = points.reduce(MKMapRect.null) { rect, point in
                rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
        }
    }

    let covered: [Polyline]
    let remaining: [Polyline]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(pack: any CityCoveragePack, coverage: CoverageSnapshot?) {
        var covered: [Polyline] = []
        var remaining: [Polyline] = []

        for segment in pack.segments {
            guard segment.countsTowardCoverage else { continue }
            let coveredIntervals = coverage?.coveredIntervalsBySegment[segment.id] ?? []
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

        self.covered = covered
        self.remaining = remaining
        let all = covered + remaining
        boundingMapRect = all.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        coordinate = MKCoordinateRegion(boundingMapRect).center
        super.init()
    }
}

final class CoverageNetworkRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? CoverageNetworkOverlay else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if zoomScale > 0.018 {
            context.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(0.42).cgColor)
            context.setLineWidth(max(1 / zoomScale, MKRoadWidthAtZoomScale(zoomScale) * 0.18))
            context.setLineDash(
                phase: 0,
                lengths: [max(4 / zoomScale, 2), max(5 / zoomScale, 2)]
            )
            draw(overlay.remaining, intersecting: mapRect, in: context)
        }

        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(max(2.5 / zoomScale, MKRoadWidthAtZoomScale(zoomScale) * 0.48))
        draw(overlay.covered, intersecting: mapRect, in: context)
    }

    private func draw(
        _ polylines: [CoverageNetworkOverlay.Polyline],
        intersecting mapRect: MKMapRect,
        in context: CGContext
    ) {
        for polyline in polylines where polyline.boundingMapRect.intersects(mapRect) {
            guard let first = polyline.points.first else { continue }
            let firstPoint = point(for: first)
            context.beginPath()
            context.move(to: firstPoint)
            for mapPoint in polyline.points.dropFirst() {
                context.addLine(to: point(for: mapPoint))
            }
            context.strokePath()
        }
    }
}
