import Foundation
import SwiftData

@Model
final class ParticipantSessionStat {
    @Attribute(.unique) var id: UUID
    var member: FamilyMember?
    var session: GameSession?
    var scoreContribution: Int = 0
    var hits: Int = 0
    var misses: Int = 0
    var squatCount: Int = 0
    var jumpCount: Int = 0
    var sideReachCount: Int = 0
    var overheadReachCount: Int = 0
    var lowReachCount: Int = 0
    var averageReactionTime: Double?
    var estimatedCalories: Double = 0

    init(member: FamilyMember) { id = UUID(); self.member = member }
}
