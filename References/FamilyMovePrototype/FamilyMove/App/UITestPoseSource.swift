import Foundation
import CoreGraphics

/// Launch-argument fixtures only. Release builds always use the real camera.
/// Synthetic screen-space joints test the UI/game loop, never Vision accuracy.
@MainActor
enum UITestPoseSource {
    static var enabled: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--synthetic-poses")
        #else
        return false
        #endif
    }
    static var roundDuration: TimeInterval? { enabled ? 8 : nil }

    static func players(screen: CGSize, session: GameSessionCoordinator, now: TimeInterval) -> [TrackedPlayer] {
        #if DEBUG
        return (1...2).map { id in
            var movement: MovementKind?
            if session.state == .playing, let obstacle = session.obstacles.first(where: { $0.playerID == id }) {
                let age = session.duration - session.remainingTime - obstacle.spawnedAt
                if age > 0.18 && age < 0.55 { movement = obstacle.type.movement }
            }
            return SimulatedBodyPose.player(id: id, screen: screen, timestamp: now, movement: movement,
                wristTarget: session.moles.first(where: { $0.playerID == id })?.position)
        }
        #else
        return []
        #endif
    }
}
