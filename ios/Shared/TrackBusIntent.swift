import ActivityKit
import AppIntents

/// A row on the Saved Stops widget: start tracking the next bus on that route, without opening the app.
/// Tapping the row of the bus already being tracked stops it.
/// Live Activity intents run in the app's process, which is the only place that can start one from the background.
struct TrackBusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Track bus"
    static var isDiscoverable = false

    @Parameter(title: "Agency") var agency: String
    @Parameter(title: "Stop") var stopId: String
    @Parameter(title: "Route") var routeId: String

    init() {}

    init(agency: String, stopId: String, routeId: String) {
        self.agency = agency
        self.stopId = stopId
        self.routeId = routeId
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let agency = Agency(rawValue: agency) {
            await TripTracker.shared.toggleFromWidget(agency: agency, stopId: stopId, routeId: routeId)
        }
        #endif
        return .result()
    }
}
