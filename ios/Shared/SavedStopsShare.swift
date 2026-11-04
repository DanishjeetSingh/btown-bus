import Foundation

/// Saved stops, written by the app and read by the Saved Stops widget through a shared App Group.
/// Names and route colors are stored here so the widget only has to fetch arrival times.
enum SavedStopsShare {
    static let appGroup = "group.me.singhdan.btownbus"
    private static let key = "saved-stops"

    struct Stop: Codable, Hashable {
        var agency: String
        var id: String
        var name: String
        var routes: [Route]
    }

    struct Route: Codable, Hashable {
        var id: String
        var shortName: String
        var colorHex: String
    }

    static func load() -> [Stop] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Stop].self, from: data)) ?? []
    }

    /// Returns true when the saved list actually changed.
    @discardableResult
    static func save(_ stops: [Stop]) -> Bool {
        guard stops != load(), let data = try? JSONEncoder().encode(stops) else { return false }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
        return true
    }
}
