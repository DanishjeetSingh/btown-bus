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

    /// Never infer a bus itinerary from a combined route stop list.
    static func stopsAway(route: TransitRoute?, vehicle: TransitVehicle, target: String) -> Int? {
        if let index = vehicle.nextStops.firstIndex(of: target) { return index + 1 }
        guard let pattern = route?.patterns.first(where: { $0.id == vehicle.patternId }),
              let next = vehicle.nextStopId else { return nil }
        var visits = pattern.stopIds
        if pattern.loops, visits.count > 1, visits.first == visits.last { visits.removeLast() }
        var counts: [Int] = []
        for index in visits.indices where visits[index] == next {
            let sequence = pattern.loops ? Array(visits[index...]) + Array(visits[..<index]) : Array(visits[index...])
            guard vehicle.nextStops.enumerated().allSatisfy({ offset, id in sequence.indices.contains(offset) && sequence[offset] == id }) else { continue }
            if let targetIndex = sequence.firstIndex(of: target) { counts.append(targetIndex + 1) }
        }
        guard let first = counts.first, counts.allSatisfy({ $0 == first }) else { return nil }
        return first
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
