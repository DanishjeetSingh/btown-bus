import Foundation
import CoreLocation

/// A ride on one bus, from the stop you boarded at to the stop you're getting off at.
///
/// `visits` is the exact run of stops the bus serves, in order (a stop can appear twice on a loop).
/// Progress only moves forward, one visit at a time, from the bus feed or your phone's GPS.
struct RideJourney: Codable, Equatable {
    /// Pickup first, destination last.
    var visits: [String]
    var destinationName: String
    /// How many of `visits` the bus has left. Its next stop is `visits[departed]`.
    var departed: Int
    var enteredCurrentStop = false
    var atDestination = false

    var destinationId: String { visits.last ?? "" }
    var nextStopId: String? { visits.indices.contains(departed) ? visits[departed] : nil }
    /// Stops still to come, counting your destination. 1 means your stop is next.
    var remainingStops: Int { atDestination ? 0 : max(0, visits.count - max(departed, 1)) }
    /// Ring the bell: you've left the stop before yours.
    var requestStop: Bool { !atDestination && departed >= 1 && remainingStops == 1 }

    /// Where you could be getting off, given the bus's upcoming stops.
    /// If the pickup is the bus's next stop you haven't left it yet; otherwise the bus already has.
    static func options(pickup: String, upcoming: [String], limit: Int = 40) -> (stops: [String], pickupAhead: Bool) {
        let pickupAhead = upcoming.first == pickup
        let stops = Array((pickupAhead ? upcoming.dropFirst() : upcoming[...]).prefix(limit))
        return (stops, pickupAhead)
    }

    /// `destinationIndex` indexes into `options(pickup:upcoming:).stops`.
    static func make(pickup: String, upcoming: [String], destinationIndex: Int, destinationName: String) -> Self? {
        let (stops, pickupAhead) = options(pickup: pickup, upcoming: upcoming)
        guard stops.indices.contains(destinationIndex) else { return nil }
        return Self(visits: [pickup] + stops[...destinationIndex], destinationName: destinationName, departed: pickupAhead ? 0 : 1)
    }

    mutating func update(location: CLLocation?, busNextStop: String?, now: Date, stopLocation: (String) -> CLLocation?) {
        guard !atDestination, !visits.isEmpty else { return }

        // The feed's next stop moves us forward, but only to a nearby later visit, so a stop the
        // route passes twice can't make the ride jump ahead.
        if let next = busNextStop {
            let window = departed..<min(visits.count, departed + 4)
            if let index = window.first(where: { visits[$0] == next }), index > departed {
                departed = index
                enteredCurrentStop = false
            } else if departed == visits.count - 1, next != destinationId, !window.contains(where: { visits[$0] == next }) {
                // The bus is already heading past your stop.
                atDestination = true
                return
            }
        }

        // GPS: arriving at the next stop and then leaving it counts as passing it.
        guard let fix = location, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 35,
              now.timeIntervalSince(fix.timestamp) >= 0, now.timeIntervalSince(fix.timestamp) < 20 else { return }
        if departed < visits.count - 1, let current = stopLocation(visits[departed]) {
            let distance = fix.distance(from: current)
            if distance <= 45 { enteredCurrentStop = true }
            if enteredCurrentStop, distance > 85, fix.speed > 2 {
                departed += 1
                enteredCurrentStop = false
            }
        }
        if departed >= 1, remainingStops == 1, let destination = stopLocation(destinationId), fix.distance(from: destination) <= 45 {
            atDestination = true
        }
    }
}
