import XCTest
import CoreGraphics
@testable import TrackingCore

final class SimulatorInputTests: XCTestCase {
    let screen = CGSize(width: 1200, height: 680)
    func baselines(_ input: SimulatorInput) -> [Int: CalibrationSnapshot] {
        Dictionary(uniqueKeysWithValues: input.players(screen: screen, timestamp: 100, elapsed: 0, moles: [])
            .map { ($0.id, CalibrationSnapshot(player: $0)!) })
    }
    func testInputWaitsForStartAndNeverSuppliesIdleWrists() {
        var input = SimulatorInput()
        XCTAssertTrue(input.players(screen: screen, timestamp: 100, elapsed: 0, moles: []).isEmpty)
        input.begin()
        let players = input.players(screen: screen, timestamp: 100, elapsed: 0, moles: [])
        XCTAssertEqual(players.count, 2)
        XCTAssertTrue(players.allSatisfy { $0.isDetected && $0.leftWrist == nil && $0.rightWrist == nil })
    }
    func testIdleSimulatorDoesNotScoreAutomatically() {
        var input = SimulatorInput(); input.begin()
        var engine = WhackAMoleEngine()
        let calibration = baselines(input)
        for step in 0...50 {
            let time = Double(step) * 0.05
            let players = input.players(screen: screen, timestamp: 100 + time, elapsed: time, moles: Array(engine.moles.values))
            _ = engine.update(players: players, calibration: calibration, screen: screen, now: time)
        }
        XCTAssertEqual(engine.stats.values.map(\.hits).reduce(0, +), 0)
        XCTAssertGreaterThanOrEqual(engine.stats.values.map(\.misses).reduce(0, +), 2)
    }
    func testClickScoresForOnlyTheTargetOwnerAndOnlyOnce() {
        var input = SimulatorInput(); input.begin()
        var engine = WhackAMoleEngine()
        let calibration = baselines(input)
        _ = engine.update(players: input.players(screen: screen, timestamp: 100, elapsed: 0, moles: []),
                          calibration: calibration, screen: screen, now: 0)
        input.hit(engine.moles[1]!, elapsed: 0.1)
        for step in 2...30 {
            let time = Double(step) * 0.05
            let players = input.players(screen: screen, timestamp: 100 + time, elapsed: time, moles: Array(engine.moles.values))
            _ = engine.update(players: players, calibration: calibration, screen: screen, now: time)
        }
        XCTAssertEqual(engine.stats[1]!.scoreContribution, 10)
        XCTAssertEqual(engine.stats[2]!.scoreContribution, 0)
    }
    func testClickCannotCarryOverToAReplacementTarget() {
        var input = SimulatorInput(); input.begin()
        let first = Mole(playerID: 1, zone: .side, position: CGPoint(x: 100, y: 300), radius: 50, spawnedAt: 0)
        input.hit(first, elapsed: 0.1)
        let replacement = Mole(playerID: 1, zone: .side, position: first.position, radius: 50, spawnedAt: 0.15)
        XCTAssertNil(input.players(screen: screen, timestamp: 100.15, elapsed: 0.15, moles: [replacement])[0].leftWrist)
        XCTAssertNil(input.players(screen: screen, timestamp: 100.4, elapsed: 0.4, moles: [first])[0].leftWrist)
    }
    func testCorrectButtonsUseTheNormalMovementDetectorForBothPlayers() {
        var input = SimulatorInput(); input.begin()
        var engine = BirdsAlligatorsEngine()
        let calibration = baselines(input)
        _ = engine.update(players: input.players(screen: screen, timestamp: 100, elapsed: 0, moles: []), calibration: calibration, now: 0)
        for id in 1...2 { input.move(engine.obstacles[id]!.type.movement, playerID: id, elapsed: 0.1) }
        for step in 1...25 {
            let time = Double(step) * 0.05
            _ = engine.update(players: input.players(screen: screen, timestamp: 100 + time, elapsed: time, moles: []),
                              calibration: calibration, now: time)
        }
        XCTAssertEqual(engine.stats[1]!.hits, 1)
        XCTAssertEqual(engine.stats[2]!.hits, 1)
    }
    func testWrongButtonDoesNotScore() {
        var input = SimulatorInput(); input.begin()
        var engine = BirdsAlligatorsEngine()
        let calibration = baselines(input)
        _ = engine.update(players: input.players(screen: screen, timestamp: 100, elapsed: 0, moles: []), calibration: calibration, now: 0)
        let expected = engine.obstacles[1]!.type.movement
        input.move(expected == .squat ? .jump : .squat, playerID: 1, elapsed: 0.1)
        for step in 1...25 {
            let time = Double(step) * 0.05
            _ = engine.update(players: input.players(screen: screen, timestamp: 100 + time, elapsed: time, moles: []),
                              calibration: calibration, now: time)
        }
        XCTAssertEqual(engine.stats[1]!.hits, 0)
    }
    func testActionsClearOnPauseAndResetRequiresStartingAgain() {
        var input = SimulatorInput(); input.begin()
        input.move(.squat, playerID: 1, elapsed: 0)
        input.move(.jump, playerID: 1, elapsed: 0.1)
        let moving = input.players(screen: screen, timestamp: 100.2, elapsed: 0.2, moles: [])[0]
        XCTAssertGreaterThan(moving.hipCenter!.y, screen.height * 0.61)
        input.clearActions()
        XCTAssertFalse(input.isMoving(1, elapsed: 0.2))
        XCTAssertEqual(input.players(screen: screen, timestamp: 100.2, elapsed: 0.2, moles: [])[0].hipCenter!.y, screen.height * 0.61)
        input.reset()
        XCTAssertFalse(input.hasStarted)
        XCTAssertTrue(input.players(screen: screen, timestamp: 101, elapsed: 0, moles: []).isEmpty)
    }
}
