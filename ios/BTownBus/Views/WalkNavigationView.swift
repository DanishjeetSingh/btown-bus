import SwiftUI
import MapKit

/// Turn-by-turn walking to your stop, like Apple Maps: a tilted 3D map that follows you and turns
/// with you, the next turn at the top, and the race with your bus at the bottom. Styled after the
/// trip banner (dark sign cards) and the Map tab (square map buttons).
struct WalkNavigationView: View {
    let pickup: TransitStop
    /// Nil when walking to a stop without tracking a bus.
    let tracked: Bool

    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var guide = WalkingGuide.shared
    @State private var camera: MapCameraPosition = .automatic
    @State private var mode: Mode = .follow

    enum Mode { case follow, overview, free }

    // MARK: The bus you're racing

    private var arrival: TransitArrival? {
        tracked ? tracker.status?.arrival : store.arrivals(at: pickup.id).first
    }
    private var bus: TransitVehicle? {
        tracked ? tracker.status?.vehicle : arrival.flatMap { store.vehicle($0.agency, $0.vehicleId) }
    }
    private var route: TransitRoute? {
        if tracked, let watch = tracker.watch { return store.route(watch.routeKey) }
        return arrival.flatMap { store.route($0.routeKey) }
    }
    private var routeHex: String { route?.colorHex ?? pickup.agency.colorHex }
    private var stopsAway: Int? {
        if tracked { return tracker.status?.stopsAway }
        return arrival.flatMap { store.stopsAway(for: $0) }
    }
    private var arrived: Bool { guide.arrived || location.isAtStop(pickup) }
    private var walkMinutes: Int { arrived ? 0 : max(1, Int(ceil(guide.remainingSeconds / 60))) }

    var body: some View {
        Map(position: $camera) {
            if let route, !route.path.isEmpty {
                MapPolyline(coordinates: route.path).stroke(Color(hex: routeHex).opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let walk = guide.route {
                MapPolyline(walk.polyline).stroke(Color.busInk, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                MapPolyline(walk.polyline).stroke(Color.busYellow, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
            Annotation(pickup.name, coordinate: pickup.coordinate, anchor: .center) {
                Circle().fill(Color.busYellow).overlay(Circle().strokeBorder(Color.busInk, lineWidth: 4)).frame(width: 26, height: 26)
            }
            .annotationTitles(.hidden)
            if let bus, let route {
                Annotation(route.shortName, coordinate: bus.coordinate, anchor: .center) {
                    BusMarker(label: route.shortName, hex: routeHex, heading: bus.heading, stale: bus.isStale, tracked: true)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            turnCard.padding(.horizontal, 12).padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: 12) {
                mapButtons
                busCard
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: guide.stepIndex)
        .sensoryFeedback(.success, trigger: arrived)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if guide.destination?.id != pickup.id { guide.start(to: pickup, showsLiveActivity: !tracked) }
            follow(animated: false)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: location.location?.timestamp) { _, _ in if mode == .follow { follow() } }
        .onChange(of: location.heading) { _, _ in if mode == .follow { follow() } }
        .onChange(of: guide.route?.distance) { _, _ in if mode == .overview { overview() } }
        .onChange(of: camera.positionedByUser) { _, moved in if moved { mode = .free } }
    }

    // MARK: Top: the next turn

    private var turnCard: some View {
        HStack(spacing: 14) {
            Image(systemName: arrived ? "checkmark" : guide.maneuverSymbol)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(arrived ? Theme.goInk : Color.busInk)
                .frame(width: 64, height: 64)
                .background(arrived ? Color.goGreen : Color.busYellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if arrived {
                    Text("YOU'RE AT THE STOP").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Color.busCream.opacity(0.6))
                    Text(pickup.name).font(Theme.display(22)).foregroundStyle(Color.goGreen).lineLimit(2).minimumScaleFactor(0.7)
                } else if guide.route == nil {
                    Text("WALKING DIRECTIONS").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Color.busCream.opacity(0.6))
                    Text(guide.problem ?? "Finding your way…").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color.busCream).lineLimit(3)
                } else {
                    Text(guide.maneuverDistance < 10 ? "Now" : formatDistance(guide.maneuverDistance)).font(Theme.display(34)).foregroundStyle(Color.busYellow).monospacedDigit()
                    Text(guide.instruction).font(.system(size: 17, weight: .heavy)).foregroundStyle(Color.busCream).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.busInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.black, lineWidth: 3))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black).offset(y: 5))
        .accessibilityElement(children: .combine)
    }

    // MARK: Bottom: you vs. the bus

    private var busCard: some View {
        let busMinutes = arrival?.minutes()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(arrived ? "YOU MADE IT" : "YOUR WALK").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Color.busCream.opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(arrived ? "Here" : "\(walkMinutes)").font(Theme.display(34)).foregroundStyle(Color.busCream).monospacedDigit()
                        if !arrived { Text("min").font(.system(size: 13, weight: .black)).foregroundStyle(Color.busCream.opacity(0.7)) }
                    }
                    if !arrived, guide.route != nil {
                        Text("\(formatDistance(guide.remainingDistance)) · arrive \(Date().addingTimeInterval(guide.remainingSeconds).clock)")
                            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.busCream.opacity(0.7))
                    }
                }
                Spacer(minLength: 4)
                if let route {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("BUS").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Color.busCream.opacity(0.6))
                            Text(busMinutes.map { $0 == 0 ? "Now" : $0 >= 60 ? shortClock(arrival!.predictedArrival) : "\($0) min" } ?? "—")
                                .font(Theme.display(22)).foregroundStyle(Color.busYellow).monospacedDigit()
                            if let stopsAway {
                                Text(stopsAway == 1 ? "next stop" : "\(stopsAway) stops away").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.busCream.opacity(0.7))
                            }
                        }
                        Text(route.shortName).font(Theme.display(18)).foregroundStyle(Color.readableInk(on: routeHex))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(width: 50, height: 50)
                            .background(Color(hex: routeHex), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.busCream, lineWidth: 2.5))
                    }
                }
            }
            if let line = verdict(busMinutes: busMinutes) {
                Text(line.text).font(.system(size: 15, weight: .black)).foregroundStyle(line.color)
            }
            Button { dismiss() } label: {
                Text(arrived ? "Done" : "End walk").font(.system(size: 16, weight: .black))
                    .foregroundStyle(arrived ? Theme.goInk : Color.busInk)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(arrived ? Color.goGreen : Color.busYellow, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
        .padding(14)
        .background(Color.busInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.black, lineWidth: 3))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black).offset(y: 5))
    }

    /// One line on who reaches the stop first, colored like the trip banner.
    private func verdict(busMinutes: Int?) -> (text: String, color: Color)? {
        guard let busMinutes else { return nil }
        if arrived { return (busMinutes <= 1 ? "It's pulling up now" : "Bus in \(busMinutes) min · stay put", .goGreen) }
        guard guide.route != nil else { return nil }
        let spare = busMinutes - walkMinutes
        if spare >= 3 { return ("\(spare) min to spare", .goGreen) }
        if spare >= 1 { return ("Tight · keep moving", .busYellow) }
        return ("The bus gets there first · hurry", .warnOrange)
    }

    // MARK: Camera

    private var mapButtons: some View {
        HStack(spacing: 10) {
            mapButton("arrow.up.left.and.arrow.down.right", on: mode == .overview, label: "Show the whole walk") { overview() }
            mapButton("location.north.line.fill", on: mode == .follow, label: "Follow me") { follow() }
        }
    }

    private func mapButton(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .black))
                .foregroundStyle(on ? Color.busInk : Theme.ink)
                .frame(width: 48, height: 48)
                .chunky(fill: on ? .busYellow : Theme.surface, radius: 16, lift: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    /// Close, tilted, and pointing the way you're facing (or walking), like Apple Maps.
    private func follow(animated: Bool = true) {
        mode = .follow
        guard let fix = location.location else { camera = .userLocation(followsHeading: true, fallback: .automatic); return }
        let heading = location.heading ?? (fix.course >= 0 && fix.speed > 0.5 ? fix.course : 0)
        // Look at a point a little ahead so you sit low on screen with the way forward in view.
        let radians = heading * .pi / 180, ahead = 35.0
        let center = CLLocationCoordinate2D(
            latitude: fix.coordinate.latitude + ahead * cos(radians) / 111_111,
            longitude: fix.coordinate.longitude + ahead * sin(radians) / (111_111 * cos(fix.coordinate.latitude * .pi / 180)))
        let next = MapCameraPosition.camera(MapCamera(centerCoordinate: center, distance: 330, heading: heading, pitch: 60))
        if animated { withAnimation(.easeInOut(duration: 0.8)) { camera = next } } else { camera = next }
    }

    /// The whole walk, flat, with the bus if it's on the way.
    private func overview() {
        mode = .overview
        var points = guide.route?.polyline.coordinates(every: 10) ?? []
        points.append(pickup.coordinate)
        if let me = location.location?.coordinate { points.append(me) }
        if let bus { points.append(bus.coordinate) }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 2.2, 0.004), longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.004)))
        withAnimation(.easeInOut(duration: 0.8)) { camera = .region(region) }
    }
}
