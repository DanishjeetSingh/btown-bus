import SwiftUI
import CoreLocation

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Binding var openStop: TransitStop?
    @AppStorage("saved-sort-closest") private var closestFirst = false

    var body: some View {
        let savedStops = ordered(store.savedStops)
        // A List, so a stop can be held and dragged into place like any iOS list.
        List {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Saved stops").font(Theme.display(34)).foregroundStyle(Theme.ink)
                    Spacer()
                    if savedStops.count > 1 { OrderToggle(closestFirst: $closestFirst) }
                }
                // Up top, where it's seen even with a long list.
                if savedStops.count > 1 {
                    Label(closestFirst ? "Closest to you first" : "Hold a stop and drag to reorder",
                          systemImage: closestFirst ? "location.fill" : "hand.draw.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            .plainRow()
            StatusBanners().plainRow()
            if savedStops.isEmpty {
                EmptySaved().plainRow()
            } else {
                ForEach(savedStops, id: \.stop.id) { item in
                    StopCard(stop: item.stop, distance: location.distance(to: item.stop), only: item.saved.routes) { openStop = item.stop }
                        .plainRow()
                }
                .onMove(perform: closestFirst ? nil : { from, to in
                    var keys = savedStops.map(\.saved.stop)
                    keys.move(fromOffsets: from, toOffset: to)
                    store.reorderSaved(keys)
                })
            }
            FinePrint().plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.top, 7, for: .scrollContent)
        .contentMargins(.bottom, 17, for: .scrollContent)
        .refreshable { await store.refreshNow() }
    }

    private func ordered(_ items: [(saved: SavedStop, stop: TransitStop)]) -> [(saved: SavedStop, stop: TransitStop)] {
        guard closestFirst, let here = location.location else { return items }
        return items.sorted { here.distance(from: $0.stop.location) < here.distance(from: $1.stop.location) }
    }

}

/// One tap flips between your own order and closest first.
private struct OrderToggle: View {
    @Binding var closestFirst: Bool

    var body: some View {
        Button { withAnimation(.spring(duration: 0.25)) { closestFirst.toggle() } } label: {
            // Both labels are laid out on top of each other and cross-fade, so the pill never changes width.
            ZStack {
                label("My order", symbol: "arrow.up.arrow.down").opacity(closestFirst ? 0 : 1)
                label("Closest", symbol: "location.fill").opacity(closestFirst ? 1 : 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11).frame(height: 32)
            .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.selection, trigger: closestFirst)
        .accessibilityLabel(closestFirst ? "Sorted closest first" : "Sorted in your order")
        .accessibilityHint("Switches the order")
    }

    private func label(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .black))
            Text(title).font(.system(size: 13, weight: .heavy))
        }
    }
}

private extension View {
    /// A List row that looks like the rest of the app's scrolling pages: no separators, no row background.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct EmptySaved: View {
    @AppStorage("tab") private var tab: AppTab = .saved

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.fill").font(.system(size: 44)).foregroundStyle(Color.busYellow).rotationEffect(.degrees(-8))
            Text("Star the stops you use").font(Theme.display(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text("Tap the star on any stop, or save just the buses you ride there. They land here with live times.")
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
    /// Saved buses to show; empty shows every bus at the stop.
    var only: [TransitKey] = []
    let open: () -> Void

    var body: some View {
        let all = store.arrivals(atPlace: stop)
        let arrivals = Array((only.isEmpty ? all : all.filter { only.contains($0.routeKey) }).prefix(4))
        let agencies = store.agencies(at: stop)
        let here = location.isAtStop(stop)
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.placeName(stop)).font(Theme.display(18, .heavy)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            AgencyMarks(agencies: agencies)
                            Text(agencies.count > 1 ? "IU + BT" : stop.agency.name)
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
                            Text(!store.loadedArrivals(atPlace: stop) ? "Checking times…" : only.isEmpty ? "No buses due soon" : "Your buses aren't due soon")
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

/// A little colored square per agency serving the stop.
struct AgencyMarks: View {
    let agencies: [Agency]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(agencies, id: \.self) { agency in
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: agency.colorHex)).frame(width: 9, height: 9)
            }
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

/// The sign-off at the bottom of a list, between two little route lines.
struct FinePrint: View {
    var body: some View {
        HStack(spacing: 10) {
            RouteLine()
            Text("INDEPENDENT TRACKER")
                .font(Theme.display(11.5)).tracking(1.6)
                .foregroundStyle(Theme.ink)
                .fixedSize()
            RouteLine().scaleEffect(x: -1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18).padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Independent tracker")
    }
}

/// A stretch of route drawn like the map: an open stop, the line, then a yellow stop.
private struct RouteLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(Theme.ink, lineWidth: 2).frame(width: 9, height: 9)
            Capsule().fill(Theme.ink).frame(width: 30, height: 3)
            Circle().fill(Color.busYellow).frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2.5))
        }
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
