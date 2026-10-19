import CoreGraphics
#if !CORE_TEST_RUNNER
import XCTest
@testable import TrackingCore
#endif

final class TrackingCoreTests: XCTestCase {
    private let squareMapper = CoordinateMapper(imageSize: CGSize(width: 1_000, height: 1_000),
                                                screenSize: CGSize(width: 1_000, height: 1_000))

    private func joint(_ x: CGFloat, _ y: CGFloat, confidence: Float = 0.9) -> JointPoint {
        JointPoint(position: CGPoint(x: x, y: y), confidence: confidence)
    }

    /// Build a person at a desired MIRRORED screen x, independent of Vision order.
    private func body(at x: CGFloat, wrists: Bool = true) -> BodyObservation {
        BodyObservation(leftWrist: wrists ? joint(1 - x - 0.05, 0.5) : nil,
                        rightWrist: wrists ? joint(1 - x + 0.05, 0.5) : nil,
                        leftShoulder: joint(1 - x - 0.04, 0.7),
                        rightShoulder: joint(1 - x + 0.04, 0.7),
                        leftHip: joint(1 - x - 0.03, 0.3),
                        rightHip: joint(1 - x + 0.03, 0.3))
    }

    func testMirrorsXAndInvertsYExactlyOnce() {
        let result = squareMapper.screenPoint(from: CGPoint(x: 0.2, y: 0.8))
        XCTAssertEqual(result.x, 800, accuracy: 0.001)
        XCTAssertEqual(result.y, 200, accuracy: 0.001)
    }

    func testAspectFillIncludesHorizontalCrop() {
        let mapper = CoordinateMapper(imageSize: CGSize(width: 1_920, height: 1_080),
                                      screenSize: CGSize(width: 1_000, height: 1_000))
        let center = mapper.screenPoint(from: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(center.x, 500, accuracy: 0.001)
        XCTAssertEqual(center.y, 500, accuracy: 0.001)
        XCTAssertEqual(mapper.screenPoint(from: CGPoint(x: 1, y: 1)).x, -388.8889, accuracy: 0.001)
    }

    func testAspectFillIncludesVerticalCrop() {
        let mapper = CoordinateMapper(imageSize: CGSize(width: 640, height: 480),
                                      screenSize: CGSize(width: 1_200, height: 600))
        XCTAssertEqual(mapper.screenPoint(from: CGPoint(x: 0.5, y: 1)).y, -150, accuracy: 0.001)
        XCTAssertEqual(mapper.screenPoint(from: CGPoint(x: 0.5, y: 0)).y, 750, accuracy: 0.001)
    }

    func testLowConfidenceJointIsUnavailable() {
        XCTAssertNil(squareMapper.screenJoint(from: joint(0.5, 0.5, confidence: 0.29)))
        XCTAssertNotNil(squareMapper.screenJoint(from: joint(0.5, 0.5, confidence: 0.30)))
    }

    func testBodyCenterUsesShouldersAndHips() {
        let center = body(at: 0.25).bodyCenter!
        XCTAssertEqual(center.x, 0.75, accuracy: 0.001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.001)
        let fallback = BodyObservation(root: joint(0.4, 0.3))
        XCTAssertEqual(fallback.bodyCenter, CGPoint(x: 0.4, y: 0.3))
    }

    func testInitialAssignmentUsesMirroredLeftAndRight() {
        var tracker = PlayerTracker()
        let players = tracker.update(observations: [body(at: 0.75), body(at: 0.25)], mapper: squareMapper, timestamp: 10)
        XCTAssertEqual(players[0].bodyCenter!.x, 250, accuracy: 0.001)
        XCTAssertEqual(players[1].bodyCenter!.x, 750, accuracy: 0.001)
    }

    func testObservationOrderDoesNotSwapPlayers() {
        var tracker = PlayerTracker()
        _ = tracker.update(observations: [body(at: 0.25), body(at: 0.75)], mapper: squareMapper, timestamp: 10)
        let players = tracker.update(observations: [body(at: 0.70), body(at: 0.30)], mapper: squareMapper, timestamp: 10.1)
        XCTAssertEqual(players[0].bodyCenter!.x, 265, accuracy: 0.001)
        XCTAssertEqual(players[1].bodyCenter!.x, 735, accuracy: 0.001)
    }

    func testSingleRightPlayerDoesNotBecomePlayerOne() {
        var tracker = PlayerTracker()
        let players = tracker.update(observations: [body(at: 0.75)], mapper: squareMapper, timestamp: 10)
        XCTAssertFalse(players[0].isDetected)
        XCTAssertTrue(players[1].isDetected)
    }

    func testSpatialContinuityRatherThanSortingEachFrame() {
        var tracker = PlayerTracker()
        let first = BodyObservation(root: joint(0.55, 0.7))
        let second = BodyObservation(root: joint(0.45, 0.3))
        _ = tracker.update(observations: [first, second], mapper: squareMapper, timestamp: 10)
        // X order reverses, but the two distinct Y positions disambiguate the people.
        let movedFirst = BodyObservation(root: joint(0.45, 0.7))
        let movedSecond = BodyObservation(root: joint(0.55, 0.3))
        let players = tracker.update(observations: [movedSecond, movedFirst], mapper: squareMapper, timestamp: 10.1)
        XCTAssertEqual(players[0].bodyCenter!.y, 300, accuracy: 0.001)
        XCTAssertEqual(players[1].bodyCenter!.y, 700, accuracy: 0.001)
        XCTAssertEqual(players[0].bodyCenter!.x, 480, accuracy: 0.001)
    }

    func testAssignmentMinimizesTotalMovementRatherThanGreedyMatch() {
        var tracker = PlayerTracker()
        _ = tracker.update(observations: [body(at: 0.1), body(at: 0.4)], mapper: squareMapper, timestamp: 10)
        let players = tracker.update(observations: [body(at: 0.35), body(at: 0.7)], mapper: squareMapper, timestamp: 10.1)
        XCTAssertEqual(players[0].bodyCenter!.x, 175, accuracy: 0.001)
        XCTAssertEqual(players[1].bodyCenter!.x, 490, accuracy: 0.001)
    }

    func testMissingPlayerKeepsIdentityAnchorButClearsWrists() {
        var tracker = PlayerTracker()
        _ = tracker.update(observations: [body(at: 0.25), body(at: 0.75)], mapper: squareMapper, timestamp: 10)
        let players = tracker.update(observations: [body(at: 0.74)], mapper: squareMapper, timestamp: 10.1)
        XCTAssertFalse(players[0].isDetected)
        XCTAssertNotNil(players[0].bodyCenter)
        XCTAssertNil(players[0].leftWrist)
        XCTAssertTrue(players[1].isDetected)
        let returned = tracker.update(observations: [body(at: 0.27), body(at: 0.73)], mapper: squareMapper, timestamp: 10.2)
        XCTAssertTrue(returned.allSatisfy(\.isDetected))
        XCTAssertLessThan(returned[0].bodyCenter!.x, returned[1].bodyCenter!.x)
    }

    func testMissingWristDoesNotReusePreviousPosition() {
        var tracker = PlayerTracker()
        _ = tracker.update(observations: [body(at: 0.25)], mapper: squareMapper, timestamp: 10)
        let players = tracker.update(observations: [body(at: 0.25, wrists: false)], mapper: squareMapper, timestamp: 10.1)
        XCTAssertTrue(players[0].isDetected)
        XCTAssertNil(players[0].leftWrist)
        XCTAssertNil(players[0].rightWrist)
    }

    func testStalledStreamExpiresJointsBeforeIdentityAnchor() {
        var tracker = PlayerTracker()
        _ = tracker.update(observations: [body(at: 0.25)], mapper: squareMapper, timestamp: 10)
        tracker.expire(at: 10.4)
        XCTAssertNil(tracker.players[0].leftWrist)
        XCTAssertNotNil(tracker.players[0].bodyCenter)
        tracker.expire(at: 11.1)
        XCTAssertNil(tracker.players[0].bodyCenter)
    }

    func testCapsTrackingAtTwoBodiesAndIgnoresEmptyObservations() {
        var tracker = PlayerTracker()
        let players = tracker.update(observations: [body(at: 0.25), body(at: 0.75), body(at: 0.5), BodyObservation()],
                                     mapper: squareMapper, timestamp: 10)
        XCTAssertEqual(players.count, 2)
        XCTAssertTrue(players.allSatisfy(\.isDetected))
    }

    func testEMAAndNilReset() {
        let smoother = PositionSmoother()
        XCTAssertEqual(smoother.smooth(CGPoint(x: 100, y: 200), previous: .zero), CGPoint(x: 30, y: 60))
        XCTAssertNil(smoother.smooth(nil as CGPoint?, previous: CGPoint(x: 100, y: 100)))
    }
}
