import Foundation

struct ParticipantRecord {
    let memberID: UUID
    var hits: Int = 0
    var squatCount: Int = 0
    var jumpCount: Int = 0
    var estimatedCalories: Double = 0
    var sideReachCount: Int = 0
    var overheadReachCount: Int = 0
    var lowReachCount: Int = 0
}
struct SessionRecord {
    let id: UUID
    let game: GameType
    let startedAt: Date
    let durationSeconds: Double
    let score: Int
    var completed = true
    let participants: [ParticipantRecord]
}
struct Achievement: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let progress: Int
    let target: Int
    let unit: String
    var unlocked: Bool { progress >= target }
    var progressLabel: String { "\(min(progress, target)) / \(target) \(unit)" }
}

struct MovementTotals {
    var reaches = 0
    var squats = 0
    var jumps = 0
}

struct StatisticsService {
    let sessions: [SessionRecord]
    var calendar = Calendar.current
    var now = Date()

    func completed(member: UUID? = nil) -> [SessionRecord] {
        sessions.filter { $0.completed && $0.startedAt <= now && (member == nil || $0.participants.contains { $0.memberID == member }) }
    }
    func weeklySessions(member: UUID? = nil) -> [SessionRecord] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return completed(member: member).filter { $0.startedAt >= week.start && $0.startedAt < week.end }
    }
    func weeklyGames(member: UUID? = nil) -> Int { weeklySessions(member: member).count }
    func weeklyActiveMinutes(member: UUID? = nil) -> Double {
        weeklySessions(member: member).reduce(0) { $0 + $1.durationSeconds } / 60
    }
    func weeklyCalories(member: UUID) -> Double {
        weeklySessions(member: member).flatMap(\.participants).filter { $0.memberID == member }.reduce(0) { $0 + $1.estimatedCalories }
    }
    func highScore(game: GameType, member: UUID? = nil) -> Int {
        completed(member: member).filter { $0.game == game }.map(\.score).max() ?? 0
    }
    func currentStreak(member: UUID) -> Int {
        let days = Set(completed(member: member).map { calendar.startOfDay(for: $0.startedAt) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
    func weeklyGoalProgress(member: UUID, goal: Int) -> Double {
        min(1, Double(weeklyGames(member: member)) / Double(max(1, goal)))
    }
    func achievements(member: UUID) -> [Achievement] {
        let personal = completed(member: member)
        let moleHits = personal.filter { $0.game == .whackAMole }.flatMap(\.participants)
            .filter { $0.memberID == member }.reduce(0) { $0 + $1.hits }
        let jumps = personal.flatMap(\.participants).filter { $0.memberID == member }.reduce(0) { $0 + $1.jumpCount }
        return [Achievement(id: "first", title: "First Move", symbol: "star.fill", progress: personal.count, target: 1, unit: "game"),
                Achievement(id: "moles", title: "Mole Hunter", symbol: "target", progress: moleHits, target: 25, unit: "moles"),
                Achievement(id: "jumps", title: "Jump Master", symbol: "figure.jumprope", progress: jumps, target: 25, unit: "jumps"),
                Achievement(id: "family", title: "Family Time", symbol: "person.2.fill", progress: personal.count, target: 10, unit: "games"),
                Achievement(id: "streak", title: "On a Roll", symbol: "flame.fill", progress: currentStreak(member: member), target: 7, unit: "days")]
    }
    func movementTotals(member: UUID) -> MovementTotals {
        completed(member: member).flatMap(\.participants).filter { $0.memberID == member }.reduce(into: MovementTotals()) {
            $0.reaches += $1.sideReachCount + $1.overheadReachCount + $1.lowReachCount
            $0.squats += $1.squatCount; $0.jumps += $1.jumpCount
        }
    }
}
