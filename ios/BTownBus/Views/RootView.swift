import SwiftUI

enum AppTab: String { case saved, nearby, map }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @AppStorage("tab") private var tab: AppTab = .nearby
    @State private var openStop: TransitStop?
    @State private var showRoutes = false

    var body: some View {
        TabView(selection: $tab) {
            SavedView(openStop: $openStop)
                .withChrome(showRoutes: $showRoutes, openStop: $openStop)
                .tabItem { Label("Saved", systemImage: "star.fill") }
                .tag(AppTab.saved)
            NearbyView(openStop: $openStop)
                .withChrome(showRoutes: $showRoutes, openStop: $openStop)
                .tabItem { Label("Nearby", systemImage: "location.circle.fill") }
                .tag(AppTab.nearby)
            MapScreen(openStop: $openStop)
                .withChrome(showRoutes: $showRoutes, openStop: $openStop)
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppTab.map)
        }
        .tint(Theme.ink)
        .sheet(item: $openStop) { stop in
            StopDetailView(stop: stop)
                .presentationDetents(tab == .map ? [.medium, .large] : [.large, .medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Theme.surface)
        }
        .sheet(isPresented: $showRoutes) {
            RoutePickerView()
                .presentationDetents([.large])
                .presentationBackground(Theme.surface)
        }
        .onAppear {
            location.requestPermission()
            if !UserDefaults.standard.bool(forKey: "tab-chosen") {
                tab = store.saved.isEmpty ? .nearby : .saved
                UserDefaults.standard.set(true, forKey: "tab-chosen")
            }
            if !store.hasChosenRoutes { showRoutes = true }
        }
        .onChange(of: openStop) { _, stop in
            store.focusedStop = stop?.id
            if stop != nil { Task { await store.refreshNow() } }
        }
    }
}

private struct Chrome: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(TripTracker.self) private var tracker
    @Binding var showRoutes: Bool
    @Binding var openStop: TransitStop?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                BrandBar {
                    HStack(spacing: 8) {
                        LocationPill()
                        Button { showRoutes = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill").font(.system(size: 13, weight: .bold))
                                Text("Routes").font(.system(size: 14, weight: .heavy))
                                Text("\(store.pickedRoutes.count)")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(Color.busYellow)
                                    .frame(minWidth: 24, minHeight: 24)
                                    .background(Color.busInk, in: Capsule())
                            }
                            .fixedSize()
                            .padding(.leading, 11).padding(.trailing, 6).frame(height: 40)
                            .foregroundStyle(Color.busInk)
                            .background(Color(hex: "#fffdf7"), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.busInk, lineWidth: 2.5))
                            .background(Capsule().fill(Color.busInk).offset(y: 3))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if tracker.watch != nil {
                    TripBanner { stop in openStop = stop }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .background(Theme.bg)
    }
}

extension View {
    func withChrome(showRoutes: Binding<Bool>, openStop: Binding<TransitStop?>) -> some View {
        modifier(Chrome(showRoutes: showRoutes, openStop: openStop))
    }
}

/// GPS status that doubles as the refresh button: tap it to fetch new times and a new position.
/// A blinking blue dot means a fresh position; a hollow ring means it's old or missing,
/// so the state doesn't depend on telling colors apart.
struct LocationPill: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var refreshing = false
    @State private var spins = 0

    var body: some View {
        if location.isAuthorized {
            Button { refresh() } label: {
                HStack(spacing: 7) {
                    dot
                    Text("GPS").font(.system(size: 13, weight: .black)).tracking(0.8)
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .black))
                        .rotationEffect(.degrees(Double(spins) * 360))
                        .animation(.easeInOut(duration: 0.7), value: spins)
                }
                .foregroundStyle(Color.busInk)
                .padding(.horizontal, 13).frame(height: 40)
                .overlay(Capsule().strokeBorder(Color.busInk, lineWidth: 2.5))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(refreshing)
            .sensoryFeedback(.impact, trigger: spins)
            .accessibilityLabel(location.freshLocation != nil ? "GPS live. Refresh" : "GPS position is old. Refresh")
        } else {
            Button {
                if location.isDenied { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                else { location.requestPermission() }
            } label: {
                Label(location.isDenied ? "Blocked" : "Locate", systemImage: "location.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.busInk)
                    .padding(.horizontal, 13).frame(height: 40)
                    .overlay(Capsule().strokeBorder(Color.busInk, lineWidth: 2.5))
            }
        }
    }

    @ViewBuilder private var dot: some View {
        if location.freshLocation != nil {
            // Only the dot's opacity animates, so nothing else in the bar moves.
            Circle().fill(Theme.me).frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(Color.busInk, lineWidth: 1.5))
                .phaseAnimator([1.0, 0.25]) { dot, opacity in dot.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            Circle().strokeBorder(Color.busInk, lineWidth: 2).frame(width: 11, height: 11)
        }
    }

    private func refresh() {
        spins += 1
        refreshing = true
        location.requestFreshFix()
        Task {
            await store.refreshNow()
            refreshing = false
        }
    }
}
