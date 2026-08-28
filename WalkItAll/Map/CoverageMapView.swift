import MapKit
import SwiftUI
import WalkItAllCore

struct CoverageMapView: UIViewRepresentable {
    let pack: any CityCoveragePack
    let coverage: CoverageSnapshot?
    let selectedWorkout: WorkoutCoverageRecord?
    let coverageRevision: Int
    let viewportCommand: MapViewportCommand
    let bottomMapInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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
            pack: pack,
            coverage: coverage,
            selectedWorkout: selectedWorkout,
            coverageRevision: coverageRevision,
            viewportCommand: viewportCommand,
            bottomMapInset: bottomMapInset,
            shouldSetInitialRegion: true
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            pack: pack,
            coverage: coverage,
            selectedWorkout: selectedWorkout,
            coverageRevision: coverageRevision,
            viewportCommand: viewportCommand,
            bottomMapInset: bottomMapInset,
            shouldSetInitialRegion: false
        )
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var signature: Signature?
        private var viewportRevision: Int?
        private var networkBounds = MKMapRect.null
        private var pendingViewportCommand = MapViewportCommand(revision: 0, target: .manhattan)
        private var pendingSelectedWorkout: WorkoutCoverageRecord?
        private var pendingBottomMapInset: CGFloat = 300
        private var overlayTask: Task<Void, Never>?
        private var viewportTask: Task<Void, Never>?

        deinit {
            overlayTask?.cancel()
            viewportTask?.cancel()
        }

        func update(
            mapView: MKMapView,
            pack: any CityCoveragePack,
            coverage: CoverageSnapshot?,
            selectedWorkout: WorkoutCoverageRecord?,
            coverageRevision: Int,
            viewportCommand: MapViewportCommand,
            bottomMapInset: CGFloat,
            shouldSetInitialRegion: Bool
        ) {
            pendingViewportCommand = viewportCommand
            pendingSelectedWorkout = selectedWorkout
            pendingBottomMapInset = bottomMapInset
            if let bounds = pack.geographicBounds {
                networkBounds = Self.mapRect(for: bounds)
            }
            let nextSignature = Signature(
                packVersion: pack.metadata.version,
                coverageRevision: coverageRevision,
                workoutID: selectedWorkout?.id
            )
            if viewportRevision != viewportCommand.revision {
                schedulePendingViewport(
                    on: mapView,
                    animated: !shouldSetInitialRegion
                )
            }

            guard nextSignature != signature else { return }
            signature = nextSignature
            overlayTask?.cancel()
            mapView.removeOverlays(mapView.overlays)

            let expectedSignature = nextSignature
            overlayTask = Task.detached(priority: .userInitiated) { [weak mapView, weak self] in
                let network = CoverageNetworkOverlay(pack: pack, coverage: coverage)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let mapView, self.signature == expectedSignature else { return }
                    self.networkBounds = network.boundingMapRect
                    mapView.addOverlay(network, level: .aboveRoads)
                    if let selectedWorkout {
                        for interval in selectedWorkout.contribution.intervals {
                            guard let segment = pack.segment(id: interval.segmentID) else { continue }
                            let slice = GeoMath.slice(
                                polyline: segment.coordinates,
                                from: interval.lowerBoundMeters,
                                to: interval.upperBoundMeters
                            )
                            guard slice.count >= 2 else { continue }
                            let coordinates = slice.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            }
                            mapView.addOverlay(
                                SelectedCoveragePolyline(coordinates: coordinates, count: coordinates.count),
                                level: .aboveRoads
                            )
                        }
                        for part in selectedWorkout.simplifiedRouteParts where part.count >= 2 {
                            let coordinates = part.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            }
                            mapView.addOverlay(
                                MKPolyline(coordinates: coordinates, count: coordinates.count),
                                level: .aboveRoads
                            )
                        }
                    }

                    if shouldSetInitialRegion || self.viewportRevision != viewportCommand.revision {
                        self.schedulePendingViewport(on: mapView, animated: false)
                    }
                }
            }
        }

        func mapViewDidLayout(_ mapView: MKMapView) {
            guard viewportRevision != pendingViewportCommand.revision else { return }
            schedulePendingViewport(on: mapView, animated: false)
        }

        private func schedulePendingViewport(on mapView: MKMapView, animated: Bool) {
            guard viewportTask == nil else { return }
            viewportTask = Task { @MainActor [weak self, weak mapView] in
                // Region changes made from within MapKit's own layout pass can
                // be overwritten by its deferred camera setup. Apply on the
                // first settled main-actor turn instead.
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let mapView else { return }
                self.viewportTask = nil
                self.applyPendingViewport(to: mapView, animated: animated)
            }
        }

        private func applyPendingViewport(to mapView: MKMapView, animated: Bool) {
            if applyViewport(
                pendingViewportCommand,
                to: mapView,
                selectedWorkout: pendingSelectedWorkout,
                bottomMapInset: pendingBottomMapInset,
                animated: animated
            ) {
                viewportRevision = pendingViewportCommand.revision
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is CoverageNetworkOverlay {
                return CoverageNetworkRenderer(overlay: overlay)
            }
            if let route = overlay as? SelectedCoveragePolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = .systemIndigo
                renderer.lineWidth = 7
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if let route = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @discardableResult
        private func applyViewport(
            _ command: MapViewportCommand,
            to mapView: MKMapView,
            selectedWorkout: WorkoutCoverageRecord?,
            bottomMapInset: CGFloat,
            animated: Bool
        ) -> Bool {
            // MapKit can accept a region while the representable has a non-zero
            // provisional size and then replace it when the view enters a window.
            // Defer the command until the map participates in the real hierarchy;
            // LayoutAwareMapView will retry it on the next layout pass.
            guard mapView.window != nil,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0
            else { return false }
            let mapRect: MKMapRect
            switch command.target {
            case .manhattan:
                mapRect = networkBounds
            case let .workout(workoutID):
                guard selectedWorkout?.id == workoutID else { return false }
                mapRect = selectedWorkout?.simplifiedRouteParts
                    .flatMap { $0 }
                    .map {
                        MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                    }
                    .reduce(MKMapRect.null) {
                        $0.union(MKMapRect(x: $1.x, y: $1.y, width: 0, height: 0))
                    } ?? .null
            }
            guard !mapRect.isNull else { return false }
            mapView.setVisibleMapRect(
                mapRect,
                edgePadding: UIEdgeInsets(
                    top: 92,
                    left: 36,
                    bottom: bottomMapInset,
                    right: 36
                ),
                animated: animated
            )
            return true
        }

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
                width: abs(southEast.x - northWest.x),
                height: abs(southEast.y - northWest.y)
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

private final class SelectedCoveragePolyline: MKPolyline {}

private struct Signature: Equatable {
    let packVersion: Int
    let coverageRevision: Int
    let workoutID: UUID?
}
