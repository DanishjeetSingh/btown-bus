import ActivityKit
import AppIntents

/// The "End" button on the Live Activity. Ending it tells the app to stop tracking.
struct EndTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop tracking bus"

    func perform() async throws -> some IntentResult {
        for activity in Activity<TripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
