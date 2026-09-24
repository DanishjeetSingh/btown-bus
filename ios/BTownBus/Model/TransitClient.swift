import Foundation
import CoreLocation

/// Talks to both agencies' public ETA Spot feeds and normalizes them.
actor TransitClient {
    static let shared = TransitClient()

    private var staticData: [Agency: (routes: [TransitRoute], stops: [TransitStop])] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: Static data

    func routesAndStops(for agency: Agency) async throws -> (routes: [TransitRoute], stops: [TransitStop]) {
        if let cached = staticData[agency] { return cached }
        async let routeData: RoutesResponse = request(agency, "get_routes")
        async let stopData: StopsResponse = request(agency, "get_stops")
        let (routesResponse, stopsResponse) = try await (routeData, stopData)

        var stopRoutes: [String: [String]] = [:]
        for route in routesResponse.get_routes {
            for stopId in route.stops ?? [] { stopRoutes[stopId.value, default: []].append(route.id.value) }
        }
        let routes = routesResponse.get_routes.map { route in
            TransitRoute(
                agency: agency, routeId: route.id.value,
                shortName: route.abbr.trimmingCharacters(in: .whitespaces),
                longName: route.name.trimmingCharacters(in: CharacterSet(charactersIn: "_ ")),
                colorHex: normalizeColor(route.color, fallback: agency.colorHex),
                path: route.encLine.map(decodePolyline) ?? [],
                stopIds: (route.stops ?? []).map(\.value)
            )
        }
        var seen = Set<String>()
        let stops = stopsResponse.get_stops.compactMap { stop -> TransitStop? in
            guard seen.insert(stop.id.value).inserted else { return nil }
            return TransitStop(agency: agency, stopId: stop.id.value, name: stop.name,
                               coordinate: CLLocationCoordinate2D(latitude: stop.lat.value, longitude: stop.lng.value),
                               routeIds: stopRoutes[stop.id.value] ?? [])
        }
        staticData[agency] = (routes, stops)
        return (routes, stops)
    }

    // MARK: Live data

    func vehicles(for agency: Agency) async throws -> [TransitVehicle] {
        let response: VehiclesResponse = try await request(agency, "get_vehicles", ["includeETAData": "1", "orderedETAArray": "1"])
        return response.get_vehicles.compactMap { vehicle in
            guard vehicle.inService?.value != 0, vehicle.lat.value != 0, vehicle.lng.value != 0 else { return nil }
            let nextStop = vehicle.nextStopID.flatMap { $0.value == "0" ? nil : $0.value } ?? vehicle.minutesToNextStops?.first?.stopID.value
            return TransitVehicle(
                agency: agency, vehicleId: vehicle.equipmentID.value, routeId: vehicle.routeID?.value,
                coordinate: CLLocationCoordinate2D(latitude: vehicle.lat.value, longitude: vehicle.lng.value),
                heading: vehicle.h?.value, direction: vehicle.direction?.trimmingCharacters(in: .whitespaces),
                nextStopId: nextStop,
                load: vehicle.load.map { Int($0.value) }, capacity: vehicle.capacity.flatMap { $0.value > 0 ? Int($0.value) : nil },
                updatedAt: Date(timeIntervalSince1970: vehicle.receiveTime.value / 1000)
            )
        }
    }

    func arrivals(for stops: [TransitKey]) async throws -> [TransitArrival] {
        let now = Date()
        let grouped = Dictionary(grouping: stops, by: \.agency)
        var results: [TransitArrival] = []
        var failures = 0
        try await withThrowingTaskGroup(of: [TransitArrival]?.self) { group in
            for (agency, keys) in grouped {
                group.addTask {
                    do {
                        let ids = keys.map(\.id).joined(separator: ",")
                        let response: ArrivalsResponse = try await self.request(agency, "get_stop_etas", ["stopIDs": ids])
                        return response.get_stop_etas.flatMap { stop in
                            (stop.enRoute ?? []).map { eta in
                                TransitArrival(agency: agency, routeId: eta.routeID.value, stopId: eta.stopID?.value ?? stop.id.value,
                                               vehicleId: eta.equipmentID?.value, destination: eta.direction,
                                               predictedArrival: now.addingTimeInterval(max(0, eta.minutes.value) * 60))
                            }
                        }
                    } catch { return nil }
                }
            }
            for try await batch in group {
                if let batch { results += batch } else { failures += 1 }
            }
        }
        if failures > 0 && failures == grouped.count { throw URLError(.cannotLoadFromNetwork) }
        return results.sorted { $0.predictedArrival < $1.predictedArrival }
    }

    // MARK: Plumbing

    private func request<T: Decodable>(_ agency: Agency, _ service: String, _ params: [String: String] = [:]) async throws -> T {
        var components = URLComponents(url: agency.feed, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "service", value: service)] + params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func normalizeColor(_ value: String?, fallback: String) -> String {
        guard let value, !value.isEmpty else { return fallback }
        return value.hasPrefix("#") ? value : "#\(value)"
    }
}

// MARK: - Wire format

/// ETA Spot mixes numbers and strings for the same fields.
struct FlexString: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string }
        else if let int = try? container.decode(Int.self) { value = String(int) }
        else { value = String(try container.decode(Double.self)) }
    }
}

struct FlexDouble: Decodable, Hashable {
    let value: Double
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { value = number }
        else if let string = try? container.decode(String.self), let number = Double(string) { value = number }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a number") }
    }
}

private struct RoutesResponse: Decodable {
    struct Route: Decodable { let id: FlexString; let name: String; let abbr: String; let color: String?; let stops: [FlexString]?; let encLine: String? }
    let get_routes: [Route]
}
private struct StopsResponse: Decodable {
    struct Stop: Decodable { let id: FlexString; let name: String; let lat: FlexDouble; let lng: FlexDouble }
    let get_stops: [Stop]
}
private struct VehiclesResponse: Decodable {
    struct NextStop: Decodable { let stopID: FlexString; let minutes: FlexDouble }
    struct Vehicle: Decodable {
        let routeID: FlexString?; let equipmentID: FlexString; let lat: FlexDouble; let lng: FlexDouble
        let h: FlexDouble?; let receiveTime: FlexDouble; let inService: FlexDouble?; let direction: String?
        let load: FlexDouble?; let capacity: FlexDouble?; let nextStopID: FlexString?; let minutesToNextStops: [NextStop]?
    }
    let get_vehicles: [Vehicle]
}
private struct ArrivalsResponse: Decodable {
    struct ETA: Decodable { let stopID: FlexString?; let routeID: FlexString; let equipmentID: FlexString?; let minutes: FlexDouble; let direction: String? }
    struct Stop: Decodable { let id: FlexString; let enRoute: [ETA]? }
    let get_stop_etas: [Stop]
}

func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
    let bytes = Array(encoded.utf8)
    var index = 0, lat = 0, lng = 0
    var points: [CLLocationCoordinate2D] = []
    func next() -> Int? {
        var result = 0, shift = 0
        while index < bytes.count {
            let byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
            if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
        }
        return nil
    }
    while index < bytes.count {
        guard let dLat = next(), let dLng = next() else { break }
        lat += dLat; lng += dLng
        points.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
    }
    return points
}
