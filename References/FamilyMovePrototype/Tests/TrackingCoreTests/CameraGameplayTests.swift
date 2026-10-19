import XCTest
import CoreGraphics
@testable import TrackingCore

final class CameraGameplayTests: XCTestCase {
    private let screen = CGSize(width: 1000, height: 700)
    private func player(_ id: Int = 1, at timestamp: TimeInterval = 10) -> TrackedPlayer {
        SimulatedBodyPose.player(id: id, screen: screen, timestamp: timestamp)
    }

    func testVisionObservationMapsToTheSameVisibleHandAndCollision() {
        func point(_ x: CGFloat, _ y: CGFloat) -> JointPoint {
            JointPoint(position: CGPoint(x: x, y: y), confidence: 0.9)
        }
        let left = BodyObservation(leftWrist: point(0.8, 0.6), root: point(0.75, 0.5))
        let right = BodyObservation(rightWrist: point(0.2, 0.6), root: point(0.25, 0.5))
        let mapper = CoordinateMapper(imageSize: CGSize(width: 640, height: 480), screenSize: screen)
        var tracker = PlayerTracker()
        let p = tracker.update(observations: [right, left], mapper: mapper, timestamp: 10)[0]
        // Aspect fill crops 25 points above/below the 750-point-high image;
        // mirroring turns camera x=0.8 into screen x=200 (P1's left region).
        let target = CGPoint(x: 200, y: 275)
        var feedback = HandFeedback(); feedback.update(players: [p], now: 10)
        let hand = feedback.trails(at: 10).first { $0.hand.side == .left }!.hand
        XCTAssertEqual(hand.position.x, target.x, accuracy: 0.001)
        XCTAssertEqual(hand.position.y, target.y, accuracy: 0.001)
        let mole = Mole(playerID: 1, zone: .side, position: hand.position, radius: 28, spawnedAt: 0)
        XCTAssertTrue(CollisionDetector().hit(player: p, mole: mole))
        let missing = tracker.update(observations: [], mapper: mapper, timestamp: 10.07)
        feedback.update(players: missing, now: 10.07)
        XCTAssertTrue(feedback.trails(at: 10.07).isEmpty)
        XCTAssertFalse(CollisionDetector().hit(player: missing[0], mole: mole))
    }

    func testHandsDisappearForLostLowConfidenceAndExpiredPoses() {
        let p = player()
        var feedback = HandFeedback(); feedback.update(players: [p], now: 10)
        XCTAssertEqual(feedback.trails(at: 10).count, 2)
        XCTAssertTrue(feedback.trails(at: 10.31).isEmpty)
        feedback.update(players: [p], now: 10.31)
        XCTAssertTrue(feedback.trails(at: 10.31).isEmpty)
        var lost = player(at: 11); lost.isDetected = false
        feedback.update(players: [lost], now: 11)
        XCTAssertTrue(feedback.trails(at: 11).isEmpty)
        var uncertain = player(at: 12)
        uncertain.leftWrist?.confidence = 0.29; uncertain.rightWrist = nil
        feedback.update(players: [uncertain], now: 12)
        XCTAssertTrue(feedback.trails(at: 12).isEmpty)
    }

    func testStationaryFrameDoesNotExtendTrailAndPlayersKeepSeparateHands() {
        var feedback = HandFeedback()
        var p = player()
        for index in 0..<6 {
            p.lastSeen = 10 + Double(index) * 0.04
            p.leftWrist?.position.x += 3
            feedback.update(players: [p, player(2, at: p.lastSeen)], now: p.lastSeen)
        }
        XCTAssertEqual(feedback.trails(at: 10.2).count, 4)
        feedback.update(players: [p, player(2, at: 10.2)], now: 10.25)
        let left = feedback.trails(at: 10.25).first { $0.hand.id == "1-left" }!
        XCTAssertEqual(left.hand.timestamp, 10.2, accuracy: 0.0001)
        XCTAssertEqual(left.points.count, 4)
        XCTAssertTrue(feedback.trails(at: 10.51).isEmpty)
    }

    func testNonFiniteWristNeverRendersOrHits() {
        var p = player(); p.rightWrist = nil
        p.leftWrist?.position.x = .nan
        XCTAssertTrue(p.confidentHands.isEmpty)
        XCTAssertFalse(CollisionDetector().hit(player: p,
            mole: Mole(playerID: 1, zone: .low, position: .zero, radius: 50, spawnedAt: 0)))
    }

    func testReacquiredHandDoesNotDrawALineAcrossTheArena() {
        var p = player(); p.rightWrist = nil
        var feedback = HandFeedback(); feedback.update(players: [p], now: 10)
        p.lastSeen = 10.07; p.leftWrist?.position.x += 300
        feedback.update(players: [p], now: 10.07)
        let trail = feedback.trails(at: 10.07).first!
        XCTAssertEqual(trail.points.count, 1)
        XCTAssertEqual(trail.hand.position, p.leftWrist?.position)
    }

    func testEverySpawnUsesAVisibleFixedHoleDespiteLiveBodyMovement() {
        var p = player(); let baseline = CalibrationSnapshot(player: p)!
        let sites = MoleArenaLayout.sites(calibrations: [1: baseline], screen: screen)
        XCTAssertEqual(sites.count, 3)
        p.bodyCenter?.x += 100; p.leftShoulder?.position.x += 100; p.hipCenter?.y += 50
        var spawner = MoleSpawner()
        for index in 0..<50 {
            let mole = spawner.spawn(player: p, calibration: baseline, screen: screen, now: Double(index))
            let hole = sites.first { $0.zone == mole.zone }!
            XCTAssertEqual(mole.position, hole.position)
            XCTAssertEqual(mole.radius, hole.radius)
        }
    }

    func testHoleReachScalesPerBodyAndRemainsInOwnHalf() {
        let adult = CalibrationSnapshot(player: player())!
        var child = CalibrationSnapshot(player: player(2))!
        child.torsoHeight *= 0.6; child.shoulderWidth *= 0.6
        let sites = MoleArenaLayout.sites(calibrations: [1: adult, 2: child], screen: screen)
        XCTAssertEqual(sites.count, 6)
        for site in sites {
            let left: CGFloat = site.playerID == 1 ? 0 : screen.width / 2
            XCTAssertGreaterThanOrEqual(site.position.x - site.radius, left)
            XCTAssertLessThanOrEqual(site.position.x + site.radius, left + screen.width / 2)
            XCTAssertGreaterThanOrEqual(site.position.y - site.radius, MoleConstants.arenaTopInset)
            XCTAssertLessThanOrEqual(site.position.y + site.radius, screen.height - MoleConstants.arenaBottomInset)
        }
        let adultOverhead = sites.first { $0.playerID == 1 && $0.zone == .overhead }!
        let childOverhead = sites.first { $0.playerID == 2 && $0.zone == .overhead }!
        XCTAssertGreaterThan(adult.shoulderCenter.y - adultOverhead.position.y,
                             child.shoulderCenter.y - childOverhead.position.y)
        XCTAssertGreaterThan(adultOverhead.radius, childOverhead.radius)
    }
}
