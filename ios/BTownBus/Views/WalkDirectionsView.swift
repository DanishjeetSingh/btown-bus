import SwiftUI
import MapKit

struct WalkDirectionsView: View {
    let stop: TransitStop
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var guide = WalkingGuide.shared
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: AppStore.downtown.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))
    @State private var following = true
    @State private var showSteps = false
    @State private var previewRouteIndex = 0
    @State private var overview = false

    var body: some View {
        Map(position: $camera) {
            if guide.choosingRoute {
                ForEach(Array(guide.alternatives.enumerated()), id: \.offset) { index, route in
                    MapPolyline(route.polyline).stroke(Color.busInk.opacity(index == previewRouteIndex ? 1 : 0.4), lineWidth: index == previewRouteIndex ? 12 : 8)
                    MapPolyline(route.polyline).stroke(index == previewRouteIndex ? Color.busYellow : Color.gray, lineWidth: index == previewRouteIndex ? 7 : 4)
                }
            } else if let route = guide.route {
                MapPolyline(route.polyline).stroke(Color.busInk, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                MapPolyline(route.polyline).stroke(Color.busYellow, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            Annotation(stop.name, coordinate: stop.coordinate) {
                Image(systemName: "bus.fill").font(.system(size: 20, weight: .black)).foregroundStyle(Color.busInk)
                    .padding(13).background(Color.busYellow, in: Circle())
                    .overlay(Circle().stroke(Color.busInk, lineWidth: 3))
                    .background(Circle().fill(Color.busInk).offset(y: 3))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) { maneuverCard.padding(.horizontal, 12).padding(.top, 8) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: 16) {
                HStack(spacing: 12) {
                    Spacer()
                    mapButton(overview ? "location.fill" : "arrow.up.left.and.arrow.down.right", label: overview ? "Follow my location" : "Route overview") {
                        if overview { follow() } else { fitRoute() }
                    }
                    if !following {
                        mapButton("location.north.fill", label: "Recenter") { follow() }
                    }
                }.padding(.horizontal, 16)
                tripPanel.padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showSteps) { directionsList }
        .onAppear {
            guide.start(to: stop)
            follow()
        }
        .onChange(of: location.location?.timestamp) { _, _ in
            updateCamera()
        }
        .onChange(of: location.heading) { _, _ in updateCamera() }
        .onChange(of: camera.positionedByUser) { _, moved in if moved { following = false } }
        .onChange(of: location.authorization) { _, _ in if guide.route == nil { guide.refresh() } }
        .onChange(of: guide.choosingRoute) { _, choosing in
            if choosing {
                previewRouteIndex = 0
                fitAlternatives()
            } else { follow() }
        }
        .onChange(of: guide.destination) { _, destination in if destination == nil { dismiss() } }
        .onDisappear { guide.stop() }
    }

    private var maneuverCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: guide.choosingRoute ? "point.topleft.down.to.point.bottomright.curvepath.fill" : guide.maneuverSymbol)
                .font(.system(size: 34, weight: .black)).foregroundStyle(Color.busInk)
                .frame(width: 64, height: 72)
                .background(guide.arrived ? Color.goGreen : Color.busYellow, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.choosingRoute ? "PICK YOUR PATH" : guide.arrived ? "AT YOUR STOP" : guide.loading ? "WALKING ROUTE" : "UP NEXT")
                    .font(.system(size: 10, weight: .black)).tracking(1).foregroundStyle(Color.busCream.opacity(0.65))
                if guide.choosingRoute { Text("Your walk").font(Theme.display(30)) }
                else if guide.loading { Text(guide.route == nil ? "Finding route" : "Rerouting").font(Theme.display(24)) }
                else if guide.arrived { Text("You're here").font(Theme.display(30)) }
                else if guide.route != nil {
                    Text(formatDistance(guide.maneuverDistance)).font(Theme.display(34)).monospacedDigit()
                } else { Text("Locating you").font(Theme.display(24)) }
                Text(guide.choosingRoute ? "Choose a route below. We’ll remember it for this stop." : guide.arrived ? stop.name : guide.instruction)
                    .font(.system(size: 15, weight: .heavy)).lineLimit(3)
            }
            Spacer(minLength: 0)
            if guide.loading { ProgressView().tint(.busYellow) }
        }
        .foregroundStyle(Color.busCream).padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chunky(fill: .busInk, stroke: .black, radius: 22, lift: 5)
        .accessibilityElement(children: .combine)
    }

    private var tripPanel: some View {
        VStack(spacing: 16) {
            if let problem = guide.activityProblem {
                Text(problem).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            if let problem = guide.problem {
                HStack {
                    Text(problem).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Retry") { guide.refresh() }.disabled(guide.loading)
                }
            }
            if location.freshLocation == nil, guide.route != nil {
                Text("Waiting for GPS · guidance is paused").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            if guide.choosingRoute {
                routeChoices
            } else {
            HStack(alignment: .firstTextBaseline) {
                metric(guide.route == nil ? "—" : "\(max(0, Int(ceil(guide.remainingSeconds / 60))))", caption: "min")
                Spacer()
                metric(guide.route == nil ? "—" : formatDistance(guide.remainingDistance), caption: "remaining")
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    metric(guide.route == nil ? "—" : context.date.addingTimeInterval(guide.remainingSeconds).formatted(date: .omitted, time: .shortened), caption: "arrival")
                }
            }
            }
            HStack(spacing: 8) {
                Image(systemName: "bus.fill").foregroundStyle(Theme.ink)
                Text(stop.name).font(Theme.display(15)).lineLimit(2)
                Spacer()
            }
            HStack(spacing: 12) {
                Button { showSteps = true } label: {
                    Label("Steps", systemImage: "list.bullet").font(.system(size: 15, weight: .black)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .chunky(fill: Theme.soft, radius: 14, lift: 3)
                }.buttonStyle(PressStyle()).disabled(guide.route == nil)
                Button { dismiss() } label: {
                    Text(guide.arrived ? "Done" : "End walk").font(.system(size: 15, weight: .black)).foregroundStyle(Color.busInk)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .chunky(fill: guide.arrived ? .goGreen : .busYellow, stroke: .busInk, radius: 14, lift: 3)
                }.buttonStyle(PressStyle())
                Menu {
                    Button("Choose a different route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { guide.changeRoute() }
                    Button("Refresh route", systemImage: "arrow.clockwise") { guide.refresh() }
                    Button("Open Apple Maps", systemImage: "map") { openMaps() }
                    if location.isDenied {
                        Button("Location settings", systemImage: "gear") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .black)).foregroundStyle(Theme.ink)
                        .frame(width: 48, height: 48).chunky(fill: Theme.soft, radius: 14, lift: 3)
                }.buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .chunky(fill: Theme.surface, radius: 22, lift: 5)
    }

    private var routeChoices: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(guide.alternatives.enumerated()), id: \.offset) { index, route in
                    Button { previewRouteIndex = index; fitAlternatives() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: previewRouteIndex == index ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(route.name.isEmpty ? "Walking route \(index + 1)" : route.name).font(.system(size: 15, weight: .heavy))
                                Text("\(max(1, Int(ceil(route.expectedTravelTime / 60)))) min · \(formatDistance(route.distance))")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Spacer(minLength: 0)
                        }.foregroundStyle(previewRouteIndex == index ? Color.busInk : Theme.ink).padding(12)
                            .chunky(fill: previewRouteIndex == index ? .busYellow : Theme.soft, radius: 14, lift: 2)
                    }.buttonStyle(PressStyle())
                }
                Button {
                    guide.selectRoute(at: previewRouteIndex)
                } label: {
                    Text("Use this route").font(.system(size: 16, weight: .black)).foregroundStyle(Color.busInk)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .chunky(fill: .busYellow, stroke: .busInk, radius: 14, lift: 3)
                }.buttonStyle(PressStyle())
            }.padding(.horizontal, 3).padding(.bottom, 5)
        }.frame(height: min(260, CGFloat(guide.alternatives.count) * 78 + 70))
    }

    private func fitAlternatives() {
        guard !guide.alternatives.isEmpty else { return }
        following = false
        overview = true
        let rect = guide.alternatives.reduce(MKMapRect.null) { $0.union($1.polyline.boundingMapRect) }
        withAnimation { camera = .rect(rect.insetBy(dx: -max(rect.width * 0.15, 100), dy: -max(rect.height * 0.15, 100))) }
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(23)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(caption.uppercased()).font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Theme.muted)
        }
    }

    private func mapButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .black)).foregroundStyle(Theme.ink)
                .frame(width: 50, height: 50).chunky(fill: Theme.surface, radius: 16, lift: 3)
        }.buttonStyle(PressStyle()).accessibilityLabel(label)
    }

    private var directionsList: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your walk").font(Theme.display(30)).foregroundStyle(Theme.ink)
                    Text(stop.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.muted)
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 14) {
                            Image(systemName: index < guide.stepIndex ? "checkmark.circle.fill" : "figure.walk")
                                .font(.system(size: 24, weight: .black)).foregroundStyle(Theme.ink)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(step.instructions).font(.system(size: 16, weight: .heavy))
                                Text(formatDistance(step.distance)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                        }.foregroundStyle(Theme.ink).padding(16)
                            .chunky(fill: index == guide.stepIndex ? .busYellow : Theme.surface, radius: 16, lift: 3)
                    }
                }.padding(20)
            }.background(Theme.bg)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSteps = false }.font(.system(size: 15, weight: .black)).tint(Theme.ink) } }
        }.presentationDetents([.medium, .large]).presentationBackground(Theme.bg)
    }

    private func follow() {
        overview = false
        following = true
        updateCamera()
    }

    private func updateCamera() {
        guard following, let fix = location.freshLocation else { return }
        let heading = location.heading ?? (fix.course >= 0 && fix.speed > 0.5 ? fix.course : 0)
        // An explicit close camera avoids MapKit choosing a zoom that fits the whole route.
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 240, heading: heading, pitch: 55))
        }
    }

    private func fitRoute() {
        if guide.choosingRoute { fitAlternatives(); return }
        guard let route = guide.route else { return }
        overview = true
        following = false
        let rect = route.polyline.boundingMapRect
        withAnimation { camera = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)) }
    }

    private func openMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
