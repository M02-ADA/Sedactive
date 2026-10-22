import Foundation

/// Subset of Vision body joints the game needs. Kept free of Vision types so the
/// squat logic can be unit-tested on macOS without a camera.
nonisolated enum Joint: Int, CaseIterable, Sendable {
    case nose, neck, leftShoulder, rightShoulder, leftHip, rightHip, root
    case leftKnee, rightKnee, leftAnkle, rightAnkle, leftWrist, rightWrist
}

nonisolated struct JointPoint: Sendable, Equatable {
    var x: Double
    var y: Double
    var confidence: Double
}

/// One person's pose in normalized display-texture coordinates:
/// origin bottom-left (matches Vision and SpriteKit), already mirrored like the on-screen image.
nonisolated struct PersonPose: Sendable, Equatable {
    var joints: [Joint: JointPoint]
    /// Texture width / height. Needed so angles are measured in square pixels, not normalized units.
    var aspect: Double = 4.0 / 3.0

    func point(_ joint: Joint, minConfidence: Double = 0.3) -> JointPoint? {
        guard let p = joints[joint], p.confidence >= minConfidence else { return nil }
        return p
    }

    /// Horizontal centre used for zone assignment.
    var centerX: Double? {
        if let r = point(.root, minConfidence: 0.2) { return r.x }
        let candidates = [Joint.leftHip, .rightHip, .neck, .leftShoulder, .rightShoulder].compactMap { point($0, minConfidence: 0.2) }
        guard !candidates.isEmpty else { return nil }
        return candidates.map(\.x).reduce(0, +) / Double(candidates.count)
    }

    var footY: Double? {
        [point(.leftAnkle), point(.rightAnkle)].compactMap { $0?.y }.min()
    }

    var footX: Double? {
        let ankles = [point(.leftAnkle), point(.rightAnkle)].compactMap { $0 }
        guard !ankles.isEmpty else { return centerX }
        return ankles.map(\.x).reduce(0, +) / Double(ankles.count)
    }

    var headPoint: JointPoint? { point(.nose, minConfidence: 0.2) ?? point(.neck, minConfidence: 0.2) }

    var hipCenter: JointPoint? {
        if let r = point(.root, minConfidence: 0.2) { return r }
        let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
        guard !hips.isEmpty else { return nil }
        return JointPoint(x: hips.map(\.x).reduce(0, +) / Double(hips.count),
                          y: hips.map(\.y).reduce(0, +) / Double(hips.count),
                          confidence: hips.map(\.confidence).min() ?? 0)
    }

    /// Neck-to-hip distance in height-normalized units; a scale reference that does not change during a squat.
    var torsoLength: Double? {
        guard let neck = point(.neck, minConfidence: 0.2), let hip = hipCenter else { return nil }
        let dx = (neck.x - hip.x) * aspect
        let dy = neck.y - hip.y
        let length = (dx * dx + dy * dy).squareRoot()
        return length > 0.02 ? length : nil
    }

    /// Visible body span (head to feet) in height-normalized units, used to auto-fit the cutout scale.
    var standingSpan: Double? {
        guard let head = headPoint, let foot = footY else { return nil }
        let span = head.y - foot
        return span > 0.1 ? span : nil
    }

    /// Interior knee angle in degrees, averaged over the sides that are confidently visible.
    var kneeAngle: Double? {
        let sides: [(Joint, Joint, Joint)] = [(.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle)]
        let angles = sides.compactMap { hipJ, kneeJ, ankleJ -> Double? in
            guard let hip = point(hipJ), let knee = point(kneeJ), let ankle = point(ankleJ) else { return nil }
            let a = ((hip.x - knee.x) * aspect, hip.y - knee.y)
            let b = ((ankle.x - knee.x) * aspect, ankle.y - knee.y)
            let la = (a.0 * a.0 + a.1 * a.1).squareRoot()
            let lb = (b.0 * b.0 + b.1 * b.1).squareRoot()
            guard la > 0.01, lb > 0.01 else { return nil }
            let cosine = max(-1, min(1, (a.0 * b.0 + a.1 * b.1) / (la * lb)))
            return acos(cosine) * 180 / .pi
        }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / Double(angles.count)
    }
}

nonisolated enum Zone: Int, CaseIterable, Sendable {
    case left, right
}

nonisolated enum ZoneAssigner {
    /// Keeps the two largest people and assigns them to the left/right play zones by horizontal position.
    /// A single person is assigned to whichever half of the frame they stand in.
    static func assign(_ people: [PersonPose]) -> [Zone: PersonPose] {
        let candidates = people.compactMap { pose -> (PersonPose, Double, Double)? in
            guard let x = pose.centerX else { return nil }
            return (pose, x, pose.torsoLength ?? 0)
        }
        let largest = candidates.sorted { $0.2 > $1.2 }.prefix(2).sorted { $0.1 < $1.1 }
        switch largest.count {
        case 2: return [.left: largest[0].0, .right: largest[1].0]
        case 1: return [largest[0].1 < 0.5 ? .left : .right: largest[0].0]
        default: return [:]
        }
    }
}

/// Zone assignment with memory. Plain left/right-of-centre assignment made a single player near the
/// midline flicker between zones on iPad (repeated found/lost). This keeps each zone's last position and
/// only moves a lone person to the other zone once they are clearly across the line.
nonisolated struct ZoneTracker: Sendable {
    /// How far past the centre line (normalized x) a lone person must be to change zone.
    var margin = 0.1
    /// How long a zone's last position is remembered.
    var memory = 1.0
    private var lastX: [Zone: Double] = [:]
    private var lastSeen: [Zone: Double] = [:]

    init(margin: Double = 0.1, memory: Double = 1.0) {
        self.margin = margin
        self.memory = memory
    }

    mutating func assign(_ people: [PersonPose], at time: Double) -> [Zone: PersonPose] {
        let positional = ZoneAssigner.assign(people)
        var result = positional
        if positional.count == 1, let (zone, person) = positional.first, let x = person.centerX {
            let recent = Zone.allCases.filter { (lastSeen[$0] ?? -.infinity) > time - memory }
            var chosen = zone
            if recent.count == 2 {
                // Both zones were occupied a moment ago: the person is whoever was nearest.
                chosen = recent.min { abs((lastX[$0] ?? 0.5) - x) < abs((lastX[$1] ?? 0.5) - x) } ?? zone
            } else if let previous = recent.first {
                let clearlyCrossed = previous == .left ? x > 0.5 + margin : x < 0.5 - margin
                chosen = clearlyCrossed ? zone : previous
            }
            result = [chosen: person]
        }
        for (zone, person) in result {
            lastX[zone] = person.centerX ?? lastX[zone]
            lastSeen[zone] = time
        }
        return result
    }
}
