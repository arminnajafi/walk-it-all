import MapKit
import SwiftUI
import WalkItAllCore

enum LifetimeRouteStyle {
    static let selectedCasingWidth: CGFloat = 8
    static let selectedRouteWidth: CGFloat = 5
}

struct LifetimeMapView: UIViewRepresentable {
    let records: [WorkoutRouteRecord]
    let selectedWorkout: WorkoutRouteRecord?
    let routeRevision: Int
    let viewportCommand: MapViewportCommand
    let mapOrnamentBottomInset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = LayoutAwareMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.onLayout = { [weak coordinator = context.coordinator] mapView in
            coordinator?.mapViewDidLayout(mapView)
        }
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        context.coordinator.update(
            mapView: mapView,
            records: records,
            selectedWorkout: selectedWorkout,
            routeRevision: routeRevision,
            viewportCommand: viewportCommand,
            bottomInset: mapOrnamentBottomInset,
            initial: true
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            records: records,
            selectedWorkout: selectedWorkout,
            routeRevision: routeRevision,
            viewportCommand: viewportCommand,
            bottomInset: mapOrnamentBottomInset,
            initial: false
        )
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var signature: Signature?
        private var viewportRevision: Int?
        private var pendingViewport = MapViewportCommand(revision: 0, target: .manhattan)
        private var pendingSelection: WorkoutRouteRecord?
        private var pendingBottomInset: CGFloat = 220
        private var appliedBottomInset: CGFloat?
        private var overlayTask: Task<Void, Never>?
        private var viewportTask: Task<Void, Never>?

        deinit {
            overlayTask?.cancel()
            viewportTask?.cancel()
        }

        func update(
            mapView: MKMapView,
            records: [WorkoutRouteRecord],
            selectedWorkout: WorkoutRouteRecord?,
            routeRevision: Int,
            viewportCommand: MapViewportCommand,
            bottomInset: CGFloat,
            initial: Bool
        ) {
            mapView.layoutMargins = UIEdgeInsets(
                top: 92,
                left: 16,
                bottom: max(16, bottomInset),
                right: 16
            )
            pendingViewport = viewportCommand
            pendingSelection = selectedWorkout
            pendingBottomInset = bottomInset

            if viewportRevision != viewportCommand.revision
                || appliedBottomInset.map({ abs($0 - bottomInset) > 1 }) ?? true
            {
                scheduleViewport(on: mapView, animated: !initial)
            }

            let nextSignature = Signature(
                routeRevision: routeRevision,
                selectedWorkoutID: selectedWorkout?.id
            )
            guard nextSignature != signature else { return }
            signature = nextSignature
            overlayTask?.cancel()
            mapView.removeOverlays(mapView.overlays)

            overlayTask = Task.detached(priority: .userInitiated) { [weak self, weak mapView] in
                let overlay = LifetimeRouteOverlay(records: records)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let mapView, self.signature == nextSignature else { return }
                    if overlay.polylineCount > 0 {
                        mapView.addOverlay(overlay, level: .aboveRoads)
                    }
                    if let selectedWorkout {
                        self.addSelection(selectedWorkout, to: mapView)
                    }
                    if initial || self.viewportRevision != viewportCommand.revision {
                        self.scheduleViewport(on: mapView, animated: false)
                    }
                }
            }
        }

        func mapViewDidLayout(_ mapView: MKMapView) {
            guard viewportRevision != pendingViewport.revision
                || appliedBottomInset.map({ abs($0 - pendingBottomInset) > 1 }) ?? true
            else { return }
            scheduleViewport(on: mapView, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is LifetimeRouteOverlay {
                return LifetimeRouteRenderer(overlay: overlay)
            }
            if let casing = overlay as? SelectedRouteCasingPolyline {
                let renderer = MKPolylineRenderer(polyline: casing)
                renderer.strokeColor = UIColor.systemBackground.withAlphaComponent(0.9)
                renderer.lineWidth = LifetimeRouteStyle.selectedCasingWidth
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if let route = overlay as? SelectedRoutePolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = LifetimeRouteStyle.selectedRouteWidth
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func addSelection(_ workout: WorkoutRouteRecord, to mapView: MKMapView) {
            for part in workout.routeParts where part.count >= 2 {
                let coordinates = part.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                mapView.addOverlay(
                    SelectedRouteCasingPolyline(coordinates: coordinates, count: coordinates.count),
                    level: .aboveRoads
                )
                mapView.addOverlay(
                    SelectedRoutePolyline(coordinates: coordinates, count: coordinates.count),
                    level: .aboveRoads
                )
            }
        }

        private func scheduleViewport(on mapView: MKMapView, animated: Bool) {
            guard viewportTask == nil else { return }
            viewportTask = Task { @MainActor [weak self, weak mapView] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let mapView else { return }
                self.viewportTask = nil
                self.applyPendingViewport(to: mapView, animated: animated)
            }
        }

        private func applyPendingViewport(to mapView: MKMapView, animated: Bool) {
            guard mapView.window != nil,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0
            else { return }

            let mapRect: MKMapRect
            switch pendingViewport.target {
            case .manhattan:
                mapRect = Self.manhattanMapRect
            case let .workout(id):
                guard pendingSelection?.id == id,
                      let bounds = pendingSelection?.geographicBounds
                else { return }
                mapRect = Self.mapRect(for: bounds)
            }
            mapView.setVisibleMapRect(
                mapRect,
                edgePadding: UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20),
                animated: animated
            )
            viewportRevision = pendingViewport.revision
            appliedBottomInset = pendingBottomInset
        }

        private static let manhattanMapRect = mapRect(for: GeoBounds(
            minimumLatitude: 40.699,
            minimumLongitude: -74.022,
            maximumLatitude: 40.882,
            maximumLongitude: -73.907
        ))

        private static func mapRect(for bounds: GeoBounds) -> MKMapRect {
            let northWest = MKMapPoint(CLLocationCoordinate2D(
                latitude: bounds.maximumLatitude,
                longitude: bounds.minimumLongitude
            ))
            let southEast = MKMapPoint(CLLocationCoordinate2D(
                latitude: bounds.minimumLatitude,
                longitude: bounds.maximumLongitude
            ))
            return MKMapRect(
                x: min(northWest.x, southEast.x),
                y: min(northWest.y, southEast.y),
                width: max(1, abs(southEast.x - northWest.x)),
                height: max(1, abs(southEast.y - northWest.y))
            )
        }
    }
}

@MainActor
private final class LayoutAwareMapView: MKMapView {
    var onLayout: ((MKMapView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onLayout?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

private final class SelectedRouteCasingPolyline: MKPolyline {}
private final class SelectedRoutePolyline: MKPolyline {}

private struct Signature: Equatable, Sendable {
    let routeRevision: Int
    let selectedWorkoutID: UUID?
}
