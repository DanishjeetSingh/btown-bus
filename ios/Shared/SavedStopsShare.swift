import Foundation
import CoreLocation

/// Saved stops, written by the app and read by the Saved Stops widget through a shared App Group.
/// Names and route colors are stored here so the widget only has to fetch arrival times.
enum SavedStopsShare {
    static let appGroup = "group.me.singhdan.btownbus"
    static let widgetKind = "SavedStops"
    private static let key = "saved-stops-v2"
    private static let trackingKey = "tracking"
    private static let locationKey = "last-location"

    struct Stop: Codable, Hashable {
        var name: String
        var latitude: Double
        var longitude: Double
        /// One stop, or an IU and a Bloomington Transit stop on the same pole.
        var stops: [Member]
        /// Every route at the stop, for names and colors.
        var routes: [Route]
        /// "agency:routeId" of the saved buses. Empty means every bus.
        var only: [String]
    }

    struct Member: Codable, Hashable {
        var agency: String
        var id: String
    }

    struct Route: Codable, Hashable {
        var agency: String
        var id: String
        var shortName: String
        var colorHex: String
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> [Stop] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Stop].self, from: data)) ?? []
    }

    /// Returns true when the saved list actually changed.
    @discardableResult
    static func save(_ stops: [Stop]) -> Bool {
        guard stops != load(), let data = try? JSONEncoder().encode(stops) else { return false }
        defaults?.set(data, forKey: key)
        return true
    }

    /// Where the app last saw you, so the widget can put the closest stop first
    /// even when it can't get a location of its own.
    static var lastLocation: CLLocation? {
        get {
            guard let values = defaults?.array(forKey: locationKey) as? [Double], values.count == 3 else { return nil }
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: values[0], longitude: values[1]), altitude: 0,
                              horizontalAccuracy: 50, verticalAccuracy: -1, timestamp: Date(timeIntervalSince1970: values[2]))
        }
        set {
            guard let newValue else { defaults?.removeObject(forKey: locationKey); return }
            defaults?.set([newValue.coordinate.latitude, newValue.coordinate.longitude, newValue.timestamp.timeIntervalSince1970], forKey: locationKey)
        }
    }

    /// The bus being tracked, as "agency:stopId:routeId", so the widget can mark its row.
    static var tracking: String? {
        get { defaults?.string(forKey: trackingKey) }
        set { defaults?.set(newValue, forKey: trackingKey) }
    }
}
