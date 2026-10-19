import CoreGraphics
import Foundation

/// Screen-space spatial matching. IDs are ours; Vision UUIDs are not tracking IDs.
struct PlayerTracker {
    private(set) var players = [TrackedPlayer(id: 1), TrackedPlayer(id: 2)]
    private let smoother = PositionSmoother()

    mutating func reset() {
        players = [TrackedPlayer(id: 1), TrackedPlayer(id: 2)]
    }

    mutating func update(observations: [BodyObservation], mapper: CoordinateMapper,
                         timestamp: TimeInterval) -> [TrackedPlayer] {
        expire(at: timestamp)
        let candidates = observations.filter { $0.bodyCenter != nil }
            .sorted { $0.quality > $1.quality }.prefix(GameConstants.maximumPlayers)
            .map { observation in
                MappedBody(observation: observation, mapper: mapper)
            }
        let assignments = match(candidates, screenWidth: mapper.screenSize.width)
        for index in players.indices {
            guard let candidateIndex = assignments[index] else {
                // Retain the center for identity matching during the grace period,
                // but discard all actionable joints as soon as detection is lost.
                clearJoints(at: index)
                continue
            }
            let body = candidates[candidateIndex]
            let previous = players[index]
            players[index].bodyCenter = smoother.smooth(body.center, previous: previous.bodyCenter)
            players[index].leftWrist = smoother.smooth(body.leftWrist, previous: previous.leftWrist)
            players[index].rightWrist = smoother.smooth(body.rightWrist, previous: previous.rightWrist)
            players[index].leftElbow = smoother.smooth(body.leftElbow, previous: previous.leftElbow)
            players[index].rightElbow = smoother.smooth(body.rightElbow, previous: previous.rightElbow)
            players[index].leftShoulder = smoother.smooth(body.leftShoulder, previous: previous.leftShoulder)
            players[index].rightShoulder = smoother.smooth(body.rightShoulder, previous: previous.rightShoulder)
            players[index].leftHip = smoother.smooth(body.leftHip, previous: previous.leftHip)
            players[index].rightHip = smoother.smooth(body.rightHip, previous: previous.rightHip)
            players[index].leftKnee = smoother.smooth(body.leftKnee, previous: previous.leftKnee)
            players[index].rightKnee = smoother.smooth(body.rightKnee, previous: previous.rightKnee)
            players[index].leftAnkle = smoother.smooth(body.leftAnkle, previous: previous.leftAnkle)
            players[index].rightAnkle = smoother.smooth(body.rightAnkle, previous: previous.rightAnkle)
            players[index].hipCenter = smoother.smooth(body.hipCenter, previous: previous.hipCenter)
            players[index].isDetected = true
            players[index].lastSeen = timestamp
        }
        return players
    }

    /// Called even if no frames arrive (background, interruption, stalled Vision).
    mutating func expire(at timestamp: TimeInterval) {
        for index in players.indices {
            let age = timestamp - players[index].lastSeen
            if age > GameConstants.maximumPoseAge { clearJoints(at: index) }
            if age > GameConstants.playerLostGracePeriod { players[index].bodyCenter = nil }
        }
    }

    private mutating func clearJoints(at index: Int) {
        players[index].isDetected = false
        players[index].leftWrist = nil
        players[index].rightWrist = nil
        players[index].leftElbow = nil
        players[index].rightElbow = nil
        players[index].leftShoulder = nil
        players[index].rightShoulder = nil
        players[index].leftHip = nil
        players[index].rightHip = nil
        players[index].leftKnee = nil
        players[index].rightKnee = nil
        players[index].leftAnkle = nil
        players[index].rightAnkle = nil
        players[index].hipCenter = nil
    }

    private func match(_ bodies: [MappedBody], screenWidth: CGFloat) -> [Int?] {
        guard !bodies.isEmpty else { return [nil, nil] }
        let centers = players.map(\.bodyCenter)
        if centers.allSatisfy({ $0 == nil }) {
            if bodies.count == 1 {
                return bodies[0].center.x < screenWidth / 2 ? [0, nil] : [nil, 0]
            }
            return bodies[0].center.x < bodies[1].center.x ? [0, 1] : [1, 0]
        }

        func cost(_ body: Int, _ player: Int) -> CGFloat {
            let anchor = centers[player] ?? CGPoint(x: screenWidth * (player == 0 ? 0.25 : 0.75),
                                                   y: bodies[body].center.y)
            return hypot(bodies[body].center.x - anchor.x, bodies[body].center.y - anchor.y)
        }

        if bodies.count == 1 {
            return cost(0, 0) <= cost(0, 1) ? [0, nil] : [nil, 0]
        }
        // Compare BOTH complete assignments; greedy nearest-neighbor can steal a body.
        return cost(0, 0) + cost(1, 1) <= cost(0, 1) + cost(1, 0) ? [0, 1] : [1, 0]
    }

    private struct MappedBody {
        let center: CGPoint
        let leftWrist: JointPoint?
        let rightWrist: JointPoint?
        let leftElbow: JointPoint?
        let rightElbow: JointPoint?
        let leftShoulder: JointPoint?
        let rightShoulder: JointPoint?
        let leftHip: JointPoint?
        let rightHip: JointPoint?
        let leftKnee: JointPoint?
        let rightKnee: JointPoint?
        let leftAnkle: JointPoint?
        let rightAnkle: JointPoint?
        let hipCenter: CGPoint?

        init(observation: BodyObservation, mapper: CoordinateMapper) {
            center = mapper.screenPoint(from: observation.bodyCenter!)
            leftWrist = mapper.screenJoint(from: observation.leftWrist)
            rightWrist = mapper.screenJoint(from: observation.rightWrist)
            leftElbow = mapper.screenJoint(from: observation.leftElbow)
            rightElbow = mapper.screenJoint(from: observation.rightElbow)
            leftShoulder = mapper.screenJoint(from: observation.leftShoulder)
            rightShoulder = mapper.screenJoint(from: observation.rightShoulder)
            leftHip = mapper.screenJoint(from: observation.leftHip)
            rightHip = mapper.screenJoint(from: observation.rightHip)
            leftKnee = mapper.screenJoint(from: observation.leftKnee)
            rightKnee = mapper.screenJoint(from: observation.rightKnee)
            leftAnkle = mapper.screenJoint(from: observation.leftAnkle)
            rightAnkle = mapper.screenJoint(from: observation.rightAnkle)
            hipCenter = observation.hipCenter.map { mapper.screenPoint(from: $0) }
        }
    }
}
