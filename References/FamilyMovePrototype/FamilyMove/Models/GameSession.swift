import Foundation
import SwiftData

@Model
final class GameSession {
    @Attribute(.unique) var id: UUID
    var gameTypeRaw: String
    var startedAt: Date
    var durationSeconds: Double
    var finalScore: Int
    var completed: Bool
    @Relationship(deleteRule: .cascade, inverse: \ParticipantSessionStat.session)
    var participantStats: [ParticipantSessionStat] = []

    init(id: UUID, gameType: GameType, startedAt: Date, durationSeconds: Double, finalScore: Int) {
        self.id = id; gameTypeRaw = gameType.rawValue; self.startedAt = startedAt
        self.durationSeconds = durationSeconds; self.finalScore = finalScore; completed = true
    }
}
