import Foundation
import MapKit

/// Projects a GPS fix onto a route, retaining along-route distance rather than
/// jumping between nearby intersections or counting straight-line distance.
enum WalkingProgress {
    struct Projection {
        var distanceAlong: Double
        var distanceFromRoute: Double
        var totalDistance: Double
    }

    static func project(_ coordinate: CLLocationCoordinate2D, onto line: MKPolyline,
                        previous: Double = 0, advanceLimit: Double = .infinity) -> Projection? {
        guard line.pointCount > 1 else { return nil }
        let point = MKMapPoint(coordinate)
        let points = line.points()
        var along = 0.0
        var best: (along: Double, distance: Double)?
        for index in 1..<line.pointCount {
            let a = points[index - 1], b = points[index]
            let dx = b.x - a.x, dy = b.y - a.y
            let squared = dx * dx + dy * dy
            let fraction = squared > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared)) : 0
            let projected = MKMapPoint(x: a.x + fraction * dx, y: a.y + fraction * dy)
            let length = a.distance(to: b)
            let candidateAlong = along + fraction * length
            let distance = projected.distance(to: point)
            if candidateAlong >= max(0, previous - 20), candidateAlong <= previous + advanceLimit,
               best == nil || distance < best!.distance {
                best = (candidateAlong, distance)
            }
            along += length
        }
        guard let best else { return nil }
        return Projection(distanceAlong: best.along, distanceFromRoute: best.distance, totalDistance: along)
    }
}
