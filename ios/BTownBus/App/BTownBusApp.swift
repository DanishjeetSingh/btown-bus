import SwiftUI

@main
struct BTownBusApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let store = AppStore.shared
    private let location = LocationService.shared
    private let tracker = TripTracker.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(tracker)
                .task {
                    tracker.resume()
                    #if DEBUG
                    await tracker.startDemoActivityIfRequested()
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
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
}
