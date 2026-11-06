import SwiftUI
import WidgetKit

@main
struct BTownBusApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let store = AppStore.shared
    private let location = LocationService.shared
    private let tracker = TripTracker.shared
    @AppStorage(AppAppearance.key, store: AppAppearance.defaults) private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(tracker)
                .preferredColorScheme(appearance.colorScheme)
                // Also set it on the window, so sheets follow and "Match phone" really goes back to the phone's setting.
                .onChange(of: appearance, initial: true) { _, value in
                    applyToWindows(value)
                    WidgetCenter.shared.reloadTimelines(ofKind: SavedStopsShare.widgetKind)
                }
                .task {
                    tracker.resume()
                    #if DEBUG
                    await tracker.startDemoActivityIfRequested()
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { applyToWindows(appearance) }
            switch phase {
            case .active:
                location.appDidBecomeActive()
                store.startPolling()
                tracker.appDidBecomeActive()
            case .background:
                // The trip tracker keeps its own loop alive through background location.
                store.stopPolling()
                location.appDidEnterBackground()
            default: break
            }
        }
    }

    private func applyToWindows(_ appearance: AppAppearance) {
        let style: UIUserInterfaceStyle = appearance == .light ? .light : appearance == .dark ? .dark : .unspecified
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}
