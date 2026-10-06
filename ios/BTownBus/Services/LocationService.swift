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
    private(set) var heading: CLLocationDirection?
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
    /// Precise Location is off for the app: fixes are only good to about a kilometre.
    var isApproximate: Bool { isAuthorized && manager.accuracyAuthorization == .reducedAccuracy }

    /// Ask for one new fix now, instead of waiting for the next movement-triggered update.
    func requestFreshFix() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    /// Walking directions need a precise position; ask for it just this once if it's off.
    func requestPreciseForWalking() {
        guard isApproximate else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Walking")
    }

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

    func setWalkingNavigation(_ on: Bool) {
        manager.desiredAccuracy = on ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = on ? 2 : 8
        if on, CLLocationManager.headingAvailable() {
            manager.headingFilter = 8
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
            heading = nil
        }
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
        // A rough fix (Precise Location off, or no GPS yet) can't tell you're at a stop.
        guard let fix = freshLocation, fix.horizontalAccuracy <= 100 else { return false }
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
        guard let latest = locations.last(where: { $0.horizontalAccuracy >= 0 }) else { return }
        Task { @MainActor in
            if let current = location, current.timestamp > latest.timestamp { return }
            // Skip a rough fix when a good one is only moments old; otherwise rough beats nothing
            // (with Precise Location off, every fix is rough).
            if latest.horizontalAccuracy >= 200, let current = location, current.horizontalAccuracy < 200,
               latest.timestamp.timeIntervalSince(current.timestamp) < 60 { return }
            location = latest
            // Update navigation and its Live Activity directly, including while locked.
            WalkingGuide.shared.locationDidUpdate()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in heading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures are common indoors; keep the last fix and let updates continue.
    }
}
