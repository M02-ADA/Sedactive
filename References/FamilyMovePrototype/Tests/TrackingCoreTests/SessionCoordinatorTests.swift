import XCTest
import CoreGraphics
@testable import TrackingCore

final class SessionCoordinatorTests: XCTestCase {
    func players(at now: TimeInterval, fullBody: Bool = true) -> [TrackedPlayer] {
        (1...2).map { id in
            let x: CGFloat = id == 1 ? 250 : 750
            func joint(_ dx: CGFloat, _ y: CGFloat) -> JointPoint {
                JointPoint(position: CGPoint(x: x + dx, y: y), confidence: 1)
            }
            var p = TrackedPlayer(id: id)
            p.isDetected = true; p.lastSeen = now
            p.bodyCenter = CGPoint(x: x, y: 350)
            p.leftShoulder = joint(-40, 300); p.rightShoulder = joint(40, 300)
            p.leftHip = joint(-30, 400); p.rightHip = joint(30, 400)
            p.hipCenter = CGPoint(x: x, y: 400)
            if fullBody {
                p.leftKnee = joint(-30, 500); p.rightKnee = joint(30, 500)
                p.leftAnkle = joint(-30, 600); p.rightAnkle = joint(30, 600)
            }
            return p
        }
    }
    @MainActor
    func advance(_ session: GameSessionCoordinator, from start: Double, through end: Double) {
        var now = start
        while now <= end {
            session.update(players: players(at: now), viewport: CGSize(width: 1000, height: 700))
            session.tick(now: now)
            now += 0.05
        }
    }
    @MainActor
    func testBothGamesCompleteSixtySecondRoundAndReplayGetsNewID() async {
        for game in GameType.allCases {
            let session = GameSessionCoordinator(game: game, automaticallyTicks: false)
            advance(session, from: 100, through: 106)
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(session.calibrations.count, 2)
            let oldID = session.roundID
            advance(session, from: 106.05, through: 166)
            XCTAssertEqual(session.state, .gameOver)
            XCTAssertEqual(session.remainingTime, 0)
            session.newRound()
            XCTAssertEqual(session.state, .positioning)
            XCTAssertEqual(session.score, 0)
            XCTAssertEqual(session.remainingTime, 60)
            XCTAssertNotEqual(session.roundID, oldID)
        }
    }
    @MainActor
    func testReadinessRequiresContinuousDetectionAndFullBodyForBirds() async {
        let session = GameSessionCoordinator(game: .birdsAndAlligators, automaticallyTicks: false)
        for step in 0..<30 {
            let now = 100 + Double(step) * 0.1
            session.update(players: players(at: now, fullBody: false), viewport: CGSize(width: 1000, height: 700))
            session.tick(now: now)
        }
        XCTAssertEqual(session.state, .positioning)
        XCTAssertTrue(session.readyIDs.isEmpty)
        advance(session, from: 104, through: 104.8)
        session.update(players: [], viewport: CGSize(width: 1000, height: 700)); session.tick(now: 104.9)
        advance(session, from: 105, through: 105.8)
        XCTAssertEqual(session.state, .positioning)
    }
    @MainActor
    func testBothLostPausesTimerAndResumeRequiresSetup() async {
        let session = GameSessionCoordinator(game: .whackAMole, automaticallyTicks: false)
        advance(session, from: 100, through: 106)
        session.update(players: [], viewport: CGSize(width: 1000, height: 700))
        session.tick(now: 106.1); session.tick(now: 108.2)
        XCTAssertEqual(session.state, .paused)
        let remaining = session.remainingTime
        session.tick(now: 200)
        XCTAssertEqual(session.remainingTime, remaining)
        session.update(players: players(at: 201), viewport: CGSize(width: 1000, height: 700))
        session.tick(now: 201)
        XCTAssertEqual(session.state, .positioning)
        advance(session, from: 201.1, through: 207)
        XCTAssertEqual(session.state, .playing)
        XCTAssertLessThan(session.remainingTime, remaining)
        XCTAssertGreaterThan(session.remainingTime, remaining - 1)
    }

    @MainActor
    func testManualPauseWaitsForExplicitResumeEvenWhenPlayersAreVisible() async {
        let session = GameSessionCoordinator(game: .whackAMole, automaticallyTicks: false)
        advance(session, from: 100, through: 106)
        session.pause(message: "Take a break.", reason: .manual, at: 106)
        advance(session, from: 106.1, through: 110)
        XCTAssertEqual(session.state, .paused)
        session.resetPositioning(at: 110)
        advance(session, from: 110.1, through: 116)
        XCTAssertEqual(session.state, .playing)
        XCTAssertLessThan(session.remainingTime, 60)
        XCTAssertGreaterThan(session.remainingTime, 58)
    }

    @MainActor
    func testLandscapeFlipInvalidatesOldPosesAndPreservesRoundTime() async {
        let session = GameSessionCoordinator(game: .whackAMole, automaticallyTicks: false)
        advance(session, from: 100, through: 106)
        session.invalidateTrackingGeometry(at: 106)
        XCTAssertEqual(session.state, .positioning)
        XCTAssertTrue(session.calibrations.isEmpty)
        XCTAssertTrue(session.moles.isEmpty)
        session.tick(now: 106.1)
        XCTAssertTrue(session.readyIDs.isEmpty)
        advance(session, from: 107, through: 113)
        XCTAssertEqual(session.state, .playing)
        XCTAssertLessThan(session.remainingTime, 60)
        XCTAssertGreaterThan(session.remainingTime, 58)
    }

    @MainActor
    func testRotationDoesNotDismissManualPause() async {
        let session = GameSessionCoordinator(game: .whackAMole, automaticallyTicks: false)
        advance(session, from: 100, through: 106)
        session.pause(message: "Your round is paused.", reason: .manual, at: 106)
        session.invalidateTrackingGeometry(at: 107)
        advance(session, from: 107.1, through: 112)
        XCTAssertEqual(session.state, .paused)
        XCTAssertEqual(session.pauseReason, .manual)
    }

    func testCalibrationRejectsMovementAndAcceptsSmallJitter() {
        let snapshots = (0..<10).map { index -> CalibrationSnapshot in
            var sample = CalibrationSnapshot(player: players(at: Double(index))[0])!
            sample.hipCenter.y += CGFloat(index % 2 == 0 ? 30 : -30)
            return sample
        }
        XCTAssertNil(CalibrationSnapshot.average(snapshots))
        let steady = (0..<10).map { index -> CalibrationSnapshot in
            var sample = CalibrationSnapshot(player: players(at: Double(index))[0])!
            sample.hipCenter.y += CGFloat(index % 2 == 0 ? 2 : -2)
            return sample
        }
        XCTAssertNotNil(CalibrationSnapshot.average(steady))
    }

    func testCalibrationRejectsChangingBodyScale() {
        let turning = (0..<10).map { index -> CalibrationSnapshot in
            var sample = CalibrationSnapshot(player: players(at: Double(index))[0])!
            sample.shoulderWidth = index % 2 == 0 ? 50 : 100
            return sample
        }
        XCTAssertNil(CalibrationSnapshot.average(turning))
    }

    @MainActor
    func testUnstableCalibrationNeverStartsCountdown() async {
        let session = GameSessionCoordinator(game: .whackAMole, automaticallyTicks: false)
        advance(session, from: 100, through: 101.1)
        XCTAssertEqual(session.state, .calibrating)
        for step in 1...22 {
            let now = 101.1 + Double(step) * 0.05
            var moving = players(at: now)
            for index in moving.indices {
                let offset: CGFloat = step % 2 == 0 ? 35 : -35
                moving[index].hipCenter!.y += offset
                moving[index].leftShoulder!.position.y += offset
                moving[index].rightShoulder!.position.y += offset
            }
            session.update(players: moving, viewport: CGSize(width: 1000, height: 700))
            session.tick(now: now)
        }
        XCTAssertEqual(session.state, .positioning)
        XCTAssertTrue(session.calibrations.isEmpty)
        XCTAssertNotNil(session.setupMessage)
    }
}
