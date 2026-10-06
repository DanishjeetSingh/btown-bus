import Foundation
import CoreLocation

/// Same rules as the web app's `src/transit/trip.ts`.
enum TripMath {
    static let walkSpeed = 1.3            // m/s
    static let walkDetour = 1.25          // straight lines undercount sidewalks
    static let leaveBuffer: TimeInterval = 60
    static let atStopRadius: CLLocationDistance = 40

    static func walkSeconds(distance: CLLocationDistance) -> Int {
        Int((distance * walkDetour / walkSpeed).rounded())
    }

    /// Within the stop radius, allowing for up to 40 m of reported GPS error.
    static func isAtStop(distance: CLLocationDistance, accuracy: CLLocationAccuracy) -> Bool {
        distance <= atStopRadius + min(max(accuracy, 0), 40)
    }

    /// Stops left before the bus reaches `target`, counting the target (1 = it's the bus's next stop).
    /// Nil when the bus's position can't be pinned down; callers still show the arrival time.
    static func stopsAway(route: TransitRoute?, vehicle: TransitVehicle, target: String) -> Int? {
        if let visits = upcomingVisits(route: route, vehicle: vehicle), let index = visits.firstIndex(of: target) {
            return index + 1
        }
        // The feed's short list can run past the end of the pattern data we have.
        return vehicle.nextStops.firstIndex(of: target).map { $0 + 1 }
    }

    /// The stops this bus will visit next, in order, starting with its next stop.
    ///
    /// The route's combined stop list mixes directions and branches, so it can't be used for this.
    /// Instead: find the bus in its current pattern (a stop it passes twice is told apart by the stop it
    /// just left), walk forward, wrap around loops, and carry on into the pattern its next trip runs.
    /// Every candidate must agree with the feed's own list of next stops. Nil if that leaves more than one answer.
    static func upcomingVisits(route: TransitRoute?, vehicle: TransitVehicle, limit: Int = 80) -> [String]? {
        let patterns = route?.patterns ?? []
        if let current = patterns.first(where: { $0.id == vehicle.patternId }),
           let visits = visits(on: current, among: patterns, vehicle: vehicle, limit: limit) {
            return visits
        }
        // The reported pattern can lag a turnaround. Accept exactly one other pattern that fits the live stops.
        guard vehicle.nextStops.count >= 2 else { return nil }
        let fits = patterns.filter { $0.id != vehicle.patternId }.compactMap { visits(on: $0, among: patterns, vehicle: vehicle, limit: limit) }
        return fits.count == 1 ? fits[0] : nil
    }

    private static func visits(on pattern: TransitPattern, among patterns: [TransitPattern], vehicle: TransitVehicle, limit: Int) -> [String]? {
        guard let next = vehicle.nextStopId ?? vehicle.nextStops.first else { return nil }
        let live = vehicle.nextStops
        var stops = pattern.stopIds
        if pattern.loops, stops.count > 1, stops.first == stops.last { stops.removeLast() }
        guard !stops.isEmpty else { return nil }

        var positions = stops.indices.filter { stops[$0] == next }
        if let last = vehicle.lastStopId {
            let matching = positions.filter { index in
                let previous = index > 0 ? stops[index - 1] : (pattern.loops ? stops.last : nil)
                return previous == last
            }
            if !matching.isEmpty { positions = matching }
        }

        var results: [[String]] = []
        for index in positions {
            var sequence: [String]
            if pattern.loops {
                let lap = Array(stops[index...]) + Array(stops[..<index])
                sequence = lap + lap
            } else {
                sequence = Array(stops[index...])
                // After the last stop, the bus starts its next trip: a pattern that begins where this one ends.
                let joins = patterns
                    .filter { $0.id != pattern.id && $0.stopIds.first == stops.last }
                    .map { sequence + $0.stopIds.dropFirst() }
                    .filter { agrees($0, with: live) }
                if joins.count == 1 {
                    sequence = joins[0]
                } else if joins.count > 1 {
                    // Several next trips fit; keep only the stops they share.
                    let shared = commonPrefix(joins)
                    if shared.count > sequence.count { sequence = shared }
                }
            }
            if agrees(sequence, with: live) { results.append(Array(sequence.prefix(limit))) }
        }
        guard let first = results.first, results.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The feed's next stops must match the start of the sequence (as far as the sequence goes).
    private static func agrees(_ sequence: [String], with live: [String]) -> Bool {
        live.enumerated().allSatisfy { offset, id in offset >= sequence.count || sequence[offset] == id }
    }

    private static func commonPrefix(_ lists: [[String]]) -> [String] {
        guard var prefix = lists.first else { return [] }
        for list in lists.dropFirst() {
            prefix = Array(zip(prefix, list).prefix { $0 == $1 }.map(\.0))
        }
        return prefix
    }

    enum LeaveState { case atStop, leaveNow, leaveSoon, tooLate }
    struct LeavePlan { var state: LeaveState; var leaveAt: Date; var minutesUntilLeave: Int }

    static func leavePlan(busArrival: Date, walkSeconds: Int?, now: Date = .now, atStop: Bool) -> LeavePlan? {
        if atStop { return LeavePlan(state: .atStop, leaveAt: now, minutesUntilLeave: 0) }
        guard let walkSeconds else { return nil }
        let walk = TimeInterval(walkSeconds)
        let leaveAt = busArrival.addingTimeInterval(-walk - leaveBuffer)
        let minutes = Int((leaveAt.timeIntervalSince(now) / 60).rounded(.down))
        if busArrival.addingTimeInterval(-walk) < now { return LeavePlan(state: .tooLate, leaveAt: leaveAt, minutesUntilLeave: minutes) }
        if minutes <= 1 { return LeavePlan(state: .leaveNow, leaveAt: leaveAt, minutesUntilLeave: minutes) }
        return LeavePlan(state: .leaveSoon, leaveAt: leaveAt, minutesUntilLeave: minutes)
    }
}

extension Date {
    /// "7:05 AM"
    var clock: String { formatted(date: .omitted, time: .shortened) }
}

func formatDistance(_ meters: CLLocationDistance) -> String {
    meters < 160 ? "\(Int((meters / 10).rounded()) * 10) m" : String(format: "%.1f mi", meters / 1609.344)
}
