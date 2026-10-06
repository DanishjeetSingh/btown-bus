import Foundation
import MapKit

/// Apple doesn't provide a stable route ID. Remember the route name and corridor,
/// never its response-array index (which can change between requests).
struct WalkingRoutePreference: Codable {
    struct Point: Codable {
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }
    var name: String
    var points: [Point]

    static func describe(name: String, polyline: MKPolyline) -> Self {
        let count = polyline.pointCount
        guard count > 0 else { return Self(name: name, points: []) }
        let stride = max(1, count / 80)
        var samples = Swift.stride(from: 0, to: count, by: stride).map { index in
            let coordinate = polyline.points()[index].coordinate
            return Point(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        let last = polyline.points()[count - 1].coordinate
        samples.append(Point(latitude: last.latitude, longitude: last.longitude))
        return Self(name: name, points: samples)
    }

    func match(in candidates: [Self]) -> Int? {
        guard points.count > 1 else { return nil }
        let scores = candidates.map { candidate -> Double in
            guard candidate.points.count > 1 else { return 0 }
            let coordinates = candidate.points.map(\.coordinate)
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            return Double(points.filter {
                (WalkingProgress.project($0.coordinate, onto: line)?.distanceFromRoute ?? .infinity) < 30
            }.count) / Double(points.count)
        }
        let named = candidates.indices.filter { candidates[$0].name == name && scores[$0] >= 0.6 }
        if named.count == 1 { return named[0] }
        let ranked = candidates.indices.sorted { scores[$0] > scores[$1] }
        guard let best = ranked.first, scores[best] >= 0.8,
              ranked.count == 1 || scores[best] - scores[ranked[1]] > 0.1 else { return nil }
        return best
    }
}
