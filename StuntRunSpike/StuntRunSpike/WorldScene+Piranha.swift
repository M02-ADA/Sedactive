import SpriteKit

/// One piranha: body with a procedurally beaten tail and snapping jaw (layered like the croc rig), its dorsal fin
/// while it swims in, and a soft shadow that slides across the deck under it during the leap.
@MainActor
final class PiranhaRig {
    let body = SKSpriteNode(texture: Art.piranhaBody)
    let tail = SKSpriteNode(texture: Art.piranhaTail)
    let jaw = SKSpriteNode(texture: Art.piranhaJaw)
    let fin = SKSpriteNode(texture: Art.piranhaFinTex)
    let shadow = SKSpriteNode(texture: Art.glow)
    /// 1 for the fish that is judged (passes in front of the players' shins), smaller for the school behind it.
    let scale: CGFloat
    var lastU = -1.0
    var launched = false
    var splashed = false

    init(scale: CGFloat) {
        self.scale = scale
        let size = Art.piranhaBody.size()
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - size.width / 2, y: size.height / 2 - p.y) }
        func anchor(_ p: CGPoint, in tex: SKTexture) -> CGPoint { CGPoint(x: p.x / tex.size().width, y: 1 - p.y / tex.size().height) }
        tail.anchorPoint = anchor(Art.piranhaTailPivot, in: Art.piranhaTail)
        tail.position = local(Art.piranhaTailJoint)
        tail.zPosition = -0.01
        body.addChild(tail)
        jaw.anchorPoint = anchor(Art.piranhaJawPivot, in: Art.piranhaJaw)
        jaw.position = local(Art.piranhaJawHinge)
        jaw.zPosition = 0.01
        body.addChild(jaw)
        fin.anchorPoint = CGPoint(x: 0.5, y: 0.12)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        for node in nodes { node.alpha = 0 }
    }

    var nodes: [SKSpriteNode] { [body, fin, shadow] }
}

/// Piranha hazard (JUMP). Rules in PiranhaLeap, performance in PiranhaAnimator; this holds the clock and the nodes.
@MainActor
final class PiranhaHazard {
    var t: Double = 0
    let side: Zone
    let count: Int
    let fish: [(lead: PiranhaRig, school: PiranhaRig, animator: PiranhaAnimator)]
    var leaps: [PiranhaLeap] = []
    var revealed = false
    var cued = false
    var locksShown = 0
    var ticks: [Int]
    /// Simulated jumps planned on this encounter's clock (autoplay bots and the script), so a speed change never
    /// shifts them against the leaps.
    var plannedJumps: [(zone: Zone, at: Double)] = []
    let sign = SKSpriteNode(texture: Art.piranhaSign)
    let glow = SKSpriteNode(texture: Art.glow)
    var dashes: [SKSpriteNode] = []
    var bubbles: [SKSpriteNode] = []
    var lastRipple: TimeInterval = 0
    var lastDrop: TimeInterval = 0

    init(side: Zone, count: Int, timing: PiranhaTiming) {
        self.side = side
        self.count = count
        fish = (0..<count).map { (PiranhaRig(scale: 1), PiranhaRig(scale: 0.8), PiranhaAnimator(timing: timing, side: side, leap: $0)) }
        ticks = Array(repeating: 0, count: count)
    }

    var allNodes: [SKNode] { fish.flatMap { $0.lead.nodes + $0.school.nodes } + [sign, glow] + dashes + bubbles }
}

extension WorldScene {
    // MARK: - Piranhas (JUMP): WARNING → REVEAL → JUMP! → LEAP → RESOLVE

    func startPiranhas(from side: Zone, count: Int) {
        let rt = jungleRuntime
        let hazard = PiranhaHazard(side: side, count: count, timing: rt.piranhaTiming)
        rt.piranhas = hazard
        for node in hazard.fish.flatMap({ $0.lead.nodes + $0.school.nodes }) { addChild(node) }
        hazard.sign.zPosition = Layer.flash - 12
        hazard.sign.setScale(0)
        addChild(hazard.sign)
        hazard.sign.run(.sequence([.wait(forDuration: 0.1), .group([.fadeIn(withDuration: 0.1),
                        .scale(to: Self.signScale, duration: 0.35).easeOutBack(overshoot: 2.2)])]), withKey: "in")
        hazard.glow.color = Palette.yellow
        hazard.glow.colorBlendFactor = 1
        hazard.glow.blendMode = .add
        hazard.glow.alpha = 0
        hazard.glow.zPosition = 30
        addChild(hazard.glow)
        for _ in 0..<12 {
            let dash = SKSpriteNode(texture: Art.piranhaDash)
            dash.color = Palette.yellow
            dash.colorBlendFactor = 1
            dash.blendMode = .add
            dash.alpha = 0
            dash.zPosition = Layer.pad + 0.05   // on the deck, behind the bodies: shows the path without covering legs
            addChild(dash)
            hazard.dashes.append(dash)
        }
        for _ in 0..<6 {
            let b = SKSpriteNode(texture: Art.bubble)
            b.alpha = 0
            addChild(b)
            hazard.bubbles.append(b)
        }
        let sideName = side == .left ? "LEFT" : "RIGHT"
        showBanner(count > 1 ? "PIRANHAS ×\(count) — \(sideName)!" : "PIRANHAS — \(sideName)!",
                   sub: "Get ready to JUMP over them", color: Palette.coral, hold: rt.piranhaTiming.warningDuration - 0.2)
        audio.play(.boil, dB: -5)
        rt.script?.piranhasWarned(hazard, scene: self)
        gameLog("piranhas: warning, \(sideName) side ×\(count) (fins circling; nothing leaps yet)")
        captureEvent("j-piranha-a-warning", after: 0.7)
    }

    /// Gameplay clock (frozen while halted): reveal, cue, planned jumps, per-leap judging, end of the beat.
    func stepPiranhas(_ hazard: PiranhaHazard) {
        let rt = jungleRuntime
        let timing = rt.piranhaTiming
        if !hazard.revealed, hazard.t >= timing.revealTime {
            hazard.revealed = true
            audio.play(.boil, dB: -9)
            audio.play(.whoosh, dB: -12)
            gameLog("piranhas: revealed — fins race in along the raft, leap path glows across the deck")
            captureEvent("j-piranha-b-reveal", after: 0.9)
        }
        if !hazard.cued, hazard.t >= timing.cueTime(from: hazard.side) {
            hazard.cued = true
            let participants = Set(activeZones())
            hazard.leaps = (0..<hazard.count).map { i in
                rt.hazardCounter += 1
                return PiranhaLeap(id: rt.hazardCounter, index: i, side: hazard.side, participants: participants, timing: timing)
            }
            hazard.locksShown = 1
            showBanner("JUMP!", sub: hazard.count > 1 ? "\(hazard.count) leaps — jump every one" : participants.count >= 2 ? "Both jump over the piranhas" : "Jump over the piranhas",
                       color: Palette.yellow, hold: 1.1)
            showTeamLock(participants: participants)
            for zone in participants { showCue(zone, up: true) }
            audio.play(.whoosh, dB: -9)
            planBotJumps(hazard)
            rt.script?.piranhasCued(hazard, scene: self)
            gameLog("piranhas: JUMP cue, leap 1/\(hazard.count) (#\(hazard.leaps.first?.team.id ?? 0)); crossings at "
                    + Zone.allCases.map { String(format: "%@ %.2f s", role(for: $0), timing.crossingTime(leap: 0, zone: $0, from: hazard.side) - hazard.t) }.joined(separator: ", "))
            captureEvent("j-piranha-c-jump-cue", after: 0.5)
        }
        // A burst: the next leap's lock and cues come back once the previous one is decided.
        if hazard.cued, hazard.locksShown < hazard.count, hazard.t >= timing.launchTime(hazard.locksShown) - 0.9 {
            let leap = hazard.leaps[hazard.locksShown]
            hazard.locksShown += 1
            showTeamLock(participants: leap.participants)
            for zone in leap.participants { showCue(zone, up: true) }
            // Just under the team lock, clear of the centre banner (which may still show the last leap's result).
            let lock = hudNodes.lockRoot.position
            floatText("LEAP \(hazard.locksShown)/\(hazard.count)", color: Palette.yellow, at: CGPoint(x: lock.x + 170, y: lock.y - 20))
            gameLog("piranhas: leap \(hazard.locksShown)/\(hazard.count) coming (#\(leap.team.id))")
        }
        // Rhythm: three rising ticks before each leap's first crossing ("3-2-1-hop").
        for i in 0..<hazard.count where hazard.cued {
            let tta = timing.crossingTime(leap: i, zone: hazard.side, from: hazard.side) - hazard.t
            let marks: [Double] = [1.05, 0.7, 0.35]
            if hazard.ticks[i] < marks.count, tta <= marks[hazard.ticks[i]] {
                hazard.ticks[i] += 1
                audio.play(.tick, dB: -10 + Float(hazard.ticks[i]) * 2)
            }
        }
        let due = hazard.plannedJumps.filter { hazard.t >= $0.at }
        hazard.plannedJumps.removeAll { hazard.t >= $0.at }
        for plan in due { simulateJump(plan.zone, manual: false) }

        let airborne = Dictionary(uniqueKeysWithValues: Zone.allCases.map { ($0, slots[$0]?.jump.isAirborne ?? false) })
        for i in hazard.leaps.indices {
            // A later leap only starts watching once the previous one's windows have closed, so the landing from
            // the last jump is never mistaken for an early one.
            let from = i == 0 ? hazard.leaps[0].cueTime : hazard.leaps[i - 1].lastWindowClose
            guard hazard.t >= from else { continue }
            let events = hazard.leaps[i].update(at: hazard.t, airborne: airborne)
            if !events.isEmpty { handleLeapEvents(hazard, leap: i, events: events) }
        }
        let over = hazard.t >= timing.endTime(count: hazard.count) && hazard.leaps.allSatisfy {
            !$0.isOpen && ($0.labelsFinal || hazard.t > $0.lastWindowClose + timing.lateLabelWindow + 0.1)
        }
        if over {
            for node in hazard.allNodes { node.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()])) }
            for zone in Zone.allCases { hideCue(zone) }
            rt.piranhas = nil
            gameLog("piranhas: gone (beat over)")
        }
    }

    private func handleLeapEvents(_ hazard: PiranhaHazard, leap i: Int, events: [PiranhaLeap.Event]) {
        let rt = jungleRuntime
        let leap = hazard.leaps[i]
        let tag = hazard.count > 1 ? " (leap \(i + 1)/\(hazard.count))" : ""
        for event in events {
            switch event {
            case .cleared(let zone, let power):
                lockContributed(zone)
                addTeamPower(power)
                hideCue(zone)
                // Credit is banked the moment the feet leave the deck in the window; the praise lands as the fish
                // passes under them.
                let wait = max(0, leap.crossing(zone) - hazard.t)
                run(.wait(forDuration: wait)) { [weak self] in
                    guard let self else { return }
                    self.popRating(zone, text: "CLEARED!", color: Palette.mint, at: self.slots[zone]?.headPoint ?? .zero)
                    self.audio.play(.pop, dB: -8)
                }
                gameLog("piranhas: \(role(for: zone)) cleared\(tag) (+\(power) power)")
                captureEvent("j-piranha-d-cleared-\(role(for: zone))", after: wait + 0.05)
            case .nipped(let zone):
                let early = events.contains(.labelled(zone, .tooEarly))
                popRating(zone, text: early ? "TOO EARLY!" : "NIPPED!", color: early ? Palette.yellow : Palette.coral,
                          at: slots[zone]?.headPoint ?? .zero)
                slots[zone]?.nippedAt = now
                if var slot = slots[zone] { slot.combo = 0; slots[zone] = slot }
                splashAt(edge: zone, count: 4, strength: 0.4)
                rt.raft.impulse(zone == .left ? -6 : 6)   // playful: the raft jostles, no Team Power lost
                hideCue(zone)
                audio.play(.nip, dB: -5)
                gameLog("piranhas: \(role(for: zone)) nipped\(tag)\(early ? " — TOO EARLY" : "")")
                captureEvent("j-piranha-e-nipped-\(role(for: zone))", after: 0.12)
            case .labelled(let zone, let result):
                switch result {
                case .tooLate:
                    popRating(zone, text: "TOO LATE!", color: Palette.yellow, at: slots[zone]?.headPoint ?? .zero)
                    gameLog("piranhas: \(role(for: zone)) jumped TOO LATE\(tag)")
                case .noJump:
                    gameLog("piranhas: \(role(for: zone)) didn't jump\(tag)")
                case .tooEarly:
                    gameLog("piranhas: \(role(for: zone)) label TOO EARLY\(tag)")
                case .cleared:
                    break
                }
            case .resolved(let outcome, let bonus):
                switch outcome {
                case .team(let zones):
                    showBanner("TEAM JUMP!", sub: zones.count >= 2 ? "They sailed right under you!" : "Right under your feet!", color: Palette.mint, hold: 1.0)
                    audio.play(.team, dB: -2)
                    addTeamPower(bonus)
                    resolveTeamLock(team: true)
                    for zone in zones { burstSparks(at: slots[zone]?.footPoint ?? .zero, color: Palette.mint, count: 6) }
                    celebrateWorld()
                    gameLog("piranhas: TEAM\(tag) (+\(bonus) bonus); power \(teamPower)/\(teamPowerMax)")
                    captureEvent("j-piranha-f-team", after: 0.25)
                case .partial(let done, let missing):
                    if done.isEmpty {
                        showBanner("CHOMP!", sub: "Jump when they leap — watch the fins!", color: Palette.coral, hold: 1.0)
                    } else {
                        showBanner("NICE!", sub: "Jump together for the TEAM bonus", color: Palette.color(for: done.first!, swapped: swapped), hold: 1.0)
                        audio.play(.chime, dB: -6)
                    }
                    resolveTeamLock(team: false)
                    gameLog("piranhas: partial\(tag): cleared [\(done.map { role(for: $0) }.sorted().joined(separator: ","))] nipped [\(missing.map { role(for: $0) }.sorted().joined(separator: ","))]")
                    captureEvent("j-piranha-f-partial", after: 0.25)
                case .cancelled:
                    hideTeamLock()
                }
                rt.script?.leapResolved(hazard, leap: i, scene: self)
            }
        }
    }

    private func planBotJumps(_ hazard: PiranhaHazard) {
        guard jungleRuntime.script == nil, model?.autoplay == true else { return }
        let crouch = SimulatedJump(start: 0).crouch
        for leap in hazard.leaps {
            for zone in leap.participants {
                guard let slot = slots[zone], slot.driver == .simulated, now - slot.lastManualSim > 20 else { continue }
                let roll = Double.random(in: 0...1)
                let offset = roll < 0.85 ? Double.random(in: -0.55 ... -0.15) : (roll < 0.93 ? -1.1 : 0.35)
                hazard.plannedJumps.append((zone, leap.crossing(zone) + offset - crouch))
            }
        }
    }

    func withdrawPiranhas(_ hazard: PiranhaHazard) {
        for i in hazard.leaps.indices { hazard.leaps[i].cancel() }
        hazard.plannedJumps = []
        for node in hazard.allNodes { node.removeAllActions(); node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])) }
    }

    // MARK: Visuals (every frame)

    func updatePiranhas(dt: Double) {
        guard let hazard = jungleRuntime.piranhas else { return }
        let rt = jungleRuntime
        let timing = rt.piranhaTiming
        let sideX: CGFloat = hazard.side == .left ? -1 : 1
        let leadZ = proj.zp + CGFloat(PiranhaPath.depthOffset)
        let schoolZ = proj.zp + 0.55

        for (i, f) in hazard.fish.enumerated() {
            apply(f.animator.pose(at: hazard.t), to: f.lead, z: leadZ, finOffset: (0, 0), hazard: hazard, judged: true, index: i)
            apply(f.animator.pose(at: hazard.t - 0.08), to: f.school, z: schoolZ, finOffset: (Double(sideX) * 0.22, 0.6), hazard: hazard, judged: false, index: i)
        }

        // Warning: boiling water where the school gathers, and the sign above it.
        let gather = (x: sideX * CGFloat(PiranhaAnimator.gatherX), z: CGFloat(PiranhaAnimator.gatherZ))
        for (i, b) in hazard.bubbles.enumerated() {
            let rise = CGFloat((now * 1.8 + Double(i) * 0.29).truncatingRemainder(dividingBy: 1))
            let z = gather.z + CGFloat(i % 3) * 0.5 - 0.5
            b.position = proj.screen(x: gather.x + CGFloat(i % 2 == 0 ? -0.3 : 0.3) + CGFloat(i) * 0.05, h: -0.22 + rise * 0.25, z: z)
            b.setScale(proj.ppu(z) * 0.09 / 40)
            b.zPosition = proj.depthZ(z)
            let boiling = hazard.t < timing.revealTime + 0.4
            b.alpha = boiling ? (1 - rise) * 0.9 : max(0, b.alpha - 0.05)
        }
        let cue = timing.cueTime(from: hazard.side)
        let pulse = reduceMotion ? 1 : 1 + 0.08 * sin(CGFloat(now) * 9)
        // Screen-anchored at the attack side's edge, beside (never over) the players, above the water.
        let bob = reduceMotion ? 0 : sin(CGFloat(now) * 3) * 6
        hazard.sign.position = CGPoint(x: sideX < 0 ? size.width * 0.075 : size.width * 0.925, y: size.height * 0.5 + bob)
        if !hazard.sign.hasActions() { hazard.sign.setScale(Self.signScale * pulse) }
        if hazard.t > cue + 0.5, hazard.sign.action(forKey: "out") == nil, hazard.sign.alpha > 0 {
            hazard.sign.run(.group([.fadeOut(withDuration: 0.25), .scale(by: 1.3, duration: 0.25)]), withKey: "out")
        }

        // Lane highlight on the attack side at foot height: where they'll come from, brightest at the launch.
        let nextLeap = (0..<hazard.count).first { hazard.t < timing.launchTime($0) + timing.flightDuration } ?? hazard.count
        let ppu = proj.ppu(proj.zp)
        hazard.glow.position = proj.screen(x: sideX * 1.3, h: 0.25, z: proj.zp)
        hazard.glow.size = CGSize(width: 1.1 * ppu, height: 0.8 * ppu)
        var glowTarget: CGFloat = 0
        if hazard.revealed, nextLeap < hazard.count {
            let toLaunch = CGFloat(timing.launchTime(nextLeap) - hazard.t)
            glowTarget = toLaunch > 0 ? 0.25 + 0.4 * (1 - min(1, toLaunch / 1.6)) + (reduceMotion ? 0 : 0.08 * sin(CGFloat(now) * 12)) : 0.15
        }
        hazard.glow.alpha += (glowTarget - hazard.glow.alpha) * 0.2

        // The leap path: a dashed arc across the deck at shin height for the next leap. It glows in from the reveal;
        // after JUMP! a chase runs along it in the direction of travel; once the fish is out, the dashes it has
        // passed dim.
        let showPath = hazard.revealed && nextLeap < hazard.count
        let launch = nextLeap < hazard.count ? timing.launchTime(nextLeap) : 0
        let flyingU = hazard.t >= launch ? (hazard.t - launch) / timing.flightDuration : -1
        for (k, dash) in hazard.dashes.enumerated() {
            let u = 0.06 + 0.88 * Double(k) / Double(hazard.dashes.count - 1)
            let p = proj.screen(x: CGFloat(PiranhaPath.x(u, from: hazard.side)), h: CGFloat(PiranhaPath.h(u)), z: leadZ)
            let q = proj.screen(x: CGFloat(PiranhaPath.x(u + 0.01, from: hazard.side)), h: CGFloat(PiranhaPath.h(u + 0.01)), z: leadZ)
            dash.position = p
            dash.zRotation = atan2(q.y - p.y, q.x - p.x)
            dash.setScale(proj.ppu(leadZ) * 0.11 / 44)
            var target: CGFloat = 0
            if showPath {
                let appear = CGFloat(min(1, (hazard.t - timing.revealTime) / 0.6))
                target = 0.32 * appear
                if hazard.cued, !reduceMotion {
                    let phase = CGFloat(u) - CGFloat(now) * 1.4
                    target += 0.35 * max(0, sin(2 * .pi * phase))
                } else if hazard.cued {
                    target = 0.55
                }
                if flyingU >= 0 { target *= u > flyingU ? 1 : 0.15 }
            }
            dash.alpha += (target - dash.alpha) * 0.25
            dash.color = hazard.cued ? Palette.yellow : Palette.coral.mixed(with: Palette.yellow, amount: 0.4)
        }
    }

    /// The warning badge is ~120 pt across: big enough to read from 3 m on a 13" screen.
    static let signScale: CGFloat = 120 / 160

    private func apply(_ pose: PiranhaPose, to rig: PiranhaRig, z leapZ: CGFloat, finOffset: (Double, Double),
                       hazard: PiranhaHazard, judged: Bool, index: Int) {
        let rt = jungleRuntime
        let timing = rt.piranhaTiming
        switch pose.state {
        case .hidden:
            for node in rig.nodes { node.alpha = 0 }
        case .circling, .surging:
            rig.body.alpha = 0
            rig.shadow.alpha = 0
            let z = CGFloat(pose.finZ + finOffset.1)
            let x = CGFloat(pose.finX + finOffset.0)
            let p = proj.screen(x: x, h: -0.22, z: z)
            rig.fin.position = p
            let s = proj.ppu(z) * 0.3 / 56 * rig.scale   // exaggerated (fins are the whole warning)
            rig.fin.xScale = s * (hazard.side == .left ? 1 : -1)
            rig.fin.yScale = s * CGFloat(max(0.05, pose.finRise))
            rig.fin.zRotation = reduceMotion ? 0 : CGFloat(pose.tail) * 0.06
            rig.fin.zPosition = proj.depthZ(z) + 0.5
            rig.fin.alpha = CGFloat(min(1, pose.finRise * 1.5))
            if judged, pose.finRise > 0.3, now - hazard.lastRipple > (pose.state == .surging ? 0.12 : 0.22) {
                hazard.lastRipple = now
                ripple(at: p, width: proj.ppu(z) * (pose.state == .surging ? 0.9 : 0.6))
            }
        case .leaping:
            rig.fin.alpha = 0
            let u = pose.u
            let x = CGFloat(PiranhaPath.x(u, from: hazard.side)), h = CGFloat(PiranhaPath.h(u))
            let p = proj.screen(x: x, h: h, z: leapZ)
            let q = proj.screen(x: CGFloat(PiranhaPath.x(u + 0.01, from: hazard.side)), h: CGFloat(PiranhaPath.h(u + 0.01)), z: leapZ)
            let facing: CGFloat = hazard.side == .left ? 1 : -1
            let s = proj.ppu(leapZ) * 0.44 / Art.piranhaBody.size().width * rig.scale
            rig.body.position = p
            rig.body.xScale = s * CGFloat(pose.stretch) * facing
            rig.body.yScale = s / CGFloat(pose.stretch)
            let angle = atan2(q.y - p.y, q.x - p.x)
            rig.body.zRotation = facing > 0 ? angle : angle - .pi
            rig.body.zPosition = proj.depthZ(leapZ) + 1
            rig.body.alpha = CGFloat(min(1, u / 0.04))
            rig.tail.zRotation = reduceMotion ? 0 : CGFloat(pose.tail) * 0.4
            rig.jaw.zRotation = -CGFloat(pose.jaw) * 0.55
            // Deck shadow: only over the logs; smaller and fainter the higher the fish.
            if abs(x) < JungleRuntime.raftHalfWidth {
                rig.shadow.position = proj.screen(x: x, h: 0, z: leapZ)
                let w = proj.ppu(leapZ) * 0.38 * rig.scale * (1 - 0.4 * min(1, max(0, h) / 0.5))
                rig.shadow.size = CGSize(width: w, height: w * 0.25)
                rig.shadow.zPosition = Layer.pad + 0.04
                rig.shadow.alpha = 0.32
            } else {
                rig.shadow.alpha = 0
            }
            if !rig.launched {
                rig.launched = true
                splashCrown(x: CGFloat(PiranhaPath.x(0, from: hazard.side)), z: leapZ, size: judged ? 0.6 : 0.45)
                if judged {
                    waterRing(x: CGFloat(PiranhaPath.x(0, from: hazard.side)), z: leapZ + 0.3, strength: 0.8)
                    audio.play(.leap, dB: -3)
                    gameLog("piranhas: leap \(index + 1)/\(hazard.count) — out of the water")
                    captureEvent("j-piranha-d-leap\(index + 1)", after: timing.flightDuration * 0.3)
                }
            }
            if judged {
                for lane in Zone.allCases {
                    let lu = PiranhaPath.progress(atLane: lane, from: hazard.side)
                    if rig.lastU < lu, u >= lu { audio.play(.snap, dB: -8) }
                }
                if now - hazard.lastDrop > 0.05, !reduceMotion { hazard.lastDrop = now; dripTrail(at: p) }
            }
            rig.lastU = u
        case .splashed:
            rig.body.alpha = 0
            rig.shadow.alpha = 0
            rig.fin.alpha = 0
            if !rig.splashed {
                rig.splashed = true
                splashCrown(x: CGFloat(PiranhaPath.x(1, from: hazard.side)), z: leapZ, size: judged ? 0.6 : 0.45)
                if judged {
                    waterRing(x: CGFloat(PiranhaPath.x(1, from: hazard.side)), z: leapZ + 0.3, strength: 0.7)
                    audio.play(.splash, dB: -9)
                }
            }
        }
    }

    /// Water flicked off the fish as it flies: a couple of droplets that fall away behind it.
    private func dripTrail(at point: CGPoint) {
        let rt = jungleRuntime
        let d = rt.droplets[rt.nextDroplet]
        rt.nextDroplet = (rt.nextDroplet + 1) % rt.droplets.count
        d.removeAllActions()
        d.isHidden = false
        d.alpha = 0.8
        d.position = CGPoint(x: point.x + CGFloat.random(in: -10...10), y: point.y + CGFloat.random(in: -8...8))
        d.setScale(CGFloat.random(in: 0.35...0.6))
        d.run(.sequence([.group([.moveBy(x: 0, y: -CGFloat.random(in: 40...80), duration: 0.35).easeIn(), .fadeOut(withDuration: 0.35)]), .hide()]))
    }

    // MARK: - Jump input → feedback (credit itself is judged per leap from the airborne state)

    func handleJump(_ events: [JumpEvent], zone: Zone, captureTime: Double?) {
        guard gameMode == .jungleDrift || gameMode == .laserBreakout else { return }
        for event in events {
            switch event {
            case .takeoff:
                if let captureTime { meter.recordFeedbackLatency(ms: (now - captureTime) * 1000) }
                // Front-loaded: the pad flares and a hop sounds on the very frame the feet are detected leaving.
                padPulse(zone)
                audio.play(.hop, dB: -12)
                if gameMode == .jungleDrift, let p = jungleRuntime.piranhas, p.cued,
                   p.leaps.contains(where: { $0.isOpen && $0.participants.contains(zone) && $0.results[zone] == nil }) {
                    lockProvisional(zone)
                } else if gameMode == .jungleDrift, sweepAwaitsJump(from: zone) {
                    lockProvisional(zone)
                } else if gameMode == .laserBreakout, laserAwaitsJump(from: zone) {
                    lockProvisional(zone)
                }
                gameLog("\(role(for: zone)) jump: takeoff")
            case .landed(let airtime):
                guard airtime >= 0.08 else { continue }
                slots[zone]?.landedAt = now
                audio.play(.land, dB: -11)
                gameLog(String(format: "%@ jump: landed (air %.2f s)", role(for: zone), airtime))
            case .settled(let airtime):
                // The rep: only a complete cycle (takeoff → landing → back to standing) counts, never the animation.
                guard airtime >= 0.08, var slot = slots[zone] else { continue }
                slot.jumps += 1
                slots[zone] = slot
                gameLog("\(role(for: zone)) jump: cycle complete (jumps \(slot.jumps))")
            }
        }
    }
}
