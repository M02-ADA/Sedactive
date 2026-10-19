import SwiftData
import Foundation

@MainActor
struct SessionRepository {
    let context: ModelContext
    func all() throws -> [GameSession] {
        try context.fetch(FetchDescriptor<GameSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }
    func contains(id: UUID) throws -> Bool { try all().contains { $0.id == id } }

    func saveCompleted(id: UUID, game: GameType, members: [FamilyMember], startedAt: Date,
                       duration: Double, score: Int, stats: [Int: PlayerRoundStats]) throws {
        guard try !contains(id: id) else { return }
        guard members.count == 2, duration > 0 else { return }
        let session = GameSession(id: id, gameType: game, startedAt: startedAt, durationSeconds: duration, finalScore: score)
        let estimator = SessionEnergyEstimator()
        session.participantStats = members.enumerated().map { index, member in
            let round = stats[index + 1, default: PlayerRoundStats()]
            let participant = ParticipantSessionStat(member: member)
            participant.scoreContribution = round.scoreContribution; participant.hits = round.hits
            participant.misses = round.misses; participant.squatCount = round.squatCount
            participant.jumpCount = round.jumpCount; participant.sideReachCount = round.sideReachCount
            participant.overheadReachCount = round.overheadReachCount; participant.lowReachCount = round.lowReachCount
            participant.averageReactionTime = round.averageReactionTime
            participant.estimatedCalories = estimator.calories(game: game, weightKg: member.bodyWeightKg, durationSeconds: duration)
            return participant
        }
        context.insert(session)
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
