import QuartzCore
import SpriteKit

struct PlayerSlot {
    enum Driver { case live, simulated, absent }

    let zone: Zone
    var detector = SquatDetector()
    var driver: Driver = .absent
    var squats = 0
    var combo = 0
    var sim: SimulatedSquat?
    var lastManualSim: TimeInterval = -100
    var livePose: PersonPose?
    var lastLiveSeen: TimeInterval = -100
    var footPoint: CGPoint = .zero
    var headPoint: CGPoint = .zero
    /// Planned simulated squat (game time) and its depth; used by autoplay and scripted scenarios.
    var botPlanned: TimeInterval?
    var botPeak = 0.85
    /// Debug control: pretend the camera lost this player (simulated input only).
    var simLost = false
    /// Jumping (Jungle Drift piranhas): its own detector on the same poses or simulation as the squat detector.
    var jump = JumpDetector()
    var simJump: SimulatedJump?
    var jumps = 0
    var landedAt: TimeInterval = -100
    var nippedAt: TimeInterval = -100
}

/// Overhead "duck" gate. Built in local units of 100 pt per world unit, then scaled by the projection.
/// The gate carries one shared `TeamChallenge` for both players.
final class Gate {
    static let unit: CGFloat = 100
    static let panelTop: CGFloat = 1.4
    let root = SKNode()
    let beam = SKSpriteNode(texture: Art.beam)
    let posts = [SKSpriteNode(texture: Art.post), SKSpriteNode(texture: Art.post)]
    var panels: [Zone: SKSpriteNode] = [:]
    var checks: [Zone: SKSpriteNode] = [:]
    /// Each half of the beam lights in a player's colour once they have contributed.
    var beamGlows: [Zone: SKSpriteNode] = [:]
    var z: CGFloat
    var warned = false
    var resolved = false
    var withdrawn = false
    var challenge: TeamChallenge?
    var ticksPlayed = 0
    var born: TimeInterval = 0
    /// Overhead light column that makes the gate readable while it is still a speck at the horizon.
    let beacon = SKSpriteNode(texture: Art.searchlight)
    let shadow = RoofShadow()

    init(z: CGFloat, playerX: CGFloat, colors: [Zone: UIColor]) {
        self.z = z
        let u = Gate.unit
        for (i, post) in posts.enumerated() {
            post.anchorPoint = CGPoint(x: 0.5, y: 0)
            post.size = CGSize(width: 0.32 * u, height: 1.95 * u)
            post.position = CGPoint(x: (i == 0 ? -2.35 : 2.35) * u, y: 0)
            root.addChild(post)
        }
        beam.size = CGSize(width: 5.1 * u, height: 0.5 * u)
        beam.position = CGPoint(x: 0, y: 1.62 * u)
        beam.zPosition = 0.2
        root.addChild(beam)
        beacon.anchorPoint = CGPoint(x: 0.5, y: 0)
        beacon.size = CGSize(width: 2.4 * u, height: 7 * u)
        beacon.position = CGPoint(x: 0, y: 1.8 * u)
        beacon.color = Palette.yellow
        beacon.colorBlendFactor = 1
        beacon.blendMode = .add
        beacon.alpha = 0.55
        root.addChild(beacon)
        for zone in Zone.allCases {
            let panel = SKSpriteNode(texture: Art.lanePanel)
            // Hangs from the beam over each player's head-and-shoulders area: "this space must be empty".
            panel.size = CGSize(width: 0.78 * u, height: 0.52 * u)
            panel.anchorPoint = CGPoint(x: 0.5, y: 1)
            panel.position = CGPoint(x: (zone == .left ? -playerX : playerX) * u, y: Gate.panelTop * u)
            panel.color = colors[zone] ?? .white
            panel.colorBlendFactor = 0.85
            panel.yScale = 0
            panel.zPosition = 0.1
            root.addChild(panel)
            panels[zone] = panel

            let check = SKSpriteNode(texture: Art.check)
            check.size = CGSize(width: 0.24 * u, height: 0.24 * u)
            check.position = CGPoint(x: 0, y: -0.26 * u)
            check.setScale(0)
            check.zPosition = 0.3
            panel.addChild(check)
            checks[zone] = check

            let glow = SKSpriteNode(texture: Art.pill)
            glow.size = CGSize(width: 2.45 * u, height: 0.62 * u)
            glow.position = CGPoint(x: (zone == .left ? -1.27 : 1.27) * u, y: beam.position.y)
            glow.color = colors[zone] ?? .white
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0
            glow.zPosition = 0.25
            root.addChild(glow)
            beamGlows[zone] = glow
        }
    }
}

/// One obstacle encounter in progress (see `EncounterTiming`).
struct Encounter {
    /// Cruise-equivalent seconds since the warning began.
    var t: Double = 0
    var gate: Gate?
    var resolved = false
}

extension WorldScene {
    // MARK: - Input sources (camera or simulation) → movement events

    func simulateSquat(_ zone: Zone, shallow: Bool = false) {
        guard var slot = slots[zone], slot.driver != .live, !slot.simLost else { return }
        if let sim = slot.sim, gameTime - sim.start < sim.duration { return }
        slot.sim = SimulatedSquat(start: gameTime, peak: shallow ? 0.35 : 0.85)
        slot.lastManualSim = now
        slots[zone] = slot
    }

    /// A simulated two-footed hop (crouch, then airborne ~0.4 s) through the same JumpDetector as camera poses.
    func simulateJump(_ zone: Zone, manual: Bool = true) {
        guard var slot = slots[zone], slot.driver != .live, !slot.simLost else { return }
        if let jump = slot.simJump, gameTime < jump.end { return }
        slot.simJump = SimulatedJump(start: gameTime)
        if manual { slot.lastManualSim = now }
        slots[zone] = slot
    }

    func setSimulatedTrackingLost(_ zone: Zone, lost: Bool) {
        guard var slot = slots[zone] else { return }
        slot.simLost = lost
        if lost { slot.sim = nil; slot.botPlanned = nil; slot.simJump = nil }
        slot.lastManualSim = now
        slots[zone] = slot
        gameLog("debug: \(role(for: zone)) tracking \(lost ? "OFF" : "ON") (simulated)")
    }

    func applyLivePoses(_ snapshot: VisionSnapshot) {
        let assigned = zoneTracker.assign(snapshot.people, at: now)
        for zone in Zone.allCases {
            guard var slot = slots[zone] else { continue }
            if let pose = assigned[zone] {
                if slot.driver != .live { slot.detector = SquatDetector(); slot.jump = JumpDetector() }
                slot.livePose = pose
                slot.lastLiveSeen = now
                slot.driver = .live
                let events = slot.detector.update(pose: pose, at: now)
                let jumpEvents = gameMode == .jungleDrift ? slot.jump.update(pose: pose, at: now) : []
                slots[zone] = slot
                handle(events, zone: zone, captureTime: snapshot.captureTime)
                handleJump(jumpEvents, zone: zone, captureTime: snapshot.captureTime)
            } else {
                slot.livePose = nil
                slots[zone] = slot
            }
        }
        layoutLiveBody()
    }

    /// Decides who drives each zone this frame: a tracked person, a simulated/autoplay player, or nobody.
    /// Simulated squats run on game time (frozen while halted); detectors always run on real time.
    func updateInputs(dt: TimeInterval) {
        let autoplay = model?.autoplay ?? false
        for zone in Zone.allCases {
            guard var slot = slots[zone] else { continue }
            let liveRecently = inputSource == .camera && now - slot.lastLiveSeen < slot.detector.config.lostTimeout
            if liveRecently { continue }
            let canSimulate = inputSource != .camera || autoplay || anyScriptRunning || now - slot.lastManualSim < 20
            if canSimulate {
                if slot.driver != .simulated {
                    slot.detector = SquatDetector()
                    slot.jump = JumpDetector()
                    slot.driver = .simulated
                }
                if let planned = slot.botPlanned, gameTime >= planned, !slot.simLost {
                    slot.botPlanned = nil
                    slot.sim = SimulatedSquat(start: gameTime, peak: slot.botPeak)
                }
                let depth: Double? = slot.simLost ? nil : (slot.sim?.depth(at: gameTime) ?? 0)
                if let sim = slot.sim, gameTime - sim.start > sim.duration + 0.2 { slot.sim = nil }
                let events = slot.detector.update(depth: depth, at: now)
                let lift: Double? = slot.simLost ? nil : (slot.simJump?.lift(at: gameTime) ?? 0)
                if let jump = slot.simJump, gameTime > jump.end + 0.2 { slot.simJump = nil }
                let jumpEvents = slot.jump.update(lift: lift, at: now)
                slots[zone] = slot
                handle(events, zone: zone, captureTime: nil)
                handleJump(jumpEvents, zone: zone, captureTime: nil)
            } else {
                let events = slot.detector.update(depth: nil, at: now)
                _ = slot.jump.update(lift: nil, at: now)
                if !slot.detector.isTracking { slot.driver = .absent }
                slots[zone] = slot
                handle(events, zone: zone, captureTime: nil)
            }
        }
    }

    // MARK: - Movement events → game logic

    /// Consumes validated movement events independently of their source. Visual feedback is triggered from
    /// here, but counts and Team Power come only from the detector events and the challenge model.
    func handle(_ events: [SquatEvent], zone: Zone, captureTime: Double?) {
        for event in events {
            if captureTime != nil {
                // Live-input event log, used to compare detected reps against a manual count.
                print(String(format: "[SQUAT] t=%.2f zone=%@ event=%@ reps=%d", now, zone == .left ? "L" : "R",
                             String(describing: event), (slots[zone]?.squats ?? 0) + (event == .repCompleted ? 1 : 0)))
            }
            switch event {
            case .found:
                roster.insert(zone)
                let before = flow.state
                flow.trackingRecovered(zone)
                if flow.state != before { gameLog("\(role(for: zone)) tracking recovered") }
                continue
            case .lost:
                guard roster.contains(zone) else { continue }
                gameLog("\(role(for: zone)) tracking LOST")
                flow.trackingLost(zone)
                continue
            default:
                break
            }
            guard flow.acceptsMovement else {
                if event != .aborted { gameLog("ignored \(event) from \(role(for: zone)) (state \(flow.state))") }
                continue
            }
            if gameMode == .jungleDrift {
                handleJungle(event, zone: zone)
                continue
            }
            let gate = activeWindowGate()
            switch event {
            case .descentStarted:
                if let captureTime { meter.recordFeedbackLatency(ms: (now - captureTime) * 1000) }
                if let gate, gate.challenge?.movementStarted(zone) == true {
                    laneResponds(zone, gate: gate)
                    lockProvisional(zone)
                } else {
                    padPulse(zone)
                }
            case .bottomReached:
                if let gate, let banked = gate.challenge?.contribute(zone, at: gameTime), banked > 0 {
                    gameLog("\(role(for: zone)) contributed to challenge #\(gate.challenge?.id ?? 0) (+\(banked) power)")
                    laneArmed(zone, gate: gate)
                    lockContributed(zone)
                    addTeamPower(banked)
                    captureEvent("c\(gate.challenge?.id ?? 0)-contribution-\(role(for: zone))", after: 0.18)
                }
            case .repCompleted:
                repCompleted(zone)
                gameLog("\(role(for: zone)) rep completed (total \(slots[zone]?.squats ?? 0))")
            case .aborted:
                if let gate, let challenge = gate.challenge, challenge.isOpen,
                   challenge.started.contains(zone), !challenge.contributed.contains(zone) {
                    laneReset(zone, gate: gate)
                    popRating(zone, text: "GO DEEPER!", color: Palette.yellow, at: slots[zone]?.headPoint ?? .zero)
                    gameLog("\(role(for: zone)) incomplete squat (not deep enough)")
                    captureEvent("c\(challenge.id)-go-deeper", after: 0.2)
                }
            case .found, .lost:
                break
            }
        }
    }

    /// The gate currently inside its warning window, if any.
    func activeWindowGate() -> Gate? {
        gates.first { $0.warned && !$0.resolved && !$0.withdrawn }
    }

    func activeZones() -> [Zone] {
        Zone.allCases.filter { slots[$0]?.driver != .absent && slots[$0]?.detector.isTracking == true }
    }

    // MARK: - Encounters: WARNING → REVEAL → APPROACH → DUCK → PASS → FEEDBACK → RECOVERY

    var cruiseSpeed: CGFloat { baseSpeed * (reduceMotion ? 0.7 : 1) }
    var encounterActive: Bool { encounter.map { !$0.resolved } ?? false }

    func updateGates(dt: CGFloat) {
        if encounter == nil, flow.state == .running, gameTime >= nextWarningAt, !setPieceBlocksGates {
            encounter = Encounter()
            beginEncounterWarning()
        }

        if var e = encounter {
            // Encounter time runs at the speed the world actually moves (cruise-equivalent seconds), so the gate
            // stays locked to the scenery through hit-stop, slow-downs and halts.
            e.t += Double(dt) * Double(worldSpeed / max(cruiseSpeed, 0.01))
            let phase = timing.phase(at: e.t)
            if e.gate == nil, phase != .warning, !e.resolved {
                e.gate = revealGate()
                hideIncomingMarker()
                gameLog("obstacle revealed at the horizon (z \(Int(e.gate!.z)))")
            }
            if let gate = e.gate {
                gate.z = proj.baseZp + cruiseSpeed * CGFloat(timing.arrivalTime - e.t)
                if !gate.warned, !gate.withdrawn, phase == .action {
                    gate.warned = true
                    beginActionCue(gate)
                }
                let everyoneIn = gate.challenge.map { $0.isOpen && !$0.participants.isEmpty && $0.contributed == $0.participants } ?? false
                let early = everyoneIn && e.t >= timing.arrivalTime - timing.impactLead
                if !gate.resolved, !gate.withdrawn, early || e.t >= timing.windowCloseTime {
                    resolve(gate)
                    e.resolved = true
                }
            }
            encounter = e
            if e.resolved, e.gate.map({ $0.z < 0.3 }) ?? true { encounter = nil }
        }

        for gate in gates {
            let ppu = proj.ppu(gate.z)
            gate.root.position = proj.screen(x: 0, h: 0, z: gate.z)
            gate.root.setScale(ppu / Gate.unit)
            gate.root.zPosition = proj.depthZ(gate.z) + (gate.z > proj.zp ? -1 : 1)
            if !gate.withdrawn {
                // Reveal: emerges from the haze over ~1 s rather than popping in; tinted by the same fog as the city.
                gate.root.alpha = min(1, CGFloat(now - gate.born) / 1.0) * smoothstep(0.3, 0.9, gate.z)
                let fog = smoothstep(14, 90, gate.z) * 0.8
                for node in [gate.beam] + gate.posts {
                    node.color = Palette.coral.mixed(with: Palette.electric, amount: palettePhase)
                    node.colorBlendFactor = fog
                }
            }
            gate.root.isHidden = false
            // The beam's shadow lies on the deck beneath it and sweeps over the players first.
            gate.shadow.update(proj, zNear: gate.z - 0.45, zFar: gate.z + 0.45, halfWidth: roofHalf,
                               alpha: mode == .immersive && !gate.beam.isHidden && !gate.withdrawn ? 0.45 * (1 - smoothstep(20, 40, gate.z)) : 0)
            guard !gate.withdrawn else { continue }
            if gate.resolved, gate.z < proj.zp * 0.8 {
                for node in Array(gate.panels.values) + Array(gate.beamGlows.values) { node.isHidden = true }
            }
            if gate.warned, !gate.resolved {
                let timeToArrival = TimeInterval((gate.z - proj.baseZp) / max(cruiseSpeed, 0.01))
                // Ticks speed up as the gate closes in.
                let tickTimes: [TimeInterval] = [1.5, 1.0, 0.5]
                if gate.ticksPlayed < tickTimes.count, timeToArrival <= tickTimes[gate.ticksPlayed] {
                    gate.ticksPlayed += 1
                    audio.play(.tick, dB: -8 + Float(gate.ticksPlayed) * 2)
                }
                let urgency = 1 - max(0, min(1, timeToArrival / timing.actionLead))
                let pulse = 0.82 + 0.18 * sin(CGFloat(now) * (6 + 14 * urgency))
                for zone in Zone.allCases where gate.challenge?.started.contains(zone) != true {
                    gate.panels[zone]?.alpha = pulse
                }
                updateCues(gate: gate, urgency: CGFloat(urgency))
            }
        }

        gates.removeAll { gate in
            if gate.z < 0.3 || (gate.withdrawn && gate.root.parent != nil && gate.root.alpha <= 0.01) {
                gate.root.removeFromParent()
                gate.shadow.node.removeFromParent()
                return true
            }
            return false
        }
        updateIncomingMarker()

        // Approach lanes on the deck: lit only while the action window is open.
        let inbound = activeWindowGate()
        laneWarn += ((inbound == nil ? 0 : 1) - laneWarn) * min(1, dt * 6)
        floorShader.uniformNamed("u_warn")?.floatValue = Float(laneWarn * (0.8 + 0.2 * sin(CGFloat(now) * 9)))
        if let inbound { floorShader.uniformNamed("u_gateZ")?.floatValue = Float(inbound.z) }
        floorShader.uniformNamed("u_laneX")?.floatValue = Float(playerX)
        floorShader.uniformNamed("u_leftColor")?.vectorFloat3Value = Palette.color(for: .left, swapped: swapped).rgb
        floorShader.uniformNamed("u_rightColor")?.vectorFloat3Value = Palette.color(for: .right, swapped: swapped).rgb
    }

    /// Phase A: early warning. Nothing is visible yet and nothing is judged; a marker pulses where it will appear.
    private func beginEncounterWarning() {
        let both = activeZones().count >= 2
        gameLog("encounter warning: DUCK INCOMING (obstacle not yet visible)")
        showBanner("DUCK INCOMING!", sub: both ? "Get ready to squat together" : "Get ready to squat", color: Palette.yellow,
                   hold: timing.warningDuration - 0.2)
        audio.play(.whoosh, dB: -12)
        audio.play(.tick, dB: -10)
        incomingMarker.removeAllActions()
        incomingMarker.isHidden = false
        incomingMarker.alpha = 0
        incomingMarker.run(.fadeIn(withDuration: 0.25))
        script?.encounterStarted(scene: self)
        captureEvent("e\(challengeCounter + 1)-a-warning", after: 0.5)
    }

    private func updateIncomingMarker() {
        guard !incomingMarker.isHidden else { return }
        let p = proj.screen(x: 0, h: 2.4, z: 80)   // just above the locomotive, where the gate will appear
        incomingMarker.position = p
        let beat = reduceMotion ? 1 : 1 + 0.12 * sin(CGFloat(now) * 10)
        incomingMarker.setScale(beat)
    }

    private func hideIncomingMarker() {
        incomingMarker.run(.sequence([.fadeOut(withDuration: 0.3), .hide()]))
    }

    /// Phase B: the obstacle appears far down the track and grows as the train carries the players toward it.
    private func revealGate() -> Gate {
        var colors: [Zone: UIColor] = [:]
        for zone in Zone.allCases { colors[zone] = Palette.color(for: zone, swapped: swapped) }
        let gate = Gate(z: proj.baseZp + cruiseSpeed * CGFloat(timing.approachDuration), playerX: playerX, colors: colors)
        gate.born = now
        gate.root.isHidden = true
        gate.root.alpha = 0
        addChild(gate.root)
        worldRoot.addChild(gate.shadow.node)
        gates.append(gate)
        // Anticipation: posts spring up out of the track, then the beam drops into place with overshoot.
        for post in gate.posts {
            post.yScale = 0
            post.run(.scaleY(to: 1, duration: 0.45).easeOutBack())
        }
        let restY = gate.beam.position.y
        gate.beam.position.y = restY + 1.6 * Gate.unit
        gate.beam.alpha = 0
        gate.beam.run(.sequence([.wait(forDuration: 0.25),
                                 .group([.moveTo(y: restY, duration: 0.45).easeOutBack(overshoot: 2.2), .fadeIn(withDuration: 0.15)])]))
        if !reduceMotion {
            gate.beacon.run(.repeatForever(.sequence([.fadeAlpha(to: 0.75, duration: 0.4), .fadeAlpha(to: 0.4, duration: 0.4)])), withKey: "pulse")
        }
        captureEvent("e\(challengeCounter + 1)-b-reveal", after: 0.9)
        return gate
    }

    /// Big overhead set pieces are staged between challenges so they never compete with a gate's cues.
    var setPieceBlocksGates: Bool {
        if tunnelActive, tunnelRings.contains(where: { !$0.isHidden && (($0.userData?["z"] as? CGFloat) ?? 0) > proj.zp + 4 }) {
            return true
        }
        if let mark = landmark, mark.kind == .bridge, mark.z > 3 { return true }
        // Warnings are timed from current speed; spawning during a boost would stretch the window unpredictably.
        if now < boostUntil + 0.5 { return true }
        return false
    }

    private func spawnGate() {
        var colors: [Zone: UIColor] = [:]
        for zone in Zone.allCases { colors[zone] = Palette.color(for: zone, swapped: swapped) }
        let gate = Gate(z: 68, playerX: playerX, colors: colors)
        gate.root.isHidden = true
        gate.root.alpha = 0
        addChild(gate.root)
        worldRoot.addChild(gate.shadow.node)
        gates.append(gate)
        // Anticipation: posts spring up out of the track, then the beam drops into place with overshoot.
        for post in gate.posts {
            post.yScale = 0
            post.run(.scaleY(to: 1, duration: 0.45).easeOutBack())
        }
        let restY = gate.beam.position.y
        gate.beam.position.y = restY + 1.6 * Gate.unit
        gate.beam.alpha = 0
        gate.beam.run(.sequence([.wait(forDuration: 0.25),
                                 .group([.moveTo(y: restY, duration: 0.45).easeOutBack(overshoot: 2.2), .fadeIn(withDuration: 0.15)])]))
        if !reduceMotion {
            gate.beacon.run(.repeatForever(.sequence([.fadeAlpha(to: 0.75, duration: 0.4), .fadeAlpha(to: 0.4, duration: 0.4)])), withKey: "pulse")
        }
    }

    /// Phase C: the obstacle is recognisable — "DUCK!" and the judging window opens (a challenge exists only from now).
    private func beginActionCue(_ gate: Gate) {
        challengeCounter += 1
        let participants = Set(activeZones())
        gate.challenge = TeamChallenge(id: challengeCounter, participants: participants)
        gameLog("challenge #\(challengeCounter) DUCK cue, window open; participants: \(participants.map { role(for: $0) }.sorted().joined(separator: "+"))")

        // Hand over from the long-range beacon to the close-range lane cues.
        gate.beacon.removeAction(forKey: "pulse")
        gate.beacon.run(.fadeOut(withDuration: 0.4))
        for (zone, panel) in gate.panels {
            guard participants.contains(zone) else { panel.isHidden = true; continue }
            panel.run(.sequence([.wait(forDuration: zone == .left ? 0 : 0.06), .scaleY(to: 1, duration: 0.28).easeOutBack(overshoot: 1.9)]))
        }
        let both = participants.count >= 2
        showBanner("DUCK!", sub: both ? "Both squat before it arrives" : "Squat before it arrives", color: Palette.yellow, hold: 1.3)
        showTeamLock(participants: participants)
        audio.play(.whoosh, dB: -10)
        for zone in Zone.allCases {
            if let cue = hudNodes.cues[zone], participants.contains(zone) {
                cue.removeAllActions()
                cue.alpha = 1
                cue.color = Palette.color(for: zone, swapped: swapped)
                cue.setScale(0.2)
                cue.isHidden = false
                cue.run(.scale(to: 1, duration: 0.25).easeOutBack())
            }
            // Autoplay players react with human-ish, non-simultaneous timing (scripts plan their own).
            if script == nil, var slot = slots[zone], slot.driver == .simulated, (model?.autoplay ?? false), now - slot.lastManualSim > 20 {
                slot.botPlanned = Double.random(in: 0...1) < 0.88 ? gameTime + Double.random(in: 0.25...1.35) : nil
                slot.botPeak = 0.85
                slots[zone] = slot
            }
        }
        script?.challengeWarned(scene: self)
        captureEvent("e\(challengeCounter)-c-duck-cue", after: 0.4)
    }

    private func resolve(_ gate: Gate) {
        gate.resolved = true
        for zone in Zone.allCases { hideCue(zone) }
        guard var challenge = gate.challenge else {
            for panel in gate.panels.values { panel.run(.fadeOut(withDuration: 0.15)) }
            return
        }
        let (outcome, bonus) = challenge.resolve()
        gate.challenge = challenge
        resolvedCount += 1

        for zone in Zone.allCases where !challenge.participants.contains(zone) {
            gate.panels[zone]?.run(.fadeOut(withDuration: 0.15))
        }
        switch outcome {
        case .team(let zones):
            for zone in zones.sorted(by: { $0.rawValue < $1.rawValue }) { credit(zone, gate: gate) }
            teamSuccess(gate)
            addTeamPower(bonus)
            resolveTeamLock(team: true)
            gameLog("challenge #\(challenge.id) TEAM (+\(bonus) bonus); power \(teamPower)/\(teamPowerMax)")
            captureEvent("c\(challenge.id)-team", after: 0.08)
            captureEvent("c\(challenge.id)-team-after", after: 0.5)
        case .partial(let done, let missing):
            for zone in done.sorted(by: { $0.rawValue < $1.rawValue }) { credit(zone, gate: gate) }
            for zone in missing.sorted(by: { $0.rawValue < $1.rawValue }) {
                if var slot = slots[zone] { slot.combo = 0; slots[zone] = slot }
                laneMiss(zone, gate: gate)
            }
            resolveTeamLock(team: false)
            if !done.isEmpty, challenge.participants.count >= 2 {
                showBanner("NICE!", sub: "Squat together for the TEAM bonus", color: Palette.color(for: done.first!, swapped: swapped), hold: 1.0)
            }
            captureEvent("c\(challenge.id)-partial", after: 0.3)
            gameLog("challenge #\(challenge.id) partial: done [\(done.map { role(for: $0) }.sorted().joined(separator: ","))] missing [\(missing.map { role(for: $0) }.sorted().joined(separator: ","))]; power \(teamPower)/\(teamPowerMax)")
        case .cancelled:
            break
        }
        nextWarningAt = gameTime + timing.recoveryDuration
        stageSetPieceAfterResolution()
        captureEvent("e\(challenge.id)-e-pass", after: 0.12)
        captureEvent("e\(challenge.id)-f-reward", after: 0.6)
        if pendingTurbo, !flow.isHalted {
            pendingTurbo = false
            gameLog("TURBO (deferred until the encounter resolved)")
            run(.wait(forDuration: 1.2)) { [weak self] in self?.turbo() }
        }
        script?.challengeResolved(scene: self)
    }

    private func credit(_ zone: Zone, gate: Gate) {
        guard var slot = slots[zone] else { return }
        slot.combo += 1
        let perfect = slot.detector.phase != .standing
        slots[zone] = slot
        laneSuccess(zone, gate: gate, perfect: perfect)
    }

    /// Pause / tracking loss policy: an inbound challenge is withdrawn (no further award; banked contributions
    /// stay) and the gate folds away, so nothing can resolve or score while the game is halted.
    func withdrawGates() {
        for gate in gates where !gate.withdrawn {
            if gate.challenge?.isOpen == true {
                gate.challenge?.cancel()
                gameLog("challenge #\(gate.challenge?.id ?? 0) withdrawn (game halted); banked contributions kept")
            }
            gate.withdrawn = true
            gate.resolved = true
            for post in gate.posts { post.run(.scaleY(to: 0, duration: 0.3).easeOut()) }
            gate.root.run(.sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.3)]))
        }
        for zone in Zone.allCases { hideCue(zone) }
        hideTeamLock()
        if encounter != nil { gameLog("encounter withdrawn (game halted)") }
        if gameMode == .jungleDrift { withdrawJungleHazards() }
        encounter = nil
        hideIncomingMarker()
    }
}

extension SKAction {
    /// Ease-out with overshoot ("back"): the motion-design "playful" curve.
    func easeOutBack(overshoot: Float = 1.70158) -> SKAction {
        timingFunction = { t in
            let s = overshoot
            let u = t - 1
            return u * u * ((s + 1) * u + s) + 1
        }
        return self
    }

    func easeOut() -> SKAction {
        timingMode = .easeOut
        return self
    }

    /// Accelerating: falls and departures.
    func easeIn() -> SKAction {
        timingMode = .easeIn
        return self
    }
}
