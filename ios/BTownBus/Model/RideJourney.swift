import Foundation
import CoreLocation

/// A particular sequence of visits, including repeated stop IDs. Progress never wraps
/// or jumps to the closest occurrence of a stop elsewhere on the route.
struct RideJourney: Codable, Equatable {
    var stopIds: [String]
    var destinationName: String
    var departedCount = 0
    var enteredCurrentStop = false
    var requestedStop = false
    var atDestination = false
    var lastFeedNextStop: String?

    var destinationId: String { stopIds.last! }
    var remainingStops: Int { atDestination ? 0 : max(1, stopIds.count - max(1, departedCount)) }

    static func make(route: TransitRoute, pickupIndex: Int, destinationOffset: Int, loops: Bool = false, stops: [TransitStop]) -> Self? {
        guard route.stopIds.indices.contains(pickupIndex), destinationOffset > 0,
              destinationOffset < route.stopIds.count, (loops || pickupIndex + destinationOffset < route.stopIds.count) else { return nil }
        let visits = (0...destinationOffset).map { route.stopIds[(pickupIndex + $0) % route.stopIds.count] }
        guard let destination = stops.first(where: { $0.agency == route.agency && $0.stopId == visits.last }) else { return nil }
        return Self(stopIds: visits, destinationName: destination.name, lastFeedNextStop: visits.first)
    }

    mutating func update(location: CLLocation?, vehicle: TransitVehicle?, stops: [TransitStop], agency: Agency, now: Date) {
        guard !atDestination else { return }
        let previousDepartedCount = departedCount
        let usable = location.flatMap { fix -> CLLocation? in
            guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 35,
                  now.timeIntervalSince(fix.timestamp) >= 0, now.timeIntervalSince(fix.timestamp) < 20 else { return nil }
            return fix
        }
        if let fix = usable {
            if departedCount < stopIds.count - 1,
               let current = stops.first(where: { $0.agency == agency && $0.stopId == stopIds[departedCount] }) {
                let distance = fix.distance(from: current.location)
                if distance <= 45 { enteredCurrentStop = true }
                if enteredCurrentStop, distance > 85, fix.speed > 2 {
                    departedCount += 1
                    enteredCurrentStop = false
                }
            }
            if departedCount == stopIds.count - 1,
               let destination = stops.first(where: { $0.agency == agency && $0.stopId == destinationId }),
               fix.distance(from: destination.location) <= 45 {
                atDestination = true
            }
        }
        // Feed transitions can confirm departure when GPS misses a stop. Only accept
        // the immediately following visit, and only after observing the current visit.
        if let vehicle, now.timeIntervalSince(vehicle.updatedAt) >= 0, now.timeIntervalSince(vehicle.updatedAt) < 30, let next = vehicle.nextStopId {
            if departedCount == previousDepartedCount, departedCount < stopIds.count - 1,
               lastFeedNextStop == stopIds[departedCount],
               next == stopIds[departedCount + 1], next != lastFeedNextStop {
                departedCount += 1
                enteredCurrentStop = false
            }
            lastFeedNextStop = next
        }
        if departedCount == stopIds.count - 1 || atDestination { requestedStop = true }
    }
}
