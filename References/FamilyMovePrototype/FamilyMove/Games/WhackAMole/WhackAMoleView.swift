import SwiftUI

struct WhackAMoleView: View {
    let moles: [Mole]
    let calibration: [Int: CalibrationSnapshot]
    let screen: CGSize
    let feedback: [FeedbackEvent]
    let debug: Bool
    var activeTime: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            CaveRim().fill(LinearGradient(colors: [Color(red: 0.31, green: 0.20, blue: 0.13),
                                                   Color(red: 0.52, green: 0.32, blue: 0.17)],
                                          startPoint: .top, endPoint: .bottom), style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.45), radius: 8)
            ForEach(MoleArenaLayout.sites(calibrations: calibration, screen: screen)) { site in
                MoleHole(radius: site.radius, playerID: site.playerID)
                    .rotationEffect(angle(zone: site.zone, playerID: site.playerID))
                    .position(site.position)
            }
            ForEach(moles) { mole in
                let color = ArcadeStyle.handColor(mole.playerID)
                ZStack {
                    if debug {
                        Circle().fill(.yellow.opacity(0.13))
                            .overlay(Circle().stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 5])))
                            .frame(width: mole.radius * 2 * MoleConstants.collisionRadiusMultiplier,
                                   height: mole.radius * 2 * MoleConstants.collisionRadiusMultiplier)
                    }
                    Circle().fill(color.opacity(0.22))
                        .frame(width: mole.radius * 2.3, height: mole.radius * 2.3).blur(radius: 10)
                    Image("MoleIllustration").resizable().scaledToFit()
                        .frame(width: mole.radius * 2, height: mole.radius * 2)
                        .rotationEffect(angle(zone: mole.zone, playerID: mole.playerID))
                        .scaleEffect(reduceMotion ? 1 : min(1, 0.65 + max(0, activeTime - mole.spawnedAt) * 3))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                    Circle().trim(from: 0, to: max(0, min(1, 1 - (activeTime - mole.spawnedAt) / MoleConstants.lifetime)))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: mole.radius * 2 + 8, height: mole.radius * 2 + 8)
                }.position(mole.position).transition(.opacity)
            }
            ForEach(feedback) { event in
                let age = max(0, min(1, (activeTime - event.createdAt) / 0.7))
                let color = ArcadeStyle.handColor(event.playerID)
                ZStack {
                    Circle().stroke(color.opacity(1 - age), lineWidth: 5)
                        .frame(width: 55 + (reduceMotion ? 0 : age * 100), height: 55 + (reduceMotion ? 0 : age * 100))
                    if !reduceMotion {
                        ForEach(0..<8) { index in
                            let angle = Double(index) * .pi / 4
                            Circle().fill(color).frame(width: 9, height: 9)
                                .offset(x: cos(angle) * (30 + age * 65), y: sin(angle) * (30 + age * 65))
                        }
                    }
                    Text("+\(GameConstants.scorePerSuccess)").font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white).shadow(color: color, radius: 7)
                        .offset(y: -40 - (reduceMotion ? 0 : age * 35))
                }.opacity(1 - age).position(event.position)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: moles.map(\.id))
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func angle(zone: MoleZone, playerID: Int) -> Angle {
        switch zone {
        case .low: return .zero
        case .overhead: return .degrees(180)
        case .side: return .degrees(playerID == 1 ? 90 : -90)
        }
    }
}

private struct MoleHole: View {
    let radius: CGFloat
    let playerID: Int
    var body: some View {
        Ellipse().fill(Color(red: 0.10, green: 0.07, blue: 0.07))
            .overlay(Ellipse().stroke(Color(red: 0.93, green: 0.43, blue: 0.20), lineWidth: 7))
            .overlay(Ellipse().stroke(ArcadeStyle.handColor(playerID).opacity(0.45), lineWidth: 2).padding(-5))
            .frame(width: radius * 2.2, height: radius * 0.7)
            .shadow(color: .black.opacity(0.65), radius: 4, y: 5)
            .offset(y: radius * 0.65)
    }
}

private struct CaveRim: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.addRect(rect)
        let points: [CGPoint] = [
            CGPoint(x: 0.015, y: 0.20), CGPoint(x: 0.04, y: 0.055), CGPoint(x: 0.18, y: 0.018),
            CGPoint(x: 0.38, y: 0.032), CGPoint(x: 0.61, y: 0.017), CGPoint(x: 0.85, y: 0.026),
            CGPoint(x: 0.96, y: 0.055), CGPoint(x: 0.985, y: 0.22), CGPoint(x: 0.974, y: 0.76),
            CGPoint(x: 0.95, y: 0.95), CGPoint(x: 0.74, y: 0.978), CGPoint(x: 0.51, y: 0.965),
            CGPoint(x: 0.27, y: 0.984), CGPoint(x: 0.045, y: 0.95), CGPoint(x: 0.022, y: 0.77)
        ].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        path.addLines(points); path.closeSubpath()
        return path
    }
}
