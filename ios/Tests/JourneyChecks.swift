import Foundation
import CoreLocation
import MapKit

// Run with scripts/check-ios-journey.sh. Exercises the same production math as the app.
@main struct JourneyChecks {
    static func main() {
        let now = Date()
        let coordinates = [0.0, 0.003, 0.006, 0.009]
        let stops = coordinates.enumerated().map { index, longitude in
            TransitStop(agency: .bt, stopId: String(index), name: "Stop \(index)",
                        coordinate: CLLocationCoordinate2D(latitude: 39, longitude: -86 + longitude), routeIds: ["r"])
        }
        let route = TransitRoute(agency: .bt, routeId: "r", shortName: "R", longName: "Route", colorHex: "#000000",
                                 path: [], stopIds: ["0", "1", "2", "3"],
                                 patterns: [TransitPattern(id: "p", name: "Outbound", stopIds: ["0", "1", "2", "3"], loops: false)])
        func vehicle(next: String, upcoming: [String] = [], at: Date? = nil) -> TransitVehicle {
            TransitVehicle(agency: .bt, vehicleId: "v", routeId: "r", coordinate: stops[0].coordinate,
                           nextStopId: next, patternId: "p", nextStops: upcoming, updatedAt: at ?? now)
        }
        func fix(_ longitude: Double, accuracy: Double = 5, age: Double = 0, speed: Double = 5) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39, longitude: longitude), altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 90, speed: speed,
                       timestamp: now.addingTimeInterval(-age))
        }
        precondition(TripMath.stopsAway(route: route, vehicle: vehicle(next: "0"), target: "3") == 4)
        precondition(TripMath.stopsAway(route: route, vehicle: vehicle(next: "3"), target: "0") == nil)
        precondition(TripMath.stopsAway(route: route, vehicle: vehicle(next: "0", upcoming: ["0", "2"]), target: "3") == nil)
        precondition(TripMath.stopsAway(route: nil, vehicle: vehicle(next: "0", upcoming: ["0", "2"]), target: "2") == 2)
        var ride = RideJourney.make(route: route, pickupIndex: 0, destinationOffset: 2, stops: stops)!
        ride.update(location: fix(-86), vehicle: nil, stops: stops, agency: .bt, now: now)
        precondition(!ride.requestedStop && ride.remainingStops == 2)
        ride.update(location: fix(-85.9985), vehicle: vehicle(next: "1"), stops: stops, agency: .bt, now: now)
        precondition(ride.departedCount == 1 && !ride.requestedStop) // GPS + feed must not advance twice.
        ride.update(location: fix(-85.997), vehicle: vehicle(next: "1"), stops: stops, agency: .bt, now: now)
        precondition(ride.enteredCurrentStop && !ride.requestedStop)
        ride.update(location: fix(-85.9955, age: 60), vehicle: nil, stops: stops, agency: .bt, now: now)
        precondition(!ride.requestedStop)
        ride.update(location: fix(-85.9955, accuracy: 150), vehicle: nil, stops: stops, agency: .bt, now: now)
        precondition(!ride.requestedStop)
        ride.update(location: fix(-85.9955), vehicle: nil, stops: stops, agency: .bt, now: now)
        precondition(ride.requestedStop && ride.remainingStops == 1 && !ride.atDestination)
        ride.update(location: fix(-85.994, speed: 0), vehicle: nil, stops: stops, agency: .bt, now: now)
        precondition(ride.atDestination && ride.remainingStops == 0)
        var oneStop = RideJourney.make(route: route, pickupIndex: 0, destinationOffset: 1, stops: stops)!
        oneStop.update(location: fix(-86), vehicle: vehicle(next: "0"), stops: stops, agency: .bt, now: now)
        precondition(!oneStop.requestedStop) // Do not alert while still at pickup.
        oneStop.update(location: nil, vehicle: vehicle(next: "1", at: now.addingTimeInterval(-100)), stops: stops, agency: .bt, now: now)
        precondition(!oneStop.requestedStop)
        oneStop.update(location: nil, vehicle: vehicle(next: "1"), stops: stops, agency: .bt, now: now)
        precondition(oneStop.requestedStop)
        let loop = RideJourney.make(route: route, pickupIndex: 3, destinationOffset: 2, loops: true, stops: stops)!
        precondition(loop.stopIds == ["3", "0", "1"])
        precondition(RideJourney.make(route: route, pickupIndex: 3, destinationOffset: 2, stops: stops) == nil)
        let repeatedRoute = TransitRoute(agency: .bt, routeId: "r", shortName: "R", longName: "Route", colorHex: "#000000", path: [], stopIds: ["0", "1", "0", "2"])
        var repeated = RideJourney.make(route: repeatedRoute, pickupIndex: 0, destinationOffset: 3, stops: stops)!
        repeated.update(location: nil, vehicle: vehicle(next: "1"), stops: stops, agency: .bt, now: now)
        precondition(repeated.departedCount == 1 && !repeated.requestedStop)
        repeated.update(location: nil, vehicle: vehicle(next: "0"), stops: stops, agency: .bt, now: now)
        precondition(repeated.departedCount == 2 && !repeated.requestedStop)
        repeated.update(location: nil, vehicle: vehicle(next: "2"), stops: stops, agency: .bt, now: now)
        precondition(repeated.departedCount == 3 && repeated.requestedStop)
        let walkingLine = MKPolyline(coordinates: [stops[0].coordinate, stops[1].coordinate, stops[2].coordinate], count: 3)
        let midpoint = WalkingProgress.project(CLLocationCoordinate2D(latitude: 39, longitude: -85.9985), onto: walkingLine)!
        precondition(midpoint.distanceFromRoute < 1 && midpoint.distanceAlong > 100 && midpoint.distanceAlong < 150)
        let later = WalkingProgress.project(stops[1].coordinate, onto: walkingLine, previous: midpoint.distanceAlong, advanceLimit: 200)!
        precondition(later.distanceAlong > midpoint.distanceAlong)
        let crossLine = MKPolyline(coordinates: [stops[0].coordinate, stops[1].coordinate, stops[2].coordinate, stops[0].coordinate], count: 4)
        let crossing = WalkingProgress.project(stops[0].coordinate, onto: crossLine, previous: 0, advanceLimit: 80)!
        precondition(crossing.distanceAlong < 1) // Do not jump to the later visit to the same point.
        let preferredPath = WalkingRoutePreference.describe(name: "Main Street", polyline: walkingLine)
        let otherCoordinates = [stops[0].coordinate, CLLocationCoordinate2D(latitude: 39.004, longitude: -85.997), stops[2].coordinate]
        let otherPath = WalkingRoutePreference.describe(name: "Other Street", polyline: MKPolyline(coordinates: otherCoordinates, count: 3))
        precondition(preferredPath.match(in: [otherPath, preferredPath]) == 1) // Response order must not change the preference.
        precondition(preferredPath.match(in: [preferredPath, otherPath]) == 0)
        precondition(preferredPath.match(in: [otherPath]) == nil)
        precondition(preferredPath.match(in: [preferredPath, preferredPath]) == nil) // Ambiguous paths require a choice.
        let preferenceData = try! JSONEncoder().encode(preferredPath)
        let restoredPreference = try! JSONDecoder().decode(WalkingRoutePreference.self, from: preferenceData)
        precondition(restoredPreference.match(in: [otherPath, preferredPath]) == 1)
        let data = try! JSONEncoder().encode(ride)
        precondition(try! JSONDecoder().decode(RideJourney.self, from: data) == ride)
        print("iOS stop-count and ride-progress checks passed")
    }
}
