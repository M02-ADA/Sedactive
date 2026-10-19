import Foundation
import CoreGraphics

/// Screen-space mannequin used by Simulator controls and UI-test fixtures.
/// This never supplies observations to Vision or runs the physical camera.
enum SimulatedBodyPose {
    static func player(id: Int, screen: CGSize, timestamp: TimeInterval,
                       movement: MovementKind? = nil, wristTarget: CGPoint? = nil,
                       restingWrists: Bool = true) -> TrackedPlayer {
        let x = screen.width * (id == 1 ? 0.25 : 0.75)
        let shoulderY = screen.height * 0.40
        let hipY = screen.height * 0.61
        let torso = hipY - shoulderY
        let ducking = movement == .squat
        let offset = torso * (movement == nil ? 0 : ducking ? 0.24 : -0.20)
        func joint(_ dx: CGFloat, _ y: CGFloat) -> JointPoint {
            JointPoint(position: CGPoint(x: x + dx, y: y), confidence: 1)
        }
        var player = TrackedPlayer(id: id)
        player.isDetected = true; player.lastSeen = timestamp
        player.bodyCenter = CGPoint(x: x, y: (shoulderY + hipY) / 2 + offset)
        player.hipCenter = CGPoint(x: x, y: hipY + offset)
        player.leftShoulder = joint(-screen.width * 0.04, shoulderY + offset)
        player.rightShoulder = joint(screen.width * 0.04, shoulderY + offset)
        player.leftHip = joint(-screen.width * 0.025, hipY + offset)
        player.rightHip = joint(screen.width * 0.025, hipY + offset)
        let legOffset = ducking ? 0 : offset
        player.leftKnee = joint(-screen.width * (ducking ? 0.08 : 0.025), screen.height * 0.75 + legOffset)
        player.rightKnee = joint(screen.width * (ducking ? 0.08 : 0.025), screen.height * 0.75 + legOffset)
        player.leftAnkle = joint(-screen.width * 0.025, screen.height * 0.89 + legOffset)
        player.rightAnkle = joint(screen.width * 0.025, screen.height * 0.89 + legOffset)
        if restingWrists {
            player.leftWrist = joint(-screen.width * 0.05, hipY)
            player.rightWrist = joint(screen.width * 0.05, hipY)
        }
        if let wristTarget { player.leftWrist = JointPoint(position: wristTarget, confidence: 1) }
        return player
    }
}
