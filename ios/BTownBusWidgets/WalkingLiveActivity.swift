import ActivityKit
import SwiftUI
import WidgetKit

struct WalkingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkingActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    WalkingManeuver(symbol: context.state.maneuverSymbol, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.phase == .arrived ? "AT YOUR STOP" : "WALK TO STOP")
                            .font(.system(size: 10, weight: .black)).tracking(1).foregroundStyle(Color.busCream.opacity(0.6))
                        Text(walkingHeadline(context.state)).font(.system(size: 25, weight: .black).width(.expanded))
                            .foregroundStyle(Color.busYellow).lineLimit(1).minimumScaleFactor(0.7)
                        Text(context.state.instruction).font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Color.busCream).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(context.attributes.stopName).font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.busCream.opacity(0.75)).lineLimit(1)
                    Spacer()
                    Button(intent: EndWalkingIntent()) {
                        Text("End walk").font(.system(size: 12, weight: .black)).foregroundStyle(Color.busInk)
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Color.busYellow, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if context.state.phase == .walking || context.state.phase == .rerouting {
                    HStack(spacing: 18) {
                        Label("\(context.state.remainingMinutes) min", systemImage: "figure.walk")
                        Text(walkingDistance(context.state.remainingMeters))
                        if let arrival = context.state.arrivalAt { Text(arrival, style: .time) }
                    }.font(.system(size: 12, weight: .bold)).foregroundStyle(Color.busCream)
                }
            }.padding(16)
                .activityBackgroundTint(Color.busInk)
                .activitySystemActionForegroundColor(Color.busYellow)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WalkingManeuver(symbol: context.state.maneuverSymbol, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(walkingHeadline(context.state)).font(.system(size: 22, weight: .black).width(.expanded))
                        .foregroundStyle(Color.busYellow).lineLimit(1).minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.instruction).font(.system(size: 15, weight: .heavy)).lineLimit(2)
                        HStack {
                            Text(context.attributes.stopName).font(.system(size: 12, weight: .bold)).lineLimit(1)
                            Spacer()
                            Button(intent: EndWalkingIntent()) { Text("End walk").font(.system(size: 12, weight: .black)) }
                                .buttonStyle(.bordered).tint(Color.busYellow)
                        }
                    }.foregroundStyle(Color.busCream)
                }
            } compactLeading: {
                Image(systemName: context.state.maneuverSymbol).foregroundStyle(Color.busYellow)
            } compactTrailing: {
                Text(context.state.phase == .walking ? walkingDistance(context.state.maneuverMeters) : context.state.phase == .arrived ? "Here" : "Walk")
                    .font(.system(size: 13, weight: .black)).foregroundStyle(Color.busYellow)
            } minimal: {
                Image(systemName: context.state.maneuverSymbol).foregroundStyle(Color.busYellow)
            }.keylineTint(Color.busYellow)
        }
    }
}

private struct WalkingManeuver: View {
    let symbol: String
    let size: CGFloat
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.5, weight: .black)).foregroundStyle(Color.busInk)
            .frame(width: size, height: size).background(Color.busYellow, in: RoundedRectangle(cornerRadius: size * 0.25))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(Color.busCream, lineWidth: 2))
    }
}
private func walkingDistance(_ meters: Int) -> String {
    meters < 160 ? "\(Int((Double(meters) / 10).rounded()) * 10) m" : String(format: "%.1f mi", Double(meters) / 1609.344)
}
private func walkingHeadline(_ state: WalkingActivityAttributes.ContentState) -> String {
    switch state.phase {
    case .choosing: return "Choose your route"
    case .locating: return "Locating you"
    case .walking: return walkingDistance(state.maneuverMeters)
    case .rerouting: return "Rerouting"
    case .unavailable: return "Directions paused"
    case .arrived: return "You're here"
    }
}
