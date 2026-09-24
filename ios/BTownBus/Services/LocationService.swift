import Foundation
import CoreLocation
import MapKit
import Observation

/// One location manager for the whole app. iOS remembers the permission, so
/// unlike the home-screen web app it's only ever asked once.
@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// True while a trip keeps location running with the app in the background.
    private(set) var backgroundTracking = false

    /// Bumped when a walking estimate arrives, so views re-read it.
    private(set) var walkRevision = 0

    @ObservationIgnored private let manager = CLLocationManager()
    // Read from view bodies, so kept out of observation and only changed asynchronously.
    @ObservationIgnored private var walkCache: [TransitKey: (seconds: Int, from: CLLocation, at: Date)] = [:]
    @ObservationIgnored private var walkRequests: Set<TransitKey> = []

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 8
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// A fix newer than two minutes; older ones are never used for "you're at the stop".
    var freshLocation: CLLocation? {
        guard let location, Date().timeIntervalSince(location.timestamp) < 120 else { return nil }
        return location
    }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { startUpdates() }
    }

    func startUpdates() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    /// Keep updating in the background only while a trip is being tracked.
    func setBackgroundTracking(_ on: Bool) {
        backgroundTracking = on
        guard isAuthorized else { return }
        manager.allowsBackgroundLocationUpdates = on
        manager.showsBackgroundLocationIndicator = on
        if on { manager.startUpdatingLocation() }
    }

    func appDidEnterBackground() {
        if !backgroundTracking { manager.stopUpdatingLocation() }
    }

    func appDidBecomeActive() {
        startUpdates()
        // Ask for a fix right away so a stale one from before the app was suspended is replaced quickly.
        if isAuthorized { manager.requestLocation() }
    }

    func distance(to stop: TransitStop) -> CLLocationDistance? {
        location.map { $0.distance(from: stop.location) }
    }

    func isAtStop(_ stop: TransitStop) -> Bool {
        guard let fix = freshLocation else { return false }
        return TripMath.isAtStop(distance: fix.distance(from: stop.location), accuracy: fix.horizontalAccuracy)
    }

    /// Walking seconds to the stop: Apple Maps walking directions when available, otherwise a padded straight line.
    func walkSeconds(to stop: TransitStop) -> Int? {
        _ = walkRevision
        guard let location else { return nil }
        if let cached = walkCache[stop.id], cached.from.distance(from: location) < 40, Date().timeIntervalSince(cached.at) < 120 {
            return cached.seconds
        }
        refreshWalk(to: stop, from: location)
        return walkCache[stop.id]?.seconds ?? TripMath.walkSeconds(distance: location.distance(from: stop.location))
    }

    private func refreshWalk(to stop: TransitStop, from origin: CLLocation) {
        guard !walkRequests.contains(stop.id) else { return }
        walkRequests.insert(stop.id)
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        request.transportType = .walking
        Task {
            defer { walkRequests.remove(stop.id) }
            if let eta = try? await MKDirections(request: request).calculateETA() {
                walkCache[stop.id] = (Int(eta.expectedTravelTime), origin, Date())
            } else {
                walkCache[stop.id] = (TripMath.walkSeconds(distance: origin.distance(from: stop.location)), origin, Date())
            }
            walkRevision += 1
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            if isAuthorized {
                startUpdates()
                if backgroundTracking { setBackgroundTracking(true) }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 200 }) else { return }
        Task { @MainActor in
            if let current = location, current.timestamp > latest.timestamp { return }
            location = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures are common indoors; keep the last fix and let updates continue.
    }
}
