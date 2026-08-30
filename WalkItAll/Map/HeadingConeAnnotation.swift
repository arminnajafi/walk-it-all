import CoreLocation
import MapKit
import UIKit

enum HeadingConeGeometry {
    static func rotationRadians(
        deviceHeading: CLLocationDirection,
        mapHeading: CLLocationDirection
    ) -> CGFloat {
        var degrees = (deviceHeading - mapHeading).truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees < -180 { degrees += 360 }
        return CGFloat(degrees * .pi / 180)
    }
}

final class HeadingConeAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

@MainActor
final class HeadingConeAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "walk-it-all-heading-cone"
    static let size = CGSize(width: 120, height: 120)

    private let directionView = UIView(frame: CGRect(origin: .zero, size: size))
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(origin: .zero, size: Self.size)
        backgroundColor = .clear
        isEnabled = false
        canShowCallout = false
        collisionMode = .none
        displayPriority = .required
        zPriority = .min
        accessibilityElementsHidden = true

        directionView.isUserInteractionEnabled = false
        directionView.backgroundColor = .clear
        addSubview(directionView)

        gradientLayer.type = .radial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.04)
        gradientLayer.locations = [0, 0.55, 1]
        gradientLayer.mask = maskLayer
        directionView.layer.addSublayer(gradientLayer)
        directionView.layer.addSublayer(outlineLayer)
        updateColors()
        updateLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        directionView.frame = bounds
        updateLayers()
    }

    func update(deviceHeading: CLLocationDirection, mapHeading: CLLocationDirection) {
        directionView.transform = CGAffineTransform(rotationAngle: HeadingConeGeometry.rotationRadians(
            deviceHeading: deviceHeading,
            mapHeading: mapHeading
        ))
    }

    private func updateLayers() {
        gradientLayer.frame = directionView.bounds
        maskLayer.frame = directionView.bounds
        outlineLayer.frame = directionView.bounds

        let center = CGPoint(x: directionView.bounds.midX, y: directionView.bounds.midY)
        let radius = min(directionView.bounds.width, directionView.bounds.height) / 2 - 5
        let halfAngle = CGFloat.pi / 5
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(
            withCenter: center,
            radius: radius,
            startAngle: -.pi / 2 - halfAngle,
            endAngle: -.pi / 2 + halfAngle,
            clockwise: true
        )
        path.close()
        maskLayer.path = path.cgPath
        maskLayer.fillColor = UIColor.black.cgColor
        outlineLayer.path = path.cgPath
    }

    private func updateColors() {
        gradientLayer.colors = [
            UIColor.systemBlue.withAlphaComponent(0.24).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.12).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.015).cgColor,
        ]
        outlineLayer.fillColor = UIColor.clear.cgColor
        outlineLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        outlineLayer.lineWidth = 0.75
    }
}
