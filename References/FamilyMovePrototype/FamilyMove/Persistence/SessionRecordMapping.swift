import Foundation

extension GameSession {
    var record: SessionRecord {
        SessionRecord(id: id, game: GameType(rawValue: gameTypeRaw) ?? .whackAMole,
                      startedAt: startedAt, durationSeconds: durationSeconds, score: finalScore, completed: completed,
                      participants: participantStats.compactMap { stat in
            guard let member = stat.member else { return nil }
            return ParticipantRecord(memberID: member.id, hits: stat.hits, squatCount: stat.squatCount,
                                     jumpCount: stat.jumpCount, estimatedCalories: stat.estimatedCalories,
                                     sideReachCount: stat.sideReachCount, overheadReachCount: stat.overheadReachCount,
                                     lowReachCount: stat.lowReachCount)
        })
    }
}
