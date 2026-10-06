import Foundation
import CoreLocation
import Observation

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

    private(set) var favorites: [TransitKey] {
        didSet { UserDefaults.standard.set(favorites.map(\.description), forKey: "favorites") }
    }
    private(set) var activeRoutes: Set<TransitKey> {
        didSet { UserDefaults.standard.set(activeRoutes.map(\.description), forKey: "routes") }
    }
    var hasChosenRoutes: Bool { UserDefaults.standard.object(forKey: "routes") != nil }
    /// A stop the user has open, so its times are polled too.
    var focusedStop: TransitKey?

    private(set) var routeByKey: [TransitKey: TransitRoute] = [:]
    private(set) var stopByKey: [TransitKey: TransitStop] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var nearbyCache: (origin: CLLocation, routes: Set<TransitKey>, limit: Int, result: [(stop: TransitStop, distance: CLLocationDistance)])?

    init() {
        favorites = (UserDefaults.standard.stringArray(forKey: "favorites") ?? []).compactMap(TransitKey.init)
        activeRoutes = Set((UserDefaults.standard.stringArray(forKey: "routes") ?? []).compactMap(TransitKey.init))
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
    var favoriteStops: [TransitStop] { favorites.compactMap { stopByKey[$0] } }
    func isFavorite(_ stop: TransitStop) -> Bool { favorites.contains(stop.id) }

    func nearbyStops(from origin: CLLocation?, limit: Int = 8) -> [(stop: TransitStop, distance: CLLocationDistance)] {
        let origin = origin ?? Self.downtown
        // Re-sorting every stop on each GPS fix is wasted work; reuse the list until you've moved ~15 m.
        if let cache = nearbyCache, cache.routes == activeRoutes, cache.limit == limit, cache.origin.distance(from: origin) < 15 {
            return cache.result.map { (stop: $0.stop, distance: origin.distance(from: $0.stop.location)) }
        }
        let pool = activeRoutes.isEmpty ? stops : stops.filter { stop in stop.routeIds.contains { activeRoutes.contains(TransitKey(agency: stop.agency, id: $0)) } }
        let result = pool.map { ($0, origin.distance(from: $0.location)) }.sorted { $0.1 < $1.1 }.prefix(limit).map { (stop: $0.0, distance: $0.1) }
        nearbyCache = (origin, activeRoutes, limit, result)
        return result
    }

    // MARK: Preferences

    func toggleFavorite(_ stop: TransitStop) {
        if let index = favorites.firstIndex(of: stop.id) { favorites.remove(at: index) } else { favorites.append(stop.id) }
    }
    func moveFavorites(from source: IndexSet, to destination: Int) { favorites.move(fromOffsets: source, toOffset: destination) }
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
            if !Self.sameArrivals(next, arrivals) { arrivals = next }
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
        var wanted = Set<TransitKey>()
        if let focusedStop { wanted.insert(focusedStop) }
        if let trip = TripTracker.shared.watch { wanted.insert(trip.stopKey) }
        favorites.prefix(12).forEach { wanted.insert($0) }
        nearbyStops(from: LocationService.shared.location).forEach { wanted.insert($0.stop.id) }
        return wanted
    }
}
