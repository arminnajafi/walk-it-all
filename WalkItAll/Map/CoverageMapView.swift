import MapKit
import SwiftUI
import WalkItAllCore

struct CoverageMapView: UIViewRepresentable {
    let pack: any CityCoveragePack
    let coverage: CoverageSnapshot?
    let selectedWorkout: WorkoutCoverageRecord?

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
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        context.coordinator.update(
            mapView: mapView,
            pack: pack,
            coverage: coverage,
            selectedWorkout: selectedWorkout,
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
            shouldSetInitialRegion: false
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var signature: Signature?

        func update(
            mapView: MKMapView,
            pack: any CityCoveragePack,
            coverage: CoverageSnapshot?,
            selectedWorkout: WorkoutCoverageRecord?,
            shouldSetInitialRegion: Bool
        ) {
            let nextSignature = Signature(
                packVersion: pack.metadata.version,
                coveredMeters: coverage?.coveredDistanceMeters ?? 0,
                workoutID: selectedWorkout?.id
            )
            guard nextSignature != signature else { return }
            signature = nextSignature
            mapView.removeOverlays(mapView.overlays)

            let network = CoverageNetworkOverlay(pack: pack, coverage: coverage)
            mapView.addOverlay(network, level: .aboveRoads)
            if let selectedWorkout, selectedWorkout.simplifiedRoute.count >= 2 {
                let coordinates = selectedWorkout.simplifiedRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                mapView.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count), level: .aboveRoads)
            }

            if shouldSetInitialRegion, !network.boundingMapRect.isNull {
                mapView.setVisibleMapRect(
                    network.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 96, left: 24, bottom: 190, right: 24),
                    animated: false
                )
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
    let coveredMeters: Double
    let workoutID: UUID?
}

