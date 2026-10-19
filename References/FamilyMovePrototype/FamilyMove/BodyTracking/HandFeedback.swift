import CoreGraphics
import Foundation

struct TrackedHand: Identifiable, Equatable {
    enum Side: String { case left, right }
    let playerID: Int
    let side: Side
    let position: CGPoint
    let timestamp: TimeInterval
    var id: String { "\(playerID)-\(side.rawValue)" }
}

extension TrackedPlayer {
    // These are the already mirrored, aspect-fill-mapped wrist coordinates used
    // for collision. The effect must never map or smooth them a second time.
    var confidentHands: [TrackedHand] {
        guard isDetected else { return [] }
        return [(TrackedHand.Side.left, leftWrist), (.right, rightWrist)].compactMap { side, wrist in
            guard let wrist, wrist.confidence >= GameConstants.minimumJointConfidence,
                  wrist.position.x.isFinite, wrist.position.y.isFinite else { return nil }
            return TrackedHand(playerID: id, side: side, position: wrist.position, timestamp: lastSeen)
        }
    }
}

struct HandFeedback {
    struct Trail {
        let hand: TrackedHand
        let points: [CGPoint]
    }
    static let trailLifetime: TimeInterval = 0.18
    private var samples: [String: [TrackedHand]] = [:]

    mutating func update(players: [TrackedPlayer], now: TimeInterval) {
        let hands = players.flatMap(\.confidentHands).filter {
            $0.timestamp <= now && now - $0.timestamp <= GameConstants.maximumPoseAge
        }
        let visible = Set(hands.map(\.id))
        samples = samples.filter { visible.contains($0.key) }
        for hand in hands {
            var history = samples[hand.id, default: []].filter { now - $0.timestamp <= Self.trailLifetime }
            // The watchdog republishes poses too. Only genuine new observations
            // may extend a trail; a stalled frame must disappear on time.
            if let last = history.last, hand.timestamp < last.timestamp { continue }
            // A reacquired pose can jump across the screen. Show its new hand
            // immediately without drawing a long beam between unrelated points.
            if let last = history.last,
               hypot(hand.position.x - last.position.x, hand.position.y - last.position.y) > 120 {
                history = []
            }
            if history.last?.timestamp != hand.timestamp { history.append(hand) }
            samples[hand.id] = Array(history.suffix(6))
        }
    }

    func trails(at now: TimeInterval) -> [Trail] {
        samples.keys.sorted().compactMap { key in
            guard let history = samples[key], let hand = history.last,
                  now >= hand.timestamp, now - hand.timestamp <= GameConstants.maximumPoseAge else { return nil }
            return Trail(hand: hand, points: history.filter { now - $0.timestamp <= Self.trailLifetime }.map(\.position))
        }
    }
}
