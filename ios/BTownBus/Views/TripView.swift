import SwiftUI
import MapKit

/// The trip sheet: walking to the stop, boarding, and riding, built from the same parts as a stop's
/// page (header, walk strip, When-to-go card, arrival rows, soft buttons) with a live map card on top.
///
/// Opened from the trip banner, or from a stop's "Walk to stop" (`walkOnlyStop`, no tracked bus).
struct TripView: View {
    var walkOnlyStop: TransitStop? = nil

    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var guide = WalkingGuide.shared
    @State private var choosingDestination = false
    @State private var showSteps = false
    @State private var trackTarget: TransitArrival?
    @State private var navigating = false

    enum Stage { case walking, missed, riding }

    // MARK: State

    /// A tracked trip whose pickup is this sheet's stop.
    private var trip: TripWatch? {
        guard let watch = tracker.watch else { return nil }
        if let walkOnlyStop, watch.stopKey != walkOnlyStop.id { return nil }
        return watch
    }

    private var stage: Stage {
        guard let trip else { return .walking }
        if trip.ride != nil { return .riding }
        return tracker.status?.phase == .boarding ? .missed : .walking
    }

    private var pickup: TransitStop? { trip.flatMap { store.stop($0.stopKey) } ?? walkOnlyStop }

    private var destination: TransitStop? {
        guard let trip, let ride = trip.ride else { return nil }
        return store.stop(TransitKey(agency: trip.agency, id: ride.destinationId))
    }

    /// The bus that matters: the tracked one, or the next one due at this stop.
    private var arrival: TransitArrival? {
        if trip != nil { return tracker.status?.arrival }
        return pickup.map { store.arrivals(at: $0.id) }?.first
    }

    private var bus: TransitVehicle? {
        if trip != nil { return tracker.status?.vehicle }
        return arrival.flatMap { store.vehicle($0.agency, $0.vehicleId) }
    }

    private var route: TransitRoute? {
        if let trip { return store.route(trip.routeKey) }
        return arrival.flatMap { store.route($0.routeKey) }
    }

    private var agency: Agency { trip?.agency ?? pickup?.agency ?? .bt }
    private var routeName: String { route?.shortName ?? trip?.routeId ?? arrival?.routeId ?? "Bus" }
    private var routeHex: String { route?.colorHex ?? agency.colorHex }

    private var atPickup: Bool {
        guard let pickup else { return false }
        return location.isAtStop(pickup) || (guide.destination?.id == pickup.id && guide.arrived)
    }

    /// Walking seconds: along the Apple Maps route while guiding, otherwise the usual estimate.
    private var walkSeconds: Int? {
        if atPickup { return 0 }
        if guide.route != nil, guide.destination?.id == pickup?.id { return Int(guide.remainingSeconds) }
        return pickup.flatMap { location.walkSeconds(to: $0) }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch stage {
                case .walking: walking
                case .missed: missed
                case .riding: riding
                }
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 30)
        }
        .background(Theme.surface)
        .sheet(isPresented: $choosingDestination) {
            DestinationPicker(routeName: routeName, routeHex: routeHex) { index in
                if tracker.board(destinationIndex: index) { choosingDestination = false }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.surface)
        }
        .sheet(isPresented: $showSteps) {
            StepsSheet(guide: guide, stopName: pickup?.name ?? "")
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
        }
        .sheet(item: $trackTarget) { arrival in
            if let pickup {
                TrackSheet(stop: pickup, arrival: arrival) {}
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.surface)
            }
        }
        .onAppear(perform: startWalkingIfNeeded)
        .onDisappear { if !navigating { guide.stop() } }
        .fullScreenCover(isPresented: $navigating) {
            if let pickup { WalkNavigationView(pickup: pickup, tracked: trip != nil) }
        }
        .onChange(of: stage) { _, newStage in
            if newStage == .riding { guide.stop() } else { startWalkingIfNeeded() }
        }
        .onChange(of: tracker.watch == nil) { _, ended in if ended, walkOnlyStop == nil { dismiss() } }
    }

    // MARK: Walking

    @ViewBuilder private var walking: some View {
        header(eyebrow: trip == nil ? "WALK TO \(agency.name.uppercased()) STOP" : "CATCHING THE \(routeName.uppercased()) AT",
               title: pickup?.name ?? "Your stop")
        TripMap(stage: .walking, pickup: pickup, destination: nil, bus: bus, route: route, routeHex: routeHex,
                walk: guide.destination?.id == pickup?.id ? guide.route : nil, stopsAhead: stopsAhead(to: pickup))
        walkStrip
        if guide.choosingRoute {
            routeChoices
        } else if let arrival, let plan = TripMath.leavePlan(busArrival: arrival.predictedArrival, walkSeconds: walkSeconds, atStop: atPickup) {
            LeaveCard(arrival: arrival, route: route, plan: plan)
        }

        if let trip {
            sectionLabel("YOUR BUS")
            busRow(trip: trip)
            if atPickup {
                yellowButton("I'm on the bus", symbol: "bus.fill") { choosingDestination = true }
            } else {
                yellowButton("Start walking", symbol: "location.north.line.fill") { navigating = true }
                softButton("I'm on the bus", symbol: "bus.fill") { choosingDestination = true }
            }
            HStack(spacing: 8) {
                softButton("Steps", symbol: "list.bullet") { showSteps = true }.disabled(guide.steps.isEmpty)
                softButton("Apple Maps", symbol: "map") { openInMaps() }
                softButton("Stop", symbol: "xmark") { tracker.stop(); dismiss() }
            }
        } else if let pickup {
            if !atPickup { yellowButton("Start walking", symbol: "location.north.line.fill") { navigating = true } }
            sectionLabel("ARRIVING")
            let arrivals = store.arrivals(at: pickup.id)
            if arrivals.isEmpty {
                emptyNote(store.arrivalsLoadedFor.contains(pickup.id) ? "No buses predicted for this stop right now." : "Checking arrival times…")
            }
            ForEach(arrivals.prefix(6)) { arrival in
                ArrivalRow(arrival: arrival, tracking: tracker.isTracking(arrival)) {
                    if tracker.isTracking(arrival) { tracker.stop() } else { trackTarget = arrival }
                }
            }
            HStack(spacing: 8) {
                softButton("Steps", symbol: "list.bullet") { showSteps = true }.disabled(guide.steps.isEmpty)
                softButton("Apple Maps", symbol: "map") { openInMaps() }
            }
        }
        if !guide.choosingRoute, guide.alternatives.count > 1 {
            Button("Use a different walking route") { guide.changeRoute() }
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var walkStrip: some View {
        if atPickup {
            strip(fill: Theme.go, ink: Theme.goInk) {
                Circle().fill(Theme.goInk).frame(width: 12, height: 12)
                Text("You're at this stop").font(.system(size: 16, weight: .heavy))
            }
        } else if !location.isAuthorized {
            Button { location.requestPermission() } label: {
                Label("Turn on location for walking directions", systemImage: "location.fill")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Theme.me, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        } else if guide.route != nil, !guide.steps.isEmpty {
            strip(fill: Theme.soft, ink: Theme.ink) {
                Image(systemName: guide.maneuverSymbol).font(.system(size: 18, weight: .black)).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(guide.instruction).font(.system(size: 16, weight: .heavy)).lineLimit(2)
                    Text("In \(formatDistance(guide.maneuverDistance)) · \(minutes(walkSeconds)) min walk · \(formatDistance(guide.remainingDistance)) to go")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
        } else if location.isApproximate, guide.route == nil {
            Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                Label("Precise Location is off. Tap to turn it on for walking directions.", systemImage: "location.slash.fill")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Theme.me, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        } else {
            strip(fill: Theme.soft, ink: Theme.ink) {
                Image(systemName: "figure.walk")
                Text(guide.problem ?? (walkSeconds.map { "\(minutes($0)) min walk" } ?? "Finding your way…"))
                    .font(.system(size: 16, weight: .heavy)).lineLimit(2)
            }
        }
    }

    private func busRow(trip: TripWatch) -> some View {
        let away = tracker.status?.stopsAway
        let minutes = arrival?.minutes()
        return HStack(spacing: 10) {
            RouteTag(name: routeName, hex: routeHex, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival?.destination ?? bus?.direction ?? route?.longName ?? "On the way").font(.system(size: 15, weight: .heavy)).lineLimit(2)
                Text(away.map { "\($0) \($0 == 1 ? "stop" : "stops") away" } ?? (bus == nil ? "Waiting for the bus's position" : "On the map"))
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                if let minutes, let arrival {
                    Text(minutes == 0 ? "Now" : minutes >= 60 ? shortClock(arrival.predictedArrival) : "\(minutes)")
                        .font(Theme.display(minutes >= 60 ? 18 : 26)).monospacedDigit()
                    if minutes > 0, minutes < 60 { Text("min").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted) }
                } else {
                    Text("—").font(Theme.display(26))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.trailing, 6)
        }
        .padding(8)
        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
    }

    private var routeChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PICK A WALKING ROUTE")
            ForEach(Array(guide.alternatives.enumerated()), id: \.offset) { index, choice in
                Button { guide.selectRoute(at: index) } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.name.isEmpty ? "Route \(index + 1)" : "Via \(choice.name)").font(.system(size: 15, weight: .heavy)).lineLimit(1)
                            Text(formatDistance(choice.distance)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("\(minutes(Int(choice.expectedTravelTime)))").font(Theme.display(26)).monospacedDigit()
                        Text("min").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: Missed

    @ViewBuilder private var missed: some View {
        header(eyebrow: "THE \(routeName.uppercased()) HAS LEFT", title: pickup?.name ?? "Your stop")
        TripMap(stage: .walking, pickup: pickup, destination: nil, bus: bus, route: route, routeHex: routeHex, walk: nil, stopsAhead: [])
        StatusCard(kicker: "DID YOU CATCH IT?", title: "On the \(routeName)?",
                   sub: "Pick your stop and we'll tell you when to ring the bell.", fill: .busYellow, ink: .busInk)
        yellowButton("I'm on it · pick my stop", symbol: "bus.fill") { choosingDestination = true }
        HStack(spacing: 8) {
            softButton("Missed it", symbol: "arrow.clockwise") { tracker.missedBus() }
            softButton("Stop", symbol: "xmark") { tracker.stop(); dismiss() }
        }
        Text("Missed it follows the next \(routeName) to this stop instead.")
            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
    }

    // MARK: Riding

    @ViewBuilder private var riding: some View {
        if let trip, let ride = trip.ride {
            header(eyebrow: "RIDING THE \(routeName.uppercased()) TO", title: ride.destinationName)
            TripMap(stage: .riding, pickup: nil, destination: destination, bus: bus, route: route, routeHex: routeHex,
                    walk: nil, stopsAhead: stopsAhead(to: destination))
            if ride.atDestination {
                StatusCard(kicker: "THIS IS YOUR STOP", title: "Get off here", sub: ride.destinationName, fill: Theme.go, ink: Theme.goInk)
            } else if ride.requestStop {
                StatusCard(kicker: "YOUR STOP IS NEXT", title: "Ring the bell", sub: "Pull the cord for \(ride.destinationName).", fill: .busInk, ink: .busYellow)
            } else {
                StatusCard(kicker: "STOPS TO GO", title: "\(ride.remainingStops) stops",
                           sub: "We'll tell you when to ring the bell.", fill: .busYellow, ink: .busInk)
            }
            if let problem = tracker.rideProblem {
                strip(fill: Theme.soft, ink: Theme.muted) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    Text(problem).font(.system(size: 13.5, weight: .semibold))
                }
            }
            sectionLabel("STOPS LEFT")
            stopsLeft(ride: ride, agency: trip.agency)
            yellowButton(ride.atDestination ? "I'm off · end trip" : "I got off", symbol: "figure.walk.departure",
                         fill: ride.atDestination ? Theme.go : .busYellow, ink: ride.atDestination ? Theme.goInk : .busInk) { tracker.stop() }
            HStack(spacing: 8) {
                softButton("Change stop", symbol: "mappin.and.ellipse") { choosingDestination = true }
                softButton("Stop", symbol: "xmark") { tracker.stop() }
            }
        }
    }

    /// The stops left, in an outlined card like the arrival rows, with the route's color as the line.
    private func stopsLeft(ride: RideJourney, agency: Agency) -> some View {
        let start = min(max(ride.departed, 1), ride.visits.count - 1)
        let upcoming = Array(ride.visits[start...])
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(upcoming.enumerated()), id: \.offset) { index, id in
                let last = index == upcoming.count - 1
                HStack(spacing: 12) {
                    ZStack {
                        Rectangle().fill(Color(hex: routeHex)).frame(width: 5)
                            .padding(.top, index == 0 ? 22 : 0).padding(.bottom, last ? 22 : 0)
                        Circle().fill(last ? Color.busYellow : Theme.surface)
                            .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 2.5))
                            .frame(width: last ? 18 : 13, height: last ? 18 : 13)
                    }
                    .frame(width: 22, height: 44)
                    Text(store.stop(TransitKey(agency: agency, id: id))?.name ?? "Stop")
                        .font(.system(size: 15, weight: last || index == 0 ? .heavy : .semibold))
                        .foregroundStyle(last || index == 0 ? Theme.ink : Theme.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    if last {
                        Text("YOUR STOP").font(.system(size: 10, weight: .black)).foregroundStyle(Color.busInk)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.busYellow, in: Capsule())
                    } else if index == 0 {
                        Text("NEXT").font(.system(size: 10, weight: .black)).tracking(0.6).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
    }

    // MARK: Parts (same look as the stop page)

    private func header(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: agency.colorHex)).frame(width: 9, height: 9)
                Text(eyebrow).font(.system(size: 11.5, weight: .black)).tracking(0.8).lineLimit(1)
            }
            .foregroundStyle(Theme.muted)
            Text(title).font(Theme.display(30)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 4)
    }

    private func strip<Content: View>(fill: Color, ink: Color, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(fill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity).padding(20)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
    }

    /// Same as "Start tracking".
    private func yellowButton(_ title: String, symbol: String, fill: Color = .busYellow, ink: Color = .busInk, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 17, weight: .black)).foregroundStyle(ink)
                .frame(maxWidth: .infinity).frame(height: 54)
                .chunky(fill: fill, radius: 16)
        }
        .buttonStyle(PressStyle())
        .padding(.top, 4)
    }

    /// Same as "Save stop".
    private func softButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .black)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 46)
                .chunky(fill: Theme.soft, radius: 15, lift: 2)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Behavior

    private func stopsAhead(to target: TransitStop?) -> [TransitStop] {
        guard let bus, let target, let visits = TripMath.upcomingVisits(route: route, vehicle: bus),
              let end = visits.firstIndex(of: target.stopId) else { return [] }
        return visits[..<end].compactMap { store.stop(TransitKey(agency: target.agency, id: $0)) }
    }

    private func minutes(_ seconds: Int?) -> Int { max(1, Int((Double(seconds ?? 0) / 60).rounded())) }

    private func startWalkingIfNeeded() {
        guard stage != .riding, let pickup, location.isAuthorized else { return }
        guide.start(to: pickup, showsLiveActivity: trip == nil)
    }

    private func openInMaps() {
        guard let pickup else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pickup.coordinate))
        item.name = pickup.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

// MARK: - Map card

/// The live map, drawn exactly like the Map tab, inside an outlined card. It keeps you, the bus,
/// and your stop in view as they move, until you pan it yourself.
private struct TripMap: View {
    let stage: TripView.Stage
    let pickup: TransitStop?
    let destination: TransitStop?
    let bus: TransitVehicle?
    let route: TransitRoute?
    let routeHex: String
    let walk: MKRoute?
    let stopsAhead: [TransitStop]

    @Environment(LocationService.self) private var location
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: AppStore.downtown.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
    @State private var framing = true

    private var target: TransitStop? { stage == .riding ? destination : pickup }

    var body: some View {
        Map(position: $camera) {
            if let route, !route.path.isEmpty {
                MapPolyline(coordinates: route.path).stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.path).stroke(Color(hex: routeHex), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            if let walk {
                MapPolyline(walk.polyline).stroke(Color.busInk, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(walk.polyline).stroke(Color.busYellow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(stopsAhead) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    Circle().fill(.white).overlay(Circle().strokeBorder(Color.busInk, lineWidth: 2)).frame(width: 11, height: 11)
                }
                .annotationTitles(.hidden)
            }
            if let target {
                // Your stop: the same yellow dot as a saved stop on the Map tab, a size up.
                Annotation(target.name, coordinate: target.coordinate, anchor: .center) {
                    Circle().fill(Color.busYellow).overlay(Circle().strokeBorder(Color.busInk, lineWidth: 3)).frame(width: 20, height: 20)
                }
                .annotationTitles(.hidden)
            }
            if let bus, let route {
                Annotation(route.shortName, coordinate: bus.coordinate, anchor: .center) {
                    BusMarker(label: route.shortName, hex: routeHex, heading: bus.heading, stale: bus.isStale, tracked: true)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.edge).offset(y: 4))
        .overlay(alignment: .topTrailing) {
            Button {
                framing = true
                frame()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(framing ? Color.busInk : Theme.ink)
                    .frame(width: 42, height: 42)
                    .chunky(fill: framing ? .busYellow : Theme.surface, radius: 14, lift: 3)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(stage == .riding ? "Show the bus and your stop" : "Show you, the bus, and your stop")
            .padding(10)
        }
        .onAppear { frame(animated: false) }
        .onChange(of: bus?.updatedAt) { _, _ in if framing { frame() } }
        .onChange(of: location.location?.timestamp) { _, _ in if framing { frame() } }
        .onChange(of: walk?.distance) { _, _ in if framing { frame() } }
        .onChange(of: stage) { _, _ in framing = true; frame() }
        .onChange(of: camera.positionedByUser) { _, moved in if moved { framing = false } }
    }

    /// You, the bus, and the stop that matters (your pickup, or your destination while riding).
    private func frame(animated: Bool = true) {
        var points: [CLLocationCoordinate2D] = []
        if let me = location.location?.coordinate { points.append(me) }
        if let target { points.append(target.coordinate) }
        if let bus { points.append(bus.coordinate) }
        if let walk { points.append(contentsOf: walk.polyline.coordinates(every: 12)) }
        guard !points.isEmpty else { return }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.45, 0.004),
                                   longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.3, 0.004)))
        if animated { withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) } } else { camera = .region(region) }
    }
}

// MARK: - Picking your stop

/// Laid out like the route picker: a big title, then outlined rows for the stops this bus makes next.
private struct DestinationPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    let routeName: String
    let routeHex: String
    let choose: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where are you getting off?").font(Theme.display(30)).foregroundStyle(Theme.ink)
                Text("The stops this \(routeName) makes next, in order. We'll tell you when to ring the bell.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                if let options = tracker.boardingOptions {
                    ForEach(Array(options.stops.enumerated()), id: \.offset) { index, stop in
                        Button { choose(index) } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(Theme.display(16)).foregroundStyle(Color.readableInk(on: routeHex))
                                    .frame(width: 38, height: 38)
                                    .background(Color(hex: routeHex), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name).font(.system(size: 15, weight: .heavy)).multilineTextAlignment(.leading)
                                    Text(index == 0 ? "Next stop" : "\(index + 1) stops").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 4)
                                if store.isFavorite(stop) { Image(systemName: "star.fill").foregroundStyle(Color.busYellow) }
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(8)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
                        }
                        .buttonStyle(PressStyle())
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(tracker.status?.vehicle == nil
                             ? "Waiting for the bus to report where it is."
                             : "This bus hasn't reported its position for a while, so its next stops aren't known yet.")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
                }
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 30)
        }
        .background(Theme.surface)
    }
}

// MARK: - Walking steps

private struct StepsSheet: View {
    let guide: WalkingGuide
    let stopName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your walk").font(Theme.display(30)).foregroundStyle(Theme.ink)
                Text(stopName).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    let done = index < guide.stepIndex, current = index == guide.stepIndex
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark" : "figure.walk").font(.system(size: 15, weight: .black))
                            .foregroundStyle(current ? Color.busInk : Theme.ink).frame(width: 38, height: 38)
                            .background(current ? Color.busYellow : Theme.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.instructions).font(.system(size: 15, weight: .heavy))
                            Text(formatDistance(step.distance)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
                    .opacity(done ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 30)
        }
        .background(Theme.surface)
    }
}

extension MKPolyline {
    /// Every nth point, enough to frame the line without copying all of it.
    func coordinates(every step: Int) -> [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        let all = points()
        return Swift.stride(from: 0, to: pointCount, by: max(1, step)).map { all[$0].coordinate } + [all[pointCount - 1].coordinate]
    }
}
