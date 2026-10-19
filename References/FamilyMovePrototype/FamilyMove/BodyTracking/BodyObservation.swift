import CoreGraphics
import Foundation

struct JointPoint {
    var position: CGPoint
    var confidence: Float
}

/// Vision-normalized, bottom-left origin, oriented upright and NOT mirrored.
struct BodyObservation {
    var id: UUID?
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
    var root: JointPoint?

    var shoulderCenter: CGPoint? { midpoint(leftShoulder, rightShoulder) }
    var hipCenter: CGPoint? { midpoint(leftHip, rightHip) }

    var bodyCenter: CGPoint? {
        if let shoulders = shoulderCenter, let hips = hipCenter {
            return CGPoint(x: (shoulders.x + hips.x) / 2, y: (shoulders.y + hips.y) / 2)
        }
        return shoulderCenter ?? hipCenter ?? root?.position
            ?? leftShoulder?.position ?? rightShoulder?.position
    }

    var quality: Float {
        [leftWrist, rightWrist, leftShoulder, rightShoulder, leftHip, rightHip]
            .compactMap { $0?.confidence }.reduce(0, +)
    }

    private func midpoint(_ first: JointPoint?, _ second: JointPoint?) -> CGPoint? {
        guard let first, let second else { return nil }
        return CGPoint(x: (first.position.x + second.position.x) / 2,
                       y: (first.position.y + second.position.y) / 2)
    }
}
