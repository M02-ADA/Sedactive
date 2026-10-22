import QuartzCore
import SpriteKit

// River Log Sweep and Crocodile Tail Sweep (JUMP). Rules: JumpSweepJudge; timing and performance: JumpSweepLogic.swift.
// Same structure as the piranhas: WARNING → REVEAL → APPROACH / ANTICIPATION → JUMP! → ACTION → RESOLVE → RECOVERY.

/// What both sweeps share: the encounter clock, the judge, planned simulated jumps, the warning badges and path dashes.
@MainActor
class SweepHazard {
    var t: Double = 0
    var judge: JumpSweepJudge?
    var revealed = false
    var cued = false
    var ticks = 0
    /// Simulated jumps planned on this encounter's clock (autoplay bots and scripts).
    var plannedJumps: [(zone: Zone, at: Double)] = []
    var signs: [SKSpriteNode] = []
    var dashes: [SKSpriteNode] = []
    var lastFx: TimeInterval = 0

    init() {}

    var nodes: [SKNode] { signs + dashes }
}

/// The log: a crop node cuts it at the waterline while it floats; body frames roll; roots and a leafy branch turn
/// with it; a contact shadow sits under it on the deck; a foam collar hugs it in the water.
@MainActor
final class LogHazard: SweepHazard {
    let animator: LogAnimator
    let crop = SKCropNode()
    let mask = SKSpriteNode(color: .white, size: CGSize(width: 8000, height: 8000))
    let body = SKSpriteNode(texture: Art.logFrames[0])
    let roots = SKSpriteNode(texture: Art.logRoots)
    let branch = SKSpriteNode(texture: Art.logBranch)
    let shadow = SKSpriteNode(texture: Art.glow)
    let foam = SKSpriteNode(texture: Art.foamCollar)
    var leaves: [SKSpriteNode] = []
    var lastState: LogPose.State = .churning
    var lashingsPassed = 0

    init(timing: LogSweepTiming) {
        animator = LogAnimator(timing: timing)
        super.init()
        mask.anchorPoint = CGPoint(x: 0.5, y: 0)
        crop.maskNode = mask
        for node in [body, roots, branch] { crop.addChild(node) }
        roots.anchorPoint = CGPoint(x: Art.logRootsAnchor.x / Art.logRoots.size().width, y: 1 - Art.logRootsAnchor.y / Art.logRoots.size().height)
        branch.anchorPoint = CGPoint(x: 0.5, y: 0)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        for node in [shadow, foam] { node.alpha = 0 }
        crop.alpha = 0
    }

    override var nodes: [SKNode] { super.nodes + [crop, shadow, foam] + leaves }
}

/// The tail sweep croc: the layered CrocRig body in the water, plus an articulated tail chain (segments + tip) with
/// contact shadows on the deck.
@MainActor
final class TailHazard: SweepHazard {
    let side: Zone
    let animator: TailSweepAnimator
    let croc = CrocRig()
    var segments: [SKSpriteNode] = []
    let tip = SKSpriteNode(texture: Art.tailTip)
    var shadows: [SKSpriteNode] = []
    var bubbles: [SKSpriteNode] = []
    var lastState: TailPose.State = .hidden
    /// Somebody was caught: the croc's reaction is pleased instead of dizzy.
    var hit = false
    var slapped = false
    var swept = false

    init(side: Zone, timing: TailSweepTiming) {
        self.side = side
        animator = TailSweepAnimator(timing: timing)
        super.init()
        for _ in 0..<TailPath.segments {
            let s = SKSpriteNode(texture: Art.tailSegment)
            s.alpha = 0
            segments.append(s)
            let shadow = SKSpriteNode(texture: Art.glow)
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0
            shadows.append(shadow)
        }
        tip.anchorPoint = CGPoint(x: 0.02, y: 1 - 43.0 / 70.0)
        tip.alpha = 0
    }

    override var nodes: [SKNode] { super.nodes + segments + [tip] + shadows + bubbles }
}

extension WorldScene {
    /// Logic depth (world z, players at FootZone.playerZ) → the projection's depth (players at proj.zp).
    private func dz(_ z: Double) -> CGFloat { CGFloat(z - FootZone.playerZ) + proj.zp }

    // MARK: - Shared: badges, cue, judging, planned jumps

    private func addSigns(_ hazard: SweepHazard, texture: SKTexture, count: Int) {
        for _ in 0..<count {
            let sign = SKSpriteNode(texture: texture)
            sign.zPosition = Layer.flash - 12
            sign.setScale(0)
            addChild(sign)
            sign.run(.sequence([.wait(forDuration: 0.1), .group([.fadeIn(withDuration: 0.1),
                     .scale(to: Self.signScale, duration: 0.35).easeOutBack(overshoot: 2.2)])]), withKey: "in")
            hazard.signs.append(sign)
        }
        for _ in 0..<12 {
            let dash = SKSpriteNode(texture: Art.piranhaDash)
            dash.color = Palette.yellow
            dash.colorBlendFactor = 1
            dash.blendMode = .add
            dash.alpha = 0
            dash.zPosition = Layer.pad + 0.05   // on the deck, behind the bodies
            addChild(dash)
            hazard.dashes.append(dash)
        }
    }

    /// Badges stay at the screen edges (never over a player); they bob, then pop away once JUMP! is up.
    private func updateSigns(_ hazard: SweepHazard, xs: [CGFloat], cueTime: Double) {
        let pulse = reduceMotion ? 1 : 1 + 0.08 * sin(CGFloat(now) * 9)
        let bob = reduceMotion ? 0 : sin(CGFloat(now) * 3) * 6
        for (i, sign) in hazard.signs.enumerated() {
            sign.position = CGPoint(x: xs[min(i, xs.count - 1)], y: size.height * 0.5 + bob)
            if !sign.hasActions() { sign.setScale(Self.signScale * pulse) }
            if hazard.t > cueTime + 0.5, sign.action(forKey: "out") == nil, sign.alpha > 0 {
                sign.run(.group([.fadeOut(withDuration: 0.25), .scale(by: 1.3, duration: 0.25)]), withKey: "out")
            }
        }
    }

    /// The path guide on the deck: dashes along `points` (world x, z), glowing in from the reveal; after JUMP! a
    /// chase runs along them in the hazard's direction of travel.
    private func updateDashes(_ hazard: SweepHazard, points: [(x: Double, z: Double)], revealAt: Double, hide: Bool) {
        for (k, dash) in hazard.dashes.enumerated() {
            guard k < points.count else { dash.alpha = 0; continue }
            let a = points[k], b = points[min(k + 1, points.count - 1)], prev = points[max(k - 1, 0)]
            let p = proj.screen(x: CGFloat(a.x), h: 0.02, z: dz(a.z))
            let q = proj.screen(x: CGFloat(b.x), h: 0.02, z: dz(b.z))
            let o = k + 1 < points.count ? q : proj.screen(x: CGFloat(prev.x), h: 0.02, z: dz(prev.z))
            dash.position = p
            dash.zRotation = k + 1 < points.count ? atan2(q.y - p.y, q.x - p.x) : atan2(p.y - o.y, p.x - o.x)
            dash.setScale(proj.ppu(dz(a.z)) * 0.12 / 44)
            var target: CGFloat = 0
            if hazard.revealed, !hide {
                target = 0.3 * CGFloat(min(1, (hazard.t - revealAt) / 0.6))
                if hazard.cued {
                    let phase = CGFloat(k) / CGFloat(points.count) - CGFloat(now) * 1.4
                    target = reduceMotion ? 0.55 : target + 0.35 * max(0, sin(2 * .pi * phase))
                }
            }
            dash.alpha += (target - dash.alpha) * 0.25
            dash.color = hazard.cued ? Palette.yellow : Palette.coral.mixed(with: Palette.yellow, amount: 0.4)
        }
    }

    /// JUMP! cue: the judge opens with the crossings computed from the hazard's actual path.
    private func cueSweep(_ hazard: SweepHazard, crossings: [Zone: Double], cueTime: Double, window: JumpWindow, sub: String, label: String) {
        let rt = jungleRuntime
        hazard.cued = true
        rt.hazardCounter += 1
        let participants = Set(activeZones())
        hazard.judge = JumpSweepJudge(id: rt.hazardCounter, crossings: crossings, cueTime: cueTime, participants: participants, window: window)
        showBanner("JUMP!", sub: participants.count >= 2 ? sub : "Jump!", color: Palette.yellow, hold: 1.1)
        showTeamLock(participants: participants)
        for zone in participants { showCue(zone, up: true) }
        audio.play(.whoosh, dB: -9)
        // Autoplay bots: mostly on time, sometimes early or late (never for a player driven by hand or camera).
        if rt.script == nil, model?.autoplay == true {
            let crouch = SimulatedJump(start: 0).crouch
            for zone in participants {
                guard let slot = slots[zone], slot.driver == .simulated, now - slot.lastManualSim > 20 else { continue }
                let roll = Double.random(in: 0...1)
                let offset = roll < 0.85 ? Double.random(in: -0.5 ... -0.15) : (roll < 0.93 ? -1.2 : 0.35)
                hazard.plannedJumps.append((zone, crossings[zone, default: cueTime] + offset - crouch))
            }
        }
        gameLog("\(label): JUMP cue (#\(rt.hazardCounter)); crossings at "
                + Zone.allCases.map { String(format: "%@ %.2f s", role(for: $0), crossings[$0, default: 0] - hazard.t) }.joined(separator: ", "))
    }

    /// Rhythm ticks before the first crossing, planned jumps, and per-frame judging.
    private func runSweepJudge(_ hazard: SweepHazard, kind: SweepKind) {
        guard hazard.cued, var judge = hazard.judge else { return }
        let first = judge.crossings.values.min() ?? 0
        let marks: [Double] = [1.05, 0.7, 0.35]
        if hazard.ticks < marks.count, first - hazard.t <= marks[hazard.ticks] {
            hazard.ticks += 1
            audio.play(.tick, dB: -10 + Float(hazard.ticks) * 2)
        }
        let due = hazard.plannedJumps.filter { hazard.t >= $0.at }
        hazard.plannedJumps.removeAll { hazard.t >= $0.at }
        for plan in due { simulateJump(plan.zone, manual: false) }
        let airborne = Dictionary(uniqueKeysWithValues: Zone.allCases.map { ($0, slots[$0]?.jump.isAirborne ?? false) })
        let events = judge.update(at: hazard.t, airborne: airborne)
        hazard.judge = judge
        if !events.isEmpty { handleSweepEvents(hazard, kind: kind, events: events) }
    }

    enum SweepKind {
        case log, tail
        var label: String { self == .log ? "log" : "tail" }
        var hitText: String { self == .log ? "BUMPED!" : "SWEPT!" }
    }

    private func handleSweepEvents(_ hazard: SweepHazard, kind: SweepKind, events: [JumpJudgeEvent]) {
        let rt = jungleRuntime
        guard let judge = hazard.judge else { return }
        for event in events {
            switch event {
            case .cleared(let zone, let power):
                lockContributed(zone)
                addTeamPower(power)
                hideCue(zone)
                // Credit is banked the moment the feet are up in the window; the praise lands as it passes under.
                let wait = max(0, judge.crossing(zone) - hazard.t)
                run(.wait(forDuration: wait)) { [weak self] in
                    guard let self else { return }
                    self.popRating(zone, text: "CLEARED!", color: Palette.mint, at: self.slots[zone]?.headPoint ?? .zero)
                    self.audio.play(.pop, dB: -8)
                }
                gameLog("\(kind.label): \(role(for: zone)) cleared (+\(power) power)")
                captureEvent("j-\(kind.label)-d-cleared-\(role(for: zone))", after: wait + 0.05)
            case .nipped(let zone):
                // Nonviolent contact: a bonk, a stagger on the stand-in, the raft jostles. No power lost.
                let early = events.contains(.labelled(zone, .tooEarly))
                popRating(zone, text: early ? "TOO EARLY!" : kind.hitText, color: early ? Palette.yellow : Palette.coral,
                          at: slots[zone]?.headPoint ?? .zero)
                slots[zone]?.nippedAt = now
                if var slot = slots[zone] { slot.combo = 0; slots[zone] = slot }
                rt.raft.impulse(zone == .left ? -7 : 7)
                hideCue(zone)
                audio.play(.bonk, dB: -6)
                audio.play(kind == .log ? .knock : .slap, dB: -8)
                if let tail = hazard as? TailHazard { tail.hit = true }
                gameLog("\(kind.label): \(role(for: zone)) \(kind == .log ? "bumped" : "swept")\(early ? " — TOO EARLY" : "")")
                captureEvent("j-\(kind.label)-e-hit-\(role(for: zone))", after: 0.12)
            case .labelled(let zone, let result):
                switch result {
                case .tooLate:
                    popRating(zone, text: "TOO LATE!", color: Palette.yellow, at: slots[zone]?.headPoint ?? .zero)
                    gameLog("\(kind.label): \(role(for: zone)) jumped TOO LATE")
                case .noJump: gameLog("\(kind.label): \(role(for: zone)) didn't jump")
                case .tooEarly: gameLog("\(kind.label): \(role(for: zone)) label TOO EARLY")
                case .cleared: break
                }
            case .resolved(let outcome, let bonus):
                switch outcome {
                case .team(let zones):
                    showBanner("TEAM JUMP!", sub: kind == .log ? "Right over the log!" : "It swept under both of you!", color: Palette.mint, hold: 1.0)
                    audio.play(.team, dB: -2)
                    addTeamPower(bonus)
                    resolveTeamLock(team: true)
                    for zone in zones { burstSparks(at: slots[zone]?.footPoint ?? .zero, color: Palette.mint, count: 6) }
                    celebrateWorld()
                    gameLog("\(kind.label): TEAM (+\(bonus) bonus); power \(teamPower)/\(teamPowerMax)")
                    captureEvent("j-\(kind.label)-f-team", after: 0.3)
                case .partial(let done, let missing):
                    if done.isEmpty {
                        showBanner(kind == .log ? "BUMP!" : "SWOOSH!", sub: kind == .log ? "Jump as it rolls to your feet" : "Jump when the tail swings in", color: Palette.coral, hold: 1.0)
                    } else {
                        showBanner("NICE!", sub: "Jump together for the TEAM bonus", color: Palette.color(for: done.first!, swapped: swapped), hold: 1.0)
                        audio.play(.chime, dB: -6)
                    }
                    resolveTeamLock(team: false)
                    gameLog("\(kind.label): partial: cleared [\(done.map { role(for: $0) }.sorted().joined(separator: ","))] hit [\(missing.map { role(for: $0) }.sorted().joined(separator: ","))]")
                    captureEvent("j-\(kind.label)-f-partial", after: 0.3)
                case .cancelled:
                    hideTeamLock()
                }
            }
        }
    }

    /// A takeoff while a sweep's window is open for this player: show it on the lock straight away.
    func sweepAwaitsJump(from zone: Zone) -> Bool {
        let rt = jungleRuntime
        return [rt.log as SweepHazard?, rt.tail].contains { h in
            guard let h, h.cued, let j = h.judge else { return false }
            return j.isOpen && j.participants.contains(zone) && j.results[zone] == nil
        }
    }

    // MARK: - River Log Sweep

    func startLogSweep() {
        let rt = jungleRuntime
        let hazard = LogHazard(timing: rt.logTiming)
        rt.log = hazard
        for node in [hazard.crop, hazard.shadow, hazard.foam] as [SKNode] { addChild(node) }
        addSigns(hazard, texture: Art.logSign, count: 2)
        for _ in 0..<6 {
            let leaf = SKSpriteNode(texture: Art.floatingLeaf)
            leaf.alpha = 0
            addChild(leaf)
            hazard.leaves.append(leaf)
        }
        showBanner("DRIFTWOOD AHEAD!", sub: "Rapids! Get ready to JUMP over the log", color: Palette.coral, hold: rt.logTiming.warningDuration - 0.2)
        audio.play(.rumble, dB: -5)
        audio.play(.knock, dB: -14)
        rt.script?.sweepWarned(hazard, scene: self)
        gameLog("log: warning — rapids ahead, leaves swirling (nothing to jump yet)")
        captureEvent("j-log-a-warning", after: 1.0)
    }

    func stepLogSweep(_ hazard: LogHazard) {
        let rt = jungleRuntime
        let timing = rt.logTiming
        if !hazard.revealed, hazard.t >= timing.revealTime {
            hazard.revealed = true
            waterRing(x: 0, z: dz(LogPath.surfaceZ), strength: 0.7)
            audio.play(.splash, dB: -12)
            gameLog("log: revealed — it surfaces in the rapids and the current carries it at the raft")
            captureEvent("j-log-b-reveal", after: 1.2)
        }
        if !hazard.cued, hazard.t >= timing.cueTime {
            cueSweep(hazard, crossings: timing.crossings, cueTime: timing.cueTime, window: timing.window,
                     sub: "Both jump over the log", label: "log")
            rt.script?.sweepCued(hazard, crossings: timing.crossings, scene: self)
            captureEvent("j-log-c-jump-cue", after: 0.4)
        }
        runSweepJudge(hazard, kind: .log)
        let judgeDone = hazard.judge.map { !$0.isOpen && ($0.labelsFinal || hazard.t > $0.lastWindowClose + $0.window.lateLabelWindow + 0.1) } ?? false
        if hazard.t >= timing.endTime, judgeDone {
            for node in hazard.nodes { node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])) }
            for zone in Zone.allCases { hideCue(zone) }
            rt.log = nil
            gameLog("log: gone downstream (beat over)")
        }
    }

    func updateLogSweep(dt: Double) {
        let rt = jungleRuntime
        guard let hazard = rt.log else { return }
        let timing = rt.logTiming
        let pose = hazard.animator.pose(at: hazard.t)
        rt.bowLiftTarget = CGFloat(pose.bowLift)
        updateSigns(hazard, xs: [size.width * 0.075, size.width * 0.925], cueTime: timing.cueTime)

        // Beats in the log's performance: the water and the raft answer each one.
        if pose.state != hazard.lastState {
            switch pose.state {
            case .lifting:
                // The standing wave heaves it at the bow: two crowns, a ring, the raft creaks as the bow rises.
                for x in [-0.7, 0.7] { splashCrown(x: CGFloat(x), z: dz(LogPath.bowZ - 0.1), size: 1.1) }
                waterRing(x: 0, z: dz(LogPath.bowZ), strength: 1)
                audio.play(.splash, dB: -3)
                audio.play(.creak, dB: -6)
                gameLog("log: the standing wave lifts it onto the bow — the bow rises, the deck tilts toward you")
                captureEvent("j-log-c-lift", after: 0.25)
            case .rolling:
                // Lands on the logs: a heavy wooden thunk, the raft jolts, then it rumbles downhill.
                audio.play(.knock, dB: -1)
                audio.play(.roll, dB: -4)
                rt.rig.run(.sequence([.moveBy(x: 0, y: -7, duration: 0.05), .moveBy(x: 0, y: 7, duration: 0.25).easeOutBack()]))
                gameLog("log: lands on the deck and rolls at the players' feet")
            case .falling:
                // The near edge is below the frame: the splash is seen as water thrown up into the bottom of the view.
                exitSpray()
                waterRing(x: 0, z: dz(1.3), strength: 1)
                audio.play(.splash, dB: 0)
                audio.play(.knock, dB: -10)
                gameLog("log: off the near edge — splash behind the raft")
                captureEvent("j-log-g-exit", after: 0.12)
            case .gone:
                audio.play(.creak, dB: -10)
            default:
                break
            }
            hazard.lastState = pose.state
        }
        if pose.state == .rolling {
            let passed = LogPath.lashingZs.filter { pose.zc < $0 }.count
            if passed > hazard.lashingsPassed { hazard.lashingsPassed = passed; audio.play(.knock, dB: -12) }
        }

        // Leaves on the rapids: they swirl into the log's line during the warning, then race past the raft.
        for (i, leaf) in hazard.leaves.enumerated() {
            let fi = Double(i)
            let lx = (fi - 2.5) * 0.8
            let t = hazard.t
            let z = 11.5 + fi * 0.6 - t * 2.1
            let x = lx * (1 - 0.35 * min(1, t / 2)) + 0.2 * sin(t * 2.2 + fi)
            let visible = z > 2.9 && t > 0.15
            let p = proj.screen(x: CGFloat(x), h: -0.2, z: dz(max(z, 0.6)))
            leaf.position = p
            leaf.setScale(proj.ppu(dz(max(z, 0.6))) * 0.22 / 48)
            leaf.zRotation = reduceMotion ? 0 : CGFloat(t * (1.4 + 0.3 * fi))
            leaf.zPosition = proj.depthZ(dz(max(z, 0.6))) + 0.3
            leaf.alpha += ((visible ? 1 : 0) - leaf.alpha) * 0.15
        }

        // The river: rapids churn ahead, foam hugs the floating log, a standing wave holds it at the bow.
        jungle?.riverShader.uniformNamed("u_log")?.vectorFloat4Value =
            SIMD4(Float(dz(pose.zc)), Float(LogPath.halfLength), pose.state == .floating ? Float(1 - pose.submerge * 0.3) : 0, Float(pose.rapids))

        guard pose.state != .churning, pose.state != .gone, pose.zc > 0.55 else {
            hazard.crop.alpha = 0; hazard.shadow.alpha = 0; hazard.foam.alpha = 0
            return
        }
        let hl = CGFloat(LogPath.halfLength), r = CGFloat(LogPath.radius)
        let zl = dz(LogPath.axisZ(x: -LogPath.halfLength, centre: pose.zc)), zr = dz(LogPath.axisZ(x: LogPath.halfLength, centre: pose.zc))
        let zc = dz(pose.zc)
        let h = CGFloat(pose.h)
        let pl = proj.screen(x: -hl, h: h, z: zl), pr = proj.screen(x: hl, h: h, z: zr)
        let mid = CGPoint(x: (pl.x + pr.x) / 2, y: (pl.y + pr.y) / 2)
        let angle = atan2(pr.y - pl.y, pr.x - pl.x)
        let length = hypot(pr.x - pl.x, pr.y - pl.y)
        let ppu = proj.ppu(zc)
        let waterY = proj.screen(x: 0, h: CGFloat(LogPath.waterH), z: zc).y
        let thick = 2 * r * ppu / Art.logDiameter

        hazard.crop.alpha = min(1, hazard.crop.alpha + 0.08)
        hazard.crop.position = CGPoint(x: mid.x, y: waterY)
        // In the water the mask starts at the waterline; out of it, the mask covers everything.
        hazard.mask.position = CGPoint(x: 0, y: pose.submerge > 0.02 ? 0 : -4000)
        let local = CGPoint(x: 0, y: mid.y - waterY)
        let n = Art.logFrameCount
        let frame = ((Int(floor(pose.roll / (2 * .pi) * Double(n))) % n) + n) % n
        hazard.body.texture = Art.logFrames[frame]
        hazard.body.position = local
        hazard.body.zRotation = angle
        hazard.body.xScale = length / Art.logLength
        hazard.body.yScale = thick
        // Roots at the right end turn about the axis with the log (the fan flips as it rolls over).
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        hazard.roots.position = CGPoint(x: local.x + dir.x * length / 2 * 0.985, y: local.y + dir.y * length / 2 * 0.985)
        hazard.roots.zRotation = angle
        hazard.roots.xScale = thick * 0.95
        hazard.roots.yScale = thick * 0.95 * CGFloat(cos(pose.roll * 0.5))
        // The leafy branch: carried round the circumference (in front when facing us, behind when away).
        let theta = 1.2 - pose.roll
        let bx = 0.32 * length / 2
        let up = CGFloat(sin(theta))
        hazard.branch.position = CGPoint(x: local.x + dir.x * bx - dir.y * up * r * ppu, y: local.y + dir.y * bx + dir.x * up * r * ppu)
        hazard.branch.zRotation = angle + (reduceMotion ? 0 : CGFloat(pose.trail) * 0.15 + CGFloat(sin(now * 9)) * 0.05)
        hazard.branch.xScale = thick * 0.8
        hazard.branch.yScale = thick * 0.8 * up
        hazard.branch.zPosition = cos(theta) > 0 ? 0.02 : -0.02
        hazard.roots.zPosition = 0.01

        // Depth: in the water by distance; on the deck, behind the players until it reaches their feet, then in front.
        let onDeck = pose.state == .rolling || pose.state == .falling || (pose.state == .lifting && pose.submerge < 0.05)
        if pose.zc < 3.8 {
            // At the raft: behind the players until it reaches their feet, then in front (it passes under them).
            hazard.crop.zPosition = pose.zc > FootZone.playerZ ? Layer.pad - 0.3 : Layer.body + 1.5
        } else {
            hazard.crop.zPosition = proj.depthZ(zc) + 0.5
        }
        // Contact shadow on the deck (it reads as resting on the logs, and as low, at the feet).
        if onDeck, pose.state != .falling {
            let deckY = proj.screen(x: 0, h: CGFloat(LogPath.deckH(z: pose.zc, bowLift: pose.bowLift)), z: zc)
            hazard.shadow.position = CGPoint(x: mid.x, y: deckY.y)
            hazard.shadow.zRotation = angle
            hazard.shadow.size = CGSize(width: length * 0.95, height: 0.2 * ppu)
            hazard.shadow.zPosition = Layer.pad + 0.04
            hazard.shadow.alpha = 0.42
        } else {
            hazard.shadow.alpha = max(0, hazard.shadow.alpha - 0.08)
        }
        // Foam collar while it floats; a little spray off the bark while it rolls.
        if pose.state == .floating {
            hazard.foam.position = CGPoint(x: mid.x, y: waterY + 2)
            hazard.foam.zRotation = angle
            hazard.foam.size = CGSize(width: length * 1.06, height: 0.3 * ppu)
            hazard.foam.zPosition = hazard.crop.zPosition + 0.05
            hazard.foam.alpha = 0.75 * CGFloat(min(1, (hazard.t - timing.revealTime) / 0.6))
            if now - hazard.lastFx > 0.45 {
                hazard.lastFx = now
                ripple(at: CGPoint(x: mid.x + CGFloat.random(in: -0.4...0.4) * length, y: waterY), width: ppu * 0.8)
            }
        } else {
            hazard.foam.alpha = max(0, hazard.foam.alpha - 0.1)
        }

        // The path: two lanes of dashes down the deck from where it will land, through the feet, chasing toward you.
        var points: [(x: Double, z: Double)] = []
        for lane in Zone.allCases {
            for k in 0..<6 { points.append((FootZone.x(lane), LogPath.landZ - 0.1 - Double(k) * 0.24)) }
        }
        updateDashes(hazard, points: points, revealAt: timing.revealTime, hide: pose.state == .rolling || pose.state == .falling)
    }

    /// Water thrown up from below the frame as the log drops off the near edge: two crowns rising from the bottom edge
    /// and a fan of droplets that arc up and fall back.
    private func exitSpray() {
        let rt = jungleRuntime
        for (i, fx) in [0.32, 0.68].enumerated() {
            let crown = rt.splashCrowns[rt.nextCrown]
            rt.nextCrown = (rt.nextCrown + 1) % rt.splashCrowns.count
            crown.removeAllActions()
            crown.position = CGPoint(x: size.width * CGFloat(fx), y: -size.height * 0.06)
            crown.setScale(size.height * 0.42 / 260 * (i == 0 ? 1 : 0.9))
            crown.zPosition = Layer.body + 2
            crown.isHidden = false
            crown.alpha = 0.95
            crown.texture = Art.splashCrown[0]
            crown.run(.sequence([.wait(forDuration: Double(i) * 0.06), .animate(with: Art.splashCrown, timePerFrame: 0.07),
                                 .fadeOut(withDuration: 0.2), .hide()]))
        }
        guard !reduceMotion else { return }
        for k in 0..<14 {
            let d = rt.droplets[rt.nextDroplet]
            rt.nextDroplet = (rt.nextDroplet + 1) % rt.droplets.count
            d.removeAllActions()
            d.isHidden = false
            d.alpha = 0.95
            let x = size.width * (0.15 + 0.7 * CGFloat(k) / 13) + CGFloat.random(in: -20...20)
            d.position = CGPoint(x: x, y: -10)
            d.setScale(CGFloat.random(in: 0.9...1.6))
            d.zPosition = Layer.body + 2.1
            let dy = CGFloat.random(in: 220...420), dx = (x - size.width / 2) * 0.25
            d.run(.sequence([.group([.moveBy(x: dx, y: dy, duration: 0.42).easeOut(), .fadeAlpha(to: 0.85, duration: 0.42)]),
                             .group([.moveBy(x: dx * 0.4, y: -dy - 40, duration: 0.45).easeIn(), .fadeOut(withDuration: 0.45)]), .hide()]))
        }
    }

    func withdrawLogSweep(_ hazard: LogHazard) {
        hazard.judge?.cancel()
        hazard.plannedJumps = []
        for node in hazard.nodes { node.removeAllActions(); node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])) }
        jungle?.riverShader.uniformNamed("u_log")?.vectorFloat4Value = .zero
        jungleRuntime.bowLiftTarget = 0
    }

    // MARK: - Crocodile Tail Sweep

    func startTailSweep(side: Zone) {
        let rt = jungleRuntime
        let hazard = TailHazard(side: side, timing: rt.tailTiming)
        rt.tail = hazard
        hazard.croc.setSide(side)
        hazard.croc.hideBody()
        hazard.croc.add(to: self)
        for node in hazard.segments + [hazard.tip] + hazard.shadows { addChild(node) }
        for _ in 0..<5 {
            let b = SKSpriteNode(texture: Art.bubble)
            b.alpha = 0
            addChild(b)
            hazard.bubbles.append(b)
        }
        addSigns(hazard, texture: Art.tailSign, count: 1)
        let sideName = side == .left ? "LEFT" : "RIGHT"
        // A different warning from the ram: yellow "TAIL" with a jump badge, a sly hiss (not the ram's growl).
        showBanner("TAIL SWEEP — \(sideName)!", sub: "Watch the tail — get ready to JUMP", color: Palette.yellow, hold: rt.tailTiming.warningDuration - 0.2)
        audio.play(.gurgle, dB: -8)
        audio.play(.hiss, dB: -10)
        rt.script?.sweepWarned(hazard, scene: self)
        gameLog("tail: warning, \(sideName) — swirl at the bow corner (nothing to jump yet)")
        captureEvent("j-tail-a-warning", after: 0.9)
    }

    func stepTailSweep(_ hazard: TailHazard) {
        let rt = jungleRuntime
        let timing = rt.tailTiming
        if !hazard.revealed, hazard.t >= timing.revealTime {
            hazard.revealed = true
            gameLog("tail: the croc surfaces side-on beside the bow, eyes on the players")
            captureEvent("j-tail-b-reveal", after: 0.8)
        }
        if !hazard.cued, hazard.t >= timing.cueTime(side: hazard.side) {
            let crossings = timing.crossings(side: hazard.side)
            cueSweep(hazard, crossings: crossings, cueTime: timing.cueTime(side: hazard.side), window: timing.window,
                     sub: "Both jump over the tail", label: "tail")
            rt.script?.sweepCued(hazard, crossings: crossings, scene: self)
            captureEvent("j-tail-c-jump-cue", after: 0.5)
        }
        runSweepJudge(hazard, kind: .tail)
        let judgeDone = hazard.judge.map { !$0.isOpen && ($0.labelsFinal || hazard.t > $0.lastWindowClose + $0.window.lateLabelWindow + 0.1) } ?? false
        if hazard.t >= timing.endTime, judgeDone {
            for node in hazard.nodes { node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])) }
            hazard.croc.remove()
            for zone in Zone.allCases { hideCue(zone) }
            rt.tail = nil
            setRiverCroc(.zero)
            gameLog("tail: the croc swims off (beat over)")
        }
    }

    func updateTailSweep(dt: Double) {
        let rt = jungleRuntime
        guard let hazard = rt.tail else { return }
        let timing = rt.tailTiming
        let side = hazard.side
        let sgn = TailPath.sign(side)
        let pose = hazard.animator.pose(at: hazard.t, hit: hazard.hit)
        updateSigns(hazard, xs: [side == .left ? size.width * 0.075 : size.width * 0.925], cueTime: timing.cueTime(side: side))
        let pivot = (x: sgn * TailPath.pivotX, z: TailPath.pivotZ)
        let pivotZ = dz(pivot.z)

        if pose.state != hazard.lastState {
            switch pose.state {
            case .surfacing:
                waterRing(x: CGFloat(pivot.x + sgn * 0.5), z: pivotZ, strength: 0.7)
                audio.play(.gurgle, dB: -10)
            case .coiling:
                audio.play(.hiss, dB: -7)
                gameLog("tail: coils — the tail lifts out of the water and winds back (anticipation)")
                captureEvent("j-tail-c-coil", after: 0.9)
            case .sweeping:
                audio.play(.swish, dB: -1)
                gameLog("tail: SWEEP — low across the deck")
                captureEvent("j-tail-d-sweep", after: timing.sweepDuration * 0.55)
            case .reacting:
                gameLog(hazard.hit ? "tail: overshoots, pleased with itself" : "tail: overshoots, spins round — dizzy!")
                captureEvent("j-tail-g-react", after: 0.5)
            case .retreating:
                waterRing(x: CGFloat(pivot.x + sgn * 0.4), z: pivotZ, strength: 0.6)
                audio.play(.splash, dB: -11)
            default:
                break
            }
            hazard.lastState = pose.state
        }

        // Bubbles and a swirl at the bow corner during the warning (where it will come from).
        for (i, b) in hazard.bubbles.enumerated() {
            let rise = CGFloat((now * 1.5 + Double(i) * 0.31).truncatingRemainder(dividingBy: 1))
            let z = pivot.z + Double(i % 3) * 0.3 - 0.2
            let p = proj.screen(x: CGFloat(pivot.x + sgn * (0.3 + 0.25 * Double(i % 2))), h: -0.2 + rise * 0.25, z: dz(z))
            b.position = p
            b.setScale(proj.ppu(dz(z)) * 0.1 / 40)
            b.zPosition = proj.depthZ(dz(z)) + 0.2
            b.alpha = hazard.t < timing.revealTime + 0.3 ? (1 - rise) * 0.9 : max(0, b.alpha - 0.05)
        }

        // The croc, head-on in the water off the bow corner, its tail behind it.
        let head = TailPath.head(side)
        let headZ = dz(head.z)
        if pose.state == .hidden || pose.state == .gone {
            hazard.croc.hideBody()
        } else {
            let water = proj.screen(x: CGFloat(head.x), h: CGFloat(LogPath.waterH), z: headZ)
            hazard.croc.applySweepHead(pose, waterPoint: water, ppu: proj.ppu(headZ), z: proj.depthZ(headZ) + 0.6,
                                      towardPlayers: CGFloat(-sgn), now: now, reduceMotion: reduceMotion)
        }
        setRiverCroc(pose.state == .gone ? .zero : SIMD4(Float(pivot.x + sgn * 0.6), Float(pivotZ), 0, Float(0.5 + (pose.state == .sweeping ? 0.6 : 0))))

        // The tail chain: joints from the hips outward, each part of the tail following the hips with a lag.
        let n = TailPath.segments
        let segLen = TailPath.length / Double(n)
        let showTail = pose.state != .hidden && pose.state != .surfacing && pose.state != .gone
        var joints: [(x: Double, z: Double, h: Double)] = [(pivot.x, pivot.z, -0.12)]
        let lowOverWater = pose.state == .sweeping || pose.state == .reacting
        for i in 0..<n {
            let f = (Double(i) + 0.5) / Double(n)
            let a = TailPath.mirrored(hazard.animator.angle(at: hazard.t, fraction: f, pose: pose), side: side)
            let last = joints[joints.count - 1]
            let x = last.x + segLen * cos(a), z = last.z + segLen * sin(a)
            let fe = Double(i + 1) / Double(n)
            var h = mixD(-0.12, pose.lift, smoothstepD(0, 0.3, fe)) + (pose.curl > 0 ? 0.3 * pose.curl * sin(.pi * fe) : 0)
            if lowOverWater {
                // Over the deck it skims at foot height; over the water it rides the surface.
                let offDeck = max(smoothstepD(1.1, 1.4, abs(x)), smoothstepD(2.8, 3.05, z), 1 - smoothstepD(0.9, 1.15, z))
                h = mixD(h, LogPath.waterH + 0.08, offDeck)
            }
            joints.append((x, z, h))
        }
        for i in 0..<n {
            let a = joints[i], b = joints[i + 1]
            let midZ = (a.z + b.z) / 2
            let visible = showTail && midZ > 0.5
            if i == n - 1 { hazard.segments[i].alpha = 0 }   // the last span is drawn by the tip
            guard visible else {
                hazard.segments[i].alpha = 0
                hazard.shadows[i].alpha = 0
                if i == n - 1 { hazard.tip.alpha = 0 }
                continue
            }
            let pa = proj.screen(x: CGFloat(a.x), h: CGFloat(a.h), z: dz(a.z))
            let pb = proj.screen(x: CGFloat(b.x), h: CGFloat(b.h), z: dz(b.z))
            let ang = atan2(pb.y - pa.y, pb.x - pa.x)
            let ppu = proj.ppu(dz(midZ))
            let thickness = mixD(0.3, 0.09, pow(Double(i) / Double(n), 0.8)) * Double(ppu) / 40
            // Crest always on top: flip vertically when the segment points leftward on screen.
            let flip: CGFloat = cos(ang) < 0 ? -1 : 1
            let overDeck = abs((a.x + b.x) / 2) < 1.15 && midZ > 1.15 && midZ < 2.85
            let depth: CGFloat = midZ < FootZone.playerZ - 0.05 ? Layer.body + 1.6 : (overDeck ? Layer.pad - 0.3 : proj.depthZ(dz(midZ)) + 0.7)
            if i < n - 1 {
                let s = hazard.segments[i]
                s.position = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
                s.zRotation = ang
                s.xScale = hypot(pb.x - pa.x, pb.y - pa.y) / 120 * 1.45
                s.yScale = CGFloat(thickness) * flip
                s.zPosition = depth + CGFloat(i) * 0.001
                s.alpha = 1
            } else {
                hazard.tip.position = pa
                hazard.tip.zRotation = ang
                hazard.tip.xScale = hypot(pb.x - pa.x, pb.y - pa.y) / 132 * 1.1
                hazard.tip.yScale = CGFloat(thickness) * flip * 1.1
                hazard.tip.zPosition = depth + 0.02
                hazard.tip.alpha = 1
            }
            // Contact shadow on the deck under each part of the tail that's over it (fainter the higher it is).
            let sh = hazard.shadows[i]
            if overDeck {
                sh.position = proj.screen(x: CGFloat((a.x + b.x) / 2), h: 0.01, z: dz(midZ))
                sh.size = CGSize(width: 0.42 * ppu, height: 0.12 * ppu)
                sh.zRotation = ang
                sh.zPosition = Layer.pad + 0.04
                sh.alpha = 0.34 * CGFloat(max(0.2, 1 - (a.h + b.h) / 2 / 0.7))
            } else {
                sh.alpha = 0
            }
        }

        // Water: drips off the raised coil; spray where the tail whips over the deck edge; the slap past the far edge.
        let tipJ = joints[n]
        let tipP = proj.screen(x: CGFloat(tipJ.x), h: CGFloat(tipJ.h), z: dz(max(tipJ.z, 0.6)))
        if pose.state == .coiling, !reduceMotion, now - hazard.lastFx > 0.09 {
            hazard.lastFx = now
            sweepDrip(at: tipP)
        }
        if pose.state == .sweeping, !hazard.swept, hazard.t >= timing.sweepStart + 0.1 {
            hazard.swept = true
            splashAt(edge: side, count: 6, strength: 0.7)
        }
        if !hazard.slapped, hazard.t >= timing.sweepEnd + 0.05 {
            hazard.slapped = true
            splashCrown(x: CGFloat(tipJ.x), z: dz(max(tipJ.z, 1.0)), size: 1.2)
            waterRing(x: CGFloat(tipJ.x), z: dz(max(tipJ.z, 1.0)), strength: 1)
            audio.play(.slap, dB: -2)
            audio.play(.splash, dB: -6)
            rt.raft.impulse(sgn * -4)
        }

        // The sweep path: an arc of dashes on the deck through both lanes, chasing in the direction of the sweep.
        let near = TailPath.lane(side, side: side), far = TailPath.lane(side == .left ? .right : .left, side: side)
        let radius = (near.radius + far.radius) / 2
        var points: [(x: Double, z: Double)] = []
        let a0 = near.angle + 0.35, a1 = far.angle - 0.3
        for k in 0..<12 {
            let a = TailPath.mirrored(mixD(a0, a1, Double(k) / 11), side: side)
            points.append((pivot.x + radius * cos(a), pivot.z + radius * sin(a)))
        }
        updateDashes(hazard, points: points, revealAt: timing.revealTime, hide: hazard.t > timing.sweepStart)
    }

    private func sweepDrip(at point: CGPoint) {
        let rt = jungleRuntime
        let d = rt.droplets[rt.nextDroplet]
        rt.nextDroplet = (rt.nextDroplet + 1) % rt.droplets.count
        d.removeAllActions()
        d.isHidden = false
        d.alpha = 0.8
        d.position = CGPoint(x: point.x + CGFloat.random(in: -14...14), y: point.y)
        d.setScale(CGFloat.random(in: 0.35...0.6))
        d.run(.sequence([.group([.moveBy(x: 0, y: -CGFloat.random(in: 50...90), duration: 0.4).easeIn(), .fadeOut(withDuration: 0.4)]), .hide()]))
    }

    func withdrawTailSweep(_ hazard: TailHazard) {
        hazard.judge?.cancel()
        hazard.plannedJumps = []
        for node in hazard.nodes + [hazard.croc.crop, hazard.croc.underCrop, hazard.croc.shadow, hazard.croc.collar] as [SKNode] {
            node.removeAllActions()
            node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
        setRiverCroc(.zero)
    }
}
