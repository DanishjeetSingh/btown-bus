import Foundation
import ActivityKit
import CoreLocation
import MapKit
import Observation
import UIKit

/// Walking navigation is independent of bus tracking and available at any stop.
@MainActor @Observable
final class WalkingGuide: NSObject {
    static let shared = WalkingGuide()
    private(set) var activityProblem: String?
    @ObservationIgnored private var activity: Activity<WalkingActivityAttributes>?
    @ObservationIgnored private var activityStateTask: Task<Void, Never>?
    @ObservationIgnored private var activityUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivityUpdate = Date.distantPast
    @ObservationIgnored private var lastActivityPhase: WalkingActivityAttributes.Phase?
    @ObservationIgnored private var lastActivityStep = -1
    private(set) var destination: TransitStop?
    private(set) var route: MKRoute?
    private(set) var alternatives: [MKRoute] = []
    private(set) var choosingRoute = false
    @ObservationIgnored private var forceRouteChoice = false
    private(set) var stepIndex = 0
    private(set) var problem: String?
    private(set) var loading = false
    private(set) var remainingDistance: Double = 0
    private(set) var maneuverDistance: Double = 0
    private(set) var arrived = false
    @ObservationIgnored private var progress = 0.0
    @ObservationIgnored private var lastFix: CLLocation?
    @ObservationIgnored private var offRouteFixes = 0
    @ObservationIgnored private var lastRequest = Date.distantPast
    @ObservationIgnored private var waitingForLocation = false
    @ObservationIgnored private var requestTask: Task<Void, Never>?

    override init() {
        super.init()
        // A walk isn't restored after process termination. Remove orphaned activities.
        let orphaned = Activity<WalkingActivityAttributes>.activities
        Task { for activity in orphaned { await activity.end(nil, dismissalPolicy: .immediate) } }
    }

    func start(to stop: TransitStop) {
        endActivity()
        activityProblem = nil
        requestTask?.cancel()
        destination = stop
        route = nil
        alternatives = []
        choosingRoute = false
        forceRouteChoice = false
        stepIndex = 0
        problem = nil
        loading = false
        arrived = false
        remainingDistance = 0
        maneuverDistance = 0
        progress = 0
        lastFix = nil
        LocationService.shared.setWalkingNavigation(true)
        LocationService.shared.requestPermission()
        LocationService.shared.setBackgroundTracking(true)
        refresh()
    }

    func stop() {
        endActivity()
        requestTask?.cancel()
        requestTask = nil
        waitingForLocation = false
        destination = nil
        route = nil
        alternatives = []
        choosingRoute = false
        stepIndex = 0
        problem = nil
        loading = false
        LocationService.shared.setWalkingNavigation(false)
        LocationService.shared.setBackgroundTracking(TripTracker.shared.watch != nil)
    }

    func refresh() {
        guard let destination else { return }
        defer { updateActivity(force: true) }
        requestTask?.cancel()
        loading = false
        waitingForLocation = false
        let location = LocationService.shared
        guard !location.isDenied else {
            problem = "Location is blocked. Enable location in Settings or open Apple Maps."
            return
        }
        guard let origin = location.freshLocation, origin.horizontalAccuracy <= 100,
              Date().timeIntervalSince(origin.timestamp) < 20 else {
            waitingForLocation = true
            problem = "Waiting for an accurate GPS position…"
            return
        }
        loading = true
        lastRequest = Date()
        problem = nil
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        requestTask = Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled, self.destination?.id == destination.id else { return }
                alternatives = response.routes
                loading = false
                guard !alternatives.isEmpty else {
                    problem = "No walking route available. Try Apple Maps."
                    updateActivity(force: true)
                    return
                }
                let descriptors = alternatives.map { WalkingRoutePreference.describe(name: $0.name, polyline: $0.polyline) }
                if !forceRouteChoice,
                   let data = UserDefaults.standard.data(forKey: preferenceKey(destination)),
                   let saved = try? JSONDecoder().decode(WalkingRoutePreference.self, from: data),
                   let index = saved.match(in: descriptors) {
                    activate(alternatives[index])
                } else {
                    // Require a choice when the remembered corridor is no longer available.
                    choosingRoute = true
                }
                updateActivity(force: true)
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                problem = "Walking directions unavailable. Try again or open Apple Maps."
                updateActivity(force: true)
            }
        }
    }

    private func preferenceKey(_ stop: TransitStop) -> String { "walking-route-choice:\(stop.id)" }

    func selectRoute(at index: Int) {
        guard alternatives.indices.contains(index), let destination else { return }
        let selected = alternatives[index]
        let descriptor = WalkingRoutePreference.describe(name: selected.name, polyline: selected.polyline)
        if let data = try? JSONEncoder().encode(descriptor) {
            UserDefaults.standard.set(data, forKey: preferenceKey(destination))
        }
        activate(selected)
    }

    func changeRoute() {
        forceRouteChoice = true
        refresh()
    }

    private func activate(_ selected: MKRoute) {
        route = selected
        choosingRoute = false
        forceRouteChoice = false
        stepIndex = 0
        progress = 0
        lastFix = nil
        offRouteFixes = 0
        arrived = false
        remainingDistance = selected.distance
        if activity == nil { startActivity() }
        locationDidUpdate()
        updateActivity(force: true)
    }

    var steps: [MKRoute.Step] { route?.steps.filter { !$0.instructions.isEmpty } ?? [] }

    var instruction: String {
        if choosingRoute { return "Choose a walking route in the app" }
        if arrived { return "You've arrived" }
        guard !steps.isEmpty else { return loading ? "Finding your route…" : "Getting your location…" }
        let next = min(stepIndex + 1, steps.count - 1)
        return next == stepIndex ? "Arrive at \(destination?.name ?? "your stop")" : steps[next].instructions
    }

    var maneuverSymbol: String {
        let text = instruction.lowercased()
        if arrived || text.contains("arrive") || text.contains("destination") { return "mappin.and.ellipse" }
        if text.contains("u-turn") { return "arrow.uturn.backward" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }

    var remainingSeconds: Double {
        guard let route, route.distance > 0 else { return 0 }
        return route.expectedTravelTime * min(1, remainingDistance / route.distance)
    }

    func locationDidUpdate() {
        guard let destination, !arrived, !choosingRoute else { return }
        defer { updateActivity() }
        if route == nil, !loading, waitingForLocation { refresh(); return }
        guard let route, let fix = LocationService.shared.freshLocation,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 35,
              Date().timeIntervalSince(fix.timestamp) < 20,
              lastFix == nil || fix.timestamp > lastFix!.timestamp else { return }
        let movement = lastFix.map { fix.distance(from: $0) } ?? 40
        if let projection = WalkingProgress.project(fix.coordinate, onto: route.polyline,
                                                     previous: progress, advanceLimit: max(80, movement * 2 + 30)) {
            remainingDistance = max(0, projection.totalDistance - projection.distanceAlong)
            if projection.distanceFromRoute > max(35, fix.horizontalAccuracy * 2) {
                offRouteFixes += 1
                if offRouteFixes >= 3, !loading, Date().timeIntervalSince(lastRequest) > 30 {
                    problem = "Updating your route…"
                    refresh()
                }
            } else {
                offRouteFixes = 0
                progress = max(progress, projection.distanceAlong)
                var end = 0.0
                for (index, step) in steps.enumerated() {
                    end += step.distance
                    if end > progress + 10 || index == steps.count - 1 {
                        stepIndex = index
                        maneuverDistance = max(0, end - progress)
                        break
                    }
                }

            }
        }
        lastFix = fix
        if remainingDistance < 60, fix.distance(from: destination.location) <= 25 {
            arrived = true
            remainingDistance = 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func activityContent() -> ActivityContent<WalkingActivityAttributes.ContentState> {
        let phase: WalkingActivityAttributes.Phase = choosingRoute ? .choosing : arrived ? .arrived : loading && route != nil ? .rerouting :
            route == nil ? (problem != nil && !waitingForLocation ? .unavailable : .locating) : .walking
        let now = Date()
        let checkedAt = lastFix?.timestamp ?? now
        let state = WalkingActivityAttributes.ContentState(phase: phase, instruction: instruction,
            maneuverSymbol: maneuverSymbol, maneuverMeters: Int(maneuverDistance.rounded()),
            remainingMeters: Int(remainingDistance.rounded()), remainingMinutes: max(0, Int(ceil(remainingSeconds / 60))),
            arrivalAt: route == nil ? nil : now.addingTimeInterval(remainingSeconds), updatedAt: checkedAt)
        return ActivityContent(state: state, staleDate: arrived ? nil : checkedAt.addingTimeInterval(45), relevanceScore: 100)
    }

    private func startActivity() {
        guard let destination else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activityProblem = "Enable Live Activities for B-Town Bus in Settings to see walking directions on your Lock Screen."
            return
        }
        do {
            let started = try Activity.request(attributes: WalkingActivityAttributes(stopName: destination.name),
                                               content: activityContent(), pushType: nil)
            activity = started
            lastActivityUpdate = .distantPast
            lastActivityPhase = nil
            lastActivityStep = -1
            activityStateTask = Task { [weak self] in
                for await state in started.activityStateUpdates {
                    guard let self else { return }
                    if state == .ended || state == .dismissed {
                        guard self.activity?.id == started.id else { return }
                        self.stop()
                        return
                    }
                }
            }
        } catch {
            activityProblem = "Walking Live Activity couldn't start. Reopen walk mode to try again."
        }
    }

    private func updateActivity(force: Bool = false) {
        guard let activity else { return }
        let content = activityContent()
        guard force || content.state.phase != lastActivityPhase || stepIndex != lastActivityStep ||
              Date().timeIntervalSince(lastActivityUpdate) >= 5 else { return }
        lastActivityUpdate = Date()
        lastActivityPhase = content.state.phase
        lastActivityStep = stepIndex
        let previous = activityUpdateTask
        activityUpdateTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await activity.update(content)
        }
    }

    private func endActivity() {
        activityStateTask?.cancel()
        activityStateTask = nil
        let pending = activityUpdateTask
        activityUpdateTask = nil
        guard let ending = activity else { return }
        activity = nil
        Task {
            await pending?.value
            await ending.end(nil, dismissalPolicy: .immediate)
        }
    }

}
