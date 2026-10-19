import CoreGraphics
import Foundation

struct PositionSmoother {
    var alpha = GameConstants.smoothingAlpha

    func smooth(_ current: CGPoint?, previous: CGPoint?) -> CGPoint? {
        // Never continue exposing a wrist when the current joint is unavailable.
        guard let current else { return nil }
        guard let previous else { return current }
        return CGPoint(x: previous.x * (1 - alpha) + current.x * alpha,
                       y: previous.y * (1 - alpha) + current.y * alpha)
    }

    func smooth(_ current: JointPoint?, previous: JointPoint?) -> JointPoint? {
        guard let current,
              let position = smooth(current.position, previous: previous?.position) else { return nil }
        return JointPoint(position: position, confidence: current.confidence)
    }
}
