import Foundation
import CoreGraphics

/// Manual input produces short pose changes. The existing collision/movement
/// engines still validate every action and award the score.
struct SimulatorInput {
    private(set) var hasStarted = false
    private var reaches: [Int: (moleID: UUID, point: CGPoint, started: TimeInterval)] = [:]
    private var movements: [Int: (kind: MovementKind, started: TimeInterval)] = [:]
    static let reachDuration: TimeInterval = 0.18
    static let movementDuration: TimeInterval = 0.9

    mutating func begin() { hasStarted = true; clearActions() }
    mutating func reset() { self = Self() }
    mutating func clearActions() { reaches = [:]; movements = [:] }

    mutating func hit(_ mole: Mole, elapsed: TimeInterval) {
        guard hasStarted, (1...2).contains(mole.playerID), !mole.isHit else { return }
        reaches[mole.playerID] = (mole.id, mole.position, elapsed)
    }
    mutating func move(_ movement: MovementKind, playerID: Int, elapsed: TimeInterval) {
        guard hasStarted, (1...2).contains(playerID), !isMoving(playerID, elapsed: elapsed) else { return }
        movements[playerID] = (movement, elapsed)
    }
    func isMoving(_ playerID: Int, elapsed: TimeInterval) -> Bool {
        guard let action = movements[playerID] else { return false }
        return elapsed >= action.started && elapsed - action.started < Self.movementDuration
    }
    func players(screen: CGSize, timestamp: TimeInterval, elapsed: TimeInterval, moles: [Mole]) -> [TrackedPlayer] {
        guard hasStarted, screen.width > 0, screen.height > 0 else { return [] }
        return (1...2).map { id in
            var movement: MovementKind?
            if let action = movements[id], (0.08..<0.45).contains(elapsed - action.started) { movement = action.kind }
            var target: CGPoint?
            if let reach = reaches[id], elapsed >= reach.started,
               elapsed - reach.started < Self.reachDuration,
               moles.contains(where: { $0.id == reach.moleID && $0.playerID == id && !$0.isHit }) {
                target = reach.point
            }
            return SimulatedBodyPose.player(id: id, screen: screen, timestamp: timestamp,
                                            movement: movement, wristTarget: target, restingWrists: false)
        }
    }
}
