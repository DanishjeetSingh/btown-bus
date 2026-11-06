import SwiftUI

/// Light, dark, or whatever the phone is set to. Kept in the shared App Group so the widget matches the app.
enum AppAppearance: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"
    static var defaults: UserDefaults? { UserDefaults(suiteName: SavedStopsShare.appGroup) }
    static var current: AppAppearance { defaults?.string(forKey: key).flatMap(AppAppearance.init) ?? .system }

    var title: String {
        switch self {
        case .system: return "Match phone"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
