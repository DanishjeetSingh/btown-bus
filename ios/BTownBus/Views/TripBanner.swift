import SwiftUI

/// The in-app twin of the Live Activity, pinned above the tab bar.
struct TripBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    let open: (TransitStop) -> Void

    var body: some View {
        if let watch = tracker.watch {
            let route = store.route(watch.routeKey)
            let stop = store.stop(watch.stopKey)
            let status = tracker.status
            let hex = route?.colorHex ?? watch.agency.colorHex
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button { if let stop { open(stop) } } label: {
                        HStack(spacing: 12) {
                            Text(route?.shortName ?? watch.routeId)
                                .font(Theme.display(18)).foregroundStyle(Color.readableInk(on: hex))
                                .frame(width: 50, height: 50)
                                .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.busCream, lineWidth: 2.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tracker.activityRunning ? "LIVE ACTIVITY ON" : "LIVE AT \(watch.threshold) STOPS AWAY")
                                    .font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(Color.busCream.opacity(0.6))
                                Text(stop?.name ?? "Your stop").font(.system(size: 15, weight: .heavy)).lineLimit(1)
                                Text(line(status)).font(.system(size: 14, weight: .black)).foregroundStyle(color(status?.phase))
                            }
                            .foregroundStyle(Color.busCream)
                            Spacer(minLength: 0)
                            countdown(status)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { tracker.stop() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .black)).foregroundStyle(Color.busCream.opacity(0.7))
                            .frame(width: 30, height: 30).overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 2))
                    }
                    .accessibilityLabel("Stop tracking")
                }
                if let away = status?.stopsAway {
                    HStack(spacing: 5) {
                        let total = max(watch.threshold, away, 1)
                        ForEach(0..<total, id: \.self) { index in
                            Capsule().fill(index < total - away ? Color(hex: hex).opacity(0.6) : index == total - away ? Color.busYellow : Color.white.opacity(0.16)).frame(height: 6)
                        }
                        Text(away == 1 ? "Next stop" : "\(away) stops").font(.system(size: 12, weight: .black)).foregroundStyle(Color.busCream).fixedSize()
                    }
                }
                if let problem = tracker.activityProblem {
                    Text(problem).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.busCream.opacity(0.6))
                }
            }
            .padding(12)
            .background(Color.busInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.black, lineWidth: 3))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black).offset(y: 5))
        }
    }

    private func line(_ status: TripStatus?) -> String {
        guard let status else { return "Checking the bus…" }
        switch status.phase {
        case .atStop: return "You're at the stop"
        case .leaveNow: return "Leave now"
        case .tooLate: return "Too late to walk it"
        case .arriving: return "Bus is arriving"
        case .departed: return "Bus has left"
        case .noPrediction: return "Waiting for a prediction…"
        case .onTheWay:
            if let leaveAt = status.leaveAt { return "Leave by \(leaveAt.clock)" }
            return "On the way"
        }
    }

    private func color(_ phase: TripActivityAttributes.Phase?) -> Color {
        switch phase {
        case .atStop, .arriving: return .goGreen
        case .tooLate: return .warnOrange
        default: return .busYellow
        }
    }

    @ViewBuilder private func countdown(_ status: TripStatus?) -> some View {
        if let arrival = status?.arrival {
            let minutes = arrival.minutes()
            Group {
                if minutes == 0 { Text("Now") }
                else if minutes >= 60 { Text(shortClock(arrival.predictedArrival)).font(Theme.display(22)) }
                else { Text("\(minutes)") + Text("min").font(.system(size: 13, weight: .black)) }
            }
            .font(Theme.display(36))
            .foregroundStyle(Color.busYellow)
            .shadow(color: Color.busYellow.opacity(0.45), radius: 8)
            .monospacedDigit()
        } else {
            Text("—").font(Theme.display(30)).foregroundStyle(Color.busYellow)
        }
    }
}
