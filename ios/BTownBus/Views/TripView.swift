import SwiftUI
import MapKit

/// The whole journey on one screen: walking to the stop with the bus on the map, boarding, and riding.
///
/// Opened from the trip banner (a tracked trip), or from a stop's "Walk to stop" (no trip; the race
/// is against the next bus due at that stop).
struct TripView: View {
    /// Set when opened from a stop without tracking a bus there.
    var walkOnlyStop: TransitStop? = nil

    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var guide = WalkingGuide.shared
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: AppStore.downtown.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
    @State private var cameraMode: CameraMode = .overview
    @State private var lastFitOrigin: CLLocation?
    @State private var choosingDestination = false
    @State private var showSteps = false
    @State private var startedTrip = false

    enum CameraMode { case overview, follow, free }
    enum Stage { case walking, missed, riding }

    // MARK: What's on screen

    /// A tracked trip whose pickup is this screen's stop.
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

    /// The arrival the race is against: the tracked bus, or the next bus due at this stop.
    private var arrival: TransitArrival? {
        if trip != nil { return tracker.status?.arrival }
        guard let pickup else { return nil }
        let due = store.arrivals(at: pickup.id)
        return due.first { $0.vehicleId != nil } ?? due.first
    }

    private var bus: TransitVehicle? {
        if trip != nil { return tracker.status?.vehicle }
        return arrival.flatMap { store.vehicle($0.agency, $0.vehicleId) }
    }

    private var route: TransitRoute? {
        if let trip { return store.route(trip.routeKey) }
        return arrival.flatMap { store.route($0.routeKey) }
    }

    private var routeHex: String { route?.colorHex ?? (trip?.agency ?? pickup?.agency ?? .bt).colorHex }

    private var destination: TransitStop? {
        guard let trip, let ride = trip.ride else { return nil }
        return store.stop(TransitKey(agency: trip.agency, id: ride.destinationId))
    }

    /// Stops between the bus and where it matters (your pickup, or your destination while riding).
    private var stopsAhead: [TransitStop] {
        guard let bus, let target = stage == .riding ? destination : pickup,
              let visits = TripMath.upcomingVisits(route: route, vehicle: bus),
              let end = visits.firstIndex(of: target.stopId) else { return [] }
        return visits[..<end].compactMap { store.stop(TransitKey(agency: target.agency, id: $0)) }
    }

    private var atPickup: Bool { pickup.map { location.isAtStop($0) || (guide.destination?.id == $0.id && guide.arrived) } ?? false }

    private var walkMinutes: Int? {
        if atPickup { return 0 }
        if guide.route != nil, guide.destination?.id == pickup?.id { return max(1, Int(ceil(guide.remainingSeconds / 60))) }
        return pickup.flatMap { location.walkSeconds(to: $0) }.map { max(1, Int((Double($0) / 60).rounded())) }
    }

    // MARK: Body

    var body: some View {
        Map(position: $camera) {
            mapContent
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    topCard
                    CircleButton(symbol: "xmark", label: "Close") { dismiss() }
                }
                mapButtons
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .sheet(isPresented: $choosingDestination) {
            DestinationPicker(routeHex: routeHex, routeName: route?.shortName ?? "") { index in
                if tracker.board(destinationIndex: index) {
                    choosingDestination = false
                    cameraMode = .overview
                    refit(force: true)
                }
            }
            .presentationDetents([.large])
            .presentationBackground(Theme.bg)
        }
        .sheet(isPresented: $showSteps) { StepsSheet(guide: guide, stopName: pickup?.name ?? "") }
        .onAppear {
            startWalkingIfNeeded()
            refit(force: true)
        }
        .onDisappear { guide.stop() }
        .onChange(of: stage) { _, newStage in
            if newStage == .riding { guide.stop() } else { startWalkingIfNeeded() }
            cameraMode = .overview
            refit(force: true)
        }
        .onChange(of: bus?.updatedAt) { _, _ in refit() }
        .onChange(of: location.location?.timestamp) { _, _ in refit() }
        .onChange(of: location.heading) { _, _ in if cameraMode == .follow { follow() } }
        .onChange(of: guide.route?.distance) { _, _ in refit(force: true) }
        .onChange(of: camera.positionedByUser) { _, moved in if moved { cameraMode = .free } }
        .onChange(of: tracker.watch == nil) { _, ended in if ended, walkOnlyStop == nil { dismiss() } }
    }

    // MARK: Map

    @MapContentBuilder private var mapContent: some MapContent {
        if let route, !route.path.isEmpty {
            MapPolyline(coordinates: route.path).stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: route.path).stroke(Color(hex: routeHex).opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if stage != .riding, let walk = guide.route, guide.destination?.id == pickup?.id {
            // Cream outline so the walk reads on both the light and the dark map.
            MapPolyline(walk.polyline).stroke(Color.busCream, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            MapPolyline(walk.polyline).stroke(Color.busInk, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            MapPolyline(walk.polyline).stroke(Color.busYellow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        ForEach(stopsAhead.indices, id: \.self) { index in
            let stop = stopsAhead[index]
            Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                Circle().fill(.white).overlay(Circle().strokeBorder(Color(hex: routeHex), lineWidth: 3)).frame(width: 12, height: 12)
            }
            .annotationTitles(.hidden)
        }
        if stage == .riding, let destination {
            Annotation(destination.name, coordinate: destination.coordinate, anchor: .bottom) {
                StopPin(symbol: "flag.checkered", fill: .goGreen)
            }
            .annotationTitles(.hidden)
        } else if let pickup {
            Annotation(pickup.name, coordinate: pickup.coordinate, anchor: .bottom) {
                StopPin(symbol: "bus.fill", fill: .busYellow)
            }
            .annotationTitles(.hidden)
        }
        if let bus, let label = route?.shortName {
            Annotation(label, coordinate: bus.coordinate, anchor: .center) {
                BusMarker(label: label, hex: routeHex, heading: bus.heading, stale: bus.isStale, tracked: true)
            }
            .annotationTitles(.hidden)
        }
        UserAnnotation()
    }

    private var mapButtons: some View {
        HStack(spacing: 10) {
            if stage == .walking, guide.route != nil {
                SquareButton(symbol: "list.bullet", label: "Walking steps") { showSteps = true }
            }
            SquareButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Show everything", on: cameraMode == .overview) {
                cameraMode = .overview
                refit(force: true)
            }
            SquareButton(symbol: "location.north.line.fill", label: "Follow", on: cameraMode == .follow) {
                cameraMode = .follow
                follow()
            }
        }
    }

    // MARK: Top card

    @ViewBuilder private var topCard: some View {
        switch stage {
        case .riding:
            if let ride = trip?.ride {
                if ride.atDestination {
                    SignCard(kicker: "THIS IS YOUR STOP", title: "Get off here", detail: ride.destinationName, symbol: "figure.walk.departure", tile: .goGreen)
                } else if ride.requestStop {
                    SignCard(kicker: "YOUR STOP IS NEXT", title: "Ring the bell", detail: ride.destinationName, symbol: "bell.fill", tile: .busYellow, alarm: true)
                } else {
                    SignCard(kicker: "NEXT STOP", title: ride.nextStopId.flatMap { store.stop(TransitKey(agency: trip!.agency, id: $0))?.name } ?? "On the way",
                             detail: "\(ride.remainingStops) stops to \(ride.destinationName)", symbol: "bus.fill", tile: Color(hex: routeHex), tileInk: Color.readableInk(on: routeHex), titleSize: 22)
                }
            }
        case .missed:
            SignCard(kicker: "THE BUS HAS LEFT", title: "Did you catch it?", detail: pickup?.name ?? "", symbol: "questionmark", tile: .busYellow)
        case .walking:
            if atPickup {
                SignCard(kicker: "YOU'RE AT THE STOP", title: "Wait here", detail: pickup?.name ?? "", symbol: "checkmark", tile: .goGreen)
            } else if guide.choosingRoute {
                SignCard(kicker: "YOUR WALK", title: "Pick a path", detail: "We'll remember it for this stop.", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", tile: .busYellow)
            } else if guide.route != nil {
                SignCard(kicker: guide.loading ? "REROUTING" : "IN \(formatDistance(guide.maneuverDistance).uppercased())",
                         title: guide.instruction, detail: nil, symbol: guide.maneuverSymbol, tile: .busYellow, titleSize: 20)
            } else if let problem = guide.problem {
                SignCard(kicker: "WALKING DIRECTIONS", title: "Not available", detail: problem, symbol: "exclamationmark", tile: .warnOrange)
            } else {
                SignCard(kicker: "WALKING DIRECTIONS", title: "Finding your way", detail: pickup?.name ?? "", symbol: "location.fill", tile: .busYellow)
            }
        }
    }

    // MARK: Bottom panel

    @ViewBuilder private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch stage {
            case .walking:
                if guide.choosingRoute { RouteChoices(guide: guide) } else { racePanel }
            case .missed:
                missedPanel
            case .riding:
                ridePanel
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chunky(fill: Theme.surface, radius: 26, lift: 5)
    }

    private var racePanel: some View {
        let busMinutes = arrival?.minutes()
        return VStack(alignment: .leading, spacing: 14) {
            PanelHeader(routeName: route?.shortName, routeHex: routeHex, kicker: trip == nil ? "NEXT BUS AT" : "CATCHING THE BUS AT", title: pickup?.name ?? "Your stop")
            RaceLanes(walkMinutes: walkMinutes, busMinutes: busMinutes, busStops: trip != nil ? tracker.status?.stopsAway : arrival.flatMap { store.stopsAway(for: $0) },
                      routeName: route?.shortName ?? "Bus", routeHex: routeHex, atStop: atPickup)
            Verdict(walkMinutes: walkMinutes, busMinutes: busMinutes, atStop: atPickup, hasBus: arrival != nil, busOnMap: bus != nil)
            HStack(spacing: 10) {
                if trip != nil {
                    PrimaryButton(title: "I'm on the bus", symbol: "bus.fill") { choosingDestination = true }
                    tripMenu
                } else if let arrival, arrival.vehicleId != nil {
                    PrimaryButton(title: startedTrip ? "Tracking" : "Track this bus", symbol: "dot.radiowaves.left.and.right") {
                        tracker.start(TripWatch(agency: arrival.agency, routeId: arrival.routeId, stopId: arrival.stopId, vehicleId: arrival.vehicleId,
                                                threshold: UserDefaults.standard.object(forKey: "threshold") as? Int ?? 5, createdAt: .now))
                        startedTrip = true
                    }
                    .disabled(startedTrip)
                    walkMenu
                } else {
                    PrimaryButton(title: "Done", symbol: "checkmark") { dismiss() }
                    walkMenu
                }
            }
        }
    }

    private var missedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(routeName: route?.shortName, routeHex: routeHex, kicker: "THE \(route?.shortName.uppercased() ?? "BUS") LEFT", title: pickup?.name ?? "Your stop")
            Text("If you got on, pick your stop and we'll tell you when to ring the bell. If not, we'll follow the next \(route?.shortName ?? "bus").")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                PrimaryButton(title: "I'm on it", symbol: "bus.fill") { choosingDestination = true }
                SecondaryButton(title: "Missed it", symbol: "arrow.clockwise") { tracker.missedBus() }
            }
        }
    }

    @ViewBuilder private var ridePanel: some View {
        if let trip, let ride = trip.ride {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    PanelHeader(routeName: route?.shortName, routeHex: routeHex, kicker: "RIDING TO", title: ride.destinationName)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("\(ride.remainingStops)").font(Theme.display(34)).monospacedDigit()
                        Text(ride.remainingStops == 1 ? "STOP" : "STOPS").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                }
                RideLadder(ride: ride, agency: trip.agency, routeHex: routeHex)
                if let problem = tracker.rideProblem {
                    Label(problem, systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 10) {
                    PrimaryButton(title: ride.atDestination ? "I'm off · End trip" : "I got off", symbol: "figure.walk.departure",
                                  fill: ride.atDestination ? .goGreen : .busYellow) { tracker.stop() }
                    Menu {
                        Button("Change my stop", systemImage: "mappin.and.ellipse") { choosingDestination = true }
                        Button("Stop tracking", systemImage: "xmark.circle", role: .destructive) { tracker.stop() }
                    } label: { MenuLabel() }
                }
            }
        }
    }

    private var tripMenu: some View {
        Menu {
            Button("Change walking route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { guide.changeRoute() }
            Button("Walk with Apple Maps", systemImage: "map") { openInMaps() }
            Button("Stop tracking", systemImage: "xmark.circle", role: .destructive) { tracker.stop(); dismiss() }
        } label: { MenuLabel() }
    }

    private var walkMenu: some View {
        Menu {
            Button("Change walking route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { guide.changeRoute() }
            Button("Walk with Apple Maps", systemImage: "map") { openInMaps() }
        } label: { MenuLabel() }
    }

    // MARK: Behavior

    private func startWalkingIfNeeded() {
        guard stage != .riding, let pickup else { return }
        guide.start(to: pickup, showsLiveActivity: trip == nil)
    }

    /// Frame you, your stop, and the bus (or the bus and your destination while riding).
    private func refit(force: Bool = false) {
        switch cameraMode {
        case .free: return
        case .follow: follow(); return
        case .overview: break
        }
        // Don't chase every GPS fix; refit when you've moved a bit or something else changed.
        if !force, let fix = location.location, let last = lastFitOrigin, fix.distance(from: last) < 20, bus == nil { return }
        lastFitOrigin = location.location
        var points: [CLLocationCoordinate2D] = []
        if let me = location.freshLocation?.coordinate { points.append(me) }
        if stage == .riding {
            if let destination { points.append(destination.coordinate) }
            if let bus, !bus.isStale { points.append(bus.coordinate) }
        } else {
            if let pickup { points.append(pickup.coordinate) }
            // Only pull the camera out for a bus that's reasonably close; otherwise the walk becomes tiny.
            if let bus, let pickup, bus.coordinateLocation.distance(from: pickup.location) < 4000 { points.append(bus.coordinate) }
            if let walk = guide.route, guide.destination?.id == pickup?.id { points.append(contentsOf: walk.polyline.coordinates(every: 12)) }
        }
        guard let region = Self.region(fitting: points) else { return }
        withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
    }

    private func follow() {
        if stage == .riding {
            guard let center = bus.map(\.coordinate) ?? location.freshLocation?.coordinate else { return }
            withAnimation(.easeInOut(duration: 0.6)) { camera = .camera(MapCamera(centerCoordinate: center, distance: 1400)) }
            return
        }
        guard let fix = location.freshLocation else { return }
        let heading = location.heading ?? (fix.course >= 0 && fix.speed > 0.5 ? fix.course : 0)
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 260, heading: heading, pitch: 50))
        }
    }

    /// A region that keeps `points` in the gap between the top card and the bottom panel.
    static func region(fitting points: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let latSpan = max(lats.max()! - lats.min()!, 0.0025), lngSpan = max(lngs.max()! - lngs.min()!, 0.003)
        let top = 0.24, bottom = 0.42
        let fullLat = latSpan / (1 - top - bottom), fullLng = lngSpan / 0.78
        let centerLat = (lats.max()! + lats.min()!) / 2 - fullLat * (bottom - top) / 2
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLat, longitude: (lngs.max()! + lngs.min()!) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: fullLat, longitudeDelta: fullLng))
    }

    private func openInMaps() {
        guard let pickup else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pickup.coordinate))
        item.name = pickup.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

// MARK: - Race

/// You and the bus as two lanes heading for the same stop. Whoever's marker is nearer the flag gets there first.
private struct RaceLanes: View {
    let walkMinutes: Int?
    let busMinutes: Int?
    let busStops: Int?
    let routeName: String
    let routeHex: String
    let atStop: Bool

    var body: some View {
        let scale = Double(max(walkMinutes ?? 0, busMinutes ?? 0, 1)) * 1.15
        VStack(spacing: 10) {
            Lane(progress: atStop ? 1 : walkMinutes.map { 1 - Double($0) / scale }, icon: { YouDot() },
                 value: atStop ? "Here" : walkMinutes.map { "\($0) min" } ?? "—", caption: atStop ? "AT THE STOP" : "YOUR WALK")
            Lane(progress: busMinutes.map { 1 - Double($0) / scale }, icon: { BusDot(label: routeName, hex: routeHex) },
                 value: busMinutes.map { $0 == 0 ? "Now" : $0 >= 60 ? "Later" : "\($0) min" } ?? "—",
                 caption: busStops.map { $0 == 1 ? "NEXT STOP" : "\($0) STOPS AWAY" } ?? "THE BUS")
        }
    }

    private struct Lane<Icon: View>: View {
        let progress: Double?
        @ViewBuilder let icon: Icon
        let value: String
        let caption: String

        var body: some View {
            HStack(spacing: 12) {
                GeometryReader { geometry in
                    let width = geometry.size.width - 34
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.soft).frame(height: 10)
                        Capsule().fill(Theme.ink.opacity(0.85)).frame(width: max(0, width * min(1, max(0, progress ?? 0))) + 17, height: 10)
                            .opacity(progress == nil ? 0 : 1)
                        Image(systemName: "flag.checkered").font(.system(size: 13, weight: .black)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        icon.offset(x: width * min(1, max(0, progress ?? 0)))
                            .opacity(progress == nil ? 0.35 : 1)
                    }
                    .frame(height: 34)
                    .animation(.spring(duration: 0.6), value: progress)
                }
                .frame(height: 34)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value).font(Theme.display(19)).monospacedDigit().lineLimit(1)
                    Text(caption).font(.system(size: 9.5, weight: .black)).tracking(0.6).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(width: 92, alignment: .trailing)
            }
            .foregroundStyle(Theme.ink)
        }
    }
}

private struct YouDot: View {
    var body: some View {
        Image(systemName: "figure.walk").font(.system(size: 15, weight: .black)).foregroundStyle(.white)
            .frame(width: 34, height: 34).background(Theme.me, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5)).background(Circle().fill(Theme.edge).offset(y: 2))
    }
}

private struct BusDot: View {
    let label: String
    let hex: String
    var body: some View {
        Text(label).font(Theme.display(11)).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(Color.readableInk(on: hex))
            .frame(width: 34, height: 34).background(Color(hex: hex), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5)).background(Circle().fill(Theme.edge).offset(y: 2))
    }
}

/// One line on who gets there first.
private struct Verdict: View {
    let walkMinutes: Int?
    let busMinutes: Int?
    let atStop: Bool
    let hasBus: Bool
    var busOnMap = false

    var body: some View {
        let (text, symbol, fill, ink): (String, String, Color, Color) = {
            guard hasBus else {
                return (busOnMap ? "No time prediction yet · the bus is on the map" : "No bus is predicted for this stop right now", "clock", Theme.soft, Theme.ink)
            }
            guard let bus = busMinutes else { return ("Waiting for the bus's prediction", "clock", Theme.soft, Theme.ink) }
            if atStop { return (bus <= 1 ? "It's pulling up now" : "You made it · bus in \(bus) min", "checkmark.circle.fill", Theme.go, Theme.goInk) }
            guard let walk = walkMinutes else { return ("Turn on location to race the bus", "location.slash", Theme.soft, Theme.ink) }
            let spare = bus - walk
            if spare >= 3 { return ("\(spare) min to spare", "checkmark.circle.fill", Theme.go, Theme.goInk) }
            if spare >= 1 { return ("Tight · keep moving", "figure.walk.motion", Color.busYellow, Color.busInk) }
            if spare >= -2 { return ("The bus gets there first · hurry", "hare.fill", Theme.warn, .white) }
            return ("You'll likely miss this one", "exclamationmark.triangle.fill", Theme.warn, .white)
        }()
        Label(text, systemImage: symbol)
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Riding

/// The stops left, drawn like a line diagram: next stop first, your stop last.
private struct RideLadder: View {
    @Environment(AppStore.self) private var store
    let ride: RideJourney
    let agency: Agency
    let routeHex: String

    var body: some View {
        let upcoming = Array(ride.visits[min(max(ride.departed, 1), ride.visits.count - 1)...])
        let rows: [String?] = upcoming.count > 5 ? Array(upcoming.prefix(3)) + [nil] + [upcoming.last!] : upcoming
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, id in
                let isLast = index == rows.count - 1
                HStack(spacing: 12) {
                    ZStack {
                        Rectangle().fill(Color(hex: routeHex)).frame(width: 6)
                            .padding(.top, index == 0 ? 15 : 0).padding(.bottom, isLast ? 15 : 0)
                        if id != nil {
                            Circle().fill(isLast ? Color.busYellow : .white)
                                .overlay(Circle().strokeBorder(Theme.edge, lineWidth: isLast ? 3 : 2.5))
                                .frame(width: isLast ? 20 : 14, height: isLast ? 20 : 14)
                        }
                    }
                    .frame(width: 22, height: 30)
                    if let id {
                        Text(store.stop(TransitKey(agency: agency, id: id))?.name ?? "Stop")
                            .font(.system(size: isLast ? 16 : 14.5, weight: isLast ? .black : (index == 0 ? .heavy : .semibold)))
                            .foregroundStyle(isLast || index == 0 ? Theme.ink : Theme.muted).lineLimit(1)
                        if index == 0, !isLast { Tag(text: "NEXT") }
                        if isLast { Tag(text: "YOUR STOP", fill: .busYellow) }
                    } else {
                        Text("\(upcoming.count - 4) more stops").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Pick where you're getting off, from the stops the bus will actually visit next.
private struct DestinationPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let routeHex: String
    let routeName: String
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where are you getting off?").font(Theme.display(26)).foregroundStyle(Theme.ink)
                    Text("Stops this \(routeName) will make next, in order. We'll tell you when to ring the bell.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                }
                Spacer()
                CircleButton(symbol: "xmark", label: "Close") { dismiss() }
            }
            .padding(20)
            if let options = tracker.boardingOptions {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(options.stops.enumerated()), id: \.offset) { index, stop in
                            Button { choose(index) } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Rectangle().fill(Color(hex: routeHex)).frame(width: 6)
                                            .padding(.top, index == 0 ? 26 : 0).padding(.bottom, index == options.stops.count - 1 ? 26 : 0)
                                        Circle().fill(.white).overlay(Circle().strokeBorder(Theme.edge, lineWidth: 2.5)).frame(width: 16, height: 16)
                                    }
                                    .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stop.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                        Text(index == 0 ? "Next stop" : "\(index + 1) stops").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    if store.isFavorite(stop) { Image(systemName: "star.fill").foregroundStyle(Color.busYellow) }
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .black)).foregroundStyle(Theme.muted)
                                }
                                .frame(minHeight: 56)
                                .padding(.horizontal, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 30)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tracker.status?.vehicle == nil
                         ? "Waiting for the bus to report where it is."
                         : "This bus hasn't reported its position for a while, so its next stops aren't known yet.")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    SecondaryButton(title: "Try again", symbol: "arrow.clockwise") { tracker.appDidBecomeActive() }
                        .frame(maxWidth: 220)
                }
                .frame(maxWidth: .infinity).padding(30)
                Spacer()
            }
        }
    }
}

// MARK: - Walking

private struct RouteChoices: View {
    let guide: WalkingGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PICK A PATH").font(.system(size: 11, weight: .black)).tracking(1).foregroundStyle(Theme.muted)
            ForEach(Array(guide.alternatives.enumerated()), id: \.offset) { index, route in
                Button { guide.selectRoute(at: index) } label: {
                    HStack(spacing: 12) {
                        Text("\(max(1, Int(ceil(route.expectedTravelTime / 60))))").font(Theme.display(22)).monospacedDigit()
                            + Text(" min").font(.system(size: 12, weight: .black))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name.isEmpty ? "Route \(index + 1)" : "Via \(route.name)").font(.system(size: 15, weight: .heavy)).lineLimit(1)
                            Text(formatDistance(route.distance)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                    }
                    .foregroundStyle(Theme.ink).padding(12)
                    .chunky(fill: index == 0 ? Color.busYellow.opacity(0.35) : Theme.soft, radius: 14, lift: 2)
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

private struct StepsSheet: View {
    let guide: WalkingGuide
    let stopName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your walk").font(Theme.display(28)).foregroundStyle(Theme.ink)
                        Text(stopName).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    CircleButton(symbol: "xmark", label: "Close") { dismiss() }
                }
                .padding(.bottom, 6)
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 14) {
                        Image(systemName: index < guide.stepIndex ? "checkmark" : "arrow.up")
                            .font(.system(size: 16, weight: .black)).foregroundStyle(Color.busInk)
                            .frame(width: 36, height: 36)
                            .background(index == guide.stepIndex ? Color.busYellow : Theme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.instructions).font(.system(size: 15.5, weight: .heavy)).foregroundStyle(Theme.ink)
                            Text(formatDistance(step.distance)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(index < guide.stepIndex ? 0.5 : 1)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }
}

// MARK: - Pieces

/// The dark "transit sign" card at the top of the trip screen.
private struct SignCard: View {
    let kicker: String
    let title: String
    let detail: String?
    let symbol: String
    let tile: Color
    var tileInk: Color = .busInk
    var titleSize: CGFloat = 26
    var alarm = false
    @State private var ring = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(tileInk)
                .frame(width: 58, height: 58)
                .background(tile, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .rotationEffect(.degrees(alarm && ring ? 12 : 0))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker).font(.system(size: 10.5, weight: .black)).tracking(1).foregroundStyle(Color.busCream.opacity(0.6))
                Text(title).font(Theme.display(titleSize)).foregroundStyle(alarm ? Color.busYellow : Color.busCream)
                    .lineLimit(2).minimumScaleFactor(0.7)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 13.5, weight: .bold)).foregroundStyle(Color.busCream.opacity(0.8)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.busInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(alarm ? Color.busYellow : .black, lineWidth: 3))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black).offset(y: 5))
        .accessibilityElement(children: .combine)
        .onAppear {
            guard alarm else { return }
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) { ring = true }
        }
    }
}

private struct PanelHeader: View {
    let routeName: String?
    let routeHex: String
    let kicker: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            if let routeName { RouteTag(name: routeName, hex: routeHex, size: 44) }
            VStack(alignment: .leading, spacing: 1) {
                Text(kicker).font(.system(size: 10.5, weight: .black)).tracking(0.9).foregroundStyle(Theme.muted)
                Text(title).font(Theme.display(18, .heavy)).foregroundStyle(Theme.ink).lineLimit(2)
            }
        }
    }
}

private struct StopPin: View {
    let symbol: String
    let fill: Color
    var body: some View {
        VStack(spacing: -3) {
            Image(systemName: symbol).font(.system(size: 17, weight: .black)).foregroundStyle(Color.busInk)
                .frame(width: 42, height: 42).background(fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.busInk, lineWidth: 3))
            Triangle().fill(Color.busInk).frame(width: 14, height: 9).rotationEffect(.degrees(180))
        }
        .shadow(color: .black.opacity(0.25), radius: 0, y: 3)
    }
}

private struct Tag: View {
    let text: String
    var fill: Color = Theme.soft
    var body: some View {
        Text(text).font(.system(size: 9.5, weight: .black)).tracking(0.6).foregroundStyle(Color.busInk)
            .padding(.horizontal, 7).padding(.vertical, 3).background(fill, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    let symbol: String
    var fill: Color = .busYellow
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 16, weight: .black)).foregroundStyle(Color.busInk)
                .frame(maxWidth: .infinity).frame(height: 52)
                .chunky(fill: fill, stroke: .busInk, radius: 16, lift: 4)
        }
        .buttonStyle(PressStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 15, weight: .black)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 52)
                .chunky(fill: Theme.soft, radius: 16, lift: 4)
        }
        .buttonStyle(PressStyle())
    }
}

private struct MenuLabel: View {
    var body: some View {
        Image(systemName: "ellipsis").font(.system(size: 19, weight: .black)).foregroundStyle(Theme.ink)
            .frame(width: 52, height: 52).chunky(fill: Theme.soft, radius: 16, lift: 4)
    }
}

private struct CircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .black)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 2.5))
                .background(Circle().fill(Theme.edge).offset(y: 3))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

private struct SquareButton: View {
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .black)).foregroundStyle(on ? Color.busInk : Theme.ink)
                .frame(width: 46, height: 46)
                .chunky(fill: on ? .busYellow : Theme.surface, radius: 14, lift: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

extension TransitVehicle {
    var coordinateLocation: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}

extension MKPolyline {
    /// Every nth point, enough to frame the line without copying all of it.
    func coordinates(every step: Int) -> [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        let all = points()
        return Swift.stride(from: 0, to: pointCount, by: max(1, step)).map { all[$0].coordinate } + [all[pointCount - 1].coordinate]
    }
}
