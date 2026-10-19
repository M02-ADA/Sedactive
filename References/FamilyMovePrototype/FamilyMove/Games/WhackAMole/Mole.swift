import Foundation
import CoreGraphics

enum MoleZone: String, CaseIterable { case side, overhead, low }
struct Mole: Identifiable {
    let id = UUID()
    let playerID: Int
    let zone: MoleZone
    let position: CGPoint
    let radius: CGFloat
    let spawnedAt: TimeInterval
    var isHit = false
}
enum MoleConstants {
    static let lifetime: TimeInterval = 2
    static let collisionRadiusMultiplier: CGFloat = 1.3
    static let arenaTopInset: CGFloat = 128
    static let arenaBottomInset: CGFloat = 80
}
