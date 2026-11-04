import AppIntents

/// The widget's refresh button. WidgetKit reloads the widget after any of its buttons runs,
/// and those reloads don't count against the daily limit, so this needs no body.
struct RefreshSavedStopsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh saved stops"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult { .result() }
}
