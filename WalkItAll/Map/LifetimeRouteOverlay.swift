import MapKit
import UIKit
import WalkItAllCore

final class LifetimeRouteOverlay: NSObject, MKOverlay, @unchecked Sendable {
    struct Polyline: @unchecked Sendable {
        let points: [MKMapPoint]
        let boundingMapRect: MKMapRect

        init(coordinates: [GeoCoordinate]) {
            points = coordinates.map {
                MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            let exactBounds = points.reduce(MKMapRect.null) { rect, point in
                rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            // Zero-width horizontal or vertical bounds can disappear from
            // MapKit's intersection tests, so expand by one map point.
            boundingMapRect = exactBounds.insetBy(dx: -1, dy: -1)
        }
    }

    private struct GridKey: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    private final class Store: @unchecked Sendable {
        let polylines: [Polyline]
        private let grid: [GridKey: [Int]]
        private let overflowIndices: [Int]
        private let cellSize: Double

        init(_ polylines: [Polyline], cellSize: Double = 8_192) {
            self.polylines = polylines
            self.cellSize = cellSize
            var grid: [GridKey: [Int]] = [:]
            var overflowIndices: [Int] = []
            for (index, polyline) in polylines.enumerated() {
                let bounds = polyline.boundingMapRect
                guard !bounds.isNull else { continue }
                let minimumX = Int(floor(bounds.minX / cellSize))
                let maximumX = Int(floor(bounds.maxX / cellSize))
                let minimumY = Int(floor(bounds.minY / cellSize))
                let maximumY = Int(floor(bounds.maxY / cellSize))
                let columnCount = maximumX - minimumX + 1
                let rowCount = maximumY - minimumY + 1
                if columnCount > 4_096
                    || rowCount > 4_096
                    || columnCount * rowCount > 4_096
                {
                    overflowIndices.append(index)
                    continue
                }
                for x in minimumX ... maximumX {
                    for y in minimumY ... maximumY {
                        grid[GridKey(x: x, y: y), default: []].append(index)
                    }
                }
            }
            self.grid = grid
            self.overflowIndices = overflowIndices
        }

        func intersecting(_ mapRect: MKMapRect) -> [Polyline] {
            guard !mapRect.isNull else { return [] }
            let minimumX = Int(floor(mapRect.minX / cellSize))
            let maximumX = Int(floor(mapRect.maxX / cellSize))
            let minimumY = Int(floor(mapRect.minY / cellSize))
            let maximumY = Int(floor(mapRect.maxY / cellSize))
            let columnCount = maximumX - minimumX + 1
            let rowCount = maximumY - minimumY + 1

            // A world-scale MapKit request can span billions of otherwise
            // empty grid cells. At that scale a linear bounds check over the
            // immutable route list is both bounded and substantially cheaper.
            if columnCount > 4_096
                || rowCount > 4_096
                || columnCount * rowCount > 4_096
            {
                return polylines.filter { $0.boundingMapRect.intersects(mapRect) }
            }

            var indices = Set(overflowIndices)
            for x in minimumX ... maximumX {
                for y in minimumY ... maximumY {
                    indices.formUnion(grid[GridKey(x: x, y: y)] ?? [])
                }
            }
            return indices.sorted().compactMap { index in
                let polyline = polylines[index]
                return polyline.boundingMapRect.intersects(mapRect) ? polyline : nil
            }
        }
    }

    private let store: Store
    let polylineCount: Int
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(records: [WorkoutRouteRecord]) {
        let polylines = records.flatMap(\.routeParts)
            .filter { $0.count >= 2 }
            .map(Polyline.init)
        store = Store(polylines)
        polylineCount = polylines.count
        boundingMapRect = polylines.reduce(MKMapRect.null) {
            $0.union($1.boundingMapRect)
        }
        coordinate = boundingMapRect.isNull
            ? CLLocationCoordinate2D(latitude: 40.758, longitude: -73.9855)
            : MKCoordinateRegion(boundingMapRect).center
        super.init()
    }

    func polylines(intersecting mapRect: MKMapRect) -> [Polyline] {
        store.intersecting(mapRect)
    }
}

final class LifetimeRouteRenderer: MKOverlayRenderer {
    static let usesDensityPass = true

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? LifetimeRouteOverlay else { return }
        let polylines = overlay.polylines(intersecting: mapRect)
        guard !polylines.isEmpty else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect(for: mapRect))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(2 / zoomScale, MKRoadWidthAtZoomScale(zoomScale) * 0.38))

        // One baseline stroke guarantees that a route remains legible even in
        // a dense area. A second low-opacity stroke per route lets repetition
        // deepen naturally without introducing a heatmap subsystem.
        context.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(0.48).cgColor)
        add(polylines, to: context)
        context.strokePath()

        context.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(0.09).cgColor)
        for polyline in polylines {
            context.beginPath()
            add(polyline, to: context)
            context.strokePath()
        }
    }

    private func add(_ polylines: [LifetimeRouteOverlay.Polyline], to context: CGContext) {
        context.beginPath()
        for polyline in polylines {
            add(polyline, to: context)
        }
    }

    private func add(_ polyline: LifetimeRouteOverlay.Polyline, to context: CGContext) {
        guard let first = polyline.points.first else { return }
        context.move(to: point(for: first))
        for point in polyline.points.dropFirst() {
            context.addLine(to: self.point(for: point))
        }
    }
}
