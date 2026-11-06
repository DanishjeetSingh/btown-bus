import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    @Environment(LocationService.self) private var location
    @State private var walking = WalkingGuide.shared
    @Binding var openStop: TransitStop?
    @Namespace private var mapScope
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: AppStore.downtown.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000))

    /// What the locate button has the map do. Panning the map lets go.
    enum Follow { case off, me, compass }
    @State private var follow: Follow = .off
    /// Keep the tracked bus in frame with you. Works with either follow mode: north up, or turning with the phone.
    @State private var withBus = false
    @State private var selectedBus: TransitVehicle?
    @State private var showLive = false

    private var shownRoutes: Set<TransitKey> {
        var shown = store.activeRoutes
        if let watch = tracker.watch { shown.insert(watch.routeKey) }
        return shown
    }

    var body: some View {
        let shown = shownRoutes
        let favorites = Set(store.saved.flatMap { item in store.stop(item.stop).map { store.members(of: $0).map(\.id) } ?? [item.stop] })
        let candidates = store.stops.filter { stop in favorites.contains(stop.id) || stop.routeIds.contains { shown.contains(TransitKey(agency: stop.agency, id: $0)) } }
        // Merged stops get one pin, which opens the combined stop.
        var pinned = Set<TransitKey>()
        let stops = candidates.map { store.representative(of: $0) }.filter { pinned.insert($0.id).inserted }
        let buses = store.vehicles.filter { vehicle in vehicle.routeId.map { shown.contains(TransitKey(agency: vehicle.agency, id: $0)) } ?? false }
        Map(position: $camera, scope: mapScope) {
            ForEach(store.routes.filter { shown.contains($0.id) }) { route in
                MapPolyline(coordinates: route.path).stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.path).stroke(Color(hex: route.colorHex), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    Button { openStop = stop } label: {
                        let favorite = favorites.contains(stop.id)
                        Circle()
                            .fill(favorite ? Color.busYellow : .white)
                            .overlay(Circle().strokeBorder(Color.busInk, lineWidth: favorite ? 2.5 : 2))
                            .frame(width: favorite ? 16 : 11, height: favorite ? 16 : 11)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
            ForEach(buses) { bus in
                let route = bus.routeId.flatMap { store.route(TransitKey(agency: bus.agency, id: $0)) }
                Annotation(route?.shortName ?? "Bus", coordinate: bus.coordinate, anchor: .center) {
                    Button { selectedBus = bus } label: {
                        BusMarker(label: route?.shortName ?? "•", hex: route?.colorHex ?? bus.agency.colorHex, heading: bus.heading,
                                  stale: bus.isStale, tracked: tracker.watch?.vehicleId == bus.vehicleId && tracker.watch?.agency == bus.agency)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
            if let walking = walking.route {
                MapPolyline(walking.polyline).stroke(Color.busInk, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(walking.polyline).stroke(Color.busYellow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [1, 9]))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                if let watch = tracker.watch {
                    let route = store.route(watch.routeKey)
                    Button {
                        withBus.toggle()
                        if withBus, follow == .off { follow = .me }
                        applyCamera()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bus.fill").font(.system(size: 14, weight: .black))
                            Text(route?.shortName ?? "Bus")
                                .font(Theme.display(11)).lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(Color.readableInk(on: route?.colorHex ?? watch.agency.colorHex))
                                .frame(minWidth: 24, minHeight: 24).padding(.horizontal, 2)
                                .background(Color(hex: route?.colorHex ?? watch.agency.colorHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .foregroundStyle(withBus ? Color.busInk : Theme.ink)
                        .padding(.horizontal, 12).frame(height: 48)
                        .chunky(fill: withBus ? .busYellow : Theme.surface, radius: 16, lift: 3)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(withBus ? "Stop keeping the bus in view" : "Keep you and the bus in view")
                }
                Button { follow = .off; withBus = false; location.setMapHeading(false); fitRoutes(preferTrip: true) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 48, height: 48)
                        .chunky(radius: 16, lift: 3)
                }
                .buttonStyle(PressStyle())
                .disabled(shown.isEmpty)
                .opacity(shown.isEmpty ? 0.45 : 1)
                .accessibilityLabel(tracker.watch == nil ? "Fit my routes" : "Fit tracked route")
                Button { cycleFollow() } label: {
                    Image(systemName: follow == .compass ? "location.north.line.fill" : follow == .me ? "location.fill" : "location")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(follow == .off ? Theme.ink : Color.busInk)
                        .frame(width: 48, height: 48)
                        .chunky(fill: follow == .off ? Theme.surface : .busYellow, radius: 16, lift: 3)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(follow == .off ? "Center on me" : follow == .me ? "Turn the map with my phone" : "Point the map north")
            }
            .padding(12)
        }
        .overlay(alignment: .topLeading) {
            LiveBuses(buses: buses, shown: shown, expanded: $showLive) { fit($0.map(\.coordinate)) }
                .padding(12)
        }
        .mapScope(mapScope)
        .sheet(item: $selectedBus) { bus in
            BusDetailSheet(key: bus.id) { stop in
                selectedBus = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openStop = stop }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.surface)
        }
        .onAppear { fitRoutes() }
        .onDisappear { location.setMapHeading(false) }
        .onChange(of: store.activeRoutes) { _, _ in if !withBus { letGo(); fitRoutes() } }
        // Follow you and the bus: the bus moves every feed update, you move with GPS, and the map turns with the phone.
        .onChange(of: trackedBus?.updatedAt) { _, _ in if withBus { frameMeAndBus() } }
        .onChange(of: location.location?.timestamp) { _, _ in if withBus { frameMeAndBus() } }
        .onChange(of: location.heading) { _, _ in if withBus, follow == .compass { frameMeAndBus() } }
        .onChange(of: camera.positionedByUser) { _, moved in if moved { letGo() } }
        .onChange(of: tracker.watch == nil) { _, ended in if ended, withBus { withBus = false; applyCamera() } }
        // At your stop there's nowhere to walk: go north up and just watch the bus come in.
        .onChange(of: tracker.status?.atStop ?? false) { _, here in
            if here { follow = .me; withBus = true; applyCamera() }
        }
    }

    /// The bus being tracked, from the tracker's own fresher polling when it has it.
    private var trackedBus: TransitVehicle? {
        guard let watch = tracker.watch else { return nil }
        return tracker.status?.vehicle ?? store.vehicle(watch.agency, watch.vehicleId)
    }

    /// Off → follow me (north up) → turn with the phone → back to north up. With the bus in view,
    /// it only switches between north up and turning with the phone.
    private func cycleFollow() {
        guard location.isAuthorized else { location.requestPermission(); return }
        switch follow {
        case .off: follow = withBus ? .compass : .me
        case .me: follow = .compass
        case .compass: follow = .me
        }
        applyCamera()
    }

    private func letGo() {
        follow = .off
        withBus = false
        location.setMapHeading(false)
    }

    private func applyCamera() {
        location.setMapHeading(withBus && follow == .compass)
        if withBus, tracker.watch != nil {
            frameMeAndBus()
            return
        }
        switch follow {
        case .off: break
        case .me: withAnimation { camera = .userLocation(followsHeading: false, fallback: camera) }
        case .compass: withAnimation { camera = .userLocation(followsHeading: true, fallback: camera) }
        }
    }

    /// Frame you and the tracked bus (or your stop, before the tracker has locked onto a bus).
    private func frameMeAndBus() {
        guard let watch = tracker.watch else { return }
        var points: [CLLocationCoordinate2D] = []
        if let me = location.location?.coordinate { points.append(me) }
        if let bus = trackedBus { points.append(bus.coordinate) }
        else if let stop = store.stop(watch.stopKey) { points.append(stop.coordinate) }
        guard !points.isEmpty else { return }
        if follow == .compass, let heading = location.heading {
            // Turned with the phone, so fit a circle around both rather than a north-up box.
            let lats = points.map(\.latitude), lngs = points.map(\.longitude)
            let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
            let separation = points.count > 1 ? CLLocation(latitude: lats[0], longitude: lngs[0]).distance(from: CLLocation(latitude: lats[1], longitude: lngs[1])) : 0
            withAnimation(.easeOut(duration: 0.4)) {
                camera = .camera(MapCamera(centerCoordinate: center, distance: max(700, separation * 3.4), heading: heading, pitch: 0))
            }
        } else {
            fit(points, padding: 1.8)
        }
    }

    private func fit(_ points: [CLLocationCoordinate2D], padding: Double = 1.6) {
        guard !points.isEmpty else { return }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        // Generous padding so nothing sits under the buttons or the trip banner.
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * padding, 0.006),
                                    longitudeDelta: max((lngs.max()! - lngs.min()!) * padding * 0.85, 0.006))
        withAnimation(.easeInOut(duration: 0.6)) { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// Zoom to the selected routes, or just the tracked bus's route when `preferTrip` and a trip is on.
    private func fitRoutes(preferTrip: Bool = false) {
        let keys: Set<TransitKey> = preferTrip ? tracker.watch.map { [$0.routeKey] } ?? shownRoutes : shownRoutes
        let points = store.routes.filter { keys.contains($0.id) }.flatMap(\.path)
        guard !points.isEmpty else { return }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (lats.max()! - lats.min()!) * 1.25 + 0.004, longitudeDelta: (lngs.max()! - lngs.min()!) * 1.25 + 0.004)
        withAnimation { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }
}

/// "5 buses live". Tap it for a breakdown by route; tap a route to see its buses.
private struct LiveBuses: View {
    @Environment(AppStore.self) private var store
    let buses: [TransitVehicle]
    let shown: Set<TransitKey>
    @Binding var expanded: Bool
    let show: ([TransitVehicle]) -> Void

    var body: some View {
        let allDown = store.failedAgencies.count == Agency.allCases.count
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                HStack(spacing: 7) {
                    Circle().fill(allDown ? Theme.warn : Theme.go).frame(width: 9, height: 9)
                    Text(buses.isEmpty ? (shown.isEmpty ? "Pick routes to see buses" : "No buses running") : "\(buses.count) \(buses.count == 1 ? "bus" : "buses") live")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                    if !shown.isEmpty {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .black)).foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 13).frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(shown.isEmpty)
            if expanded {
                breakdown
            }
        }
        .frame(maxWidth: expanded ? 290 : nil, alignment: .leading)
        .chunky(radius: 18, lift: 2)
    }

    private var breakdown: some View {
        let routes = store.routes.filter { shown.contains($0.id) }
        let byRoute = Dictionary(grouping: buses) { bus in bus.routeId.map { TransitKey(agency: bus.agency, id: $0) } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(store.failedAgencies).sorted { $0.rawValue < $1.rawValue }, id: \.self) { agency in
                    Text("\(agency.shortName) feed is down").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.warn)
                }
                ForEach(routes) { route in
                    let running = byRoute[route.id] ?? []
                    let stale = running.filter(\.isStale).count
                    Button { if !running.isEmpty { show(running); withAnimation { expanded = false } } } label: {
                        HStack(spacing: 9) {
                            RouteTag(name: route.shortName, hex: route.colorHex, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(route.longName).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(running.isEmpty ? "Not running now" : stale > 0 ? "\(stale) not reporting lately" : route.agency.name)
                                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("\(running.count)").font(Theme.display(18)).foregroundStyle(running.isEmpty ? Theme.muted : Theme.ink)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Everything the feed says about one bus: where it's headed, how full it is, whether it's late, and its next stops.
struct BusDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    let key: TransitKey
    let openStop: (TransitStop) -> Void

    var body: some View {
        if let bus = store.vehicles.first(where: { $0.id == key }) {
            content(bus)
        } else {
            Text("This bus stopped reporting.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ bus: TransitVehicle) -> some View {
        let route = bus.routeId.flatMap { store.route(TransitKey(agency: bus.agency, id: $0)) }
        let tracked = tracker.watch?.vehicleId == bus.vehicleId && tracker.watch?.agency == bus.agency
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    RouteTag(name: route?.shortName ?? "?", hex: route?.colorHex ?? bus.agency.colorHex, size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(route?.longName ?? "Bus") · \(bus.agency.shortName)".uppercased())
                            .font(.system(size: 11.5, weight: .black)).tracking(0.8).foregroundStyle(Theme.muted).lineLimit(1)
                        Text(bus.direction?.isEmpty == false ? bus.direction! : "Direction unavailable")
                            .font(Theme.display(22)).foregroundStyle(Theme.ink).lineLimit(2)
                    }
                }
                if tracked {
                    Label("You're tracking this bus", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.busInk)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Color.busYellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack(spacing: 10) {
                    crowding(bus)
                    schedule(bus)
                }
                Text("NEXT STOPS").font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 2)
                nextStops(bus)
                Group {
                    if bus.isStale {
                        Text("Position may be out of date. Last report ") + Text(bus.updatedAt, style: .relative) + Text(" ago.")
                    } else {
                        Text("Position updated ") + Text(bus.updatedAt, style: .relative) + Text(" ago.")
                    }
                }
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(bus.isStale ? Theme.warn : Theme.muted)
            }
            .padding(20)
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(12)
            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func crowding(_ bus: TransitVehicle) -> some View {
        let share: Double? = bus.load.flatMap { load in bus.capacity.map { min(1, max(0, Double(load) / Double($0))) } }
        let label: String = {
            guard let share else { return "Crowding unavailable" }
            switch share {
            case ..<0.3: return "Lots of room"
            case ..<0.6: return "Some seats"
            case ..<0.85: return "Getting full"
            default: return "Packed"
            }
        }()
        return tile {
            Label("HOW FULL", systemImage: "person.2.fill").font(.system(size: 11, weight: .black)).tracking(0.6).foregroundStyle(Theme.muted)
            Text(label).font(.system(size: 16, weight: .heavy)).foregroundStyle(share == nil ? Theme.muted : Theme.ink)
            if let share {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface)
                        Capsule().fill(share < 0.6 ? Theme.go : share < 0.85 ? Color.busYellow : Theme.warn)
                            .frame(width: max(8, proxy.size.width * share))
                    }
                }
                .frame(height: 8)
                .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1.5))
            }
        }
    }

    private func schedule(_ bus: TransitVehicle) -> some View {
        let (label, color): (String, Color) = {
            guard let value = bus.onSchedule else { return ("Schedule unavailable", Theme.muted) }
            if value >= 0 { return ("On time", Theme.go) }
            let late = Int(abs(value).rounded())
            return ("\(late) min late", late <= 5 ? Color.busYellow : Theme.warn)
        }()
        return tile {
            Label("SCHEDULE", systemImage: "clock.fill").font(.system(size: 11, weight: .black)).tracking(0.6).foregroundStyle(Theme.muted)
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label).font(.system(size: 16, weight: .heavy)).foregroundStyle(bus.onSchedule == nil ? Theme.muted : Theme.ink)
            }
        }
    }

    @ViewBuilder private func nextStops(_ bus: TransitVehicle) -> some View {
        let ids = bus.nextStops.isEmpty ? (bus.nextStopId.map { [$0] } ?? []) : bus.nextStops
        if ids.isEmpty {
            Text("Upcoming stops unavailable").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        ForEach(Array(ids.prefix(5).enumerated()), id: \.offset) { index, id in
            let stop = store.stop(TransitKey(agency: bus.agency, id: id))
            let minutes = index < bus.nextStopMinutes.count ? bus.nextStopMinutes[index] : nil
            Button { if let stop { openStop(stop) } } label: {
                HStack(spacing: 10) {
                    Text("\(index + 1)").font(.system(size: 12, weight: .black)).foregroundStyle(Theme.muted).frame(width: 18)
                    Text(stop.map { store.placeName($0) } ?? "Upcoming stop").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    if let minutes {
                        Text(minutes <= 0 ? "Now" : "\(minutes) min").font(.system(size: 14, weight: .black)).monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    if stop != nil {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .black)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2))
            }
            .buttonStyle(PressStyle())
            .disabled(stop == nil)
        }
    }
}

struct BusMarker: View {
    let label: String
    let hex: String
    let heading: Double?
    let stale: Bool
    let tracked: Bool

    var body: some View {
        ZStack {
            if tracked {
                // The pulse animates only the ring. A repeating withAnimation here would also animate the
                // marker's position forever, which made the tracked bus slide around the map.
                Circle().stroke(Color.busYellow, lineWidth: 4).frame(width: 46, height: 46)
                    .phaseAnimator([false, true]) { ring, expanded in
                        ring.scaleEffect(expanded ? 1.3 : 0.7).opacity(expanded ? 0 : 1)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.6) : nil
                    }
            }
            if let heading {
                Triangle().fill(Color.busInk).frame(width: 16, height: 11).offset(y: -24).rotationEffect(.degrees(heading))
            }
            Text(label)
                .font(Theme.display(12)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 34, height: 34)
                .background(Color(hex: hex), in: Circle())
                .overlay(Circle().strokeBorder(tracked ? Color.busYellow : .white, lineWidth: 3))
                .background(Circle().fill(Color.busInk).padding(-2).offset(y: 2))
        }
        .frame(width: 52, height: 52)
        .saturation(stale ? 0.3 : 1).opacity(stale ? 0.7 : 1)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
