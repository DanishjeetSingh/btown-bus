import SwiftUI
import WidgetKit

/// Home Screen widget: the next buses at each saved stop.
struct SavedStopsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SavedStops", provider: SavedStopsProvider()) { entry in
            SavedStopsView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.bg }
        }
        .configurationDisplayName("Saved Stops")
        .description("The next buses at your saved stops.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Data

struct SavedStopsEntry: TimelineEntry {
    struct Bus: Hashable {
        var route: String
        var colorHex: String
        var arrival: Date
    }
    struct Stop: Hashable {
        var name: String
        var buses: [Bus]
    }

    let date: Date
    let stops: [Stop]
    /// Nil when there are no saved stops yet; empty buses means nothing is due.
    let failed: Bool

    static let placeholder = SavedStopsEntry(date: .now, stops: [
        Stop(name: "7th & Woodlawn (IMU)", buses: [
            Bus(route: "E", colorHex: "#0000a0", arrival: .now.addingTimeInterval(240)),
            Bus(route: "F", colorHex: "#8a2983", arrival: .now.addingTimeInterval(660)),
        ]),
        Stop(name: "Sample Gates", buses: [Bus(route: "6", colorHex: "#9e6b3f", arrival: .now.addingTimeInterval(420))]),
    ], failed: false)
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
            // One entry per minute so the minutes count down between network refreshes.
            let entries = (0..<15).map { minute in
                SavedStopsEntry(date: now.addingTimeInterval(Double(minute) * 60), stops: entry.stops, failed: entry.failed)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(10 * 60))))
        }
    }

    private func fetch(now: Date) async -> SavedStopsEntry {
        let saved = SavedStopsShare.load()
        guard !saved.isEmpty else { return SavedStopsEntry(date: now, stops: [], failed: false) }
        let keys = saved.compactMap { stop in Agency(rawValue: stop.agency).map { TransitKey(agency: $0, id: stop.id) } }
        guard let arrivals = try? await TransitClient.shared.arrivals(for: keys) else {
            return SavedStopsEntry(date: now, stops: saved.map { .init(name: $0.name, buses: []) }, failed: true)
        }
        let stops = saved.map { stop -> SavedStopsEntry.Stop in
            let colors = Dictionary(stop.routes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let buses = arrivals
                .filter { $0.agency.rawValue == stop.agency && $0.stopId == stop.id }
                .map { arrival in
                    SavedStopsEntry.Bus(route: colors[arrival.routeId]?.shortName ?? arrival.routeId,
                                        colorHex: colors[arrival.routeId]?.colorHex ?? arrival.agency.colorHex,
                                        arrival: arrival.predictedArrival)
                }
            return .init(name: stop.name, buses: buses)
        }
        return SavedStopsEntry(date: now, stops: stops, failed: false)
    }
}

// MARK: - Views

private enum WidgetTheme {
    static let bg = adaptive(light: "#fff4de", dark: "#14120e")
    static let ink = adaptive(light: "#15130f", dark: "#fff4de")
    static let muted = adaptive(light: "#6b6356", dark: "#b3a893")
    static let surface = adaptive(light: "#fffdf7", dark: "#211e18")
    static let edge = adaptive(light: "#15130f", dark: "#000000")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

struct SavedStopsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SavedStopsEntry

    private var stopLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        default: return 5
        }
    }
    private let busLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            header
            if entry.stops.isEmpty {
                Spacer(minLength: 0)
                Text("Star stops in B-Town Bus to see them here.")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(WidgetTheme.muted)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.stops.prefix(stopLimit).enumerated()), id: \.offset) { _, stop in
                    stopRow(stop)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("B").font(.system(size: 11, weight: .black).width(.expanded)).foregroundStyle(Color.busYellow)
                .frame(width: 18, height: 18).background(Color.busInk, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("SAVED STOPS").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(WidgetTheme.muted)
            Spacer(minLength: 0)
            if entry.failed {
                Image(systemName: "wifi.slash").font(.system(size: 10, weight: .bold)).foregroundStyle(WidgetTheme.muted)
            }
        }
    }

    @ViewBuilder private func stopRow(_ stop: SavedStopsEntry.Stop) -> some View {
        let upcoming = stop.buses.filter { $0.arrival > entry.date.addingTimeInterval(-30) }.prefix(busLimit)
        VStack(alignment: .leading, spacing: 5) {
            Text(stop.name)
                .font(.system(size: family == .systemSmall ? 14 : 15, weight: .heavy).width(.expanded))
                .foregroundStyle(WidgetTheme.ink).lineLimit(family == .systemSmall ? 2 : 1).minimumScaleFactor(0.8)
            if upcoming.isEmpty {
                Text(entry.failed ? "Couldn't load times" : "No buses due soon")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(WidgetTheme.muted)
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { index, bus in chip(bus, big: index == 0) }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { index, bus in chip(bus, big: index == 0) }
                }
            }
        }
    }

    /// Same look as the app's time chips: route color block, then the wait.
    private func chip(_ bus: SavedStopsEntry.Bus, big: Bool) -> some View {
        let minutes = max(0, Int((bus.arrival.timeIntervalSince(entry.date) / 60).rounded(.up)))
        return HStack(spacing: 0) {
            Text(bus.route)
                .font(.system(size: big ? 13 : 11.5, weight: .black).width(.expanded))
                .foregroundStyle(Color.readableInk(on: bus.colorHex))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: big ? 30 : 26, maxHeight: .infinity)
                .background(Color(hex: bus.colorHex))
            Rectangle().fill(WidgetTheme.edge).frame(width: 1.5)
            Group {
                if minutes == 0 { Text("Now") }
                else if minutes >= 60 { Text(bus.arrival, style: .time) }
                else { Text("\(minutes)") + Text("m").font(.system(size: 10, weight: .bold)).foregroundColor(WidgetTheme.muted) }
            }
            .font(.system(size: big ? 15 : 13, weight: .black)).monospacedDigit()
            .foregroundStyle(WidgetTheme.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 6)
        }
        .frame(height: big ? 28 : 24)
        .background(WidgetTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(WidgetTheme.edge, lineWidth: 1.5))
    }
}
