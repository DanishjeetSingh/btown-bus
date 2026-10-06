import ActivityKit
import AppIntents

struct EndWalkingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End walk to stop"
    func perform() async throws -> some IntentResult {
        for activity in Activity<WalkingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
