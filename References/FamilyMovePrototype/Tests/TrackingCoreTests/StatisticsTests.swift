import XCTest
@testable import TrackingCore

final class StatisticsTests: XCTestCase {
    let first = UUID(), second = UUID()
    var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }
    func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))! }
    func record(_ day: Int, score: Int = 20, completed: Bool = true, member: UUID? = nil) -> SessionRecord {
        SessionRecord(id: UUID(), game: .whackAMole, startedAt: date(day), durationSeconds: 60, score: score,
                      completed: completed, participants: [ParticipantRecord(memberID: member ?? first, hits: 2, estimatedCalories: 3)])
    }
    func testWeeklyCountsMinutesCaloriesAndProfileFiltering() {
        let service = StatisticsService(sessions: [record(16), record(15), record(11), record(16, completed: false), record(16, member: second)], calendar: calendar, now: date(16))
        XCTAssertEqual(service.weeklyGames(), 3)
        XCTAssertEqual(service.weeklyGames(member: first), 2)
        XCTAssertEqual(service.weeklyActiveMinutes(), 3)
        XCTAssertEqual(service.weeklyCalories(member: first), 6)
        XCTAssertEqual(service.weeklyGoalProgress(member: first, goal: 10), 0.2)
        XCTAssertEqual(service.weeklyGoalProgress(member: first, goal: 1), 1)
    }
    func testStreakEndsTodayOrYesterdayAndDeduplicatesDays() {
        let sessions = [record(16), record(16), record(15), record(14), record(12)]
        XCTAssertEqual(StatisticsService(sessions: sessions, calendar: calendar, now: date(16)).currentStreak(member: first), 3)
        XCTAssertEqual(StatisticsService(sessions: sessions, calendar: calendar, now: date(17)).currentStreak(member: first), 3)
        XCTAssertEqual(StatisticsService(sessions: sessions, calendar: calendar, now: date(18)).currentStreak(member: first), 0)
    }
    func testHighScoresExcludeIncompleteAndOtherProfiles() {
        let service = StatisticsService(sessions: [record(15, score: 50), record(16, score: 80, member: second), record(16, score: 999, completed: false)], calendar: calendar, now: date(16))
        XCTAssertEqual(service.highScore(game: .whackAMole), 80)
        XCTAssertEqual(service.highScore(game: .whackAMole, member: first), 50)
        XCTAssertEqual(service.highScore(game: .birdsAndAlligators), 0)
    }
    func testEmptyHistory() {
        let service = StatisticsService(sessions: [], calendar: calendar, now: date(16))
        XCTAssertEqual(service.currentStreak(member: first), 0)
        XCTAssertEqual(service.weeklyGoalProgress(member: first, goal: 10), 0)
        XCTAssertFalse(service.achievements(member: first).contains { $0.unlocked })
    }
    func testMovementTotalsAndAchievementProgressStayPersonal() {
        let firstRecord = ParticipantRecord(memberID: first, hits: 12, squatCount: 4, jumpCount: 3,
                                            sideReachCount: 5, overheadReachCount: 4, lowReachCount: 3)
        let secondRecord = ParticipantRecord(memberID: second, hits: 25, jumpCount: 25, sideReachCount: 25)
        let session = SessionRecord(id: UUID(), game: .whackAMole, startedAt: date(16), durationSeconds: 60,
                                    score: 370, participants: [firstRecord, secondRecord])
        let service = StatisticsService(sessions: [session], calendar: calendar, now: date(16))
        let moves = service.movementTotals(member: first)
        XCTAssertEqual(moves.reaches, 12); XCTAssertEqual(moves.squats, 4); XCTAssertEqual(moves.jumps, 3)
        let achievement = service.achievements(member: first).first { $0.id == "moles" }!
        XCTAssertFalse(achievement.unlocked)
        XCTAssertEqual(achievement.progressLabel, "12 / 25 moles")
        XCTAssertTrue(service.achievements(member: second).first { $0.id == "moles" }!.unlocked)
    }

    func testDecimalInputHandlesCommaAndWhitespace() {
        XCTAssertEqual(ProfileValidation.decimal(" 68,5 "), 68.5)
        XCTAssertNil(ProfileValidation.decimal("not a number"))
        XCTAssertFalse(ProfileValidation.valid(name: " ", weight: 68))
        XCTAssertFalse(ProfileValidation.valid(name: "Parent", weight: .infinity))
    }
    func testStreakAcrossDaylightSavingUsesCalendarDays() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))! }
        let sessions = (6...9).map { SessionRecord(id: UUID(), game: .whackAMole, startedAt: d($0), durationSeconds: 60, score: 10, participants: [ParticipantRecord(memberID: first)]) }
        XCTAssertEqual(StatisticsService(sessions: sessions, calendar: cal, now: d(9)).currentStreak(member: first), 4)
    }
}
