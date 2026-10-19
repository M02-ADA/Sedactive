import Foundation

enum ObstacleType: String, CaseIterable {
    case bird, alligator
    var movement: MovementKind { self == .bird ? .squat : .jump }
}
struct Obstacle: Identifiable {
    let id = UUID()
    let playerID: Int
    let type: ObstacleType
    let spawnedAt: TimeInterval
    var isResolved = false
}
struct ObstacleSpawner {
    private var history: [Int: [ObstacleType]] = [:]
    mutating func spawn(playerID: Int, now: TimeInterval) -> Obstacle {
        var type = ObstacleType.allCases.randomElement()!
        let previous = history[playerID, default: []]
        if previous.count == 2 && previous.allSatisfy({ $0 == type }) { type = type == .bird ? .alligator : .bird }
        history[playerID] = Array((previous + [type]).suffix(2))
        return Obstacle(playerID: playerID, type: type, spawnedAt: now)
    }
}
enum ObstacleConstants { static let lifetime: TimeInterval = 2 }
