import SwiftUI

struct StopDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let stop: TransitStop
    @State private var trackTarget: TransitArrival?

    var body: some View {
        let arrivals = store.arrivals(at: stop.id)
        let here = location.isAtStop(stop)
        let walk = location.walkSeconds(to: stop)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(spacing: 8) {
                    FavoriteToggle(stop: stop)
                }
                walkStrip(here: here, walk: walk)
                if let first = arrivals.first, let plan = TripMath.leavePlan(busArrival: first.predictedArrival, walkSeconds: walk, atStop: here) {
                    LeaveCard(arrival: first, route: store.route(first.routeKey), plan: plan)
                }
                Text("ARRIVING").font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 4)
                if arrivals.isEmpty {
                    Text(store.arrivalsLoadedFor.contains(stop.id) ? "No buses predicted for this stop right now." : "Checking arrival times…")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(20)
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
                }
                ForEach(arrivals.prefix(10)) { arrival in
                    ArrivalRow(arrival: arrival, tracking: tracker.isTracking(arrival)) {
                        if tracker.isTracking(arrival) { tracker.stop() } else { trackTarget = arrival }
                    }
                }
                Text("Predictions come from the transit feeds and can change. Walk times use Apple Maps walking directions when available.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).padding(.top, 8)
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 30)
        }
        .background(Theme.surface)
        .sheet(item: $trackTarget) { arrival in
            TrackSheet(stop: stop, arrival: arrival) { dismiss() }
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.surface)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: stop.agency.colorHex)).frame(width: 9, height: 9)
                    Text("\(stop.agency.name.uppercased()) STOP").font(.system(size: 11.5, weight: .black)).tracking(0.8)
                }
                .foregroundStyle(Theme.muted)
                Text(stop.name).font(Theme.display(30)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 6) {
                    ForEach(stop.routeIds.compactMap { store.route(TransitKey(agency: stop.agency, id: $0)) }) { route in
                        Text(route.shortName).font(Theme.display(13))
                            .foregroundStyle(Color.readableInk(on: route.colorHex))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Color(hex: route.colorHex), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.edge, lineWidth: 2))
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private func walkStrip(here: Bool, walk: Int?) -> some View {
        if here {
            HStack(spacing: 10) {
                Circle().fill(Theme.goInk).frame(width: 12, height: 12)
                Text("You're at this stop").font(.system(size: 16, weight: .heavy))
            }
            .foregroundStyle(Theme.goInk)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Theme.go, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else if let walk, let distance = location.distance(to: stop) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                Text("\(max(1, Int((Double(walk) / 60).rounded()))) min walk").font(.system(size: 16, weight: .heavy))
                Text("· \(formatDistance(distance))").foregroundStyle(Theme.muted).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else {
            Button { location.requestPermission() } label: {
                Label("Turn on location for walk times", systemImage: "location.fill")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Theme.me, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }
}

struct FavoriteToggle: View {
    @Environment(AppStore.self) private var store
    let stop: TransitStop

    var body: some View {
        let on = store.isFavorite(stop)
        Button { withAnimation(.spring(duration: 0.25)) { store.toggleFavorite(stop) } } label: {
            Label(on ? "Saved" : "Save stop", systemImage: on ? "star.fill" : "star")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(on ? Color.busInk : Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 46)
                .chunky(fill: on ? .busYellow : Theme.soft, radius: 15, lift: 2)
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact, trigger: on)
    }
}

struct LeaveCard: View {
    let arrival: TransitArrival
    let route: TransitRoute?
    let plan: TripMath.LeavePlan

    var body: some View {
        let name = route?.shortName ?? arrival.routeId
        let minutes = arrival.minutes()
        let (kicker, title, sub, fill, ink): (String, String, String, Color, Color) = {
            switch plan.state {
            case .atStop: return ("NEXT BUS", minutes >= 60 ? "\(name) at \(shortClock(arrival.predictedArrival))" : "\(name) in \(minutes) min", "Stay put, it's on the way.", Theme.go, Theme.goInk)
            case .leaveNow: return ("WHEN TO GO", "Leave now", "For the \(arrival.predictedArrival.clock) \(name)", .busInk, .busYellow)
            case .tooLate: return ("HEADS UP", "Too late to walk it", "Catch the one after, or run.", Theme.warn, .white)
            case .leaveSoon: return ("WHEN TO GO", plan.minutesUntilLeave >= 60 ? "Leave at \(shortClock(plan.leaveAt))" : "Leave in \(plan.minutesUntilLeave) min", "Leave by \(plan.leaveAt.clock) for the \(arrival.predictedArrival.clock) \(name)", .busYellow, .busInk)
            }
        }()
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker).font(.system(size: 11.5, weight: .black)).tracking(1).opacity(0.75)
            Text(title).font(Theme.display(32)).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .chunky(fill: fill, radius: 22)
    }
}

struct ArrivalRow: View {
    @Environment(AppStore.self) private var store
    let arrival: TransitArrival
    let tracking: Bool
    let onTrack: () -> Void

    var body: some View {
        let route = store.route(arrival.routeKey)
        let away = store.stopsAway(for: arrival)
        let minutes = arrival.minutes()
        HStack(spacing: 10) {
            RouteTag(name: route?.shortName ?? arrival.routeId, hex: route?.colorHex ?? arrival.agency.colorHex, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.destination ?? route?.longName ?? "Direction unavailable").font(.system(size: 15, weight: .heavy)).lineLimit(2)
                Text(away.map { "\($0) \($0 == 1 ? "stop" : "stops") away" } ?? route?.longName ?? "")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(minutes == 0 ? "Now" : minutes >= 60 ? shortClock(arrival.predictedArrival) : "\(minutes)")
                    .font(Theme.display(minutes >= 60 ? 18 : 26)).monospacedDigit()
                if minutes > 0 && minutes < 60 { Text("min").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted) }
            }
            .foregroundStyle(Theme.ink)
            Button(action: onTrack) {
                Text(tracking ? "Tracking" : "Track").font(.system(size: 13, weight: .black))
                    .foregroundStyle(tracking ? Color.busInk : Theme.ink)
                    .padding(.horizontal, 11).frame(height: 38)
                    .chunky(fill: tracking ? .busYellow : Theme.surface, radius: 12, lift: 2)
            }
            .buttonStyle(PressStyle())
        }
        .padding(8)
        .background(tracking ? Theme.soft : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
    }
}

/// Pick what to follow and when the Live Activity should start.
struct TrackSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let stop: TransitStop
    let arrival: TransitArrival
    let onStarted: () -> Void
    @AppStorage("threshold") private var threshold = 5
    @State private var followThisBus = true

    var body: some View {
        let route = store.route(arrival.routeKey)
        let away = store.stopsAway(for: arrival)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RouteTag(name: route?.shortName ?? arrival.routeId, hex: route?.colorHex ?? arrival.agency.colorHex, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track to").font(.system(size: 12, weight: .black)).tracking(0.8).foregroundStyle(Theme.muted)
                    Text(stop.name).font(Theme.display(20)).foregroundStyle(Theme.ink).lineLimit(2)
                }
            }
            if arrival.vehicleId != nil {
                Picker("Follow", selection: $followThisBus) {
                    Text("This bus · \(arrival.minutes() >= 60 ? shortClock(arrival.predictedArrival) : "\(arrival.minutes()) min")").tag(true)
                    Text("Next \(route?.shortName ?? "") bus").tag(false)
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: $threshold, in: 2...10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start at \(threshold) stops away").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                        Text(away.map { "It's \($0) \($0 == 1 ? "stop" : "stops") away now." } ?? "Stop count shows once the bus reports its position.")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("The Live Activity shows the bus countdown, your walk time, and when to leave. It also starts early if you need to leave before then, and alerts you when it's time to go.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
            }
            .padding(14).background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                tracker.start(TripWatch(agency: arrival.agency, routeId: arrival.routeId, stopId: arrival.stopId,
                                        vehicleId: followThisBus ? arrival.vehicleId : nil, threshold: threshold, createdAt: .now))
                dismiss()
                onStarted()
            } label: {
                Text("Start tracking").font(.system(size: 17, weight: .black)).foregroundStyle(Color.busInk)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .chunky(fill: .busYellow, radius: 16)
            }
            .buttonStyle(PressStyle())
            Text("Keeps location on in the background while tracking (you'll see the blue location pill), so the walk time stays current and it knows when you reach the stop. Stops by itself after the bus passes.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
        .padding(20)
    }
}
