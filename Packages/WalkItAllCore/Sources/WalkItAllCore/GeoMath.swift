import Foundation

public enum GeoMath {
    public static let earthRadiusMeters = 6_371_008.8

    public struct Projection: Sendable {
        public let distanceMeters: Double
        public let offsetMeters: Double
        public let coordinate: GeoCoordinate
        public let localBearingDegrees: Double
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

    public static func polylineLength(_ coordinates: [GeoCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { partial, pair in
            partial + distance(pair.0, pair.1)
        }
    }

    public static func bearing(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let deltaLongitude = radians(b.longitude - a.longitude)
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return normalizedDegrees(degrees(atan2(y, x)))
    }

    public static func undirectedHeadingDifference(_ a: Double, _ b: Double) -> Double {
        let direct = abs(normalizedDegrees(a) - normalizedDegrees(b))
        let circular = min(direct, 360 - direct)
        return min(circular, abs(180 - circular))
    }

    public static func project(_ coordinate: GeoCoordinate, onto polyline: [GeoCoordinate]) -> Projection? {
        guard polyline.count >= 2 else { return nil }

        let referenceLatitude = radians(coordinate.latitude)
        let origin = coordinate
        var bestDistance = Double.greatestFiniteMagnitude
        var bestOffset = 0.0
        var bestCoordinate = polyline[0]
        var bestBearing = 0.0
        var cumulative = 0.0

        for (a, b) in zip(polyline, polyline.dropFirst()) {
            let aPoint = localMeters(a, origin: origin, referenceLatitude: referenceLatitude)
            let bPoint = localMeters(b, origin: origin, referenceLatitude: referenceLatitude)
            let dx = bPoint.x - aPoint.x
            let dy = bPoint.y - aPoint.y
            let squaredLength = dx * dx + dy * dy
            let rawT: Double
            if squaredLength > 0 {
                rawT = -(aPoint.x * dx + aPoint.y * dy) / squaredLength
            } else {
                rawT = 0
            }
            let t = min(1, max(0, rawT))
            let x = aPoint.x + t * dx
            let y = aPoint.y + t * dy
            let candidateDistance = hypot(x, y)
            let pieceLength = distance(a, b)

            if candidateDistance < bestDistance {
                bestDistance = candidateDistance
                bestOffset = cumulative + t * pieceLength
                bestCoordinate = interpolate(from: a, to: b, fraction: t)
                bestBearing = bearing(from: a, to: b)
            }
            cumulative += pieceLength
        }

        return Projection(
            distanceMeters: bestDistance,
            offsetMeters: bestOffset,
            coordinate: bestCoordinate,
            localBearingDegrees: bestBearing
        )
    }

    public static func interpolate(
        from a: GeoCoordinate,
        to b: GeoCoordinate,
        fraction: Double
    ) -> GeoCoordinate {
        let t = min(1, max(0, fraction))
        return GeoCoordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    public static func slice(
        polyline: [GeoCoordinate],
        from lowerBoundMeters: Double,
        to upperBoundMeters: Double
    ) -> [GeoCoordinate] {
        guard polyline.count >= 2 else { return polyline }
        let total = polylineLength(polyline)
        let lower = min(total, max(0, min(lowerBoundMeters, upperBoundMeters)))
        let upper = min(total, max(0, max(lowerBoundMeters, upperBoundMeters)))
        guard upper > lower else { return [] }

        var result: [GeoCoordinate] = []
        var cumulative = 0.0
        for (start, end) in zip(polyline, polyline.dropFirst()) {
            let pieceLength = distance(start, end)
            let pieceStart = cumulative
            let pieceEnd = cumulative + pieceLength
            defer { cumulative = pieceEnd }
            guard pieceEnd >= lower, pieceStart <= upper, pieceLength > 0 else { continue }

            let startFraction = max(0, (lower - pieceStart) / pieceLength)
            let endFraction = min(1, (upper - pieceStart) / pieceLength)
            let clippedStart = interpolate(from: start, to: end, fraction: startFraction)
            let clippedEnd = interpolate(from: start, to: end, fraction: endFraction)
            if result.last != clippedStart { result.append(clippedStart) }
            if result.last != clippedEnd { result.append(clippedEnd) }
        }
        return result
    }

    static func globalMeters(_ coordinate: GeoCoordinate, referenceLatitude: Double = 40.75) -> (x: Double, y: Double) {
        let latitudeRadians = radians(coordinate.latitude)
        let longitudeRadians = radians(coordinate.longitude)
        return (
            earthRadiusMeters * longitudeRadians * cos(radians(referenceLatitude)),
            earthRadiusMeters * latitudeRadians
        )
    }

    private static func localMeters(
        _ coordinate: GeoCoordinate,
        origin: GeoCoordinate,
        referenceLatitude: Double
    ) -> (x: Double, y: Double) {
        let x = earthRadiusMeters
            * radians(coordinate.longitude - origin.longitude)
            * cos(referenceLatitude)
        let y = earthRadiusMeters * radians(coordinate.latitude - origin.latitude)
        return (x, y)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }
}
