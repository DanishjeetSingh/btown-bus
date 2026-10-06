import ActivityKit
import SwiftUI

/// The Live Activity for one tracked bus heading to one stop.
struct TripActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable {
        /// Bus is coming; you have time before you need to leave.
        case onTheWay
        /// Your walk plus a minute of buffer means it's time to go.
        case leaveNow
        /// Walking won't make it in time.
        case tooLate
        /// You're standing at the stop.
        case atStop
        /// The bus is at or just about to reach your stop.
        case arriving
        /// The bus has passed your stop.
        case departed
        /// The feed has no prediction for this bus right now.
        case noPrediction
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        var busArrival: Date?
        var stopsAway: Int?
        var walkSeconds: Int?
        var leaveAt: Date?
        var updatedAt: Date
    }

    var routeShortName: String
    var routeColorHex: String
    var stopName: String
    var agencyName: String
    /// Stops away that started this activity, used to scale the progress ladder.
    var startStops: Int
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        let number = UInt64(value.prefix(6), radix: 16) ?? 0x006298
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }

    /// Black or white, whichever reads better on this hex color.
    static func readableInk(on hex: String) -> Color {
        var value = hex.replacingOccurrences(of: "#", with: "")
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        let number = UInt64(value.prefix(6), radix: 16) ?? 0
        func linear(_ channel: UInt64) -> Double {
            let c = Double(channel) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((number >> 16) & 0xff) + 0.7152 * linear((number >> 8) & 0xff) + 0.0722 * linear(number & 0xff)
        return luminance > 0.4 ? Color(hex: "#15130f") : .white
    }

    static let busYellow = Color(hex: "#ffcb2f")
    static let busInk = Color(hex: "#15130f")
    static let busCream = Color(hex: "#fff4de")
    static let goGreen = Color(hex: "#34d27a")
    static let warnOrange = Color(hex: "#ff7a52")
}
