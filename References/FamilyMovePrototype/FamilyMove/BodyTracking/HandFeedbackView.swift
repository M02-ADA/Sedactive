import SwiftUI

enum ArcadeStyle {
    static func handColor(_ playerID: Int) -> Color {
        playerID == 1 ? Color(red: 0.12, green: 0.90, blue: 1) : Color(red: 1, green: 0.22, blue: 0.77)
    }
}

struct HandFeedbackView: View {
    let players: [TrackedPlayer]
    @State private var feedback = HandFeedback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
            Canvas { context, _ in
                for trail in feedback.trails(at: ProcessInfo.processInfo.systemUptime) {
                    let color = ArcadeStyle.handColor(trail.hand.playerID)
                    let center = trail.hand.position
                    if !reduceMotion, let first = trail.points.first, trail.points.count > 1 {
                        var path = Path(); path.move(to: first)
                        trail.points.dropFirst().forEach { path.addLine(to: $0) }
                        context.stroke(path, with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                        context.stroke(path, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    let halo = CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)
                    context.fill(Path(ellipseIn: halo), with: .radialGradient(
                        Gradient(colors: [color.opacity(0.8), color.opacity(0.25), color.opacity(0)]),
                        center: center, startRadius: 5, endRadius: 42))
                    let ring = Path(ellipseIn: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36))
                    context.stroke(ring, with: .color(color), lineWidth: 7)
                    context.stroke(ring, with: .color(.white.opacity(0.95)), lineWidth: 2)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.white))
                }
            }
        }
        .onChange(of: players.flatMap(\.confidentHands), initial: true) { _, _ in
            feedback.update(players: players, now: ProcessInfo.processInfo.systemUptime)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

