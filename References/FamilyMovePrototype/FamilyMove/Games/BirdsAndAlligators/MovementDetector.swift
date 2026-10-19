import Foundation
import CoreGraphics

enum MovementKind { case squat, jump }
enum MovementPhase { case standing, moving, qualified, returning }

struct MovementThresholds {
    var squatDisplacement: CGFloat = 0.18
    var jumpDisplacement: CGFloat = 0.13
    var standingTolerance: CGFloat = 0.07
    var ankleDisplacement: CGFloat = 0.05
    var kneeAngle: CGFloat = 125
    var minimumMovementDuration: TimeInterval = 0.10
    var maximumMovementDuration: TimeInterval = 2
    var cooldown: TimeInterval = 0.5
}

struct MovementDetector {
    var thresholds = MovementThresholds()
    private(set) var phase = MovementPhase.standing
    private var candidate: MovementKind?
    private var beganAt: TimeInterval = 0
    private var completedAt: TimeInterval = -.infinity
    private var lastSample: TimeInterval = -.infinity
    private var armed = false

    mutating func reset() {
        let previousCompletion = completedAt
        self = MovementDetector(thresholds: thresholds)
        completedAt = previousCompletion
    }

    mutating func update(player: TrackedPlayer, calibration: CalibrationSnapshot,
                         now: TimeInterval) -> MovementKind? {
        guard player.isDetected, let hip = player.hipCenter else { reset(); return nil }
        guard player.lastSeen > lastSample else { return nil }
        if player.lastSeen - lastSample > GameConstants.maximumPoseAge { phase = .standing; armed = false; candidate = nil }
        lastSample = player.lastSeen
        let displacement = (hip.y - calibration.standingHipY) / calibration.torsoHeight
        let standing = abs(displacement) <= thresholds.standingTolerance
        if !armed {
            if standing && now - completedAt >= thresholds.cooldown { armed = true }
            return nil
        }
        if phase == .returning {
            if standing && now - completedAt >= thresholds.cooldown { phase = .standing }
            return nil
        }
        if phase != .standing && now - beganAt > thresholds.maximumMovementDuration {
            phase = .standing; candidate = nil; armed = false; return nil
        }
        switch phase {
        case .standing:
            if displacement > thresholds.squatDisplacement * 0.5 {
                candidate = .squat; phase = .moving; beganAt = now
            } else if displacement < -thresholds.jumpDisplacement * 0.5 {
                candidate = .jump; phase = .moving; beganAt = now
            }
        case .moving:
            if standing { phase = .standing; candidate = nil }
        case .qualified:
            if standing, now - beganAt >= thresholds.minimumMovementDuration {
                let result = candidate
                phase = .returning; completedAt = now; candidate = nil
                return result
            }
        case .returning: break
        }
        if phase == .moving {
            if candidate == .squat && displacement >= thresholds.squatDisplacement && kneeEvidence(player) {
                phase = .qualified
            } else if candidate == .jump && displacement <= -thresholds.jumpDisplacement && ankleEvidence(player, calibration) {
                phase = .qualified
            }
        }
        return nil
    }

    private func kneeEvidence(_ player: TrackedPlayer) -> Bool {
        func angle(_ hip: JointPoint?, _ knee: JointPoint?, _ ankle: JointPoint?) -> CGFloat? {
            guard let hip, let knee, let ankle else { return nil }
            let a = CGPoint(x: hip.position.x - knee.position.x, y: hip.position.y - knee.position.y)
            let b = CGPoint(x: ankle.position.x - knee.position.x, y: ankle.position.y - knee.position.y)
            let length = hypot(a.x, a.y) * hypot(b.x, b.y)
            guard length > 1 else { return nil }
            return acos(min(1, max(-1, (a.x * b.x + a.y * b.y) / length))) * 180 / .pi
        }
        let angles = [angle(player.leftHip, player.leftKnee, player.leftAnkle),
                      angle(player.rightHip, player.rightKnee, player.rightAnkle)].compactMap { $0 }
        return angles.isEmpty || angles.reduce(0, +) / CGFloat(angles.count) < thresholds.kneeAngle
    }

    private func ankleEvidence(_ player: TrackedPlayer, _ calibration: CalibrationSnapshot) -> Bool {
        var differences: [CGFloat] = []
        if let current = player.leftAnkle?.position, let baseline = calibration.leftAnkle { differences.append(baseline.y - current.y) }
        if let current = player.rightAnkle?.position, let baseline = calibration.rightAnkle { differences.append(baseline.y - current.y) }
        return differences.isEmpty || differences.reduce(0, +) / CGFloat(differences.count) >= calibration.torsoHeight * thresholds.ankleDisplacement
    }
}
