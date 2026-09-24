import Foundation
import ActivityKit
import UserNotifications
import Observation

/// A bus + stop the user asked to be told about.
struct TripWatch: Codable, Equatable {
    var agency: Agency
    var routeId: String
    var stopId: String
    /// The bus being followed. When nil, the tracker locks onto the next bus on the route.
    var vehicleId: String?
    /// Start the Live Activity once the bus is this many stops away.
    var threshold: Int
    var createdAt: Date

    var stopKey: TransitKey { TransitKey(agency: agency, id: stopId) }
    var routeKey: TransitKey { TransitKey(agency: agency, id: routeId) }
}

struct TripStatus: Equatable {
    var arrival: TransitArrival?
    var stopsAway: Int?
    var walkSeconds: Int?
    var leaveAt: Date?
    var atStop: Bool
    var phase: TripActivityAttributes.Phase
    var checkedAt: Date
}

/// Watches one trip, in the foreground or (with background location on) the background,
/// and drives the Live Activity: it starts once the bus is close, updates as it moves,
/// alerts when it's time to leave, and ends after the bus passes the stop.
@MainActor @Observable
final class TripTracker {
    static let shared = TripTracker()
    private static let storageKey = "trip-watch"
    private static let maxDuration: TimeInterval = 2 * 60 * 60

    private(set) var watch: TripWatch?
    private(set) var status: TripStatus?
    private(set) var activityRunning = false
    /// Why a Live Activity couldn't start, if it couldn't.
    private(set) var activityProblem: String?

    @ObservationIgnored private var activity: Activity<TripActivityAttributes>?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var endingOnPurpose = false
    @ObservationIgnored private var sawArrivingAt: Date?
    @ObservationIgnored private var lostBusSince: Date?
    @ObservationIgnored private var notified: Set<String> = []
    @ObservationIgnored private var ticking = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(TripWatch.self, from: data),
           Date().timeIntervalSince(saved.createdAt) < Self.maxDuration {
            watch = saved
        }
        if let existing = Activity<TripActivityAttributes>.activities.first {
            if watch == nil { Task { await existing.end(nil, dismissalPolicy: .immediate) } } else { adopt(existing) }
        }
    }

    /// Call once at launch to resume a saved trip.
    func resume() {
        guard watch != nil else { return }
        LocationService.shared.setBackgroundTracking(true)
        startLoop()
    }

    func start(_ newWatch: TripWatch) {
        endActivity(immediately: true)
        watch = newWatch
        status = nil
        sawArrivingAt = nil
        lostBusSince = nil
        notified = []
        activityProblem = nil
        save()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        LocationService.shared.requestPermission()
        LocationService.shared.setBackgroundTracking(true)
        startLoop()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        endActivity(immediately: true)
        watch = nil
        status = nil
        save()
        LocationService.shared.setBackgroundTracking(false)
    }

    func isTracking(_ arrival: TransitArrival) -> Bool {
        guard let watch else { return false }
        return watch.agency == arrival.agency && watch.stopId == arrival.stopId && watch.routeId == arrival.routeId
            && (watch.vehicleId == nil || watch.vehicleId == arrival.vehicleId)
    }

    func appDidBecomeActive() {
        // A Live Activity that couldn't start from the background can start now.
        if watch != nil { Task { await tick() } }
    }

    // MARK: Loop

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.watch != nil else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(self.activity == nil ? 15 : 10))
            }
        }
    }

    private func tick() async {
        // The loop and app-activation can both ask for a tick; never run two, or two activities could start.
        guard !ticking, var watch else { return }
        ticking = true
        defer { ticking = false }
        let now = Date()
        if now.timeIntervalSince(watch.createdAt) > Self.maxDuration { stop(); return }

        let client = TransitClient.shared
        guard let base = try? await client.routesAndStops(for: watch.agency),
              let stop = base.stops.first(where: { $0.stopId == watch.stopId }) else { return }
        let route = base.routes.first { $0.routeId == watch.routeId }
        let stopKey = watch.stopKey, agency = watch.agency
        async let arrivalsRequest = client.arrivals(for: [stopKey])
        async let vehiclesRequest = client.vehicles(for: agency)
        guard let arrivals = try? await arrivalsRequest else { return }
        let vehicles = (try? await vehiclesRequest) ?? []
        guard self.watch == watch else { return } // changed while we were waiting

        let candidates = arrivals.filter { $0.routeId == watch.routeId }
        var arrival = watch.vehicleId.flatMap { id in candidates.first { $0.vehicleId == id } }
        var departed = false
        if watch.vehicleId == nil, let first = candidates.first {
            arrival = first
            watch.vehicleId = first.vehicleId
            self.watch = watch
            save()
        } else if arrival == nil {
            // The followed bus dropped out of the predictions: it has passed the stop, or the feed lost it.
            let lockedBus = watch.vehicleId.flatMap { id in vehicles.first { $0.vehicleId == id } }
            if let sawArrivingAt, now.timeIntervalSince(sawArrivingAt) < 10 * 60, lockedBus?.nextStopId != watch.stopId {
                departed = true
            } else {
                lostBusSince = lostBusSince ?? now
                if now.timeIntervalSince(lostBusSince!) > 3 * 60, let next = candidates.first {
                    watch.vehicleId = next.vehicleId
                    self.watch = watch
                    save()
                    arrival = next
                    lostBusSince = nil
                }
            }
        } else {
            lostBusSince = nil
        }

        let vehicle = arrival?.vehicleId.flatMap { id in vehicles.first { $0.vehicleId == id } }
        let stopsAway = route.flatMap { TripMath.stopsAway(stopIds: $0.stopIds, nextStopId: vehicle?.nextStopId, target: watch.stopId) }
        let location = LocationService.shared
        let atStop = location.isAtStop(stop)
        let walk = location.walkSeconds(to: stop)
        let plan = arrival.flatMap { TripMath.leavePlan(busArrival: $0.predictedArrival, walkSeconds: walk, now: now, atStop: atStop) }
        let minutes = arrival?.minutes(from: now)
        if let minutes, minutes <= 2 { sawArrivingAt = now }

        let phase: TripActivityAttributes.Phase
        if departed { phase = .departed }
        else if arrival == nil { phase = .noPrediction }
        else if (minutes ?? 99) <= 1 || (stopsAway == 1 && (minutes ?? 99) <= 2) { phase = .arriving }
        else if atStop { phase = .atStop }
        else {
            switch plan?.state {
            case .tooLate: phase = .tooLate
            case .leaveNow: phase = .leaveNow
            default: phase = .onTheWay
            }
        }
        let next = TripStatus(arrival: arrival, stopsAway: stopsAway, walkSeconds: atStop ? 0 : walk,
                              leaveAt: plan?.state == .atStop ? nil : plan?.leaveAt, atStop: atStop, phase: phase, checkedAt: now)
        let previousPhase = status?.phase
        status = next

        // Close enough by stop count, or by time when stop count isn't available, or it's already time to walk.
        let close = (stopsAway.map { $0 <= watch.threshold } ?? false)
            || (stopsAway == nil && (minutes ?? 99) <= watch.threshold * 2)
            || phase == .leaveNow || phase == .tooLate || phase == .arriving
            || (plan.map { $0.state != .atStop && $0.leaveAt.timeIntervalSince(now) < 120 } ?? false)

        if phase == .departed {
            finish(with: next, stop: stop)
            return
        }
        if activity == nil, close, arrival != nil {
            startActivity(watch: watch, route: route, stop: stop, status: next)
        } else if let activity {
            let alert = alertFor(phase: phase, previous: previousPhase, route: route, stop: stop, status: next)
            await activity.update(content(for: next), alertConfiguration: alert)
        }
        if activity == nil { notifyIfNeeded(close: close, phase: phase, route: route, stop: stop, status: next) }
    }

    #if DEBUG
    /// Launch with `-demoLiveActivity` to see the Live Activity layout when no buses are running.
    func startDemoActivityIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-demoLiveActivity"), watch == nil else { return }
        for old in Activity<TripActivityAttributes>.activities { await old.end(nil, dismissalPolicy: .immediate) }
        let attributes = TripActivityAttributes(routeShortName: "6", routeColorHex: "#9e6b3f", stopName: "7th St & Woodlawn Ave (IMU)",
                                                agencyName: Agency.bt.name, startStops: 5)
        let status = TripStatus(arrival: TransitArrival(agency: .bt, routeId: "6", stopId: "0", vehicleId: nil, destination: nil,
                                                        predictedArrival: .now.addingTimeInterval(7 * 60)),
                                stopsAway: 3, walkSeconds: 4 * 60, leaveAt: .now.addingTimeInterval(2 * 60), atStop: false, phase: .onTheWay, checkedAt: .now)
        do {
            _ = try Activity.request(attributes: attributes, content: content(for: status), pushType: nil)
        } catch {
            print("Demo Live Activity failed: \(error)")
        }
    }
    #endif

    // MARK: Live Activity

    private func startActivity(watch: TripWatch, route: TransitRoute?, stop: TransitStop, status: TripStatus) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activityProblem = "Live Activities are off for B-Town Bus in Settings."
            return
        }
        let attributes = TripActivityAttributes(
            routeShortName: route?.shortName ?? watch.routeId,
            routeColorHex: route?.colorHex ?? watch.agency.colorHex,
            stopName: stop.name,
            agencyName: watch.agency.name,
            startStops: max(status.stopsAway ?? watch.threshold, 1)
        )
        do {
            let started = try Activity.request(attributes: attributes, content: content(for: status), pushType: nil)
            activityProblem = nil
            adopt(started)
        } catch {
            // Usually because the app is in the background; it starts when you next open the app.
            activityProblem = "The Live Activity will start the next time the app is open."
        }
    }

    private func adopt(_ newActivity: Activity<TripActivityAttributes>) {
        activity = newActivity
        activityRunning = true
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in newActivity.activityStateUpdates {
                guard let self else { return }
                if state == .dismissed || state == .ended {
                    self.activity = nil
                    self.activityRunning = false
                    // Ended from the Lock Screen button: stop tracking too.
                    if !self.endingOnPurpose { self.stop() }
                    return
                }
            }
        }
    }

    private func content(for status: TripStatus) -> ActivityContent<TripActivityAttributes.ContentState> {
        let state = TripActivityAttributes.ContentState(
            phase: status.phase, busArrival: status.arrival?.predictedArrival, stopsAway: status.stopsAway,
            walkSeconds: status.walkSeconds, leaveAt: status.leaveAt, updatedAt: status.checkedAt)
        // If the app stops updating, iOS dims the activity instead of showing old times as fresh.
        return ActivityContent(state: state, staleDate: status.checkedAt.addingTimeInterval(3 * 60), relevanceScore: 100)
    }

    private func alertFor(phase: TripActivityAttributes.Phase, previous: TripActivityAttributes.Phase?, route: TransitRoute?, stop: TransitStop, status: TripStatus) -> AlertConfiguration? {
        guard phase != previous else { return nil }
        let name = route?.shortName ?? "Your bus"
        switch phase {
        case .leaveNow: return AlertConfiguration(title: "Leave now", body: "\(name) reaches \(stop.name) in \(status.arrival?.minutes() ?? 0) min.", sound: .default)
        case .arriving: return AlertConfiguration(title: "\(name) is arriving", body: status.atStop ? "It's pulling up to your stop." : "It's almost at \(stop.name).", sound: .default)
        default: return nil
        }
    }

    private func finish(with status: TripStatus, stop: TransitStop) {
        loopTask?.cancel()
        loopTask = nil
        if let activity {
            endingOnPurpose = true
            Task {
                await activity.end(content(for: status), dismissalPolicy: .after(Date().addingTimeInterval(2 * 60)))
                endingOnPurpose = false
            }
        }
        activity = nil
        activityRunning = false
        watch = nil
        save()
        LocationService.shared.setBackgroundTracking(false)
    }

    private func endActivity(immediately: Bool) {
        guard let activity else { return }
        endingOnPurpose = true
        self.activity = nil
        activityRunning = false
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            endingOnPurpose = false
        }
    }

    // MARK: Notifications (fallback when a Live Activity can't start)

    private func notifyIfNeeded(close: Bool, phase: TripActivityAttributes.Phase, route: TransitRoute?, stop: TransitStop, status: TripStatus) {
        let name = route?.shortName ?? "Your bus"
        if close, !notified.contains("close") {
            notified.insert("close")
            let away = status.stopsAway.map { "\($0) \($0 == 1 ? "stop" : "stops") away" } ?? "\(status.arrival?.minutes() ?? 0) min away"
            post(title: "\(name) is \(away)", body: leaveLine(status) ?? "Heading to \(stop.name).")
        }
        if phase == .leaveNow, !notified.contains("leave") {
            notified.insert("leave")
            post(title: "Leave now", body: "\(name) reaches \(stop.name) in \(status.arrival?.minutes() ?? 0) min.")
        }
    }

    private func leaveLine(_ status: TripStatus) -> String? {
        if status.atStop { return "You're at the stop." }
        guard let leaveAt = status.leaveAt else { return nil }
        return "Leave by \(leaveAt.clock)."
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func save() {
        if let watch, let data = try? JSONEncoder().encode(watch) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.storageKey) }
    }
}
