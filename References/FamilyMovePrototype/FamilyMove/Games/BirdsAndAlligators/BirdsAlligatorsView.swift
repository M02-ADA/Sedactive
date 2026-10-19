import SwiftUI

struct BirdsAlligatorsView: View {
    let obstacles: [Obstacle]
    let calibration: [Int: CalibrationSnapshot]
    let screen: CGSize
    var body: some View {
        ZStack {
            ForEach(obstacles) { obstacle in
                if let baseline = calibration[obstacle.playerID] {
                    VStack(spacing: 4) {
                        Image(obstacle.type == .bird ? "BirdIllustration" : "AlligatorIllustration")
                            .resizable().scaledToFit().frame(width: 140, height: 100)
                        Text(obstacle.type == .bird ? "DUCK" : "JUMP")
                            .accessibilityIdentifier("expectedMovement-\(obstacle.playerID)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 6)
                            .background(PlayerStyle.color(for: obstacle.playerID), in: Capsule())
                    }
                    .position(x: screen.width * (obstacle.playerID == 1 ? 0.25 : 0.75),
                              y: min(max(GameConstants.gameplayTopInset + 86, screen.height - GameConstants.gameplayBottomInset - 86),
                                     max(GameConstants.gameplayTopInset + 86, obstacle.type == .bird
                                  ? baseline.shoulderCenter.y - 80 : baseline.hipCenter.y + 70)))
                }
            }
        }.allowsHitTesting(false)
    }
}
