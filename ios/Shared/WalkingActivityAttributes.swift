import ActivityKit
import Foundation

struct WalkingActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable {
        case locating, choosing, walking, rerouting, unavailable, arrived
    }
    struct ContentState: Codable, Hashable {
        var phase: Phase
        var instruction: String
        var maneuverSymbol: String
        var maneuverMeters: Int
        var remainingMeters: Int
        var remainingMinutes: Int
        var arrivalAt: Date?
        var updatedAt: Date
    }
    var stopName: String
}
