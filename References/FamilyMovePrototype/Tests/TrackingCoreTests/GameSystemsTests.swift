import XCTest
import CoreGraphics
import SwiftData
@testable import TrackingCore

final class GameSystemsTests: XCTestCase {
    func player(_ id: Int = 1, hipY: CGFloat = 400, time: Double = 1) -> TrackedPlayer {
        let x: CGFloat = id == 1 ? 250 : 750
        func joint(_ x: CGFloat, _ y: CGFloat) -> JointPoint { JointPoint(position: CGPoint(x: x, y: y), confidence: 0.9) }
        var player = TrackedPlayer(id: id)
        player.isDetected = true; player.lastSeen = time
        player.bodyCenter = CGPoint(x: x, y: hipY - 50)
        player.leftShoulder = joint(x - 40, hipY - 100); player.rightShoulder = joint(x + 40, hipY - 100)
        player.leftHip = joint(x - 30, hipY); player.rightHip = joint(x + 30, hipY)
        player.hipCenter = CGPoint(x: x, y: hipY)
        return player
    }

    func testCollisionInsideOutsideNilWrongPlayerAndAlreadyHit() {
        let detector = CollisionDetector()
        var p = player()
        var mole = Mole(playerID: 1, zone: .side, position: CGPoint(x: 250, y: 350), radius: 50, spawnedAt: 0)
        XCTAssertFalse(detector.hit(player: p, mole: mole))
        p.leftWrist = JointPoint(position: CGPoint(x: 315, y: 350), confidence: 0.9)
        XCTAssertTrue(detector.hit(player: p, mole: mole))
        p.leftWrist!.position.x = 316
        XCTAssertFalse(detector.hit(player: p, mole: mole))
        p.leftWrist!.position = mole.position
        mole.isHit = true
        XCTAssertFalse(detector.hit(player: p, mole: mole))
        mole.isHit = false
        p.leftWrist!.confidence = 0.29
        XCTAssertFalse(detector.hit(player: p, mole: mole))
        var other = player(2); other.leftWrist = JointPoint(position: mole.position, confidence: 1)
        XCTAssertFalse(detector.hit(player: other, mole: mole))
    }

    func testSpawnerSafeHalvesRepetitionAndOuterSide() {
        var spawner = MoleSpawner()
        for id in 1...2 {
            let p = player(id); let baseline = CalibrationSnapshot(player: p)!
            var zones: [MoleZone] = []
            for index in 0..<200 {
                let mole = spawner.spawn(player: p, calibration: baseline, screen: CGSize(width: 1000, height: 700), now: Double(index))
                XCTAssertGreaterThanOrEqual(mole.position.x - mole.radius, id == 1 ? 0 : 500)
                XCTAssertLessThanOrEqual(mole.position.x + mole.radius, id == 1 ? 500 : 1000)
                XCTAssertGreaterThanOrEqual(mole.position.y - mole.radius, 125)
                XCTAssertLessThanOrEqual(mole.position.y + mole.radius, 700)
                if mole.zone == .side {
                    if id == 1 { XCTAssertLessThan(mole.position.x, p.bodyCenter!.x) }
                    else { XCTAssertGreaterThan(mole.position.x, p.bodyCenter!.x) }
                }
                zones.append(mole.zone)
                if zones.count >= 3 { XCTAssertFalse(zones.suffix(3).allSatisfy { $0 == mole.zone }) }
            }
        }
    }

    func testMoleHitScoresOnlyOnceThenWaitsToRespawn() {
        var engine = WhackAMoleEngine()
        var p = player(); let baseline = CalibrationSnapshot(player: p)!
        _ = engine.update(players: [p], calibration: [1: baseline], screen: CGSize(width: 1000, height: 700), now: 0)
        let mole = engine.moles[1]!
        p.leftWrist = JointPoint(position: mole.position, confidence: 1)
        XCTAssertEqual(engine.update(players: [p], calibration: [1: baseline], screen: CGSize(width: 1000, height: 700), now: 0.1).count, 1)
        _ = engine.update(players: [p], calibration: [1: baseline], screen: CGSize(width: 1000, height: 700), now: 0.11)
        XCTAssertEqual(engine.stats[1]!.scoreContribution, 10)
        XCTAssertNil(engine.moles[1])
    }

    func testMoleTimeoutCountsMissWithoutScore() {
        var engine = WhackAMoleEngine()
        let p = player(); let baseline = CalibrationSnapshot(player: p)!
        _ = engine.update(players: [p], calibration: [1: baseline], screen: CGSize(width: 1000, height: 700), now: 0)
        _ = engine.update(players: [p], calibration: [1: baseline], screen: CGSize(width: 1000, height: 700), now: 2)
        XCTAssertEqual(engine.stats[1]!.misses, 1)
        XCTAssertEqual(engine.stats[1]!.hits, 0)
    }

    func testStandingDoesNotCountAndSquatRequiresReturn() {
        var detector = MovementDetector()
        let baseline = CalibrationSnapshot(player: player())!
        for index in 0..<5 { XCTAssertNil(detector.update(player: player(time: Double(index) * 0.1), calibration: baseline, now: Double(index) * 0.1)) }
        XCTAssertNil(detector.update(player: player(hipY: 425, time: 0.5), calibration: baseline, now: 0.5))
        XCTAssertEqual(detector.phase, .qualified)
        XCTAssertNil(detector.update(player: player(hipY: 425, time: 0.6), calibration: baseline, now: 0.6))
        XCTAssertEqual(detector.update(player: player(time: 0.7), calibration: baseline, now: 0.7), .squat)
        XCTAssertNil(detector.update(player: player(time: 0.8), calibration: baseline, now: 0.8))
    }

    func testJumpRequiresLandingAndCooldownSurvivesReset() {
        var detector = MovementDetector()
        let baseline = CalibrationSnapshot(player: player())!
        XCTAssertNil(detector.update(player: player(time: 0), calibration: baseline, now: 0))
        XCTAssertNil(detector.update(player: player(hipY: 380, time: 0.1), calibration: baseline, now: 0.1))
        XCTAssertEqual(detector.phase, .qualified)
        XCTAssertEqual(detector.update(player: player(time: 0.3), calibration: baseline, now: 0.3), .jump)
        detector.reset()
        XCTAssertNil(detector.update(player: player(time: 0.4), calibration: baseline, now: 0.4))
        XCTAssertNil(detector.update(player: player(hipY: 380, time: 0.5), calibration: baseline, now: 0.5))
        XCTAssertNil(detector.update(player: player(time: 0.6), calibration: baseline, now: 0.6))
    }

    func testLostTrackingCancelsMovement() {
        var detector = MovementDetector(); let baseline = CalibrationSnapshot(player: player())!
        _ = detector.update(player: player(time: 0), calibration: baseline, now: 0)
        _ = detector.update(player: player(hipY: 425, time: 0.1), calibration: baseline, now: 0.1)
        var lost = player(time: 0.2); lost.isDetected = false
        XCTAssertNil(detector.update(player: lost, calibration: baseline, now: 0.2))
        XCTAssertNil(detector.update(player: player(time: 0.3), calibration: baseline, now: 0.3))
    }

    func testReliableLegEvidenceRejectsStraightKneeSquatAndStationaryAnkleJump() {
        func legs(_ player: TrackedPlayer, ankleY: CGFloat = 600) -> TrackedPlayer {
            var p = player
            p.leftKnee = JointPoint(position: CGPoint(x: 220, y: 500), confidence: 1)
            p.leftAnkle = JointPoint(position: CGPoint(x: 220, y: ankleY), confidence: 1)
            return p
        }
        let baseline = CalibrationSnapshot(player: legs(player()))!
        var detector = MovementDetector()
        _ = detector.update(player: legs(player(time: 0)), calibration: baseline, now: 0)
        _ = detector.update(player: legs(player(hipY: 425, time: 0.1)), calibration: baseline, now: 0.1)
        XCTAssertNotEqual(detector.phase, .qualified)
        detector.reset()
        _ = detector.update(player: legs(player(time: 0.2)), calibration: baseline, now: 0.2)
        _ = detector.update(player: legs(player(hipY: 380, time: 0.3)), calibration: baseline, now: 0.3)
        XCTAssertNotEqual(detector.phase, .qualified)
        _ = detector.update(player: legs(player(hipY: 380, time: 0.4), ankleY: 580), calibration: baseline, now: 0.4)
        XCTAssertEqual(detector.phase, .qualified)
        XCTAssertEqual(detector.update(player: legs(player(time: 0.5)), calibration: baseline, now: 0.5), .jump)
    }

    func testBirdPlayersCompleteIndependentExpectedMovements() {
        var engine = BirdsAlligatorsEngine()
        let baselines = [1: CalibrationSnapshot(player: player())!, 2: CalibrationSnapshot(player: player(2))!]
        _ = engine.update(players: [player(), player(2)], calibration: baselines, now: 0)
        let events = engine.obstacles
        _ = engine.update(players: [player(time: 0.05), player(2, time: 0.05)], calibration: baselines, now: 0.05)
        let moving = (1...2).map { id in player(id, hipY: events[id]!.type == .bird ? 425 : 380, time: 0.15) }
        _ = engine.update(players: moving, calibration: baselines, now: 0.15)
        let feedback = engine.update(players: [player(time: 0.3), player(2, time: 0.3)], calibration: baselines, now: 0.3)
        XCTAssertEqual(feedback.count, 2)
        XCTAssertEqual(engine.stats.values.map(\.scoreContribution).reduce(0, +), 20)
        XCTAssertTrue(engine.obstacles.isEmpty)
    }

    func testWrongMovementDoesNotResolveObstacle() {
        var engine = BirdsAlligatorsEngine()
        let baselines = [1: CalibrationSnapshot(player: player())!]
        _ = engine.update(players: [player()], calibration: baselines, now: 0)
        let event = engine.obstacles[1]!
        _ = engine.update(players: [player(time: 0.05)], calibration: baselines, now: 0.05)
        _ = engine.update(players: [player(hipY: event.type == .bird ? 380 : 425, time: 0.15)], calibration: baselines, now: 0.15)
        _ = engine.update(players: [player(time: 0.3)], calibration: baselines, now: 0.3)
        XCTAssertEqual(engine.stats[1]!.hits, 0)
        XCTAssertEqual(engine.obstacles[1]?.id, event.id)
    }

    func testObstacleRepetitionLimitIsIndependentPerPlayer() {
        var spawner = ObstacleSpawner(); var history: [Int: [ObstacleType]] = [:]
        for index in 0..<200 {
            for id in 1...2 {
                let obstacle = spawner.spawn(playerID: id, now: Double(index))
                history[id, default: []].append(obstacle.type)
                if history[id]!.count >= 3 { XCTAssertFalse(history[id]!.suffix(3).allSatisfy { $0 == obstacle.type }) }
            }
        }
    }

    func testClockExcludesPauseAndClampsAtZero() {
        var clock = RoundClock(duration: 60)
        clock.resume(at: 100)
        XCTAssertEqual(clock.remaining(at: 110), 50)
        clock.pause(at: 110)
        XCTAssertEqual(clock.remaining(at: 1000), 50)
        clock.resume(at: 1000)
        XCTAssertEqual(clock.remaining(at: 1050), 0)
        XCTAssertEqual(clock.remaining(at: 2000), 0)
    }

    func testEnergyFormulaIsPerParticipant() {
        let estimator = SessionEnergyEstimator()
        XCTAssertEqual(estimator.calories(game: .whackAMole, weightKg: 60, durationSeconds: 60), 3.15, accuracy: 0.001)
        XCTAssertEqual(estimator.calories(game: .whackAMole, weightKg: 30, durationSeconds: 60), 1.575, accuracy: 0.001)
    }

    @MainActor
    func testPersistenceRelationshipsIdempotentSaveAndHistoricalEnergy() async throws {
        let container = try ModelContainer(for: FamilyMember.self, GameSession.self, ParticipantSessionStat.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let profiles = ProfileRepository(context: context)
        try profiles.add(name: "Parent", weight: 60); try profiles.add(name: "Child", weight: 25)
        let members = try profiles.all()
        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(try profiles.settings().weeklyGameGoal, 10)
        let repository = SessionRepository(context: context); let id = UUID()
        var stats = PlayerRoundStats(); stats.hits = 2; stats.sideReachCount = 2
        for _ in 0..<2 {
            try repository.saveCompleted(id: id, game: .whackAMole, members: members, startedAt: Date(),
                                         duration: 60, score: 20, stats: [1: stats])
        }
        let sessions = try repository.all()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].participantStats.count, 2)
        let stored = sessions[0].participantStats.first { $0.member?.id == members[0].id }!
        XCTAssertEqual(stored.scoreContribution, 20)
        let calories = stored.estimatedCalories
        try profiles.update(members[0], weight: 80, height: 170)
        XCTAssertEqual(stored.estimatedCalories, calories)
        XCTAssertTrue(stored.session === sessions[0])
        context.delete(sessions[0]); try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<ParticipantSessionStat>()).isEmpty)
        XCTAssertEqual(try profiles.all().count, 2)
    }
}
