import SwiftUI

enum PlayerStyle {
    static let blue = AppColors.player1
    static let red = AppColors.player2
    static func color(for id: Int) -> Color { id == 1 ? blue : red }
}

struct DebugOverlayView: View {
    let players: [TrackedPlayer]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(players) { player in
                if player.isDetected {
                    let color = PlayerStyle.color(for: player.id)
                    skeleton(for: player).stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    ForEach(Array([("LH", player.leftHip), ("RH", player.rightHip),
                                   ("LK", player.leftKnee), ("RK", player.rightKnee),
                                   ("LA", player.leftAnkle), ("RA", player.rightAnkle)].enumerated()), id: \.offset) { _, entry in
                        if let joint = entry.1 {
                            marker(at: joint.position, label: String(format: "P%d %@ %.2f", player.id, entry.0, joint.confidence), color: color, isCenter: true)
                        }
                    }
                    if let center = player.bodyCenter {
                        marker(at: center, label: "P\(player.id) CENTER", color: color, isCenter: true)
                    }
                    if let wrist = player.leftWrist {
                        marker(at: wrist.position, label: String(format: "P%d LW %.2f", player.id, wrist.confidence), color: color)
                    }
                    if let wrist = player.rightWrist {
                        marker(at: wrist.position, label: String(format: "P%d RW %.2f", player.id, wrist.confidence), color: color)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func skeleton(for player: TrackedPlayer) -> Path {
        Path { path in
            func connect(_ a: CGPoint?, _ b: CGPoint?) {
                guard let a, let b else { return }
                path.move(to: a)
                path.addLine(to: b)
            }
            connect(player.leftShoulder?.position, player.rightShoulder?.position)
            connect(player.leftShoulder?.position, player.leftElbow?.position)
            connect(player.leftElbow?.position, player.leftWrist?.position)
            connect(player.rightShoulder?.position, player.rightElbow?.position)
            connect(player.rightElbow?.position, player.rightWrist?.position)
            connect(player.bodyCenter, player.hipCenter)
            connect(player.leftHip?.position, player.leftKnee?.position)
            connect(player.leftKnee?.position, player.leftAnkle?.position)
            connect(player.rightHip?.position, player.rightKnee?.position)
            connect(player.rightKnee?.position, player.rightAnkle?.position)
        }
    }

    private func marker(at point: CGPoint, label: String, color: Color, isCenter: Bool = false) -> some View {
        ZStack {
            Circle().fill(color).frame(width: isCenter ? 14 : 23, height: isCenter ? 14 : 23)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            Text(label).font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4)
                .background(color, in: Capsule()).fixedSize().offset(y: -27)
        }
        .position(point)
    }
}
