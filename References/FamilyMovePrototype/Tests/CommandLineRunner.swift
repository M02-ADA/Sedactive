// Runs the SAME test methods when only Apple's Command Line Tools are available
// (that installation does not include XCTest). Normal `swift test` uses XCTest.
#if CORE_TEST_RUNNER
import Foundation
import CoreGraphics
import Darwin

class XCTestCase {}
private var failures = 0

private func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    if !condition {
        failures += 1
        print("FAIL \(file):\(line): \(message)")
    }
}

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    check(a == b, "\(a) != \(b)", file: file, line: line)
}
func XCTAssertEqual(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    check(abs(a - b) <= accuracy, "\(a) != \(b) ± \(accuracy)", file: file, line: line)
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    check(value == nil, "Expected nil", file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    check(value != nil, "Expected a value", file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(value, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(!value, "Expected false", file: file, line: line)
}
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    check(a < b, "\(a) is not less than \(b)", file: file, line: line)
}

@main
struct CoreTestRunner {
    static func main() {
        let tests = TrackingCoreTests()
        let cases: [(String, () -> Void)] = [
            ("Mirror and Y inversion", tests.testMirrorsXAndInvertsYExactlyOnce),
            ("Horizontal aspect-fill crop", tests.testAspectFillIncludesHorizontalCrop),
            ("Vertical aspect-fill crop", tests.testAspectFillIncludesVerticalCrop),
            ("Confidence cutoff", tests.testLowConfidenceJointIsUnavailable),
            ("Body center and fallback", tests.testBodyCenterUsesShouldersAndHips),
            ("Initial mirrored assignment", tests.testInitialAssignmentUsesMirroredLeftAndRight),
            ("Observation order stability", tests.testObservationOrderDoesNotSwapPlayers),
            ("Single right player assignment", tests.testSingleRightPlayerDoesNotBecomePlayerOne),
            ("Continuity across X-order changes", tests.testSpatialContinuityRatherThanSortingEachFrame),
            ("Global minimum movement assignment", tests.testAssignmentMinimizesTotalMovementRatherThanGreedyMatch),
            ("Loss and reacquisition", tests.testMissingPlayerKeepsIdentityAnchorButClearsWrists),
            ("Missing wrists cleared", tests.testMissingWristDoesNotReusePreviousPosition),
            ("Stalled stream expiry", tests.testStalledStreamExpiresJointsBeforeIdentityAnchor),
            ("Two-player cap", tests.testCapsTrackingAtTwoBodiesAndIgnoresEmptyObservations),
            ("EMA smoothing", tests.testEMAAndNilReset)
        ]
        for (name, test) in cases {
            let before = failures
            test()
            if before == failures { print("PASS \(name)") }
        }
        print("\(cases.count) tests, \(failures) failed assertions")
        if failures > 0 { exit(1) }
    }
}
#endif
