import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    @Environment(LocationService.self) private var location
    @State private var walking = WalkingGuide.shared
    /// Keep you and the tracked bus framed together, following both, until you pan the map.
    @State private var focusOnBus = false
    @Binding var openStop: TransitStop?
    @Namespace private var mapScope
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: AppStore.downtown.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000))

    private var shownRoutes: Set<TransitKey> {
        var shown = store.activeRoutes
        if let watch = tracker.watch { shown.insert(watch.routeKey) }
        return shown
    }

    var body: some View {
        let shown = shownRoutes
        let favorites = Set(store.favorites)
        let stops = store.stops.filter { stop in favorites.contains(stop.id) || stop.routeIds.contains { shown.contains(TransitKey(agency: stop.agency, id: $0)) } }
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
                    BusMarker(label: route?.shortName ?? "•", hex: route?.colorHex ?? bus.agency.colorHex, heading: bus.heading,
                              stale: bus.isStale, tracked: tracker.watch?.vehicleId == bus.vehicleId && tracker.watch?.agency == bus.agency)
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
                        focusOnBus.toggle()
                        if focusOnBus { focusMeAndBus() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill").font(.system(size: 14, weight: .black))
                            Text("+").font(.system(size: 15, weight: .black))
                            Text(route?.shortName ?? "Bus")
                                .font(Theme.display(11)).lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(Color.readableInk(on: route?.colorHex ?? watch.agency.colorHex))
                                .frame(minWidth: 24, minHeight: 24).padding(.horizontal, 2)
                                .background(Color(hex: route?.colorHex ?? watch.agency.colorHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .foregroundStyle(focusOnBus ? Color.busInk : Theme.ink)
                        .padding(.horizontal, 12).frame(height: 48)
                        .chunky(fill: focusOnBus ? .busYellow : Theme.surface, radius: 16, lift: 3)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(focusOnBus ? "Stop following you and the bus" : "Show you and the bus")
                }
                Button { focusOnBus = false; fitRoutes(preferTrip: true) } label: {
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
                MapUserLocationButton(scope: mapScope)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(Theme.ink)
                    .frame(width: 48, height: 48)
                    .chunky(radius: 16, lift: 3)
            }
            .padding(12)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 7) {
                Circle().fill(store.failedAgencies.count == Agency.allCases.count ? Theme.warn : Theme.go).frame(width: 9, height: 9)
                Text(buses.isEmpty ? (shown.isEmpty ? "Pick routes to see buses" : "No buses running") : "\(buses.count) \(buses.count == 1 ? "bus" : "buses") live")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 13).frame(height: 36)
            .chunky(radius: 18, lift: 2)
            .padding(12)
        }
        .mapScope(mapScope)
        .onAppear { fitRoutes() }
        .onChange(of: store.activeRoutes) { _, _ in focusOnBus = false; fitRoutes() }
        // Follow both while focused: the bus moves every feed update, you move with GPS.
        .onChange(of: trackedBus?.updatedAt) { _, _ in if focusOnBus { focusMeAndBus() } }
        .onChange(of: location.location?.timestamp) { _, _ in if focusOnBus { focusMeAndBus() } }
        .onChange(of: camera.positionedByUser) { _, moved in if moved { focusOnBus = false } }
        .onChange(of: camera.followsUserLocation) { _, following in if following { focusOnBus = false } }
        .onChange(of: tracker.watch == nil) { _, ended in if ended { focusOnBus = false } }
    }

    /// The bus being tracked, from the tracker's own fresher polling when it has it.
    private var trackedBus: TransitVehicle? {
        guard let watch = tracker.watch else { return nil }
        return tracker.status?.vehicle ?? store.vehicle(watch.agency, watch.vehicleId)
    }

    /// Frame you and the tracked bus. Before the tracker has locked onto a bus, frame you and your stop.
    private func focusMeAndBus() {
        guard let watch = tracker.watch else { return }
        var points: [CLLocationCoordinate2D] = []
        if let me = location.location?.coordinate { points.append(me) }
        if let bus = trackedBus { points.append(bus.coordinate) }
        else if let stop = store.stop(watch.ride.map { TransitKey(agency: watch.agency, id: $0.destinationId) } ?? watch.stopKey) {
            points.append(stop.coordinate)
        }
        guard !points.isEmpty else { return }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        // Generous padding so neither marker sits under the buttons or the trip banner.
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.8, 0.006),
                                    longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.006))
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

struct BusMarker: View {
    let label: String
    let hex: String
    let heading: Double?
    let stale: Bool
    let tracked: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if tracked {
                Circle().stroke(Color.busYellow, lineWidth: 4).frame(width: 46, height: 46)
                    .scaleEffect(pulse ? 1.3 : 0.7).opacity(pulse ? 0 : 1)
                    .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } }
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
