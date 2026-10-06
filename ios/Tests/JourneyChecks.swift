import Foundation
import CoreLocation
import MapKit

// Run with scripts/check-ios-journey.sh. Exercises the same production math as the app.
@main struct JourneyChecks {
    static func main() {
        stopCounting()
        rideProgress()
        walkingMath()
        print("iOS stop-count and ride-progress checks passed")
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

    static func rideProgress() {
        let now = Date()
        let ids = ["0", "1", "2", "3"]
        let places = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CLLocation(latitude: 39, longitude: -86 + Double(index) * 0.003))
        })
        let at: (String) -> CLLocation? = { places[$0] }
        func fix(_ longitude: Double, accuracy: Double = 5, age: Double = 0, speed: Double = 5) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 39, longitude: longitude), altitude: 0, horizontalAccuracy: accuracy,
                       verticalAccuracy: 5, course: 90, speed: speed, timestamp: now.addingTimeInterval(-age))
        }

        // Boarding while the bus is still at the pickup.
        let options = RideJourney.options(pickup: "0", upcoming: ["0", "1", "2", "3"])
        precondition(options.pickupAhead && options.stops == ["1", "2", "3"])
        var ride = RideJourney.make(pickup: "0", upcoming: ["0", "1", "2", "3"], destinationIndex: 1, destinationName: "Stop 2")!
        precondition(ride.visits == ["0", "1", "2"] && ride.remainingStops == 2 && !ride.requestStop)
        // Still at the pickup: no alert.
        ride.update(location: fix(-86), busNextStop: "0", now: now, stopLocation: at)
        precondition(ride.departed == 0 && !ride.requestStop)
        // Feed says the bus left the pickup; GPS agreeing must not advance twice.
        ride.update(location: fix(-85.9985), busNextStop: "1", now: now, stopLocation: at)
        precondition(ride.departed == 1 && !ride.requestStop)
        // Stale or inaccurate GPS is ignored.
        ride.update(location: fix(-85.9955, age: 60), busNextStop: nil, now: now, stopLocation: at)
        ride.update(location: fix(-85.9955, accuracy: 150), busNextStop: nil, now: now, stopLocation: at)
        precondition(ride.departed == 1)
        // GPS: reach stop 1, then leave it. Your stop is next, so ring the bell.
        ride.update(location: fix(-85.997), busNextStop: nil, now: now, stopLocation: at)
        ride.update(location: fix(-85.9955), busNextStop: nil, now: now, stopLocation: at)
        precondition(ride.requestStop && ride.remainingStops == 1 && !ride.atDestination)
        ride.update(location: fix(-85.994, speed: 0), busNextStop: nil, now: now, stopLocation: at)
        precondition(ride.atDestination && ride.remainingStops == 0 && !ride.requestStop)

        // Boarding after the bus already left the pickup: a one-stop ride asks for the bell right away.
        let late = RideJourney.make(pickup: "0", upcoming: ["1", "2"], destinationIndex: 0, destinationName: "Stop 1")!
        precondition(late.visits == ["0", "1"] && late.departed == 1 && late.requestStop)

        // A loop that passes "0" twice: the feed can only move one nearby visit at a time.
        var loop = RideJourney.make(pickup: "0", upcoming: ["0", "1", "0", "2"], destinationIndex: 2, destinationName: "Stop 2")!
        precondition(loop.visits == ["0", "1", "0", "2"])
        loop.update(location: nil, busNextStop: "1", now: now, stopLocation: at)
        precondition(loop.departed == 1)
        loop.update(location: nil, busNextStop: "0", now: now, stopLocation: at)
        precondition(loop.departed == 2 && !loop.requestStop)
        loop.update(location: nil, busNextStop: "2", now: now, stopLocation: at)
        precondition(loop.departed == 3 && loop.requestStop)
        // The bus heads past your stop: time to get off (or you already did).
        loop.update(location: nil, busNextStop: "9", now: now, stopLocation: at)
        precondition(loop.atDestination)

        let data = try! JSONEncoder().encode(ride)
        precondition(try! JSONDecoder().decode(RideJourney.self, from: data) == ride)
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
