import SwiftUI
import CoreLocation

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Binding var openStop: TransitStop?
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Saved stops").font(Theme.display(34)).foregroundStyle(Theme.ink)
                    Spacer()
                    if store.favoriteStops.count > 1 {
                        Button(editing ? "Done" : "Reorder") { withAnimation { editing.toggle() } }
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.muted)
                    }
                }
                StatusBanners()
                if store.favoriteStops.isEmpty {
                    EmptySaved()
                } else if editing {
                    ForEach(Array(store.favoriteStops.enumerated()), id: \.element.id) { index, stop in
                        HStack {
                            Text(stop.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink)
                            Spacer()
                            Button { store.moveFavorites(from: [index], to: max(0, index - 1)) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                            Button { store.moveFavorites(from: [index], to: min(store.favoriteStops.count, index + 2)) } label: { Image(systemName: "arrow.down") }.disabled(index == store.favoriteStops.count - 1)
                        }
                        .font(.system(size: 16, weight: .black)).foregroundStyle(Theme.ink)
                        .padding(14).chunky(radius: 18, lift: 2)
                    }
                } else {
                    ForEach(store.favoriteStops) { stop in
                        StopCard(stop: stop, distance: location.distance(to: stop)) { openStop = stop }
                    }
                }
                FinePrint()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 24)
        }
        .refreshable { await store.refreshNow() }
    }
}

private struct EmptySaved: View {
    @AppStorage("tab") private var tab: AppTab = .saved

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.fill").font(.system(size: 44)).foregroundStyle(Color.busYellow).rotationEffect(.degrees(-8))
            Text("Star the stops you use").font(Theme.display(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text("Tap the star on any stop and it lands here with live times, one tap from opening the app.")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { tab = .nearby } label: {
                Text("Find stops nearby").font(.system(size: 16, weight: .black)).foregroundStyle(Color.busInk)
                    .padding(.horizontal, 22).frame(height: 50).chunky(fill: .busYellow, radius: 16)
            }
            .buttonStyle(PressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
    }
}

struct NearbyView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Binding var openStop: TransitStop?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(location.location == nil ? "Near downtown" : "Near you").font(Theme.display(34)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(store.activeRoutes.isEmpty ? "ALL ROUTES" : "YOUR ROUTES").font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.muted)
                }
                StatusBanners()
                if !location.isAuthorized {
                    Button {
                        if location.isDenied { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        else { location.requestPermission() }
                    } label: {
                        Label(location.isDenied ? "Location is off for B-Town Bus. Tap to open Settings." : "Turn on location to see stops around you", systemImage: "location.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).chunky(fill: Theme.me, radius: 16)
                    }
                    .buttonStyle(PressStyle())
                }
                if !store.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
                ForEach(store.nearbyStops(from: location.location), id: \.stop.id) { item in
                    StopCard(stop: item.stop, distance: location.location == nil ? nil : item.distance) { openStop = item.stop }
                }
                FinePrint()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 24)
        }
        .refreshable { await store.refreshNow() }
    }
}

struct StopCard: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    let stop: TransitStop
    let distance: CLLocationDistance?
    let open: () -> Void

    var body: some View {
        let arrivals = Array(store.arrivals(at: stop.id).prefix(4))
        let here = location.isAtStop(stop)
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name).font(Theme.display(18, .heavy)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: stop.agency.colorHex)).frame(width: 9, height: 9)
                            Text(stop.agency.name)
                            if here {
                                Text("YOU'RE HERE").font(.system(size: 10, weight: .black)).foregroundStyle(Theme.goInk)
                                    .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.go, in: Capsule())
                            } else if let distance {
                                Text("· \(formatDistance(distance)) · \(max(1, TripMath.walkSeconds(distance: distance) / 60)) min walk")
                            }
                        }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.trailing, 48)
                    FlowRow(spacing: 7) {
                        if arrivals.isEmpty {
                            Text(store.arrivalsLoadedFor.contains(stop.id) ? "No buses due soon" : "Checking times…")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        ForEach(Array(arrivals.enumerated()), id: \.element.id) { index, arrival in
                            TimeChip(route: store.route(arrival.routeKey), arrival: arrival, prominent: index == 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .chunky(stroke: here ? Theme.go : Theme.edge)
            }
            .buttonStyle(PressStyle())
            StarButton(stop: stop).padding(10)
        }
    }
}

struct StarButton: View {
    @Environment(AppStore.self) private var store
    let stop: TransitStop

    var body: some View {
        let on = store.isFavorite(stop)
        Button {
            withAnimation(.spring(duration: 0.25)) { store.toggleFavorite(stop) }
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(on ? Color.busInk : Theme.muted)
                .frame(width: 42, height: 42)
                .background(on ? Color.busYellow : Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
        }
        .sensoryFeedback(.impact, trigger: on)
        .accessibilityLabel(on ? "Remove from saved stops" : "Save stop")
    }
}

struct StatusBanners: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.loaded, !store.failedAgencies.isEmpty {
            let names = store.failedAgencies.map(\.shortName).sorted().joined(separator: " & ")
            Text(store.failedAgencies.count == Agency.allCases.count ? "Live feeds are down right now. Retrying automatically." : "\(names) feed is down. Other times are live.")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).chunky(fill: Theme.warn, radius: 16, lift: 0)
        }
    }
}

struct FinePrint: View {
    var body: some View {
        Text("Independent tracker · Not affiliated with Bloomington Transit or Indiana University.")
            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 14)
    }
}

/// Wraps chips onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
