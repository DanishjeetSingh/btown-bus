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
        return TripMath.stopsAway(stopIds: route.stopIds, nextStopId: vehicle.nextStopId, target: arrival.stopId)
    }
    var favoriteStops: [TransitStop] { favorites.compactMap { stopByKey[$0] } }
    func isFavorite(_ stop: TransitStop) -> Bool { favorites.contains(stop.id) }

    func nearbyStops(from origin: CLLocation?, limit: Int = 8) -> [(stop: TransitStop, distance: CLLocationDistance)] {
        let origin = origin ?? Self.downtown
        let pool = activeRoutes.isEmpty ? stops : stops.filter { stop in stop.routeIds.contains { activeRoutes.contains(TransitKey(agency: stop.agency, id: $0)) } }
        return pool.map { ($0, origin.distance(from: $0.location)) }.sorted { $0.1 < $1.1 }.prefix(limit).map { (stop: $0.0, distance: $0.1) }
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
        if !newRoutes.isEmpty || routes.isEmpty {
            // Keep a failed agency's last data instead of blanking it.
            let keptRoutes = routes.filter { failed.contains($0.agency) }
            let keptStops = stops.filter { failed.contains($0.agency) }
            routes = (newRoutes + keptRoutes).sorted { a, b in
                a.agency != b.agency ? a.agency == .iu : a.shortName.localizedStandardCompare(b.shortName) == .orderedAscending
            }
            stops = newStops + keptStops
            vehicles = newVehicles
            routeByKey = Dictionary(routes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            stopByKey = Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        failedAgencies = failed
        loaded = true

        guard includeArrivals else { return }
        let wanted = wantedStops()
        guard !wanted.isEmpty else { return }
        if let next = try? await client.arrivals(for: Array(wanted)) {
            arrivals = next
            arrivalsLoadedFor = wanted
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
