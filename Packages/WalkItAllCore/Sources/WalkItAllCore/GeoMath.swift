import Foundation

public enum GeoMath {
    public static let earthRadiusMeters = 6_371_008.8

    public struct Projection: Sendable {
        public let distanceMeters: Double
    }

    public static func distance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let deltaLatitude = lat2 - lat1
        let deltaLongitude = radians(b.longitude - a.longitude)
        let sinLatitude = sin(deltaLatitude / 2)
        let sinLongitude = sin(deltaLongitude / 2)
        let value = sinLatitude * sinLatitude
            + cos(lat1) * cos(lat2) * sinLongitude * sinLongitude
        return earthRadiusMeters * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    public static func project(
        _ coordinate: GeoCoordinate,
        onto polyline: [GeoCoordinate]
    ) -> Projection? {
        guard polyline.count >= 2 else { return nil }
        let referenceLatitude = radians(coordinate.latitude)
        var bestDistance = Double.greatestFiniteMagnitude

        for (start, end) in zip(polyline, polyline.dropFirst()) {
            let a = localMeters(start, origin: coordinate, referenceLatitude: referenceLatitude)
            let b = localMeters(end, origin: coordinate, referenceLatitude: referenceLatitude)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let squaredLength = dx * dx + dy * dy
            let fraction = squaredLength > 0
                ? min(1, max(0, -(a.x * dx + a.y * dy) / squaredLength))
                : 0
            bestDistance = min(
                bestDistance,
                hypot(a.x + fraction * dx, a.y + fraction * dy)
            )
        }
        return Projection(distanceMeters: bestDistance)
    }

    private static func localMeters(
        _ coordinate: GeoCoordinate,
        origin: GeoCoordinate,
        referenceLatitude: Double
    ) -> (x: Double, y: Double) {
        (
            earthRadiusMeters * radians(coordinate.longitude - origin.longitude) * cos(referenceLatitude),
            earthRadiusMeters * radians(coordinate.latitude - origin.latitude)
        )
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
