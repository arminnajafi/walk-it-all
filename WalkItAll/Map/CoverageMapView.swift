import MapKit
import SwiftUI
import WalkItAllCore

struct CoverageMapView: UIViewRepresentable {
    let pack: any CityCoveragePack
    let coverage: CoverageSnapshot?
    let selectedWorkout: WorkoutCoverageRecord?
    let coverageRevision: Int
    let bottomMapInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.layoutMargins = UIEdgeInsets(top: 72, left: 0, bottom: bottomMapInset, right: 0)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        context.coordinator.update(
            mapView: mapView,
            pack: pack,
            coverage: coverage,
            selectedWorkout: selectedWorkout,
            coverageRevision: coverageRevision,
            shouldSetInitialRegion: true
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.layoutMargins = UIEdgeInsets(top: 72, left: 0, bottom: bottomMapInset, right: 0)
        context.coordinator.update(
            mapView: mapView,
            pack: pack,
            coverage: coverage,
            selectedWorkout: selectedWorkout,
            coverageRevision: coverageRevision,
            shouldSetInitialRegion: false
        )
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var signature: Signature?
        private var overlayTask: Task<Void, Never>?

        deinit {
            overlayTask?.cancel()
        }

        func update(
            mapView: MKMapView,
            pack: any CityCoveragePack,
            coverage: CoverageSnapshot?,
            selectedWorkout: WorkoutCoverageRecord?,
            coverageRevision: Int,
            shouldSetInitialRegion: Bool
        ) {
            let nextSignature = Signature(
                packVersion: pack.metadata.version,
                coverageRevision: coverageRevision,
                workoutID: selectedWorkout?.id
            )
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
                    mapView.addOverlay(network, level: .aboveRoads)
                    if let selectedWorkout {
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

                    if shouldSetInitialRegion, !network.boundingMapRect.isNull {
                        var region = MKCoordinateRegion(network.boundingMapRect)
                        region.span.latitudeDelta *= 1.12
                        region.span.longitudeDelta *= 1.35
                        region.center.latitude -= region.span.latitudeDelta * 0.10
                        mapView.setRegion(region, animated: false)
                    }
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is CoverageNetworkOverlay {
                return CoverageNetworkRenderer(overlay: overlay)
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
    }
}

private struct Signature: Equatable {
    let packVersion: Int
    let coverageRevision: Int
    let workoutID: UUID?
}
