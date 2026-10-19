import Foundation

enum GameSessionState { case positioning, calibrating, countdown, playing, paused, gameOver }
enum SessionPauseReason { case tracking, camera, background, manual }

struct PlayerRoundStats {
    var hits = 0
    var misses = 0
    var squatCount = 0
    var jumpCount = 0
    var sideReachCount = 0
    var overheadReachCount = 0
    var lowReachCount = 0
    var totalReactionTime: Double = 0
    var scoreContribution: Int { hits * GameConstants.scorePerSuccess }
    var averageReactionTime: Double? { hits == 0 ? nil : totalReactionTime / Double(hits) }
}

struct FeedbackEvent: Identifiable {
    let id = UUID()
    let playerID: Int
    let position: CGPoint
    let createdAt: TimeInterval
    var text = "Excellent!"
}
