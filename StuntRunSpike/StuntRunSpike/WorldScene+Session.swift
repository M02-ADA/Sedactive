import QuartzCore
import SpriteKit

/// Deterministic, simulator-friendly test script. Each step covers one encounter and starts at its WARNING; every
/// time is in seconds relative to that encounter's "DUCK!" cue (negative = before the cue: during the warning or
/// approach). It drives the same detector and game logic as real input; it is never evidence of tracking accuracy.
final class ScenarioScript {
    enum Squat { case none, full(Double), shallow(Double) }
    enum Control {
        case none
        /// Lose a player's tracking at `at`; recover after `recover` s, then resume after `resume` s (real time).
        case loseTracking(Zone, at: Double, recover: Double, resume: Double)
        case pause(at: Double, resume: Double)
        case replayAfterResolve(Double)
    }
    struct Step {
        var name: String
        var left: Squat
        var right: Squat
        var control: Control = .none
    }

    static let coop: [Step] = [
        Step(name: "both succeed, staggered", left: .full(0.3), right: .full(1.3)),
        Step(name: "parent only (child misses)", left: .full(0.5), right: .none),
        Step(name: "child late but in time", left: .full(0.2), right: .full(2.0)),
        Step(name: "child LATE (bottom after the beam passed)", left: .full(0.4), right: .full(2.5)),
        Step(name: "parent EARLY during the warning", left: .full(-3.4), right: .full(0.6)),
        Step(name: "parent EARLY during the approach", left: .full(-1.6), right: .full(0.5)),
        Step(name: "parent incomplete (too shallow)", left: .shallow(0.4), right: .full(0.8)),
        Step(name: "tracking lost during the approach", left: .none, right: .none,
             control: .loseTracking(.left, at: -1.8, recover: 2.0, resume: 1.5)),
        Step(name: "pause inside the DUCK window", left: .full(0.4), right: .none, control: .pause(at: 0.9, resume: 2.0)),
        Step(name: "both succeed, then replay", left: .full(0.5), right: .full(1.0), control: .replayAfterResolve(2.5)),
        Step(name: "new session: both succeed", left: .full(0.6), right: .full(0.7)),
    ]

    private var steps: [Step]
    private(set) var index = 0
    private var current: Step?
    private var timers: [(fireAt: Double, realTime: Bool, action: (WorldScene) -> Void)] = []

    init(steps: [Step]) { self.steps = steps }

    var isFinished: Bool { index >= steps.count && timers.isEmpty }

    func encounterStarted(scene: WorldScene) {
        guard index < steps.count else { current = nil; return }
        let step = steps[index]
        index += 1
        current = step
        scene.gameLog("script step \(index)/\(steps.count): \(step.name)")
        let cue = scene.gameTime + scene.timing.cueTime
        for (zone, plan) in [(Zone.left, step.left), (.right, step.right)] {
            guard var slot = scene.slots[zone] else { continue }
            switch plan {
            case .none: slot.botPlanned = nil
            case .full(let t): slot.botPlanned = cue + t; slot.botPeak = 0.85
            case .shallow(let t): slot.botPlanned = cue + t; slot.botPeak = 0.35
            }
            scene.slots[zone] = slot
        }
        switch step.control {
        case .loseTracking(let zone, let at, let recover, let resume):
            schedule(at: cue + at, real: false) { scene in
                scene.setSimulatedTrackingLost(zone, lost: true)
                self.schedule(at: scene.now + recover + 0.6, real: true) { scene in
                    scene.setSimulatedTrackingLost(zone, lost: false)
                    self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "script") }
                }
            }
        case .pause(let at, let resume):
            schedule(at: cue + at, real: false) { scene in
                scene.pauseGame(source: "script")
                self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "script") }
            }
        case .none, .replayAfterResolve:
            break
        }
    }

    func challengeWarned(scene: WorldScene) {}

    func challengeResolved(scene: WorldScene) {
        if case .replayAfterResolve(let delay) = current?.control {
            schedule(at: scene.now + delay, real: true) { $0.replay(source: "script") }
        }
    }

    func tick(scene: WorldScene) {
        let due = timers.enumerated().filter { $0.element.fireAt <= ($0.element.realTime ? scene.now : scene.gameTime) }
        guard !due.isEmpty else { return }
        timers = timers.enumerated().filter { item in !due.contains { $0.offset == item.offset } }.map(\.element)
        for item in due { item.element.action(scene) }
    }

    private func schedule(at time: Double, real: Bool, _ action: @escaping (WorldScene) -> Void) {
        timers.append((time, real, action))
    }
}

extension WorldScene {
    // MARK: - Session flow

    /// Applies play-state transitions once per frame. Game time only advances while the world is not halted,
    /// so simulated movements, bot plans and script timers can never fire stale while paused.
    func updateFlow(dt: TimeInterval) {
        if flow.tick(at: now) { gameLog("state: running") }
        if !flow.isHalted { gameTime += dt }
        script?.tick(scene: self)
        if let s = script, s.isFinished, encounter == nil {
            script = nil
            gameLog("script finished")
            model?.scriptRunning = false
            model?.autoplay = autoplayBeforeScript
        }

        let state = flow.state
        if case .countdown(let endsAt) = state {
            let remaining = Int(ceil(endsAt - now))
            if remaining != lastCountdownShown, remaining > 0 {
                lastCountdownShown = remaining
                showBanner("\(remaining)", sub: remaining == 3 ? "Get ready" : nil, color: .white, hold: 0.8)
                audio.play(.tick, dB: -6)
            }
        }
        guard state != lastFlowState else { return }
        let previous = lastFlowState
        lastFlowState = state
        lastCountdownShown = nil
        model?.playState = state
        switch state {
        case .running:
            // Fresh start: nothing begun while halted can complete into a rep, and hazards restart with space.
            for zone in Zone.allCases { slots[zone]?.detector.rearm() }
            if previous != nil {
                showBanner("GO!", sub: nil, color: Palette.mint, hold: 0.6)
                audio.play(.lock, dB: -4)
            }
            nextWarningAt = max(nextWarningAt, gameTime + 2.0)
            if pendingTurbo {
                pendingTurbo = false
                gameLog("TURBO (deferred, now running)")
                run(.wait(forDuration: 0.5)) { [weak self] in self?.turbo() }
            }
        case .paused:
            withdrawGates()
            showBanner("PAUSED", sub: "Progress saved · Resume when ready", color: Palette.yellow, hold: nil)
            gameLog("state: paused")
            captureEvent("paused", after: 0.7)
        case .trackingLost(let zones):
            withdrawGates()
            let names = zones.map { role(for: $0) }.sorted().joined(separator: " & ")
            showBanner("\(names): STEP BACK IN", sub: "Into your glowing zone · progress saved", color: Palette.yellow, hold: nil)
            gameLog("state: tracking lost (\(names))")
            captureEvent("tracking-lost", after: 0.8)
        case .ready:
            showBanner("READY!", sub: "Everyone's back · tap Resume", color: Palette.mint, hold: nil)
            gameLog("state: ready (waiting for explicit resume)")
            captureEvent("ready", after: 0.5)
        case .countdown:
            gameLog("state: countdown")
            captureEvent("countdown", after: 0.45)
        }
    }

    func togglePause() {
        switch flow.state {
        case .running, .countdown: pauseGame(source: "button")
        case .paused, .ready: resumeGame(source: "button")
        case .trackingLost: gameLog("resume refused: someone is still out of tracking")
        }
    }

    func pauseGame(source: String) {
        if flow.pause() { gameLog("pause (\(source))") }
    }

    func resumeGame(source: String) {
        if flow.resume(at: now) { gameLog("resume (\(source))") } else { gameLog("resume refused in state \(flow.state)") }
    }

    /// New session: counters, challenge state and pending effects are reset; settings are kept.
    func replay(source: String) {
        flow.replay(at: now)
        gameLog("replay (\(source)) → session \(flow.session)")
        if gameMode == .jungleDrift { resetJungle() }
        if gameMode == .laserBreakout { resetLaser() }
        if gameMode == .moonbound { resetMoon() }
        captureEvent("replay", after: 0.6)
        for gate in gates {
            gate.challenge?.cancel()
            gate.root.removeFromParent()
            gate.shadow.node.removeFromParent()
        }
        gates.removeAll()
        teamPower = 0
        updateMeter(animated: false)
        boostUntil = 0
        palettePhaseTarget = 0
        resolvedCount = 0
        pendingTurbo = false
        sessionDistanceStart = distance
        for zone in Zone.allCases {
            guard var slot = slots[zone] else { continue }
            slot.squats = 0
            slot.combo = 0
            slot.sim = nil
            slot.botPlanned = nil
            slot.simJump = nil   // a hop planned for the old session must not land in the new one
            slot.jumps = 0
            slot.detector.rearm()
            slots[zone] = slot
            hudNodes.countLabels[zone]?.attributedText = arcadeText("0", size: 54, color: .white, strokeWidth: -5)
            hudNodes.comboLabels[zone]?.attributedText = nil
            hudNodes.ratings[zone]?.removeAllActions()
            hudNodes.ratings[zone]?.alpha = 0
            hideCue(zone)
        }
        hud.children.filter { $0.name == "float" }.forEach { $0.removeFromParent() }
        hideTeamLock()
        lastFlowState = nil
        encounter = nil
        incomingMarker.removeAllActions()
        incomingMarker.isHidden = true
        nextWarningAt = gameTime + SessionFlow.countdownDuration + 1.5
    }

    func startScript() {
        if gameMode == .jungleDrift {
            startJungleScript()
            return
        }
        if gameMode == .laserBreakout {
            startLaserScript()
            return
        }
        if gameMode == .moonbound {
            startMoonScript()
            return
        }
        if let directory = model?.evidenceDirectory {
            // Listening check for the TEAM DUCK audio: hero layering vs Revision 3's single chord.
            audio.exportMix([(.lock, 0, -3), (.impact, 0.07, 0), (.shatter, 0.07, -3), (.whoosh, 0.07, -9), (.team, 0.15, -2)],
                            duration: 1.6, to: directory.appendingPathComponent("team-duck-hero-mix.wav"))
            audio.exportMix([(.team, 0, -1)], duration: 1.6, to: directory.appendingPathComponent("team-duck-legacy-mix.wav"))
        }
        if script == nil { autoplayBeforeScript = model?.autoplay ?? false }
        script = ScenarioScript(steps: ScenarioScript.coop)
        model?.scriptRunning = true
        model?.autoplay = false
        for zone in Zone.allCases { slots[zone]?.simLost = false }
        replay(source: "script start")
    }

    func gameLog(_ message: String) {
        let line = String(format: "[GAME] t=%7.2f real=%7.2f s=%d %@", gameTime, now - logStart, flow.session, message)
        print(line)
        if let directory = model?.evidenceDirectory {
            let url = directory.appendingPathComponent("game.log")
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - Shared challenge HUD ("team lock")

    func showTeamLock(participants: Set<Zone>) {
        let root = hudNodes.lockRoot
        root.removeAllActions()
        root.isHidden = false
        root.alpha = 0
        root.setScale(0.8)
        for zone in Zone.allCases {
            hudNodes.lockSlots[zone]?.alpha = participants.contains(zone) ? 1 : 0.2
            hudNodes.lockSlots[zone]?.setScale(1)
            hudNodes.lockFills[zone]?.removeAllActions()
            hudNodes.lockFills[zone]?.setScale(0)
        }
        lockCount = 0
        lockTotal = participants.count
        updateLockLabel()
        root.run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1.15, duration: 0.3).easeOutBack()]))
    }

    /// Provisional: the movement started. The slot reacts, but nothing is counted yet.
    func lockProvisional(_ zone: Zone) {
        guard let slot = hudNodes.lockSlots[zone] else { return }
        slot.removeAllActions()
        slot.run(.sequence([.scale(to: 1.3, duration: 0.07), .scale(to: 1, duration: 0.18).easeOutBack()]))
    }

    /// The contribution counted: the slot fills with a check, and the shared count goes up.
    func lockContributed(_ zone: Zone) {
        lockCount += 1
        updateLockLabel()
        // Front-loaded: visible at 60% on the very first frame, then pops (game-feel: biggest change first).
        hudNodes.lockFills[zone]?.setScale(0.6)
        hudNodes.lockFills[zone]?.run(.sequence([.scale(to: 1.3, duration: 0.08).easeOut(), .scale(to: 1, duration: 0.15)]))
        hudNodes.lockLabel.run(popAction())
    }

    func resolveTeamLock(team: Bool) {
        let root = hudNodes.lockRoot
        if team, !reduceMotion {
            root.run(.sequence([.scale(to: 1.4, duration: 0.12).easeOut(), .scale(to: 1.15, duration: 0.2),
                                .wait(forDuration: 0.6), .group([.fadeOut(withDuration: 0.25), .scale(to: 0.8, duration: 0.25)]), .hide()]))
            burstSparks(at: root.position, color: Palette.yellow, count: 8)
        } else {
            root.run(.sequence([.wait(forDuration: 0.8), .fadeOut(withDuration: 0.25), .hide()]))
        }
    }

    func hideTeamLock() {
        hudNodes.lockRoot.removeAllActions()
        hudNodes.lockRoot.run(.sequence([.fadeOut(withDuration: 0.2), .hide()]))
    }

    private func updateLockLabel() {
        hudNodes.lockLabel.attributedText = arcadeText("\(lockCount)/\(max(1, lockTotal))", size: 26,
                                                       color: lockCount >= lockTotal && lockTotal > 0 ? Palette.mint : .white, strokeWidth: -5)
    }
}
