import SwiftUI
import WidgetKit
import CoreLocation
import AppIntents

/// Home Screen widget: one row per bus line at each saved stop, closest stop first, with the bus after it.
/// Tap a row to track that bus with a Live Activity, without opening the app.
struct SavedStopsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SavedStopsShare.widgetKind, provider: SavedStopsProvider()) { entry in
            SavedStopsView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.bg }
        }
        .configurationDisplayName("Saved Stops")
        .description("Your next bus at each saved stop, closest first. Tap one to track it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Data

struct SavedStopsEntry: TimelineEntry {
    struct Bus: Hashable {
        var agency: String
        var stopId: String
        var routeId: String
        var route: String
        var colorHex: String
        var arrival: Date
    }

    /// One bus line at a saved stop.
    struct Row: Hashable {
        var name: String
        /// Only the first row of each stop shows its name; the rest sit under it.
        var showsName: Bool
        /// The saved bus, shown even when none is due. Nil when nothing at all is due at the stop.
        var route: SavedStopsShare.Route?
        /// This line's upcoming buses, soonest first. The view skips ones that have left.
        var buses: [Bus]
    }

    let date: Date
    let rows: [Row]
    let fetchedAt: Date
    let failed: Bool
    var tracking: String? = nil

    static let placeholder = SavedStopsEntry(date: .now, rows: [
        Row(name: "Sample Gates", showsName: true, buses: [Bus(agency: "iu", stopId: "", routeId: "", route: "E", colorHex: "#0000a0", arrival: .now.addingTimeInterval(240)),
                                                           Bus(agency: "iu", stopId: "", routeId: "", route: "E", colorHex: "#0000a0", arrival: .now.addingTimeInterval(840))]),
        Row(name: "Sample Gates", showsName: false, buses: [Bus(agency: "bt", stopId: "", routeId: "", route: "6", colorHex: "#9e6b3f", arrival: .now.addingTimeInterval(540))]),
        Row(name: "Wells Library", showsName: true, buses: [Bus(agency: "iu", stopId: "", routeId: "", route: "X", colorHex: "#8a2983", arrival: .now.addingTimeInterval(780)),
                                                            Bus(agency: "iu", stopId: "", routeId: "", route: "X", colorHex: "#8a2983", arrival: .now.addingTimeInterval(1500))]),
    ], fetchedAt: .now, failed: false)
}

struct SavedStopsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SavedStopsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SavedStopsEntry) -> Void) {
        if context.isPreview && SavedStopsShare.load().isEmpty { completion(.placeholder); return }
        Task { completion(await fetch(now: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedStopsEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = await fetch(now: now)
            // One entry per minute so the minutes count down between refreshes. iOS rations refreshes
            // (a few an hour at best), so the entries run past the requested refresh in case it comes late.
            let entries = (0..<20).map { minute in
                SavedStopsEntry(date: now.addingTimeInterval(Double(minute) * 60), rows: entry.rows,
                                fetchedAt: entry.fetchedAt, failed: entry.failed, tracking: entry.tracking)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60))))
        }
    }

    /// Your position: the widget's own fix if iOS gives it one, or the app's last one, whichever is newer.
    private func currentLocation() -> CLLocation? {
        let own = CLLocationManager().location
        let shared = SavedStopsShare.lastLocation
        guard let own else { return shared }
        guard let shared else { return own }
        return own.timestamp > shared.timestamp ? own : shared
    }

    private func fetch(now: Date) async -> SavedStopsEntry {
        var saved = SavedStopsShare.load()
        let tracking = SavedStopsShare.tracking
        guard !saved.isEmpty else { return SavedStopsEntry(date: now, rows: [], fetchedAt: now, failed: false, tracking: tracking) }
        if let here = currentLocation() {
            saved.sort { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude)) }
        }
        let keys = saved.flatMap { stop in stop.stops.compactMap { member in Agency(rawValue: member.agency).map { TransitKey(agency: $0, id: member.id) } } }
        let arrivals = try? await TransitClient.shared.arrivals(for: Array(Set(keys)))

        let rows = saved.flatMap { stop -> [SavedStopsEntry.Row] in
            let members = Set(stop.stops.map { "\($0.agency):\($0.id)" })
            let routes = Dictionary(stop.routes.map { ("\($0.agency):\($0.id)", $0) }, uniquingKeysWith: { a, _ in a })
            let buses = (arrivals ?? [])
                .filter { members.contains("\($0.agency.rawValue):\($0.stopId)") }
                .map { arrival in
                    let route = routes["\(arrival.agency.rawValue):\(arrival.routeId)"]
                    return SavedStopsEntry.Bus(agency: arrival.agency.rawValue, stopId: arrival.stopId, routeId: arrival.routeId,
                                               route: route?.shortName ?? arrival.routeId, colorHex: route?.colorHex ?? arrival.agency.colorHex,
                                               arrival: arrival.predictedArrival)
                }
            // One row per line: every saved bus (even if none is due), or every line due at a stop saved with all buses.
            let keys = stop.only.isEmpty ? buses.map { "\($0.agency):\($0.routeId)" }.uniqued() : stop.only
            let lines = keys.map { key in
                SavedStopsEntry.Row(name: stop.name, showsName: false, route: routes[key], buses: buses.filter { "\($0.agency):\($0.routeId)" == key })
            }
            .sorted { ($0.buses.first?.arrival ?? .distantFuture) < ($1.buses.first?.arrival ?? .distantFuture) }
            var rows = lines.isEmpty ? [SavedStopsEntry.Row(name: stop.name, showsName: true, route: nil, buses: [])] : lines
            rows[0].showsName = true
            return rows
        }
        return SavedStopsEntry(date: now, rows: rows, fetchedAt: now, failed: arrivals == nil, tracking: tracking)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Views

private enum WidgetTheme {
    static let bg = adaptive(light: "#fff4de", dark: "#14120e")
    static let ink = adaptive(light: "#15130f", dark: "#fff4de")
    static let muted = adaptive(light: "#6b6356", dark: "#b3a893")
    static let surface = adaptive(light: "#fffdf7", dark: "#211e18")
    static let chip = adaptive(light: "#f3e1bd", dark: "#2c2820")
    static let edge = adaptive(light: "#15130f", dark: "#000000")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

struct SavedStopsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SavedStopsEntry

    private var small: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.rows.isEmpty {
                Spacer(minLength: 0)
                Text("Save stops or buses in B-Town Bus to see them here.")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(WidgetTheme.muted)
                Spacer(minLength: 0)
            } else {
                // Names are never shrunk or cut off; a long one wraps to two lines,
                // and only as many rows as fit are shown.
                RowsThatFit(spacing: small ? 8 : 7) {
                    ForEach(Array(entry.rows.prefix(10).enumerated()), id: \.offset) { _, row in
                        rowView(row)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                if family == .systemLarge {
                    Text("Closest stop first · Tap a bus to track it")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetTheme.muted)
                }
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if !small {
                Text("B").font(.system(size: 11, weight: .black).width(.expanded)).foregroundStyle(Color.busYellow)
                    .frame(width: 20, height: 20).background(Color.busInk, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if entry.failed {
                Image(systemName: "wifi.slash").font(.system(size: 11, weight: .bold)).foregroundStyle(WidgetTheme.muted)
            }
            Text(updatedLabel)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(WidgetTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(intent: RefreshSavedStopsIntent()) {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .black)).foregroundStyle(Color.busInk)
                    .frame(width: 34, height: 34)
                    .background(Color.busYellow, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh times")
        }
    }

    /// "Updated just now", "Updated 4 min ago".
    private var updatedLabel: String {
        let minutes = Int(entry.date.timeIntervalSince(entry.fetchedAt) / 60)
        if minutes < 1 { return small ? "Just now" : "Updated just now" }
        return small ? "\(minutes) min ago" : "Updated \(minutes) min ago"
    }

    /// {stop}   [bus  time]  then 12
    @ViewBuilder private func rowView(_ row: SavedStopsEntry.Row) -> some View {
        let upcoming = row.buses.filter { $0.arrival > entry.date.addingTimeInterval(-30) }
        let next = upcoming.first
        let tracked = next.map { "\($0.agency):\($0.stopId):\($0.routeId)" == entry.tracking } ?? false
        let name = Text(row.showsName ? row.name : "")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(tracked ? Color.busInk : WidgetTheme.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        let times = HStack(spacing: 6) {
            chip(next: next, route: row.route)
            if next != nil { then(upcoming.dropFirst().first, tracked: tracked) }
        }
        let content = Group {
            if small {
                VStack(alignment: .leading, spacing: 4) {
                    if row.showsName { name }
                    times
                }
            } else {
                HStack(spacing: 10) {
                    name
                    times
                }
            }
        }
        .padding(.horizontal, tracked ? 6 : 0).padding(.vertical, tracked ? 3 : 0)
        .background(tracked ? Color.busYellow : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        if let next {
            Button(intent: TrackBusIntent(agency: next.agency, stopId: next.stopId, routeId: next.routeId)) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Route color block, then the wait, on a soft pill. No outlines: at widget size they read as stray lines.
    private func chip(next: SavedStopsEntry.Bus?, route: SavedStopsShare.Route?) -> some View {
        let label = next?.route ?? route?.shortName
        let hex = next?.colorHex ?? route?.colorHex ?? "#6b6356"
        return HStack(spacing: 0) {
            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .black).width(.expanded))
                    .foregroundStyle(Color.readableInk(on: hex))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 7)
                    .frame(minWidth: 30, maxHeight: .infinity)
                    .background(Color(hex: hex))
            }
            wait(next).lineLimit(1).fixedSize().padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(WidgetTheme.chip)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The bus after the coming one, as a quiet "then 12".
    @ViewBuilder private func then(_ bus: SavedStopsEntry.Bus?, tracked: Bool) -> some View {
        let color = tracked ? Color.busInk.opacity(0.7) : WidgetTheme.muted
        Group {
            if let bus {
                let minutes = max(0, Int((bus.arrival.timeIntervalSince(entry.date) / 60).rounded(.up)))
                if minutes >= 60 { Text("then ") + Text(bus.arrival, style: .time) }
                else { Text("then \(minutes)") }
            } else {
                Text("then –")
            }
        }
        .font(.system(size: 12, weight: .bold)).monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1).fixedSize()
        .frame(minWidth: small ? 0 : 52, alignment: .leading)
    }

    @ViewBuilder private func wait(_ bus: SavedStopsEntry.Bus?) -> some View {
        if let bus {
            let minutes = max(0, Int((bus.arrival.timeIntervalSince(entry.date) / 60).rounded(.up)))
            Group {
                if minutes == 0 { Text("Now") }
                else if minutes >= 60 { Text(bus.arrival, style: .time) }
                else { Text("\(minutes)") + Text(small ? "m" : " min").font(.system(size: 11, weight: .bold)).foregroundColor(WidgetTheme.muted) }
            }
            .font(.system(size: 16, weight: .black)).monospacedDigit()
            .foregroundStyle(WidgetTheme.ink)
        } else {
            Text(entry.failed ? "No data" : "None soon")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(WidgetTheme.muted)
        }
    }
}

/// Stacks rows top to bottom and leaves out any that wouldn't fit whole, so a row is never cut in half
/// and long stop names can wrap instead of shrinking.
private struct RowsThatFit: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let natural = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: min(natural, proposal.height ?? natural))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var full = false
        for view in subviews {
            let height = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            if !full, y + height <= bounds.maxY + 0.5 {
                view.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            } else {
                // Out of room: park the rest out of sight.
                full = true
                view.place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 2000), proposal: ProposedViewSize(width: bounds.width, height: height))
            }
        }
    }
}
