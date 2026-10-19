import Foundation

struct WhackAMoleEngine {
    private(set) var moles: [Int: Mole] = [:]
    private(set) var stats = [1: PlayerRoundStats(), 2: PlayerRoundStats()]
    private var nextSpawn: [Int: TimeInterval] = [:]
    private var spawner = MoleSpawner()
    private let collision = CollisionDetector()

    mutating func discardActive() { moles = [:]; nextSpawn = [:] }

    mutating func update(players: [TrackedPlayer], calibration: [Int: CalibrationSnapshot],
                         screen: CGSize, now: TimeInterval) -> [FeedbackEvent] {
        var feedback: [FeedbackEvent] = []
        for id in 1...2 {
            let player = players.first { $0.id == id && $0.isDetected }
            if var mole = moles[id] {
                let age = now - mole.spawnedAt
                if age < MoleConstants.lifetime, let player, collision.hit(player: player, mole: mole) {
                    mole.isHit = true
                    moles[id] = nil
                    stats[id]!.hits += 1; stats[id]!.totalReactionTime += age
                    switch mole.zone {
                    case .side: stats[id]!.sideReachCount += 1
                    case .overhead: stats[id]!.overheadReachCount += 1
                    case .low: stats[id]!.lowReachCount += 1
                    }
                    feedback.append(FeedbackEvent(playerID: id, position: mole.position, createdAt: now))
                    nextSpawn[id] = now + Double.random(in: GameConstants.nextEventDelay)
                    NSLog("[SUCCESS] P%d %@ reaction %.2f score %d", id, mole.zone.rawValue, age, stats[id]!.scoreContribution)
                } else if age >= MoleConstants.lifetime {
                    moles[id] = nil; stats[id]!.misses += 1
                    nextSpawn[id] = now + Double.random(in: GameConstants.nextEventDelay)
                    NSLog("[MISS] P%d %@", id, mole.zone.rawValue)
                }
            } else if now >= nextSpawn[id, default: 0], let player, let baseline = calibration[id] {
                let mole = spawner.spawn(player: player, calibration: baseline, screen: screen, now: now)
                moles[id] = mole
                NSLog("[EVENT SPAWN] P%d %@ %.2f (%.0f, %.0f)", id, mole.zone.rawValue, now, mole.position.x, mole.position.y)
            }
        }
        return feedback
    }
}
