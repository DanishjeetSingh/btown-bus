import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
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
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button { fitRoutes(preferTrip: true) } label: {
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
        .onChange(of: store.activeRoutes) { _, _ in fitRoutes() }
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
