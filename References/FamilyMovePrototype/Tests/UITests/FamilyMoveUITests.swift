import XCTest

final class FamilyMoveUITests: XCTestCase {
    let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["--ui-testing", "--reset-test-store"]
        if name.contains("Synthetic") { app.launchArguments.append("--synthetic-poses") }
        if name.contains("ManualSimulator") { app.launchArguments.append("--simulator-controls") }
        if name.contains("ManualSimulatorMoles") { app.launchArguments.append("--short-round") }
        if name.contains("ManualSimulator") || name.contains("Synthetic") || name.contains("CameraMode") { app.launchArguments.append("--seed-test-family") }
        app.launch()
    }
    func addMember(_ name: String, weight: String) {
        XCTAssertTrue(app.buttons["addPlayer"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["addPlayer"].firstMatch.tap()
        let nameField = app.textFields["memberName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText(name)
        let weightField = app.textFields["memberWeight"]
        weightField.tap(); weightField.typeText(weight)
        app.buttons["saveMember"].tap()
        XCTAssertTrue(app.buttons["addPlayer"].firstMatch.waitForExistence(timeout: 5))
    }
    func createFamily() {
        if name.contains("ManualSimulator") || name.contains("Synthetic") || name.contains("CameraMode") {
            XCTAssertTrue(app.buttons["game-whackAMole"].waitForExistence(timeout: 8))
            return
        }
        addMember("Parent", weight: "65")
        XCTAssertFalse(app.buttons["continueHome"].exists)
        addMember("Child", weight: "25")
        app.buttons["continueHome"].tap()
        XCTAssertTrue(app.buttons["game-whackAMole"].waitForExistence(timeout: 5))
    }
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testOnboardingAndProfilesPersistAcrossLaunch() {
        XCTAssertTrue(app.buttons["addPlayer"].firstMatch.waitForExistence(timeout: 5))
        snapshot("01-Onboarding")
        createFamily()
        snapshot("02-Home")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["game-birdsAndAlligators"].waitForExistence(timeout: 5))
    }
    func testGameDetailAndExactlyTwoPlayerSelection() {
        createFamily()
        app.buttons["game-whackAMole"].tap()
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 5))
        snapshot("03-Game-Detail")
        app.buttons["detailPlay"].tap()
        let play = app.buttons["startGame"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); XCTAssertFalse(play.isEnabled)
        app.buttons["select-Parent"].tap(); XCTAssertFalse(play.isEnabled)
        app.buttons["select-Child"].tap(); XCTAssertTrue(play.isEnabled)
        snapshot("04-Player-Selection")
    }
    func testProgressWeightEditPersists() {
        createFamily()
        app.segmentedControls.buttons["Your Progress"].tap()
        app.buttons["editBodyweight"].tap()
        let field = app.textFields["editWeight"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        field.typeText("70")
        app.buttons["saveMeasurements"].tap()
        XCTAssertTrue(app.buttons["editBodyweight"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(app.staticTexts["STREAK"].isHittable)
        snapshot("05-Progress")
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.segmentedControls.buttons["Your Progress"].tap()
        XCTAssertTrue(app.buttons["editBodyweight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editBodyweight"].label.contains("70.0"))
    }
    func startGame(_ game: String) {
        app.buttons["game-\(game)"].tap()
        app.buttons["detailPlay"].tap()
        XCTAssertTrue(app.buttons["select-Parent"].waitForExistence(timeout: 5))
        app.buttons["select-Parent"].tap(); app.buttons["select-Child"].tap()
        app.buttons["startGame"].tap()
        if name.contains("ManualSimulator") {
            XCTAssertTrue(app.buttons["simStartRound"].waitForExistence(timeout: 5))
            app.buttons["simStartRound"].tap()
        }
        XCTAssertTrue(app.buttons["Pause game"].waitForExistence(timeout: 12))
        let status = app.staticTexts["playerStatus-1"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertFalse(status.label.contains("Move back"))
    }
    func testSyntheticMoleRoundPauseAndReplay() {
        createFamily(); startGame("whackAMole")
        app.buttons["Pause game"].tap()
        XCTAssertTrue(app.staticTexts["Take a breather"].waitForExistence(timeout: 3))
        snapshot("06-Manual-Pause")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Pause game"].waitForExistence(timeout: 12))
        snapshot("07-Mole-Gameplay-Synthetic")
        XCTAssertTrue(app.buttons["resultsDone"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(Int(app.staticTexts["finalScore"].label) ?? 0, 0)
        snapshot("08-Mole-Results")
        app.buttons["playAgain"].tap()
        // Positioning lasts only one second with the stable synthetic bodies.
        // Assert the persistent replay screen, rather than racing that heading.
        XCTAssertTrue(app.buttons["Leave game"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["resultsDone"].exists)
        app.buttons["Leave game"].tap()
        if app.alerts["End this round?"].waitForExistence(timeout: 1) { app.buttons["End Round"].tap() }
        XCTAssertTrue(app.buttons["game-whackAMole"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["weeklyHouseholdGames"].label.contains("1"))
    }
    func testCameraModeDoesNotSilentlyUseSimulatorControls() {
        createFamily()
        app.buttons["game-whackAMole"].tap(); app.buttons["detailPlay"].tap()
        XCTAssertTrue(app.buttons["select-Parent"].waitForExistence(timeout: 5))
        app.buttons["select-Parent"].tap(); app.buttons["select-Child"].tap()
        app.buttons["startGame"].tap()
        XCTAssertTrue(app.staticTexts["Play with your Mac camera"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["simStartRound"].exists)
        XCTAssertFalse(app.buttons["Pause game"].exists)
        snapshot("14-Camera-Mode-On-Simulator")
        app.buttons["Leave game"].tap()
        XCTAssertTrue(app.buttons["game-whackAMole"].waitForExistence(timeout: 5))
    }
    func testSyntheticBirdsRoundAndExitConfirmation() {
        createFamily(); startGame("birdsAndAlligators")
        app.buttons["Leave game"].tap()
        XCTAssertTrue(app.alerts["End this round?"].waitForExistence(timeout: 3))
        app.buttons["Keep Playing"].tap()
        XCTAssertTrue(app.buttons["Pause game"].waitForExistence(timeout: 12))
        snapshot("09-Birds-Gameplay-Synthetic")
        XCTAssertTrue(app.buttons["resultsDone"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(Int(app.staticTexts["finalScore"].label) ?? 0, 0)
        snapshot("10-Birds-Results")
        app.buttons["resultsDone"].tap()
        XCTAssertTrue(app.buttons["game-birdsAndAlligators"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["weeklyHouseholdGames"].label.contains("1"))
    }

    func testManualSimulatorMolesRequireClicksAndCompleteRound() {
        createFamily(); startGame("whackAMole")
        let liveScore = app.staticTexts["liveScore"]
        XCTAssertTrue(liveScore.waitForExistence(timeout: 3))
        let unexpectedScore = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != '0'"), object: liveScore)
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedScore], timeout: 2.2), .timedOut)
        for id in 1...2 {
            let target = app.buttons["simMole-\(id)"]
            XCTAssertTrue(target.waitForExistence(timeout: 4))
            target.tap()
            let scored = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
                (Int((element as? XCUIElement)?.label ?? "") ?? 0) >= id * 10
            }, object: liveScore)
            XCTAssertEqual(XCTWaiter.wait(for: [scored], timeout: 3), .completed)
        }
        snapshot("11-Manual-Simulator-Moles")
        XCTAssertTrue(app.buttons["resultsDone"].waitForExistence(timeout: 24))
        XCTAssertEqual(Int(app.staticTexts["finalScore"].label), 20)
        snapshot("12-Manual-Simulator-Results")
        app.buttons["resultsDone"].tap()
        XCTAssertTrue(app.buttons["game-whackAMole"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["weeklyHouseholdGames"].label.contains("1"))
    }

    func testManualSimulatorBirdsButtonsDriveScoring() {
        createFamily(); startGame("birdsAndAlligators")
        let liveScore = app.staticTexts["liveScore"]
        XCTAssertTrue(liveScore.waitForExistence(timeout: 3))
        XCTAssertEqual(liveScore.label, "0")
        XCTAssertTrue(app.buttons["simDuck-1"].exists)
        XCTAssertTrue(app.buttons["simJump-2"].exists)
        for _ in 0..<4 {
            let cue = app.staticTexts["expectedMovement-1"]
            guard cue.waitForExistence(timeout: 3) else { continue }
            let action = app.buttons[cue.label == "DUCK" ? "simDuck-1" : "simJump-1"]
            if action.isEnabled { action.tap() }
            let scored = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
                (Int((element as? XCUIElement)?.label ?? "") ?? 0) > 0
            }, object: liveScore)
            if XCTWaiter.wait(for: [scored], timeout: 1.2) == .completed { break }
        }
        XCTAssertGreaterThan(Int(liveScore.label) ?? 0, 0)
        snapshot("13-Manual-Simulator-Birds")
        app.buttons["Pause game"].tap()
        XCTAssertTrue(app.staticTexts["Take a breather"].waitForExistence(timeout: 3))
        app.buttons["Leave game"].tap()
        XCTAssertTrue(app.alerts["End this round?"].waitForExistence(timeout: 3))
        app.buttons["End Round"].tap()
        XCTAssertTrue(app.buttons["game-birdsAndAlligators"].waitForExistence(timeout: 5))
    }
}
