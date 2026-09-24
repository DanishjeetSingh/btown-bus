import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BTownBusWidgets: WidgetBundle {
    var body: some Widget {
        TripLiveActivity()
    }
}

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenTripView(context: context)
                .activityBackgroundTint(Color.busInk)
                .activitySystemActionForegroundColor(Color.busYellow)
        } dynamicIsland: { context in
            let state = context.state
            let route = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RouteBadge(name: route.routeShortName, hex: route.routeColorHex, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BusCountdown(state: state, size: 26)
                        .frame(minWidth: 78, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.stopName).font(.system(size: 15, weight: .heavy)).lineLimit(1)
                        Text(headline(state)).font(.system(size: 13, weight: .bold)).foregroundStyle(accent(state.phase)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        StopLadder(stopsAway: state.stopsAway, start: route.startStops, color: Color(hex: route.routeColorHex))
                        HStack {
                            WalkLine(state: state)
                            Spacer()
                            Button(intent: EndTripIntent()) { Text("End").font(.system(size: 13, weight: .heavy)).padding(.horizontal, 6) }
                                .buttonStyle(.bordered).tint(Color.busCream)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                RouteBadge(name: route.routeShortName, hex: route.routeColorHex, size: 24)
            } compactTrailing: {
                BusCountdown(state: state, size: 15)
                    .frame(maxWidth: 56)
            } minimal: {
                RouteBadge(name: route.routeShortName, hex: route.routeColorHex, size: 22)
            }
            .keylineTint(Color.busYellow)
        }
    }
}

// MARK: - Lock Screen

struct LockScreenTripView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        let state = context.state
        let route = context.attributes
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RouteBadge(name: route.routeShortName, hex: route.routeColorHex, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.stopName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.busCream.opacity(0.7)).lineLimit(1)
                    Text(headline(state))
                        .font(.system(size: 22, weight: .black).width(.expanded))
                        .foregroundStyle(accent(state.phase))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("BUS IN").font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Color.busCream.opacity(0.6))
                    BusCountdown(state: state, size: 28)
                }
                .frame(width: 92, alignment: .trailing)
            }
            StopLadder(stopsAway: state.stopsAway, start: route.startStops, color: Color(hex: route.routeColorHex))
            HStack {
                WalkLine(state: state)
                Spacer()
                Button(intent: EndTripIntent()) {
                    Text("End").font(.system(size: 13, weight: .heavy)).padding(.horizontal, 6)
                }
                .buttonStyle(.bordered).tint(Color.busCream)
            }
        }
        .padding(16)
        .foregroundStyle(Color.busCream)
    }
}

// MARK: - Pieces

private func headline(_ state: TripActivityAttributes.ContentState) -> String {
    switch state.phase {
    case .atStop: return "You're at the stop"
    case .leaveNow: return "Leave now"
    case .tooLate: return "Too late to walk it"
    case .arriving: return "Bus is arriving"
    case .departed: return "Bus has left"
    case .noPrediction: return "Waiting for the bus"
    case .onTheWay:
        if let leaveAt = state.leaveAt { return "Leave at \(hourMinute(leaveAt))" }
        return "On the way"
    }
}

/// "1:39", no AM/PM, to keep the headline short.
private func hourMinute(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm"
    return formatter.string(from: date)
}

private func accent(_ phase: TripActivityAttributes.Phase) -> Color {
    switch phase {
    case .atStop, .arriving: return .goGreen
    case .tooLate: return .warnOrange
    case .departed, .noPrediction: return .busCream
    default: return .busYellow
    }
}

struct RouteBadge: View {
    let name: String
    let hex: String
    let size: CGFloat

    var body: some View {
        Text(name)
            .font(.system(size: size * 0.42, weight: .black).width(.expanded))
            .minimumScaleFactor(0.5).lineLimit(1)
            .foregroundStyle(Color.readableInk(on: hex))
            .padding(.horizontal, size * 0.08)
            .frame(minWidth: size, minHeight: size)
            .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Color.busCream, lineWidth: max(1.5, size * 0.05)))
    }
}

/// Minutes until the bus reaches the stop, counting down on its own between updates.
struct BusCountdown: View {
    let state: TripActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if state.phase == .departed {
                Text("Gone")
            } else if let arrival = state.busArrival, arrival > .now {
                Text(timerInterval: Date.now...arrival, countsDown: true, showsHours: false)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            } else if state.busArrival != nil {
                Text("Now")
            } else {
                Text("--")
            }
        }
        .font(.system(size: size, weight: .black).width(.expanded))
        .foregroundStyle(Color.busYellow)
        .lineLimit(1).minimumScaleFactor(0.6)
    }
}

struct StopLadder: View {
    let stopsAway: Int?
    let start: Int
    let color: Color

    var body: some View {
        let total = max(start, stopsAway ?? 0, 1)
        let passed = total - min(stopsAway ?? total, total)
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < passed ? color.opacity(0.7) : index == passed ? Color.busYellow : Color.white.opacity(0.18))
                    .frame(height: 6)
            }
            Text(stopsAway.map { $0 == 1 ? "Next stop" : "\($0) stops" } ?? "")
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.busCream)
                .fixedSize()
        }
    }
}

struct WalkLine: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.phase == .atStop ? "mappin.and.ellipse" : "figure.walk")
            if state.phase == .atStop {
                Text("You're here — stay put")
            } else if let walk = state.walkSeconds {
                Text("\(max(1, Int((Double(walk) / 60).rounded()))) min walk to the stop")
            } else {
                Text("Walk time needs location").foregroundStyle(Color.busCream.opacity(0.7))
            }
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color.busCream)
        .lineLimit(1)
    }
}
