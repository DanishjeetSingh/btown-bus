import SwiftUI

struct StopDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let stop: TransitStop
    @State private var showWalking = false
    @State private var trackTarget: TransitArrival?
    /// Buses picked with the chips, just for this look at the stop. Empty shows every bus.
    @State private var filter: Set<TransitKey> = []
    /// The buses to put in the save sheet when it opens, or nil while it's closed.
    @State private var saving: Set<TransitKey>?

    var body: some View {
        let all = store.arrivals(atPlace: stop)
        let arrivals = filter.isEmpty ? all : all.filter { filter.contains($0.routeKey) }
        let here = location.isAtStop(stop)
        let walk = location.walkSeconds(to: stop)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(spacing: 8) {
                    FavoriteToggle(stop: stop, filter: filter) { saving = $0 }
                    walkButton(here: here, walk: walk)
                }
                if !location.isAuthorized { locationPrompt }
                if let first = arrivals.first, let plan = TripMath.leavePlan(busArrival: first.predictedArrival, walkSeconds: walk, atStop: here) {
                    LeaveCard(arrival: first, route: store.route(first.routeKey), plan: plan)
                }
                // The filter sits right above what it filters.
                ArrivingFilter(routes: store.routes(at: stop), filter: $filter, savedRoutes: Set(store.savedEntry(for: stop)?.routes ?? []))
                    .padding(.top, 4)
                if arrivals.isEmpty {
                    Text(!store.loadedArrivals(atPlace: stop) ? "Checking arrival times…"
                         : filter.isEmpty ? "No buses predicted for this stop right now." : "None of these buses are due right now.")
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
        .sheet(isPresented: $showWalking) {
            TripView(walkOnlyStop: stop)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
        }
        .sheet(isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } })) {
            SaveStopSheet(stop: stop, initial: saving ?? [])
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
        }
        .sheet(item: $trackTarget) { arrival in
            TrackSheet(stop: stop, arrival: arrival) { dismiss() }
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.surface)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                let members = store.members(of: stop)
                let agencies = store.agencies(at: stop)
                HStack(spacing: 6) {
                    AgencyMarks(agencies: agencies)
                    Text(agencies.count > 1 ? "IU + BLOOMINGTON TRANSIT STOP" : "\(stop.agency.name.uppercased()) STOP").font(.system(size: 11.5, weight: .black)).tracking(0.8)
                }
                .foregroundStyle(Theme.muted)
                Text(store.placeName(stop)).font(Theme.display(30)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if members.count > 1, let other = members.first(where: { $0.name != store.placeName(stop) }) {
                    Text("Same stop as \(other.name)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
    }

    /// Walk time rides on the button, like the saved buses ride on Save.
    private func walkButton(here: Bool, walk: Int?) -> some View {
        let detail: String? = here ? "You're here"
            : walk.map { seconds in
                let minutes = "\(max(1, Int((Double(seconds) / 60).rounded()))) min"
                return location.distance(to: stop).map { "\(minutes) · \(formatDistance($0))" } ?? minutes
            }
        return Button { showWalking = true } label: {
            HStack(spacing: 7) {
                Image(systemName: here ? "map" : "figure.walk")
                VStack(alignment: .leading, spacing: -1) {
                    Text(here ? "Map" : "Walk here")
                    if let detail { Text(detail).font(.system(size: 11.5, weight: .heavy)).opacity(0.75) }
                }
            }
            .font(.system(size: 15, weight: .black)).lineLimit(1)
            .foregroundStyle(here ? Theme.goInk : Theme.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity).frame(height: 46)
            .chunky(fill: here ? Theme.go : Theme.soft, radius: 15, lift: 2)
        }
        .buttonStyle(PressStyle())
    }

    private var locationPrompt: some View {
        Button { location.requestPermission() } label: {
            Label("Turn on location for walk times", systemImage: "location.fill")
                .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(Theme.me, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

/// "6", "6 and E", "6, E and 9".
func busList(_ routes: [TransitRoute]) -> String {
    let names = routes.map(\.shortName)
    guard names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " and " + names.last!
}

/// Opens the save sheet, which shows exactly what's being saved before anything is.
struct FavoriteToggle: View {
    @Environment(AppStore.self) private var store
    let stop: TransitStop
    var filter: Set<TransitKey> = []
    let open: (Set<TransitKey>) -> Void

    var body: some View {
        let entry = store.savedEntry(for: stop)
        let routes = store.routes(at: stop)
        let picked = Set(routes.map(\.id)).intersection(filter)
        // Picking buses at a saved stop that differ from what's saved offers to update the save.
        let differs = entry != nil && !picked.isEmpty && picked != Set(entry?.routes ?? [])
        let title = entry == nil ? (picked.isEmpty ? "Save stop" : "Save these buses") : differs ? "Update saved buses" : "Saved"
        let savedRoutes = routes.filter { entry?.routes.contains($0.id) ?? false }
        // A stop saved for only some buses says which, right on the button.
        let detail: String? = differs || savedRoutes.isEmpty ? nil
            : savedRoutes.count <= 3 ? "Just \(busList(savedRoutes))" : "Just \(savedRoutes.count) buses"
        Button {
            open(entry == nil || differs ? picked : Set(entry?.routes ?? []))
        } label: {
            HStack(spacing: 7) {
                Image(systemName: entry != nil ? "star.fill" : "star")
                VStack(alignment: .leading, spacing: -1) {
                    Text(title)
                    if let detail { Text(detail).font(.system(size: 11.5, weight: .heavy)).opacity(0.75) }
                }
            }
                .font(.system(size: 15, weight: .black)).lineLimit(1)
                .foregroundStyle(entry != nil && !differs ? Color.busInk : Theme.ink)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity).frame(height: 46)
                .chunky(fill: entry != nil && !differs ? .busYellow : Theme.soft, radius: 15, lift: 2)
        }
        .buttonStyle(PressStyle())
    }
}

/// The ARRIVING header with the stop's buses as chips that narrow the list below it, for this visit only
/// (saving is separate). Chips wrap rather than scroll, so nothing is ever cut off. Unpicked chips fade
/// and get a dashed outline, so the state doesn't rely on color. Saved buses carry a star, and "Mine"
/// picks exactly those when more than one is saved.
struct ArrivingFilter: View {
    let routes: [TransitRoute]
    @Binding var filter: Set<TransitKey>
    var savedRoutes: Set<TransitKey> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("ARRIVING").font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Theme.muted)
                Spacer()
                if !filter.isEmpty {
                    Button("Show all \(routes.count)") { withAnimation(.spring(duration: 0.25)) { filter = [] } }
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                }
            }
            if routes.count > 1 {
                FlowRow(spacing: 6) {
                    if savedRoutes.count >= 2 {
                        let on = filter == savedRoutes
                        Button { withAnimation(.spring(duration: 0.25)) { filter = on ? [] : savedRoutes } } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 10, weight: .black))
                                Text("Mine").font(Theme.display(14))
                            }
                            .foregroundStyle(Color.busInk)
                            .padding(.horizontal, 9).frame(minWidth: 40).frame(height: 32)
                            .background(Color.busYellow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.edge, style: StrokeStyle(lineWidth: 2, dash: !filter.isEmpty && !on ? [4, 3] : [])))
                            .opacity(!filter.isEmpty && !on ? 0.5 : 1)
                        }
                        .buttonStyle(PressStyle())
                        .sensoryFeedback(.selection, trigger: on)
                        .accessibilityLabel("My saved buses")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    ForEach(routes) { route in
                        let on = filter.contains(route.id)
                        Button {
                            withAnimation(.spring(duration: 0.25)) { if on { filter.remove(route.id) } else { filter.insert(route.id) } }
                        } label: {
                            RouteChip(route: route, dimmed: !filter.isEmpty && !on, saved: savedRoutes.contains(route.id))
                        }
                        .buttonStyle(PressStyle())
                        .sensoryFeedback(.selection, trigger: on)
                        .accessibilityLabel("\(route.longName)\(savedRoutes.contains(route.id) ? ", saved" : "")")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }
}

struct RouteChip: View {
    let route: TransitRoute
    var dimmed = false
    /// One of the buses saved at this stop.
    var saved = false

    var body: some View {
        HStack(spacing: 3) {
            if saved { Image(systemName: "star.fill").font(.system(size: 10, weight: .black)) }
            Text(route.shortName).font(Theme.display(14))
        }
        .foregroundStyle(Color.readableInk(on: route.colorHex))
        .padding(.horizontal, 9).frame(minWidth: 40).frame(height: 32)
        .background(Color(hex: route.colorHex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(dimmed ? Theme.muted : Theme.edge, style: StrokeStyle(lineWidth: 2, dash: dimmed ? [4, 3] : [])))
        .opacity(dimmed ? 0.45 : 1)
    }
}

/// Shows what's about to be saved (every bus, or just some) and lets you adjust it before saving.
/// For a stop that's already saved, the same sheet changes or removes it.
struct SaveStopSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let stop: TransitStop
    @State private var draft: Set<TransitKey>

    init(stop: TransitStop, initial: Set<TransitKey>) {
        self.stop = stop
        _draft = State(initialValue: initial)
    }

    var body: some View {
        let entry = store.savedEntry(for: stop)
        let routes = store.routes(at: stop)
        let chosen = routes.filter { draft.contains($0.id) }
        let changed = entry.map { Set($0.routes) != draft } ?? true
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry == nil ? "SAVE THIS STOP" : "YOUR SAVED STOP").font(.system(size: 11.5, weight: .black)).tracking(1).foregroundStyle(Theme.muted)
                        Text(store.placeName(stop)).font(Theme.display(26)).foregroundStyle(Theme.ink)
                    }
                    // What you're saving, in plain words.
                    VStack(alignment: .leading, spacing: 10) {
                        Text(entry == nil || changed ? "YOU'RE SAVING" : "SAVED").font(.system(size: 11, weight: .black)).tracking(0.8).foregroundStyle(Color.busInk.opacity(0.7))
                        if chosen.isEmpty {
                            Text("Every bus at this stop").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color.busInk)
                        } else {
                            FlowRow(spacing: 6) { ForEach(chosen) { RouteChip(route: $0) } }
                            Text("Only \(chosen.count == 1 ? "this bus" : "these buses") will show on your Saved tab and widget.")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.busInk.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .chunky(fill: .busYellow, radius: 18, lift: 3)

                    Text("Pick the buses you ride from here, or keep every bus.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                    choice(title: "Every bus", subtitle: "All \(routes.count) that stop here", route: nil, on: draft.isEmpty) { draft = [] }
                    ForEach(routes) { route in
                        choice(title: route.longName, subtitle: route.agency.name, route: route, on: draft.contains(route.id)) {
                            if draft.contains(route.id) { draft.remove(route.id) } else { draft.insert(route.id) }
                        }
                    }
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                Button {
                    store.saveStop(stop, routes: routes.map(\.id).filter { draft.contains($0) })
                    dismiss()
                } label: {
                    Text(entry == nil ? (chosen.isEmpty ? "Save with every bus" : "Save with the \(busList(chosen))") : changed ? "Save changes" : "Done")
                        .font(.system(size: 17, weight: .black)).foregroundStyle(Color.busInk).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .chunky(fill: .busYellow, radius: 16)
                }
                .buttonStyle(PressStyle())
                if entry != nil {
                    Button(role: .destructive) {
                        store.toggleFavorite(stop)
                        dismiss()
                    } label: {
                        Text("Remove from saved").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity).frame(height: 40)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16)
            .background(Theme.surface)
        }
    }

    private func choice(title: String, subtitle: String, route: TransitRoute?, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.spring(duration: 0.2)) { action() } } label: {
            HStack(spacing: 12) {
                if let route { RouteTag(name: route.shortName, hex: route.colorHex, size: 38) }
                else { Image(systemName: "bus.fill").font(.system(size: 17, weight: .bold)).frame(width: 38, height: 38) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .heavy)).lineLimit(1)
                    Text(subtitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(on ? Theme.ink : Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .padding(10)
            .background(on ? Color.busYellow.opacity(0.35) : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2))
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.selection, trigger: on)
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
        StatusCard(kicker: kicker, title: title, sub: sub, fill: fill, ink: ink)
    }
}

/// The big "When to go" card. Also used for the trip screen's headline states.
struct StatusCard: View {
    let kicker: String
    let title: String
    let sub: String
    let fill: Color
    let ink: Color

    var body: some View {
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
                    Text(store.placeName(stop)).font(Theme.display(20)).foregroundStyle(Theme.ink).lineLimit(2)
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
                LocationService.shared.requestAlwaysForWidgetTracking()
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
            Text("Keeps location on in the background while tracking (you'll see the blue location pill), so the walk time stays current and it knows when you reach the stop. Tracking ends on its own once the bus has passed your stop.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
        .padding(20)
    }
}
