import Foundation
import CoreLocation
import MapKit

// Run with scripts/check-ios-journey.sh. Exercises the same production math as the app.
@main struct JourneyChecks {
    static func main() {
        stopCounting()
        walkingMath()
        print("iOS stop-count and walking checks passed")
    }

    static func bus(pattern: String?, next: String?, last: String? = nil, upcoming: [String] = []) -> TransitVehicle {
        TransitVehicle(agency: .bt, vehicleId: "v", routeId: "r", coordinate: .init(latitude: 39, longitude: -86),
                       nextStopId: next, patternId: pattern, lastStopId: last, nextStops: upcoming, updatedAt: Date())
    }

    static func route(_ patterns: [TransitPattern]) -> TransitRoute {
        // The combined list deliberately mixes directions, like the real feed. It must not be used for counting.
        TransitRoute(agency: .bt, routeId: "r", shortName: "R", longName: "Route", colorHex: "#000000", path: [],
                     stopIds: Array(Set(patterns.flatMap(\.stopIds))).sorted(), patterns: patterns)
    }

    static func stopCounting() {
        // Bloomington Transit style: one-way patterns. Outbound ends where Inbound begins.
        let outbound = TransitPattern(id: "out", name: "Outbound", stopIds: ["hub", "a", "b", "end"], loops: false)
        let inbound = TransitPattern(id: "in", name: "Inbound", stopIds: ["end", "c", "d", "hub"], loops: false)
        let twoWay = route([outbound, inbound])
        precondition(TripMath.stopsAway(route: twoWay, vehicle: bus(pattern: "out", next: "a"), target: "b") == 2)
        precondition(TripMath.stopsAway(route: twoWay, vehicle: bus(pattern: "out", next: "a"), target: "a") == 1)
        // Past the end of Outbound the bus turns around into Inbound.
        precondition(TripMath.stopsAway(route: twoWay, vehicle: bus(pattern: "out", next: "b"), target: "d") == 4)
        precondition(TripMath.upcomingVisits(route: twoWay, vehicle: bus(pattern: "out", next: "b")) == ["b", "end", "c", "d", "hub"])
        // The feed's own next stops (which run into the next trip) must agree.
        precondition(TripMath.stopsAway(route: twoWay, vehicle: bus(pattern: "out", next: "end", upcoming: ["end", "c", "d"]), target: "d") == 3)
        // Reported pattern lags a turnaround: the live stops only fit Inbound.
        precondition(TripMath.stopsAway(route: twoWay, vehicle: bus(pattern: "out", next: "c", upcoming: ["c", "d"]), target: "hub") == 3)
        // Unknown pattern and target not in the feed's list: no guess.
        precondition(TripMath.stopsAway(route: twoWay, vehicle: bus(pattern: nil, next: "a"), target: "d") == nil)
        precondition(TripMath.stopsAway(route: nil, vehicle: bus(pattern: nil, next: "a", upcoming: ["a", "b"]), target: "b") == 2)

        // Two next trips start where Outbound ends; only their shared stops are certain.
        let shortIn = TransitPattern(id: "in2", name: "Inbound short", stopIds: ["end", "c", "x"], loops: false)
        let branching = route([outbound, inbound, shortIn])
        precondition(TripMath.stopsAway(route: branching, vehicle: bus(pattern: "out", next: "b"), target: "c") == 3)
        precondition(TripMath.stopsAway(route: branching, vehicle: bus(pattern: "out", next: "b"), target: "d") == nil)
        precondition(TripMath.stopsAway(route: branching, vehicle: bus(pattern: "out", next: "end", upcoming: ["end", "c", "d"]), target: "d") == 3)

        // IU style: a loop that passes stop "1" twice, closed with a repeat of its first stop.
        let loop = TransitPattern(id: "loop", name: "F", stopIds: ["1", "2", "3", "1", "4", "5", "1"], loops: true)
        let campus = route([loop])
        // The stop the bus just left says which visit to "1" comes next.
        precondition(TripMath.stopsAway(route: campus, vehicle: bus(pattern: "loop", next: "1", last: "3"), target: "5") == 3)
        precondition(TripMath.stopsAway(route: campus, vehicle: bus(pattern: "loop", next: "1", last: "5"), target: "5") == 6)
        // Without it, the two visits disagree, so there's no count.
        precondition(TripMath.stopsAway(route: campus, vehicle: bus(pattern: "loop", next: "1"), target: "5") == nil)
        // Wrapping around the loop.
        precondition(TripMath.stopsAway(route: campus, vehicle: bus(pattern: "loop", next: "5"), target: "2") == 3)
    }

    static func walkingMath() {
        let coordinates = [0.0, 0.003, 0.006].map { CLLocationCoordinate2D(latitude: 39, longitude: -86 + $0) }
        let walkingLine = MKPolyline(coordinates: coordinates, count: 3)
        let midpoint = WalkingProgress.project(CLLocationCoordinate2D(latitude: 39, longitude: -85.9985), onto: walkingLine)!
        precondition(midpoint.distanceFromRoute < 1 && midpoint.distanceAlong > 100 && midpoint.distanceAlong < 150)
        let later = WalkingProgress.project(coordinates[1], onto: walkingLine, previous: midpoint.distanceAlong, advanceLimit: 200)!
        precondition(later.distanceAlong > midpoint.distanceAlong)
        let crossLine = MKPolyline(coordinates: coordinates + [coordinates[0]], count: 4)
        let crossing = WalkingProgress.project(coordinates[0], onto: crossLine, previous: 0, advanceLimit: 80)!
        precondition(crossing.distanceAlong < 1) // Do not jump to the later visit to the same point.
        let preferred = WalkingRoutePreference.describe(name: "Main Street", polyline: walkingLine)
        let otherCoordinates = [coordinates[0], CLLocationCoordinate2D(latitude: 39.004, longitude: -85.997), coordinates[2]]
        let other = WalkingRoutePreference.describe(name: "Other Street", polyline: MKPolyline(coordinates: otherCoordinates, count: 3))
        precondition(preferred.match(in: [other, preferred]) == 1) // Response order must not change the preference.
        precondition(preferred.match(in: [preferred, other]) == 0)
        precondition(preferred.match(in: [other]) == nil)
    }
}
