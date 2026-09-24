import SwiftUI

struct RoutePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your routes").font(Theme.display(32)).foregroundStyle(Theme.ink)
                        Text("Picked routes show up on the map and in Nearby.").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                if !store.loaded { ProgressView().frame(maxWidth: .infinity).padding(30) }
                ForEach(Agency.allCases.sorted { a, _ in a == .iu }, id: \.self) { agency in
                    let routes = store.routes.filter { $0.agency == agency }
                    if !routes.isEmpty {
                        let allOn = routes.allSatisfy { store.activeRoutes.contains($0.id) }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                RoundedRectangle(cornerRadius: 3).fill(Color(hex: agency.colorHex)).frame(width: 9, height: 9)
                                Text(agency.name.uppercased()).font(.system(size: 13, weight: .black)).tracking(0.8).foregroundStyle(Theme.ink)
                                Spacer()
                                Button(allOn ? "None" : "All") { store.setAgency(agency, on: !allOn) }
                                    .font(.system(size: 13, weight: .black)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .background(Theme.soft, in: Capsule()).overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 2))
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                ForEach(routes) { route in RouteToggle(route: route) }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .safeAreaInset(edge: .bottom) {
            Button { dismiss() } label: {
                Text("Done").font(.system(size: 17, weight: .black)).foregroundStyle(Color.busInk)
                    .frame(maxWidth: .infinity).frame(height: 52).chunky(fill: .busYellow, radius: 16)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, 18).padding(.bottom, 8)
            .onDisappear { store.markRoutesChosen() }
        }
    }
}

private struct RouteToggle: View {
    @Environment(AppStore.self) private var store
    let route: TransitRoute

    var body: some View {
        let on = store.activeRoutes.contains(route.id)
        Button { store.toggleRoute(route) } label: {
            HStack(spacing: 10) {
                Text(route.shortName).font(Theme.display(14))
                    .foregroundStyle(on ? Theme.ink : Color.readableInk(on: route.colorHex))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(minWidth: 38, minHeight: 38).padding(.horizontal, 2)
                    .background(on ? Theme.surface : Color(hex: route.colorHex), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.edge, lineWidth: 2))
                Text(route.longName).font(.system(size: 12.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    .foregroundStyle(on ? Color.readableInk(on: route.colorHex) : Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(6).frame(minHeight: 54)
            .chunky(fill: on ? Color(hex: route.colorHex) : Theme.surface, radius: 15, lift: 2)
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.selection, trigger: on)
    }
}
