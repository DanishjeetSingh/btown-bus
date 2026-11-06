import Foundation
import MapKit

/// A second opinion on when the tracked bus reaches your stop, from Apple Maps driving times (which
/// account for traffic): the bus to its next stop, then stop to stop up to yours, plus some time for
/// each stop on the way. Only ever for the one bus being tracked, to stay well inside Apple's limits.
@MainActor
final class MapsETA {
    static let shared = MapsETA()
    private static let dwellKey = "maps-eta-seconds-per-stop"

    /// Time added per stop on the way. A bus only stops when someone's waiting or rings, so this isn't
    /// a full stop each time: it starts at 10 s (about every other stop) and is learned from real trips.
    private(set) var secondsPerStop: TimeInterval = UserDefaults.standard.object(forKey: dwellKey) as? Double ?? 10

    /// Pure driving time to your stop, and how many stops sit between the bus and yours.
    private var latest: (key: String, driveArrival: Date, stopsBetween: Int, at: Date)?
    /// Stop-to-stop driving times. Traffic changes slowly, so these are reused for 10 minutes.
    private var segments: [String: (seconds: TimeInterval, at: Date)] = [:]
    private var running = false
    private var nextRun = Date.distantPast

    /// The latest estimate for this bus reaching this stop, if it's recent.
    func estimate(bus: TransitKey, stop: TransitKey) -> (arrival: Date, driveArrival: Date, stopsBetween: Int)? {
        guard let latest, latest.key == "\(bus)>\(stop)", Date().timeIntervalSince(latest.at) < 180 else { return nil }
        let arrival = latest.driveArrival.addingTimeInterval(secondsPerStop * Double(latest.stopsBetween))
        return (arrival, latest.driveArrival, latest.stopsBetween)
    }

    /// After a trip: on average the bus lost this much per stop on the way, beyond driving time.
    /// Move partway toward it, so one odd trip doesn't swing the estimate.
    func learn(secondsPerStop observed: TimeInterval) {
        let clamped = min(45, max(0, observed))
        secondsPerStop = (secondsPerStop * 0.7 + clamped * 0.3).rounded()
        UserDefaults.standard.set(secondsPerStop, forKey: Self.dwellKey)
    }

    /// Starts a new estimate if one is due (at most once a minute) and returns right away.
    /// `path` is the bus's remaining stops in order, ending with yours.
    func refreshIfDue(bus: TransitVehicle, path: [TransitStop]) {
        guard !running, Date() >= nextRun, let target = path.last, path.count <= 15 else { return }
        running = true
        nextRun = Date().addingTimeInterval(60)
        let key = "\(bus.id)>\(target.id)"
        Task {
            defer { running = false }
            do {
                // Only the first stretch moves with the bus; the rest come from the cache when they can.
                var total = try await Self.drive(from: bus.coordinate, to: path[0].coordinate)
                for (from, to) in zip(path, path.dropFirst()) {
                    let segment = "\(from.id)>\(to.id)"
                    if let cached = segments[segment], Date().timeIntervalSince(cached.at) < 600 {
                        total += cached.seconds
                        continue
                    }
                    let seconds = try await Self.drive(from: from.coordinate, to: to.coordinate)
                    segments[segment] = (seconds, Date())
                    total += seconds
                }
                // The bus was at that position when it last reported, not now.
                latest = (key, bus.updatedAt.addingTimeInterval(total), path.count - 1, Date())
            } catch let error as MKError where error.code == .loadingThrottled {
                // Apple asks apps to back off when throttled.
                nextRun = Date().addingTimeInterval(180)
            } catch {
                // No route or no network: no estimate this round.
            }
        }
    }

    private static func drive(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.departureDate = Date()
        return try await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}

/// Keeps score between the feed's prediction and Apple Maps': both guesses are noted about once a
/// minute while tracking, then compared with when the bus actually left your stop.
@MainActor @Observable
final class ETAAccuracy {
    static let shared = ETAAccuracy()
    private static let storageKey = "eta-accuracy"

    struct Trip: Codable {
        var date: Date
        var route: String
        /// Average miss, in seconds, of guesses made 2 to 20 minutes before the bus arrived.
        var feedError: Double
        var mapsError: Double
    }

    private(set) var trips: [Trip] = []
    @ObservationIgnored private var samples: [(at: Date, feed: Date, maps: Date, driveArrival: Date, stopsBetween: Int)] = []
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var route = ""

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey), let saved = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = saved
        }
    }

    func observe(bus: TransitKey, stop: TransitKey, route: String, feed: Date?,
                 maps: (arrival: Date, driveArrival: Date, stopsBetween: Int)?, now: Date) {
        guard let feed, let maps else { return }
        let key = "\(bus)>\(stop)"
        if key != self.key {
            // A different bus (the tracker switched) or a new trip: start over.
            self.key = key
            self.route = route
            samples = []
        }
        if let last = samples.last, now.timeIntervalSince(last.at) < 50 { return }
        samples.append((now, feed, maps.arrival, maps.driveArrival, maps.stopsBetween))
    }

    /// The tracked bus just left your stop.
    func busPassed(at time: Date) {
        // Judge guesses made 2 to 20 minutes out; closer in, both are easy.
        let judged = samples.filter { (120...1200).contains(time.timeIntervalSince($0.at)) }
        samples = []
        key = nil
        guard !judged.isEmpty else { return }
        let count = Double(judged.count)
        let trip = Trip(date: time, route: route,
                        feedError: judged.map { abs($0.feed.timeIntervalSince(time)) }.reduce(0, +) / count,
                        mapsError: judged.map { abs($0.maps.timeIntervalSince(time)) }.reduce(0, +) / count)
        trips = Array((trips + [trip]).suffix(30))
        // What each stop on the way really cost, beyond driving time.
        let perStop = judged.filter { $0.stopsBetween > 0 }.map { time.timeIntervalSince($0.driveArrival) / Double($0.stopsBetween) }
        if !perStop.isEmpty { MapsETA.shared.learn(secondsPerStop: perStop.reduce(0, +) / Double(perStop.count)) }
        if let data = try? JSONEncoder().encode(trips) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }

    /// "Last 4 trips: Apple Maps was off by 1.2 min on average, the feed by 2.6 min."
    var summary: String? {
        guard !trips.isEmpty else { return nil }
        let count = Double(trips.count)
        let feed = trips.map(\.feedError).reduce(0, +) / count / 60
        let maps = trips.map(\.mapsError).reduce(0, +) / count / 60
        let label = trips.count == 1 ? "Last trip" : "Last \(trips.count) trips"
        return "\(label): Apple Maps was off by \(String(format: "%.1f", maps)) min on average, the feed by \(String(format: "%.1f", feed)) min. "
            + "Maps now allows \(Int(MapsETA.shared.secondsPerStop)) s per stop on the way, learned from your trips."
    }
}
