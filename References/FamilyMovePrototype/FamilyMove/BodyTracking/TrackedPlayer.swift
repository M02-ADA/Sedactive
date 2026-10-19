import CoreGraphics
import Foundation

struct TrackedPlayer: Identifiable {
    enum PlayerSide { case left, right }

    let id: Int
    var side: PlayerSide { id == 1 ? .left : .right }
    var bodyCenter: CGPoint?
    var leftWrist: JointPoint?
    var rightWrist: JointPoint?
    var leftElbow: JointPoint?
    var rightElbow: JointPoint?
    var leftShoulder: JointPoint?
    var rightShoulder: JointPoint?
    var leftHip: JointPoint?
    var rightHip: JointPoint?
    var leftKnee: JointPoint?
    var rightKnee: JointPoint?
    var leftAnkle: JointPoint?
    var rightAnkle: JointPoint?
    var hipCenter: CGPoint?
    var isDetected = false
    var lastSeen: TimeInterval = -.infinity

    var isVisibleNow: Bool { isDetected && bodyCenter != nil }
}
