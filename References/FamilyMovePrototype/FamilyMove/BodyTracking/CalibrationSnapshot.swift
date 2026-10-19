import Foundation
import CoreGraphics

struct CalibrationSnapshot {
    var bodyCenter: CGPoint
    var shoulderCenter: CGPoint
    var hipCenter: CGPoint
    var shoulderWidth: CGFloat
    var torsoHeight: CGFloat
    var standingBodyCenterY: CGFloat { bodyCenter.y }
    var standingHipY: CGFloat { hipCenter.y }
    var leftKnee: CGPoint?
    var rightKnee: CGPoint?
    var leftAnkle: CGPoint?
    var rightAnkle: CGPoint?

    init?(player: TrackedPlayer) {
        guard player.isDetected, let center = player.bodyCenter,
              let left = player.leftShoulder?.position, let right = player.rightShoulder?.position,
              let hip = player.hipCenter else { return nil }
        bodyCenter = center
        shoulderCenter = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        hipCenter = hip
        shoulderWidth = hypot(left.x - right.x, left.y - right.y)
        torsoHeight = hypot(shoulderCenter.x - hip.x, shoulderCenter.y - hip.y)
        guard torsoHeight >= 20, shoulderWidth >= 15 else { return nil }
        leftKnee = player.leftKnee?.position; rightKnee = player.rightKnee?.position
        leftAnkle = player.leftAnkle?.position; rightAnkle = player.rightAnkle?.position
    }

    static func average(_ samples: [Self]) -> Self? {
        guard var result = samples.first else { return nil }
        func point(_ values: [CGPoint]) -> CGPoint {
            CGPoint(x: values.map(\.x).reduce(0, +) / CGFloat(values.count),
                    y: values.map(\.y).reduce(0, +) / CGFloat(values.count))
        }
        func optional(_ values: [CGPoint?]) -> CGPoint? {
            let points = values.compactMap { $0 }; return points.isEmpty ? nil : point(points)
        }
        result.bodyCenter = point(samples.map(\.bodyCenter))
        result.shoulderCenter = point(samples.map(\.shoulderCenter))
        result.hipCenter = point(samples.map(\.hipCenter))
        result.shoulderWidth = samples.map(\.shoulderWidth).reduce(0, +) / CGFloat(samples.count)
        result.torsoHeight = samples.map(\.torsoHeight).reduce(0, +) / CGFloat(samples.count)
        // A moving baseline would make later reaches and jumps relative to the
        // wrong posture. Accept ordinary joint jitter, but reject body movement.
        func rms(_ points: [CGPoint], around center: CGPoint) -> CGFloat {
            sqrt(points.reduce(0) { $0 + pow($1.x - center.x, 2) + pow($1.y - center.y, 2) } / CGFloat(points.count))
        }
        let movementLimit = result.torsoHeight * GameConstants.calibrationMaximumMovementRatio
        guard rms(samples.map(\.hipCenter), around: result.hipCenter) <= movementLimit,
              rms(samples.map(\.shoulderCenter), around: result.shoulderCenter) <= movementLimit,
              samples.allSatisfy({
                  abs($0.torsoHeight - result.torsoHeight) <= result.torsoHeight * GameConstants.calibrationMaximumScaleVariation &&
                  abs($0.shoulderWidth - result.shoulderWidth) <= result.shoulderWidth * GameConstants.calibrationMaximumScaleVariation
              }) else { return nil }
        result.leftKnee = optional(samples.map(\.leftKnee)); result.rightKnee = optional(samples.map(\.rightKnee))
        result.leftAnkle = optional(samples.map(\.leftAnkle)); result.rightAnkle = optional(samples.map(\.rightAnkle))
        return result
    }
}
