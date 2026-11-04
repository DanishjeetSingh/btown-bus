import Foundation
import CoreLocation
import Observation
import WidgetKit

/// A starred stop, optionally narrowed to the buses you actually ride there.
struct SavedStop: Codable, Hashable, Identifiable {
    var stop: TransitKey
    /// Only these routes (from either agency at a merged stop). Empty means every bus.
    var routes: [TransitKey] = []
    var id: TransitKey { stop }
}

@MainActor @Observable
final class AppStore {
    static let shared = AppStore()
    static let downtown = CLLocation(latitude: 39.1699, longitude: -86.5258)

    private(set) var routes: [TransitRoute] = []
    private(set) var stops: [TransitStop] = []
    private(set) var vehicles: [TransitVehicle] = []
    private(set) var arrivals: [TransitArrival] = []
    private(set) var failedAgencies: Set<Agency> = []
    private(set) var loaded = false
    private(set) var arrivalsLoadedFor: Set<TransitKey> = []

    private(set) var saved: [SavedStop] {
        didSet {
            if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "saved-stops") }
            shareSavedStops()
        }
    }
    private(set) var activeRoutes: Set<TransitKey> {
        didSet { UserDefaults.standard.set(activeRoutes.map(\.description), forKey: "routes") }
    }
    var hasChosenRoutes: Bool { UserDefaults.standard.object(forKey: "routes") != nil }
    /// A stop the user has open, so its times are polled too.
    var focusedStop: TransitKey?

    private(set) var routeByKey: [TransitKey: TransitRoute] = [:]
    private(set) var stopByKey: [TransitKey: TransitStop] = [:]
    /// IU and Bloomington Transit stops on the same pole, paired both ways. They show as one stop.
    private(set) var partnerByKey: [TransitKey: TransitStop] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastWidgetNudge = Date.distantPast
    @ObservationIgnored private var nearbyCache: (origin: CLLocation, routes: Set<TransitKey>, limit: Int, result: [(stop: TransitStop, distance: CLLocationDistance)])?

    init() {
        if let data = UserDefaults.standard.data(forKey: "saved-stops"), let decoded = try? JSONDecoder().decode([SavedStop].self, from: data) {
            saved = decoded
        } else {
            // Before buses could be saved, favorites were a plain list of stop keys.
            saved = (UserDefaults.standard.stringArray(forKey: "favorites") ?? []).compactMap(TransitKey.init).map { SavedStop(stop: $0) }
        }
        activeRoutes = Set((UserDefaults.standard.stringArray(forKey: "routes") ?? []).compactMap(TransitKey.init))
    }

    /// Hand the saved stops (with names, route colors and chosen buses) to the Saved Stops widget.
    private func shareSavedStops() {
        guard !stopByKey.isEmpty else { return }
        let shared = savedStops.map { item in
            SavedStopsShare.Stop(
                name: placeName(item.stop),
                latitude: item.stop.coordinate.latitude,
                longitude: item.stop.coordinate.longitude,
                stops: members(of: item.stop).map { SavedStopsShare.Member(agency: $0.agency.rawValue, id: $0.stopId) },
                routes: routes(at: item.stop).map { SavedStopsShare.Route(agency: $0.agency.rawValue, id: $0.routeId, shortName: $0.shortName, colorHex: $0.colorHex) },
                only: item.saved.routes.map(\.description))
        }
        if SavedStopsShare.save(shared) { WidgetCenter.shared.reloadTimelines(ofKind: SavedStopsShare.widgetKind) }
    }

    /// Fresh times in the app are free to show in the widget too, so nudge it while the app is open.
    private func nudgeWidget() {
        guard !saved.isEmpty, Date().timeIntervalSince(lastWidgetNudge) > 60 else { return }
        lastWidgetNudge = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: SavedStopsShare.widgetKind)
    }

    // MARK: Lookups

    func route(_ key: TransitKey) -> TransitRoute? { routeByKey[key] }
    func stop(_ key: TransitKey) -> TransitStop? { stopByKey[key] }
    func arrivals(at stop: TransitKey) -> [TransitArrival] { arrivals.filter { $0.stopKey == stop } }
    func vehicle(_ agency: Agency, _ id: String?) -> TransitVehicle? {
        guard let id else { return nil }
        return vehicles.first { $0.agency == agency && $0.vehicleId == id }
    }
    func stopsAway(for arrival: TransitArrival) -> Int? {
        guard let vehicle = vehicle(arrival.agency, arrival.vehicleId), let route = route(arrival.routeKey) else { return nil }
        return TripMath.stopsAway(route: route, vehicle: vehicle, target: arrival.stopId)
    }

    // MARK: Merged stops

    func partner(of stop: TransitStop) -> TransitStop? { partnerByKey[stop.id] }
    /// The stop plus its partner from the other agency, if they share a pole.
    func members(of stop: TransitStop) -> [TransitStop] { [stop] + [partner(of: stop)].compactMap { $0 } }
    /// IU's names are the short campus ones ("Sample Gates"), so a merged stop goes by those.
    func placeName(_ stop: TransitStop) -> String {
        if stop.agency != .iu, let partner = partner(of: stop), partner.agency == .iu { return partner.name }
        return stop.name
    }
    func routes(at stop: TransitStop) -> [TransitRoute] {
        members(of: stop).flatMap { member in member.routeIds.compactMap { routeByKey[TransitKey(agency: member.agency, id: $0)] } }
    }
    /// Every bus due at the stop, both agencies.
    func arrivals(atPlace stop: TransitStop) -> [TransitArrival] {
        let keys = Set(members(of: stop).map(\.id))
        return arrivals.filter { keys.contains($0.stopKey) }
    }
    func loadedArrivals(atPlace stop: TransitStop) -> Bool {
        members(of: stop).allSatisfy { arrivalsLoadedFor.contains($0.id) }
    }

    /// Pairs each stop with the other agency's nearest stop when both are within 15 m of each other.
    /// Stops for the same street corner but the other direction sit 17 m or more apart, so they stay separate.
    private static func pairStops(_ stops: [TransitStop]) -> [TransitKey: TransitStop] {
        let iu = stops.filter { $0.agency == .iu }, bt = stops.filter { $0.agency == .bt }
        func nearest(to stop: TransitStop, in pool: [TransitStop]) -> TransitStop? {
            pool.map { ($0, $0.location.distance(from: stop.location)) }.filter { $0.1 <= 15 }.min { $0.1 < $1.1 }?.0
        }
        var pairs: [TransitKey: TransitStop] = [:]
        for stop in iu {
            guard let match = nearest(to: stop, in: bt), nearest(to: match, in: iu)?.id == stop.id else { continue }
            pairs[stop.id] = match
            pairs[match.id] = stop
        }
        return pairs
    }

    // MARK: Saved

    /// The saved entry covering this stop, saved from either agency's side.
    func savedEntry(for stop: TransitStop) -> SavedStop? {
        let keys = Set(members(of: stop).map(\.id))
        return saved.first { keys.contains($0.stop) }
    }
    var savedStops: [(saved: SavedStop, stop: TransitStop)] { saved.compactMap { item in stopByKey[item.stop].map { (item, $0) } } }
    func isFavorite(_ stop: TransitStop) -> Bool { savedEntry(for: stop) != nil }
    /// The stop's buses, narrowed to the saved ones if you picked any.
    func savedArrivals(_ item: SavedStop, at stop: TransitStop) -> [TransitArrival] {
        let all = arrivals(atPlace: stop)
        guard !item.routes.isEmpty else { return all }
        let wanted = Set(item.routes)
        return all.filter { wanted.contains($0.routeKey) }
    }

    func nearbyStops(from origin: CLLocation?, limit: Int = 8) -> [(stop: TransitStop, distance: CLLocationDistance)] {
        let origin = origin ?? Self.downtown
        // Re-sorting every stop on each GPS fix is wasted work; reuse the list until you've moved ~15 m.
        if let cache = nearbyCache, cache.routes == activeRoutes, cache.limit == limit, cache.origin.distance(from: origin) < 15 {
            return cache.result.map { (stop: $0.stop, distance: origin.distance(from: $0.stop.location)) }
        }
        let pool = activeRoutes.isEmpty ? stops : stops.filter { stop in stop.routeIds.contains { activeRoutes.contains(TransitKey(agency: stop.agency, id: $0)) } }
        var seen = Set<TransitKey>()
        let result = pool.map { ($0, origin.distance(from: $0.location)) }.sorted { $0.1 < $1.1 }
            .filter { item in
                // A merged stop is listed once, under whichever half is closer.
                guard !seen.contains(item.0.id) else { return false }
                members(of: item.0).forEach { seen.insert($0.id) }
                return true
            }
            .prefix(limit).map { (stop: $0.0, distance: $0.1) }
        nearbyCache = (origin, activeRoutes, limit, result)
        return result
    }

    // MARK: Preferences

    func toggleFavorite(_ stop: TransitStop) {
        if let entry = savedEntry(for: stop) { saved.removeAll { $0.stop == entry.stop } } else { saved.append(SavedStop(stop: stop.id)) }
    }
    /// Save just this bus at the stop, or add/remove it from the stop's saved buses.
    /// Removing the last one goes back to every bus.
    func toggleSavedRoute(_ route: TransitKey, at stop: TransitStop) {
        guard let entry = savedEntry(for: stop), let index = saved.firstIndex(of: entry) else {
            saved.append(SavedStop(stop: stop.id, routes: [route]))
            return
        }
        if let position = saved[index].routes.firstIndex(of: route) { saved[index].routes.remove(at: position) }
        else { saved[index].routes.append(route) }
    }
    func moveFavorites(from source: IndexSet, to destination: Int) { saved.move(fromOffsets: source, toOffset: destination) }
    func toggleRoute(_ route: TransitRoute) {
        if activeRoutes.contains(route.id) { activeRoutes.remove(route.id) } else { activeRoutes.insert(route.id) }
    }
    /// Remember that the picker was seen, even if nothing was picked.
    func markRoutesChosen() {
        UserDefaults.standard.set(activeRoutes.map(\.description), forKey: "routes")
    }
    func setAgency(_ agency: Agency, on: Bool) {
        for route in routes where route.agency == agency {
            if on { activeRoutes.insert(route.id) } else { activeRoutes.remove(route.id) }
        }
    }

    // MARK: Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(includeArrivals: true)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshNow() async { await refresh(includeArrivals: true) }

    private func refresh(includeArrivals: Bool) async {
        let client = TransitClient.shared
        var failed = Set<Agency>()
        var newRoutes: [TransitRoute] = [], newStops: [TransitStop] = [], newVehicles: [TransitVehicle] = []
        await withTaskGroup(of: (Agency, [TransitRoute], [TransitStop], [TransitVehicle])?.self) { group in
            for agency in Agency.allCases {
                group.addTask {
                    do {
                        async let base = client.routesAndStops(for: agency)
                        async let live = client.vehicles(for: agency)
                        let (staticData, vehicles) = try await (base, live)
                        return (agency, staticData.routes, staticData.stops, vehicles)
                    } catch { return nil }
                }
            }
            for await result in group {
                guard let (_, r, s, v) = result else { continue }
                newRoutes += r; newStops += s; newVehicles += v
            }
        }
        for agency in Agency.allCases where !newRoutes.contains(where: { $0.agency == agency }) { failed.insert(agency) }
        // Observation fires on every assignment, even of an equal value, and that redraws every
        // screen (map included). So only assign what actually changed.
        if !newRoutes.isEmpty || routes.isEmpty {
            // Keep a failed agency's last data instead of blanking it.
            let mergedRoutes = (newRoutes + routes.filter { failed.contains($0.agency) }).sorted { a, b in
                a.agency != b.agency ? a.agency == .iu : a.shortName.localizedStandardCompare(b.shortName) == .orderedAscending
            }
            let mergedStops = newStops + stops.filter { failed.contains($0.agency) }
            if mergedRoutes.map(\.id) != routes.map(\.id) || mergedRoutes.map(\.patterns) != routes.map(\.patterns) {
                routes = mergedRoutes
                routeByKey = Dictionary(mergedRoutes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            }
            if mergedStops.map(\.id) != stops.map(\.id) {
                stops = mergedStops
                stopByKey = Dictionary(mergedStops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                partnerByKey = Self.pairStops(mergedStops)
                shareSavedStops()
                nearbyCache = nil
            }
            let mergedVehicles = newVehicles + vehicles.filter { failed.contains($0.agency) }
            if mergedVehicles != vehicles { vehicles = mergedVehicles }
        }
        if failed != failedAgencies { failedAgencies = failed }
        if !loaded { loaded = true }

        guard includeArrivals else { return }
        let wanted = wantedStops()
        guard !wanted.isEmpty else { return }
        if let next = try? await client.arrivals(for: Array(wanted)) {
            if !Self.sameArrivals(next, arrivals) {
                arrivals = next
                nudgeWidget()
            }
            if wanted != arrivalsLoadedFor { arrivalsLoadedFor = wanted }
        }
    }

    /// Feed times are whole minutes, so predictions within 30 s of the last ones aren't news.
    private static func sameArrivals(_ a: [TransitArrival], _ b: [TransitArrival]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { x, y in
            x.id.hasPrefix("\(y.agency.rawValue):\(y.stopId):\(y.routeId):") && x.vehicleId == y.vehicleId
                && x.destination == y.destination && abs(x.predictedArrival.timeIntervalSince(y.predictedArrival)) < 30
        }
    }

    private func wantedStops() -> Set<TransitKey> {
        var places: [TransitStop] = []
        if let focusedStop, let stop = stopByKey[focusedStop] { places.append(stop) }
        places += savedStops.prefix(12).map(\.stop)
        places += nearbyStops(from: LocationService.shared.location).map(\.stop)
        var wanted = Set(places.flatMap { members(of: $0).map(\.id) })
        if let trip = TripTracker.shared.watch { wanted.insert(trip.stopKey) }
        return wanted
    }
}
