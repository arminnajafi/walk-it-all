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
    let liveTrailSession: LiveTrailSession?
    let liveTrailRevision: Int
    let showsUserLocation: Bool
    let viewportCommand: MapViewportCommand
    let mapOrnamentBottomInset: CGFloat
    let onUserTrackingModeChange: (MapUserTrackingMode) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = LayoutAwareMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.onLayout = { [weak coordinator = context.coordinator] mapView in
            coordinator?.mapViewDidLayout(mapView)
        }
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = true
        mapView.showsCompass = true
        mapView.showsScale = false
        mapView.showsUserLocation = showsUserLocation
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        context.coordinator.update(
            mapView: mapView,
            records: records,
            selectedWorkout: selectedWorkout,
            routeRevision: routeRevision,
            liveTrailSession: liveTrailSession,
            liveTrailRevision: liveTrailRevision,
            showsUserLocation: showsUserLocation,
            viewportCommand: viewportCommand,
            bottomInset: mapOrnamentBottomInset,
            onUserTrackingModeChange: onUserTrackingModeChange,
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
            liveTrailSession: liveTrailSession,
            liveTrailRevision: liveTrailRevision,
            showsUserLocation: showsUserLocation,
            viewportCommand: viewportCommand,
            bottomInset: mapOrnamentBottomInset,
            onUserTrackingModeChange: onUserTrackingModeChange,
            initial: false
        )
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var historyRevision: Int?
        private var selectedWorkoutID: UUID?
        private var liveTrailSignature: LiveTrailSignature?
        private var viewportRevision: Int?
        private var pendingViewport = MapViewportCommand(revision: 0, target: .manhattan)
        private var pendingSelection: WorkoutRouteRecord?
        private var pendingLiveTrailSession: LiveTrailSession?
        private var pendingBottomInset: CGFloat = 220
        private var appliedBottomInset: CGFloat?
        private var onUserTrackingModeChange: ((MapUserTrackingMode) -> Void)?
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
            liveTrailSession: LiveTrailSession?,
            liveTrailRevision: Int,
            showsUserLocation: Bool,
            viewportCommand: MapViewportCommand,
            bottomInset: CGFloat,
            onUserTrackingModeChange: @escaping (MapUserTrackingMode) -> Void,
            initial: Bool
        ) {
            self.onUserTrackingModeChange = onUserTrackingModeChange
            mapView.showsUserLocation = showsUserLocation
            mapView.layoutMargins = UIEdgeInsets(
                top: 92,
                left: 16,
                bottom: max(16, bottomInset),
                right: 16
            )
            pendingViewport = viewportCommand
            pendingSelection = selectedWorkout
            pendingLiveTrailSession = liveTrailSession
            pendingBottomInset = bottomInset

            if viewportRevision != viewportCommand.revision
                || appliedBottomInset.map({ abs($0 - bottomInset) > 1 }) ?? true
            {
                scheduleViewport(
                    on: mapView,
                    animated: !initial && !UIAccessibility.isReduceMotionEnabled
                )
            }

            let nextLiveTrailSignature = LiveTrailSignature(
                revision: liveTrailRevision,
                sessionID: liveTrailSession?.id,
                state: liveTrailSession?.state
            )
            if nextLiveTrailSignature != liveTrailSignature {
                liveTrailSignature = nextLiveTrailSignature
                replaceLiveTrail(liveTrailSession, on: mapView)
            }

            if selectedWorkoutID != selectedWorkout?.id {
                selectedWorkoutID = selectedWorkout?.id
                replaceSelection(selectedWorkout, on: mapView)
            }

            guard historyRevision != routeRevision else { return }
            historyRevision = routeRevision
            overlayTask?.cancel()

            overlayTask = Task.detached(priority: .userInitiated) { [weak self, weak mapView] in
                let snapshot = LifetimeRouteSnapshot(records: records)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let mapView, self.historyRevision == routeRevision else { return }
                    mapView.removeOverlays(mapView.overlays.filter {
                        $0 is LifetimeWorkoutRouteOverlay
                    })
                    if !snapshot.overlays.isEmpty {
                        mapView.addOverlays(snapshot.overlays, level: .aboveRoads)
                    }
                    // Re-add contextual overlays after the immutable history
                    // swap so they retain their visual priority. Use the most
                    // recent values because selection or Live Trail can change
                    // while a large history snapshot is being constructed.
                    self.replaceSelection(self.pendingSelection, on: mapView)
                    // Keep the temporary Live Trail above the immutable
                    // history even when a Health refresh replaces that history.
                    self.replaceLiveTrail(self.pendingLiveTrailSession, on: mapView)
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
            if let history = overlay as? LifetimeWorkoutRouteOverlay {
                return LifetimeRouteRenderer.make(overlay: history)
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
            if let casing = overlay as? LiveTrailCasingPolyline {
                let renderer = MKPolylineRenderer(polyline: casing)
                renderer.strokeColor = UIColor.systemBackground.withAlphaComponent(
                    casing.isFinished ? 0.72 : 0.92
                )
                renderer.lineWidth = 9
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if let route = overlay as? LiveTrailPolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(
                    route.isFinished ? 0.62 : 1
                )
                renderer.lineWidth = 5.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard case .userLocation = pendingViewport.target,
                  viewportRevision != pendingViewport.revision,
                  userLocation.location != nil
            else { return }
            applyPendingViewport(
                to: mapView,
                animated: !UIAccessibility.isReduceMotionEnabled
            )
        }

        func mapView(
            _ mapView: MKMapView,
            didChange mode: MKUserTrackingMode,
            animated: Bool
        ) {
            let translatedMode: MapUserTrackingMode
            switch mode {
            case .none: translatedMode = .free
            case .follow: translatedMode = .follow
            case .followWithHeading: translatedMode = .followWithHeading
            @unknown default: translatedMode = .free
            }
            onUserTrackingModeChange?(translatedMode)
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

        private func replaceSelection(_ workout: WorkoutRouteRecord?, on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays.filter {
                $0 is SelectedRouteCasingPolyline || $0 is SelectedRoutePolyline
            })
            if let workout {
                addSelection(workout, to: mapView)
            }
        }

        private func replaceLiveTrail(_ session: LiveTrailSession?, on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays.filter {
                $0 is LiveTrailCasingPolyline || $0 is LiveTrailPolyline
            })
            guard let session else { return }
            let finished = session.state == .finished
            for part in session.coordinateParts where part.count >= 2 {
                let coordinates = part.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let casing = LiveTrailCasingPolyline(
                    coordinates: coordinates,
                    count: coordinates.count
                )
                casing.isFinished = finished
                mapView.addOverlay(casing, level: .aboveRoads)
                let route = LiveTrailPolyline(coordinates: coordinates, count: coordinates.count)
                route.isFinished = finished
                mapView.addOverlay(route, level: .aboveRoads)
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
                mapView.setUserTrackingMode(.none, animated: false)
                mapRect = Self.manhattanMapRect
            case let .workout(id):
                mapView.setUserTrackingMode(.none, animated: false)
                guard pendingSelection?.id == id,
                      let bounds = pendingSelection?.geographicBounds
                else { return }
                mapRect = Self.mapRect(for: bounds)
            case let .userLocation(mode):
                guard mapView.showsUserLocation,
                      mapView.userLocation.location != nil
                else { return }
                let trackingMode: MKUserTrackingMode = mode == .followWithHeading
                    ? .followWithHeading
                    : .follow
                mapView.setUserTrackingMode(trackingMode, animated: animated)
                viewportRevision = pendingViewport.revision
                appliedBottomInset = pendingBottomInset
                return
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

private final class LiveTrailCasingPolyline: MKPolyline {
    var isFinished = false
}

private final class LiveTrailPolyline: MKPolyline {
    var isFinished = false
}

private struct LiveTrailSignature: Equatable, Sendable {
    let revision: Int
    let sessionID: UUID?
    let state: LiveTrailState?
}
