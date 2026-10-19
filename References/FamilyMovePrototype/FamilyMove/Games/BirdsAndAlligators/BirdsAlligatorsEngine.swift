import Foundation

struct BirdsAlligatorsEngine {
    private(set) var obstacles: [Int: Obstacle] = [:]
    private(set) var stats = [1: PlayerRoundStats(), 2: PlayerRoundStats()]
    private var detectors = [1: MovementDetector(), 2: MovementDetector()]
    private var spawner = ObstacleSpawner()
    private var nextSpawn: [Int: TimeInterval] = [:]

    mutating func discardActive() {
        obstacles = [:]; nextSpawn = [:]; detectors = [1: MovementDetector(), 2: MovementDetector()]
    }

    mutating func update(players: [TrackedPlayer], calibration: [Int: CalibrationSnapshot],
                         now: TimeInterval) -> [FeedbackEvent] {
        var feedback: [FeedbackEvent] = []
        for id in 1...2 {
            let player = players.first { $0.id == id && $0.isDetected }
            if let obstacle = obstacles[id], let baseline = calibration[id] {
                let age = now - obstacle.spawnedAt
                if age >= ObstacleConstants.lifetime {
                    obstacles[id] = nil; stats[id]!.misses += 1
                    nextSpawn[id] = now + Double.random(in: GameConstants.nextEventDelay)
                    detectors[id]!.reset(); NSLog("[MISS] P%d %@", id, obstacle.type.rawValue)
                } else if let player {
                    if let movement = detectors[id]!.update(player: player, calibration: baseline, now: now),
                       movement == obstacle.type.movement {
                        obstacles[id] = nil; stats[id]!.hits += 1; stats[id]!.totalReactionTime += age
                        if movement == .squat { stats[id]!.squatCount += 1 } else { stats[id]!.jumpCount += 1 }
                        nextSpawn[id] = now + Double.random(in: GameConstants.nextEventDelay)
                        feedback.append(FeedbackEvent(playerID: id, position: player.bodyCenter ?? baseline.bodyCenter, createdAt: now))
                        NSLog("[SUCCESS] P%d %@ reaction %.2f", id, obstacle.type.rawValue, age)
                    }
                } else { detectors[id]!.reset() }
            } else if now >= nextSpawn[id, default: 0], player != nil, calibration[id] != nil {
                let obstacle = spawner.spawn(playerID: id, now: now)
                obstacles[id] = obstacle; detectors[id]!.reset()
                NSLog("[EVENT SPAWN] P%d %@ %.2f", id, obstacle.type.rawValue, now)
            }
        }
        return feedback
    }
}
