import Foundation
import CoreGraphics

struct CollisionDetector {
    func hit(player: TrackedPlayer, mole: Mole) -> Bool {
        guard player.id == mole.playerID, player.isDetected, !mole.isHit else { return false }
        return player.confidentHands.contains { hand in
            hypot(hand.position.x - mole.position.x, hand.position.y - mole.position.y)
                <= mole.radius * MoleConstants.collisionRadiusMultiplier
        }
    }
}
