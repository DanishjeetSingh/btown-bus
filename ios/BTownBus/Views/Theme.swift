import SwiftUI
import UIKit

/// Same palette as the web app: school-bus yellow, ink, cream.
enum Theme {
    static let bg = adaptive(light: "#fff4de", dark: "#14120e")
    static let surface = adaptive(light: "#fffdf7", dark: "#211e18")
    static let soft = adaptive(light: "#f7e8c6", dark: "#2c2820")
    static let ink = adaptive(light: "#15130f", dark: "#fff4de")
    static let muted = adaptive(light: "#6b6356", dark: "#b3a893")
    static let edge = adaptive(light: "#15130f", dark: "#000000")
    static let go = adaptive(light: "#139a48", dark: "#34d27a")
    static let goInk = adaptive(light: "#ffffff", dark: "#07210f")
    static let warn = adaptive(light: "#e4572e", dark: "#ff7a52")
    static let me = Color(hex: "#2f6bff")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
}

/// Outlined card with a hard drop shadow.
struct Chunky: ViewModifier {
    var fill: Color = Theme.surface
    var stroke: Color = Theme.edge
    var radius: CGFloat = 22
    var lift: CGFloat = 4

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: 2.5))
            .background(shape.fill(stroke).offset(y: lift))
    }
}

extension View {
    func chunky(fill: Color = Theme.surface, stroke: Color = Theme.edge, radius: CGFloat = 22, lift: CGFloat = 4) -> some View {
        modifier(Chunky(fill: fill, stroke: stroke, radius: radius, lift: lift))
    }
}

/// Pushes down a couple of points on press, like the web buttons.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct RouteTag: View {
    let name: String
    let hex: String
    var size: CGFloat = 44

    var body: some View {
        Text(name)
            .font(Theme.display(size * 0.38))
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(Color.readableInk(on: hex))
            .padding(.horizontal, 4)
            .frame(minWidth: size, minHeight: size)
            .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2.5))
    }
}

/// "5m", "Now", or "7:05a" for long waits.
struct TimeChip: View {
    let route: TransitRoute?
    let arrival: TransitArrival
    var prominent = false

    var body: some View {
        let hex = route?.colorHex ?? arrival.agency.colorHex
        HStack(spacing: 0) {
            Text(route?.shortName ?? arrival.routeId)
                .font(Theme.display(prominent ? 15 : 13))
                .lineLimit(1).fixedSize()
                .foregroundStyle(Color.readableInk(on: hex))
                .padding(.horizontal, 8)
                .frame(minWidth: prominent ? 38 : 32, maxHeight: .infinity)
                .background(Color(hex: hex))
            Rectangle().fill(Theme.edge).frame(width: 2)
            waitText
                .font(.system(size: prominent ? 18 : 15, weight: .black))
                .monospacedDigit()
                .padding(.horizontal, 9)
        }
        .frame(height: prominent ? 40 : 34)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.edge, lineWidth: 2))
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private var waitText: some View {
        let minutes = arrival.minutes()
        if minutes == 0 { Text("Now") }
        else if minutes >= 60 { Text(shortClock(arrival.predictedArrival)) }
        else { Text("\(minutes)") + Text("m").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.muted) }
    }
}

func shortClock(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    let hour = parts.hour ?? 0
    return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", parts.minute ?? 0))\(hour < 12 ? "a" : "p")"
}

/// Yellow bar with the school-bus double trim.
struct BrandBar<Trailing: View>: View {
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text("B")
                .font(Theme.display(24))
                .foregroundStyle(Color.busYellow)
                .frame(width: 40, height: 40)
                .background(Color.busInk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .rotationEffect(.degrees(-4))
            VStack(alignment: .leading, spacing: -2) {
                Text("B-TOWN").font(Theme.display(17))
                Text("BUS").font(Theme.display(17))
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .layoutPriority(-1)
            Spacer()
            trailing
        }
        .foregroundStyle(Color.busInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.busYellow.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                Rectangle().fill(Color.busInk).frame(height: 3)
                Rectangle().fill(Color.busInk).frame(height: 3)
            }
            .background(Color.busYellow)
            .offset(y: 7)
        }
        .padding(.bottom, 7)
    }
}
