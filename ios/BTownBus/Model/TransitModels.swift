import Foundation
import CoreLocation

enum Agency: String, Codable, CaseIterable, Hashable {
    case bt, iu

    var name: String { self == .iu ? "IU Campus Bus" : "Bloomington Transit" }
    var shortName: String { self == .iu ? "IU" : "BT" }
    var colorHex: String { self == .iu ? "#990000" : "#006298" }
    var feed: URL {
        URL(string: self == .iu ? "https://iucbs.etaspot.net/service.php" : "https://bloomingtontransit.etaspot.net/service.php")!
    }
}

/// "agency:id", shared with the web app's storage format.
struct TransitKey: Hashable, Codable, CustomStringConvertible {
    var agency: Agency
    var id: String
    var description: String { "\(agency.rawValue):\(id)" }

    init(agency: Agency, id: String) { self.agency = agency; self.id = id }
    init?(_ raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let agency = Agency(rawValue: parts[0]) else { return nil }
        self.init(agency: agency, id: parts[1])
    }
}

struct TransitRoute: Identifiable, Hashable {
    var agency: Agency
    var routeId: String
    var shortName: String
    var longName: String
    var colorHex: String
    var path: [CLLocationCoordinate2D]
    /// Stop IDs in the order the route serves them.
    var stopIds: [String]

    var id: TransitKey { TransitKey(agency: agency, id: routeId) }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TransitStop: Identifiable, Hashable {
    var agency: Agency
    var stopId: String
    var name: String
    var coordinate: CLLocationCoordinate2D
    var routeIds: [String]

    var id: TransitKey { TransitKey(agency: agency, id: stopId) }
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TransitVehicle: Identifiable, Hashable {
    var agency: Agency
    var vehicleId: String
    var routeId: String?
    var coordinate: CLLocationCoordinate2D
    var heading: Double?
    var direction: String?
    var nextStopId: String?
    var load: Int?
    var capacity: Int?
    var updatedAt: Date

    var id: TransitKey { TransitKey(agency: agency, id: vehicleId) }
    var isStale: Bool { Date().timeIntervalSince(updatedAt) > 90 }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.updatedAt == b.updatedAt }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TransitArrival: Identifiable, Hashable {
    var agency: Agency
    var routeId: String
    var stopId: String
    var vehicleId: String?
    var destination: String?
    var predictedArrival: Date

    var id: String { "\(agency.rawValue):\(stopId):\(routeId):\(vehicleId ?? "\(predictedArrival.timeIntervalSince1970)")" }
    var routeKey: TransitKey { TransitKey(agency: agency, id: routeId) }
    var stopKey: TransitKey { TransitKey(agency: agency, id: stopId) }

    func minutes(from now: Date = .now) -> Int { max(0, Int((predictedArrival.timeIntervalSince(now) / 60).rounded(.up))) }
}
