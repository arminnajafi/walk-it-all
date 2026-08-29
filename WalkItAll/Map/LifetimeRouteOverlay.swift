import MapKit
import UIKit
import WalkItAllCore

/// An immutable, prebuilt set of geographically bounded workout overlays.
///
/// Keeping one native overlay per workout lets MapKit discard routes outside
/// the visible region before asking for a renderer. A single worldwide custom
/// overlay delayed the first route draw because MapKit treated all history as
/// one enormous rendering surface.
final class LifetimeRouteSnapshot: @unchecked Sendable {
    let overlays: [LifetimeWorkoutRouteOverlay]
    let polylineCount: Int
    let boundingMapRect: MKMapRect

    init(records: [WorkoutRouteRecord]) {
        overlays = records.compactMap(LifetimeWorkoutRouteOverlay.init)
        polylineCount = overlays.reduce(0) { $0 + $1.polylines.count }
        boundingMapRect = overlays.reduce(MKMapRect.null) {
            $0.union($1.boundingMapRect)
        }
    }
}

/// A workout normally occupies one small geographic area even when GPS gaps
/// divide it into several route parts. `MKMultiPolyline` preserves that natural
/// grouping while giving MapKit a tight bounding rectangle for native culling.
final class LifetimeWorkoutRouteOverlay: MKMultiPolyline, @unchecked Sendable {
    let workoutID: UUID

    init?(record: WorkoutRouteRecord) {
        let polylines = record.routeParts.compactMap { part -> MKPolyline? in
            guard part.count >= 2 else { return nil }
            let coordinates = part.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            return MKPolyline(coordinates: coordinates, count: coordinates.count)
        }
        guard !polylines.isEmpty else { return nil }
        workoutID = record.id
        super.init(polylines)
    }
}

enum LifetimeRouteRenderer {
    static let usesNativeSpatialCulling = true
    static let strokeAlpha: CGFloat = 0.42

    static func make(overlay: LifetimeWorkoutRouteOverlay) -> MKMultiPolylineRenderer {
        let renderer = MKMultiPolylineRenderer(multiPolyline: overlay)
        renderer.strokeColor = UIColor.systemIndigo.withAlphaComponent(strokeAlpha)
        renderer.lineWidth = 2.5
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }
}
