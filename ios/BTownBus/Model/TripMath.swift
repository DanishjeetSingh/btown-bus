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

    /// Stops left before the bus reaches `target`, counting the target (1 = your stop is next). Routes are loops.
    static func stopsAway(stopIds: [String], nextStopId: String?, target: String) -> Int? {
        guard !stopIds.isEmpty, let nextStopId else { return nil }
        let n = stopIds.count
        var best: Int?
        for (i, from) in stopIds.enumerated() where from == nextStopId {
            for (j, to) in stopIds.enumerated() where to == target {
                let gap = (j - i + n) % n
                if best == nil || gap < best! { best = gap }
            }
        }
        return best.map { $0 + 1 }
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
