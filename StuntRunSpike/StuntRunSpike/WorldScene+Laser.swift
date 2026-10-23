import QuartzCore
import SpriteKit

/// One security gate: a frame fixed in the corridor with an emitter rig on each wall and one beam per lane (one beam
/// wall-to-wall for a shared height, two half-beams for a split grid). Its encounter clock `t` starts at the warning;
/// every visual state (deploy, charge, fire, sweep, lock, shutdown) is a function of `t`, the same clock the judge uses.
@MainActor
final class LaserGate {
    var t: Double = 0
    let step: LaserStep
    var pattern: LaserPattern { step.pattern }
    /// Position in its sequence (0-based) and the sequence length (1 for a single laser).
    let seqIndex: Int
    let seqCount: Int
    var encounter: LaserEncounter?
    let frame = SKSpriteNode(texture: Art.gateFrame)
    var beams: [Zone: SKSpriteNode] = [:]
    /// Receiver/terminus flare where each beam ends.
    var caps: [Zone: SKSpriteNode] = [:]
    /// The light each beam throws on the floor under it.
    var floorGlow: [Zone: SKSpriteNode] = [:]
    var rigs: [Zone: EmitterRig] = [:]
    /// Beam height per lane, fixed at the reveal from that lane's player (body-relative).
    var beamH: [Zone: CGFloat] = [.left: 0.9, .right: 0.9]
    var revealed = false
    var deployed = false
    var charging = false
    var armed = false
    var locked = false
    var cued = false
    var passed = false
    var poweredDown = false
    var resolved = false
    var shorted = false
    var outcome: TeamChallenge.Outcome?
    /// Last drawn beam intensity per lane (a team short-out decays from it; a beam that is already off stays off).
    var level: [Zone: CGFloat] = [:]
    /// Someone was zapped: the beam flares before it shuts down.
    var flaredAt: Double?
    var ticks = 0
    var plannedSquats: [(zone: Zone, at: Double, hold: Double)] = []
    var plannedJumps: [(zone: Zone, at: Double)] = []
    let phaseSeed = Float.random(in: 0...6.28)
    /// Run-wide laser number (for logs and evidence names).
    var number = 0

    // Emitter timeline after the reveal (seconds): deploy → charge → fire → sweep → lock (before the cue).
    static let deployAt = 0.05, chargeAt = 0.4, fireAt = 1.0, sweepFrom = 1.25
    // Iris: the aperture opens, then the pods orbit the rim to the lane heights and lock; fire 0.4 s later.
    static let irisOpenFrom = 0.6, irisOpenAt = 1.8, irisPodsFrom = 1.4, irisLockAt = 2.4
    static let irisCentreH: CGFloat = 1.0, irisPodRadius: CGFloat = 1.9

    /// Per-lane crossing and cue times on this gate's clock (equal for a gate; staggered for a turret wave).
    let crossings: [Zone: Double]
    let cueAt: [Zone: Double]
    var cuedLanes: Set<Zone> = []
    var passedLanes: Set<Zone> = []
    var rotating = false
    var clamped = false
    /// Turret: the beam half between the players' plane and the camera (drawn in front of them; the far half behind).
    var nearBeams: [Zone: SKSpriteNode] = [:]
    var rails: [Zone: SKShapeNode] = [:]
    /// Iris gate parts: the ring, its aperture blades and the chase lamps around it.
    var irisRing: SKSpriteNode?
    /// The ring runs through floor and ceiling slots: everything below the floor line is masked off.
    let irisCrop = SKCropNode()
    let irisMask = SKSpriteNode(color: .white, size: CGSize(width: 4000, height: 3000))
    var blades: [SKSpriteNode] = []
    var lamps: [SKSpriteNode] = []
    var irisOpened = false
    var podsLocked = false
    /// Emitter timeline after the reveal for this kind of hardware.
    let deployR: Double, chargeR: Double, fireR: Double

    var firstCrossing: Double { crossings.values.min() ?? 0 }
    var lastCrossing: Double { crossings.values.max() ?? 0 }
    var firstCue: Double { cueAt.values.min() ?? 0 }

    /// Depth of the hardware (z): the gate rides with the corridor; a turret is clamped to its rail beside the cart.
    func depth(_ timing: LaserTiming) -> Double {
        guard step.turret else { return timing.gateZ(at: t) }
        let endR = TurretSweep.endTime(timing: timing, stagger: step.stagger) - timing.revealTime
        return TurretSweep.depth(r: t - timing.revealTime, endR: endR, speed: timing.speed)
    }

    init(step: LaserStep, seqIndex: Int = 0, seqCount: Int = 1, timing: LaserTiming) {
        self.step = step
        self.seqIndex = seqIndex
        self.seqCount = seqCount
        crossings = step.turret ? TurretSweep.crossings(timing: timing, stagger: step.stagger)
            : Dictionary(uniqueKeysWithValues: Zone.allCases.map { ($0, timing.crossingTime) })
        cueAt = crossings.mapValues { $0 - timing.cueLead }
        if step.turret {
            (deployR, chargeR, fireR) = (TurretSweep.clampAt, TurretSweep.clampAt + 0.25, TurretSweep.fireAt)
        } else if step.iris {
            (deployR, chargeR, fireR) = (Self.irisPodsFrom, Self.irisLockAt, Self.irisLockAt + 0.3)
        } else {
            (deployR, chargeR, fireR) = (Self.deployAt, Self.chargeAt, Self.fireAt)
        }
        for zone in Zone.allCases {
            let beam = SKSpriteNode(color: .white, size: CGSize(width: 64, height: 32))
            beam.anchorPoint = CGPoint(x: 0, y: 0.5)
            beam.shader = Shaders.laserBeam
            beam.blendMode = .add
            beam.isHidden = true      // brightness comes from the shader's intensity; hidden while off
            beams[zone] = beam
            let cap = SKSpriteNode(texture: Art.glow)
            cap.colorBlendFactor = 1
            cap.blendMode = .add
            cap.alpha = 0
            caps[zone] = cap
            let glow = SKSpriteNode(texture: Art.glow)
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0
            floorGlow[zone] = glow
            rigs[zone] = EmitterRig()
            if step.turret {
                let near = SKSpriteNode(color: .white, size: CGSize(width: 64, height: 32))
                near.anchorPoint = CGPoint(x: 0, y: 0.5)
                near.shader = Shaders.laserBeam
                near.blendMode = .add
                near.isHidden = true
                nearBeams[zone] = near
                let rail = SKShapeNode()
                rail.fillColor = VaultPalette.metalLight
                rail.strokeColor = VaultPalette.ink
                rail.lineWidth = 1.5
                rail.alpha = 0
                rails[zone] = rail
            }
        }
        if step.iris {
            irisRing = SKSpriteNode(texture: Art.irisRing)
            for _ in 0..<6 {
                let blade = SKSpriteNode(texture: Art.irisBlade)
                blade.anchorPoint = CGPoint(x: 0, y: 0.5)
                blades.append(blade)
            }
            for _ in 0..<12 {
                let lamp = SKSpriteNode(texture: Art.indicatorLamp)
                lamp.colorBlendFactor = 1
                lamps.append(lamp)
            }
            for rig in rigs.values { rig.showsHatch = false }
            irisMask.anchorPoint = CGPoint(x: 0.5, y: 0)
            irisCrop.maskNode = irisMask
            for (i, node) in ([irisRing!] + blades + lamps).enumerated() {
                node.zPosition = i == 0 ? 0.01 : (i <= blades.count ? 0 : 0.02)
                irisCrop.addChild(node)
            }
        }
        frame.anchorPoint = CGPoint(x: 0.5, y: 0)
        frame.colorBlendFactor = 1
        frame.color = VaultPalette.cyan
        frame.alpha = 0
    }

    /// One beam wall-to-wall (the right rig is its receiver); set at the reveal when both lanes need the same height.
    var sharedBeam = false
    var worldNodes: [SKNode] {
        [frame] + Array(beams.values) + Array(nearBeams.values) + Array(caps.values) + Array(floorGlow.values) + Array(rails.values) + rigs.values.map(\.node)
            + (step.iris ? [irisCrop] : [])
    }

    func color(_ zone: Zone) -> UIColor { pattern.action(for: zone) == .duck ? VaultPalette.laser : VaultPalette.gold }
}

/// Everything Laser Breakout needs at runtime (scene extensions cannot store properties).
@MainActor
final class LaserRuntime {
    var director = LaserDirector()
    let difficulty = LaserDifficulty.fromDefaults()
    let timing: LaserTiming
    var alert = SecurityAlert()
    var freshness = DuckFreshness()
    /// Gates in flight (a sequence overlaps them: the next one's warning starts while the previous one approaches).
    var gates: [LaserGate] = []
    /// Every gate of the current beat, finished ones included (for the sequence preview and the combo outcome).
    var beatGates: [LaserGate] = []
    /// The current choreographed sequence and the next step to spawn.
    var sequence: LaserSequence?
    var seqNext = 0
    var seqSpacing = 0.0
    var beat: LaserBeat?
    var phase: LaserPhase?
    var nextBeatAt: Double = 3.5
    var laserIndex = 0
    var hazardCounter = 0
    var alarm: CGFloat = 0
    var flash: CGFloat = 0
    var exit: CGFloat = 0
    var speedScale: CGFloat = 1
    var finaleAt: Double?
    var finaleDone = false
    var stats = (dodges: 0, chances: 0, teamDodges: 0)
    var combos = 0
    var script: LaserScript?
    /// A laser or sequence withdrawn by a halt is played again (whole) after the resume (never silently skipped).
    var retry: LaserBeat?
    /// Heist presentation (set pieces, drone, live bodies, HUD, camera).
    let heist = HeistRuntime()
    /// Camera field of view target (1 = normal; < 1 pushes in on a threat, > 1 pulls back for a reveal).
    var fov: CGFloat = 1
    // HUD.
    let alertBack = SKSpriteNode(texture: Art.pill)
    let alertFill = SKSpriteNode(texture: Art.pill)
    let alertLabel = SKLabelNode()
    let phaseLabel = SKLabelNode()
    let alarmWash = SKSpriteNode(texture: Art.glow)
    /// Per-lane move preview: one shape-coded badge per step (current one large), and the move word under it.
    var strip: [Zone: [SKSpriteNode]] = [:]
    var stripWord: [Zone: SKLabelNode] = [:]

    init() {
        timing = difficulty.apply(to: LaserTiming.fromDefaults())
        director.beats = LaserDirector.getaway(for: difficulty.level)
    }

    /// The gate closest to the players that hasn't passed them yet (lighting, drone gaze, music, camera).
    var leadGate: LaserGate? {
        gates.filter { $0.revealed && !$0.passed }.max { $0.t < $1.t } ?? gates.filter(\.revealed).max { $0.t < $1.t }
    }

    /// The open gate waiting for this lane's move (the earliest one).
    func awaiting(_ zone: Zone, _ action: LaserAction) -> LaserGate? {
        gates.filter { g in
            g.cued && g.encounter?.isOpen == true && g.pattern.action(for: zone) == action && g.encounter?.results[zone] == nil
        }.max { $0.t < $1.t }
    }
}

extension WorldScene {
    /// Gameplay speed is part of the timing (the beam's approach is defined at it), so Reduce Motion doesn't change it.
    var laserCruise: CGFloat { CGFloat(laserRuntime.timing.speed) }

    // MARK: - Build

    func buildLaser() {
        let start = CACurrentMediaTime()
        // Security hardware art is drawn once here, not on the first gate (no hitch mid-run).
        SKTexture.preload(Art.laserTextures + [Art.irisRing, Art.irisBlade, Art.emitterHatch, Art.emitterArm, Art.emitterHead, Art.chargeRing, Art.indicatorLamp]) {}
        let world = LaserWorld()
        if worldRoot.parent == nil { addChild(worldRoot) }
        worldRoot.addChild(world.root)
        laser = world
        let rt = laserRuntime
        rt.alertBack.color = Palette.deepNavy
        rt.alertBack.colorBlendFactor = 1
        rt.alertBack.alpha = 0.85
        rt.alertFill.colorBlendFactor = 1
        rt.alertFill.color = VaultPalette.laser
        rt.alertFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        rt.alertLabel.attributedText = arcadeText("SECURITY ALERT", size: 18, color: .white, strokeWidth: -5)
        rt.phaseLabel.verticalAlignmentMode = .center
        hudNodes.distanceLabel.isHidden = true   // the phase title takes its place
        for node in [rt.alertBack, rt.alertFill, rt.alertLabel, rt.phaseLabel] as [SKNode] { node.zPosition = 5; hud.addChild(node) }
        rt.alertFill.zPosition = 5.1
        rt.alarmWash.color = VaultPalette.laser
        rt.alarmWash.colorBlendFactor = 1
        rt.alarmWash.blendMode = .add
        rt.alarmWash.alpha = 0
        rt.alarmWash.zPosition = Layer.flash - 30
        addChild(rt.alarmWash)
        buildHeist()
        gameLog(String(format: "mode: Laser Breakout (art %.0f ms)", (CACurrentMediaTime() - start) * 1000))
    }

    func layoutLaser() {
        guard let world = laser else { return }
        let rt = laserRuntime
        world.layout(size: size, proj: proj)
        let w: CGFloat = 300
        rt.alertBack.size = CGSize(width: w, height: 22)
        rt.alertBack.position = CGPoint(x: size.width / 2, y: 46)
        rt.alertFill.position = CGPoint(x: size.width / 2 - w / 2 + 3, y: 46)
        rt.alertLabel.position = CGPoint(x: size.width / 2, y: 64)
        rt.phaseLabel.position = CGPoint(x: size.width / 2, y: size.height - 118)
        rt.alarmWash.size = CGSize(width: size.width * 1.6, height: size.height * 1.2)
        rt.alarmWash.position = CGPoint(x: size.width / 2, y: size.height * 0.95)
        layoutHeist()
    }

    // MARK: - Frame

    func updateLaser(dt rawDT: CGFloat, motionDT: CGFloat) {
        guard let world = laser else { return }
        let rt = laserRuntime
        let dt = Double(rawDT)
        let travel = worldSpeed * motionDT
        distance += travel
        world.root.isHidden = mode != .immersive
        let halted = flow.isHalted

        // The gate clock advances with the world actually travelled, so the gate stays fixed to the corridor.
        if !halted { runLaserDirector(dt: Double(motionDT) * Double(worldSpeed / max(laserCruise, 0.01))) }
        updateLaserGates(dt: rawDT)
        updateFinale(dt: dt)

        // Alarm: the phase sets the base, the Security Alert pushes it up; a halt calms it.
        var base: CGFloat = 0
        switch rt.phase {
        case .alarm?: base = 0.7
        case .pursuit?: base = 0.55
        case .lockdown?: base = 0.85
        case nil: base = 0
        }
        if rt.finaleAt != nil { base = 0 }
        let target = halted ? base * 0.4 : min(1, base + CGFloat(rt.alert.level) * 0.3)
        rt.alarm += (target - rt.alarm) * min(1, rawDT * 2)
        rt.flash = max(0, rt.flash - rawDT * 1.6)
        rt.heist.failFlash = max(0, rt.heist.failFlash - rawDT * 2.5)
        rt.alarmWash.alpha = (reduceMotion ? rt.alarm * 0.05 : rt.alarm * (0.05 + 0.05 * (0.5 + 0.5 * sin(CGFloat(now) * 7)))) + rt.heist.failFlash * 0.22

        var beam = SIMD3<Float>(0, 0, 0)
        if let g = rt.leadGate, g.armed, !g.shorted {
            let z = CGFloat(g.depth(rt.timing))
            beam = SIMD3(Float(z), Float(g.beamH[.left] ?? 0.5), Float(min(1, max(0, (40 - z) / 30))))
        }
        updateHeist(dt: rawDT, motionDT: motionDT)
        world.update(dt: motionDT, travel: travel, distance: distance, now: now, proj: proj, size: size, alarm: rt.alarm, beam: beam,
                     flash: rt.flash, exit: rt.exit, reduceMotion: reduceMotion, gameTime: gameTime)
        updateLaserHUD()
        rt.script?.tick(scene: self)
        if let s = rt.script, s.isFinished, rt.beat == nil {
            rt.script = nil
            model?.scriptRunning = false
            model?.autoplay = autoplayBeforeScript
            gameLog("laser script finished")
        }
    }

    private func updateLaserHUD() {
        let rt = laserRuntime
        let level = CGFloat(rt.alert.level)
        rt.alertFill.size = CGSize(width: max(1, (rt.alertBack.size.width - 6) * level), height: 16)
        rt.alertFill.color = level > 0.6 ? VaultPalette.laser : VaultPalette.gold
        rt.alertFill.alpha = level > 0.6 && !reduceMotion ? 0.75 + 0.25 * sin(CGFloat(now) * 9) : 1
    }

    // MARK: - Director: phases, breathers, lasers, sequences, escape

    private func runLaserDirector(dt: Double) {
        let rt = laserRuntime
        for g in rt.gates { g.t += dt; stepLaserGate(g) }
        // Sequences: each next step starts so that its first crossing comes `spacing` seconds after the previous one's.
        if let seq = rt.sequence, rt.seqNext < seq.steps.count,
           rt.gates.last.map({ $0.t >= $0.firstCrossing + rt.seqSpacing - seq.steps[rt.seqNext].firstCrossing(rt.timing) }) ?? true {
            startLaserGate(seq.steps[rt.seqNext], index: rt.seqNext, count: seq.steps.count)
            rt.seqNext += 1
        }
        if let d = laser?.doors, d.mode == .closingAhead { stepClosingDoors() }
        guard rt.beat == nil, rt.gates.isEmpty, rt.finaleAt == nil, gameTime >= rt.nextBeatAt, flow.state == .running else { return }
        if let beat = rt.retry {
            rt.retry = nil
            startHazardBeat(beat)
            return
        }
        guard let beat = rt.director.next() else { return }
        switch beat {
        case .phase(let phase):
            rt.phase = phase
            let number = phase == .alarm ? 1 : phase == .pursuit ? 2 : 3
            rt.phaseLabel.attributedText = arcadeText("\(number)/3 · \(phase.rawValue)", size: 22, color: phase == .pursuit ? VaultPalette.cyan : VaultPalette.laser, strokeWidth: -5)
            switch phase {
            case .alarm:
                showBanner("ALARM TRIGGERED!", sub: "We've got the diamond — now get out!", color: VaultPalette.laser, hold: 2.2)
                audio.play(.siren, dB: -4)
                // The vault's blast doors start closing ahead: the cart must make it through the gap.
                laser?.startDoors(z: 34, open: 1, mode: .closingAhead)
            case .pursuit:
                showBanner("SECURITY PURSUIT", sub: "Cameras locked on — keep moving!", color: VaultPalette.cyan, hold: 1.8)
                audio.play(.siren, dB: -8)
            case .lockdown:
                showBanner("FINAL LOCKDOWN!", sub: "One last security sequence!", color: VaultPalette.laser, hold: 1.8)
                audio.play(.siren, dB: -3)
            }
            gameLog("laser phase: \(phase.rawValue)")
            captureEvent("l-phase-\(number)", after: 0.8)
            rt.nextBeatAt = gameTime + 1.6
        case .breather(let seconds):
            rt.nextBeatAt = gameTime + seconds
        case .laser, .sequence:
            startHazardBeat(beat)
        case .vaultOpen:
            rt.beat = beat
            startVaultOpen()
        case .override:
            rt.beat = beat
            startOverride()
        case .escape:
            startEscape()
        }
    }

    /// A single laser is a one-step sequence; a sequence announces itself once and shows each lane its own moves.
    private func startHazardBeat(_ beat: LaserBeat) {
        let rt = laserRuntime
        let seq: LaserSequence
        switch beat {
        case .laser(let p): seq = LaserSequence(name: "", steps: [LaserStep(pattern: p)], spacing: 0)
        case .sequence(let s): seq = s
        default: return
        }
        rt.beat = beat
        rt.sequence = seq
        rt.seqNext = 0
        rt.beatGates = []
        rt.seqSpacing = effectiveSpacing(seq)
        let parent = role(for: .left), child = role(for: .right)
        func moves(_ zone: Zone) -> String { seq.actions(for: zone).map { $0 == .duck ? "DUCK" : "JUMP" }.joined(separator: " ▸ ") }
        let hold = rt.timing.warningDuration + 0.4
        if seq.steps.count == 1 {
            let step = seq.steps[0]
            switch step.pattern {
            case _ where step.turret:
                let move = step.pattern.action(for: .left) == .duck ? "DUCK" : "JUMP"
                showBanner("TURRET SWEEP!", sub: step.stagger > 0 ? "It swings in lane by lane — \(move) as it passes you" : "It swings toward you — \(move) as it passes",
                           color: step.pattern == .floorSweep ? VaultPalette.gold : VaultPalette.laser, hold: hold)
            case .highBeam where step.sweep:
                showBanner("LASER SWEEP!", sub: "The beam swings in — DUCK when it locks", color: VaultPalette.laser, hold: hold)
            case .highBeam:
                showBanner("SECURITY BEAM!", sub: "High laser — get ready to DUCK", color: VaultPalette.laser, hold: hold)
            case .floorSweep:
                showBanner(step.sweep ? "LOW SWEEP!" : "FLOOR LASER!", sub: "Low laser — get ready to JUMP", color: VaultPalette.gold, hold: hold)
            case .splitGrid:
                let duck = step.pattern.action(for: .left) == .duck ? parent : child
                let jump = step.pattern.action(for: .left) == .jump ? parent : child
                showBanner("SPLIT GRID!", sub: "\(duck) ducks · \(jump) jumps", color: VaultPalette.cyan, hold: hold)
            }
        } else {
            let same = moves(.left) == moves(.right)
            let sub = same ? moves(.left) : "\(parent): \(moves(.left))  ·  \(child): \(moves(.right))"
            let title: String
            switch seq.name {
            case "DOUBLE PULSE": title = "DOUBLE PULSE!"
            case "CROSSFIRE": title = "CROSSFIRE!"
            case "GAUNTLET": title = "SECURITY GAUNTLET!"
            default: title = "LASER COMBO!"
            }
            showBanner(title, sub: sub, color: same ? VaultPalette.laser : VaultPalette.cyan, hold: hold)
        }
        showSequenceStrip(seq)
        gameLog(String(format: "laser beat: %@ %@ (spacing %.2f s, difficulty warn×%.2f gap×%.2f)", seq.steps.count == 1 ? "single" : seq.name,
                       seq.steps.map { "\($0.pattern)\($0.sweep ? "+sweep" : "")\($0.turret ? "+turret\($0.stagger > 0 ? "-wave" : "")" : "")" }.joined(separator: ", "), rt.seqSpacing,
                       rt.difficulty.warningScale, rt.difficulty.spacingScale))
    }

    /// The sequence's spacing at the current difficulty, never below what each lane needs to recover between moves.
    private func effectiveSpacing(_ seq: LaserSequence) -> Double {
        var spacing = seq.spacing * laserRuntime.difficulty.spacingScale
        for zone in Zone.allCases {
            let acts = seq.actions(for: zone)
            for i in acts.indices.dropFirst() { spacing = max(spacing, LaserSequence.minGap(acts[i - 1], acts[i])) }
        }
        return spacing
    }

    /// Opening set piece: the doors ahead close as they approach and slam shut just after the cart squeezes through.
    private func stepClosingDoors() {
        guard let world = laser, var d = world.doors else { return }
        let zp = proj.zp
        if d.z > zp {
            d.open = 0.62 + 0.38 * smoothstep(zp + 2, 34, d.z)
        } else if !d.slammed {
            d.slammed = true
            audio.play(.doorSlam, dB: -2)
            shakeUntil = now + 0.25
            shakeAmplitude = reduceMotion ? 0 : 6
            gameLog("laser: blast doors slam shut behind the cart")
        } else {
            d.open = max(0, d.open - 0.15)
        }
        world.doors = d
        if d.z < -1 { world.removeDoors() }
    }

    // MARK: - Sequence preview (per lane: what *you* do, in order)

    private func showSequenceStrip(_ seq: LaserSequence) {
        let rt = laserRuntime
        clearSequenceStrip()
        for zone in Zone.allCases {
            var icons: [SKSpriteNode] = []
            for (i, action) in seq.actions(for: zone).enumerated() {
                let icon = SKSpriteNode(texture: action == .duck ? Art.duckBadge : Art.jumpBadge)
                icon.zPosition = 6
                icon.setScale(0)
                icon.run(.sequence([.wait(forDuration: 0.08 * Double(i) + (zone == .left ? 0 : 0.1)), .scale(to: 0.3, duration: 0.3).easeOutBack(overshoot: 2)]))
                hud.addChild(icon)
                icons.append(icon)
            }
            rt.strip[zone] = icons
            let word = SKLabelNode()
            word.zPosition = 6
            word.alpha = 0
            hud.addChild(word)
            rt.stripWord[zone] = word
        }
    }

    private func clearSequenceStrip() {
        let rt = laserRuntime
        for node in rt.strip.values.flatMap({ $0 }) + Array(rt.stripWord.values) as [SKNode] {
            node.run(.sequence([.group([.fadeOut(withDuration: 0.25), .scale(by: 0.8, duration: 0.25)]), .removeFromParent()]))
        }
        rt.strip = [:]
        rt.stripWord = [:]
    }

    /// Each player's moves sit under their own name card (Parent top-left, Child top-right), in order: the current
    /// step is large with its move word, later steps wait small; done steps dim (cyan tint = cleared, dark = missed).
    /// Shape-coded pictograms and ▼/▲ words, so high and low never depend on colour.
    private func updateSequenceStrip() {
        let rt = laserRuntime
        guard let seq = rt.sequence else { return }
        let top = size.height - 40
        for zone in Zone.allCases {
            guard let icons = rt.strip[zone], !icons.isEmpty else { continue }
            let done = rt.beatGates.prefix { g in g.encounter?.results[zone] != nil || g.resolved || !(g.encounter?.participants.contains(zone) ?? true) }.count
            let current = min(done, icons.count - 1)
            let y = top - 92
            let sizes = icons.indices.map { i -> CGFloat in i == current && done < icons.count ? 0.62 : (i < done ? 0.3 : 0.38) }
            let total = sizes.reduce(0) { $0 + 160 * $1 } + CGFloat(icons.count - 1) * 10
            var x = zone == .left ? 40 : size.width - 40 - total
            for (i, icon) in icons.enumerated() {
                let target = sizes[i]
                if icon.action(forKey: "pop") == nil, !icon.hasActions() { icon.setScale(icon.xScale + (target - icon.xScale) * 0.25) }
                let w = 160 * target
                let isCurrent = i == current && done < icons.count
                icon.position = CGPoint(x: x + w / 2, y: y + (isCurrent && !reduceMotion ? sin(CGFloat(now) * 4) * 3 : 0))
                x += w + 10
                let result = i < rt.beatGates.count ? rt.beatGates[i].encounter?.results[zone] : nil
                icon.alpha = i < done ? (result == .cleared ? 0.7 : 0.4) : (isCurrent ? 1 : 0.8)
                icon.color = result == .cleared ? VaultPalette.cyan : Palette.deepNavy
                icon.colorBlendFactor = i < done ? 0.65 : 0
            }
            if let word = rt.stripWord[zone] {
                if done < icons.count {
                    let action = seq.actions(for: zone)[current]
                    let text = (action == .duck ? "▼ DUCK" : "▲ JUMP") + (icons.count > 1 ? "  \(current + 1)/\(icons.count)" : "")
                    if word.name != text {
                        word.name = text
                        word.attributedText = arcadeText(text, size: 26, color: .white, strokeWidth: -5)
                    }
                    word.horizontalAlignmentMode = zone == .left ? .left : .right
                    word.position = CGPoint(x: zone == .left ? 40 : size.width - 40, y: y - 72)
                    word.alpha = 1
                } else {
                    word.alpha = max(0, word.alpha - 0.1)
                }
            }
        }
    }

    // MARK: - One gate: WARNING → REVEAL (deploy) → CHARGE → FIRE → SWEEP/LOCK → CUE → CROSSING → SHUTDOWN

    private func startLaserGate(_ step: LaserStep, index: Int, count: Int) {
        let rt = laserRuntime
        let gate = LaserGate(step: step, seqIndex: index, seqCount: count, timing: rt.timing)
        rt.gates.append(gate)
        rt.beatGates.append(gate)
        rt.laserIndex += 1
        gate.number = rt.laserIndex
        for node in gate.worldNodes { laser?.root.addChild(node) }
        // Pulse one: a single two-tone beep; every later step: a higher triple (the ear hears "another one").
        audio.play(.laserWarn, dB: index == 0 ? -6 : -8, variant: index == 0 ? 0 : 1)
        if index == 0 { audio.play(.beamOn, dB: -12) }
        if index > 0 { pulseStripIcon(index) }
        heistReact(.warning)
        rt.script?.laserWarned(gate, scene: self)
        gameLog("laser #\(rt.laserIndex): warning \(step.pattern)\(step.sweep ? " (sweep)" : "")\(step.turret ? " (turret)" : "")\(count > 1 ? " — step \(index + 1)/\(count)" : "") (nothing visible yet)")
        captureEvent("l-\(rt.laserIndex)-a-warning", after: 0.8)
    }

    private func pulseStripIcon(_ index: Int) {
        for zone in Zone.allCases {
            guard let icons = laserRuntime.strip[zone], index < icons.count else { continue }
            if reduceMotion { continue }
            icons[index].run(.sequence([.scale(to: 0.7, duration: 0.12), .scale(to: 0.6, duration: 0.15)]), withKey: "pop")
        }
    }

    /// When a sweep's beam locks at its judged height (before the cue, well before the judging window opens).
    private func sweepLockTime(_ timing: LaserTiming) -> Double { timing.cueTime - 0.3 }

    private func stepLaserGate(_ gate: LaserGate) {
        let rt = laserRuntime
        let timing = rt.timing
        let r = gate.t - timing.revealTime
        if !gate.revealed, r >= 0 {
            gate.revealed = true
            // Freeze each lane's beam height from that player's standing height (body-relative).
            for zone in Zone.allCases {
                let action = gate.pattern.action(for: zone)
                gate.beamH[zone] = action == .jump ? CGFloat(Corridor.lowBeamH) : CGFloat(Corridor.highBeamH(forHeadHeight: Double(standingHeadHeight(zone))))
            }
            // One beam wall to wall (into a receiver) when both lanes need the same height; otherwise each lane keeps
            // its own body-relative height and the two emitters' beams meet mid-corridor. Turrets: one per lane.
            gate.sharedBeam = !gate.step.turret && !gate.step.iris && !gate.pattern.isSplit && abs((gate.beamH[.left] ?? 0) - (gate.beamH[.right] ?? 0)) < 0.08
            rt.hazardCounter += 1
            // The child's window is wider than the parent's (difficulty.childWindowScale).
            let windows = Dictionary(uniqueKeysWithValues: Zone.allCases.map { zone in
                (zone, isChildLane(zone) ? rt.difficulty.childWindow(timing.window) : timing.window)
            })
            gate.encounter = LaserEncounter(id: rt.hazardCounter, pattern: gate.pattern, participants: Set(activeZones()), timing: timing,
                                            duckMark: rt.freshness.mark(), crossings: gate.crossings, cueTime: gate.firstCue, laneWindows: windows)
            gameLog(String(format: "laser #%d: %@ revealed at z %.1f (beams at P %.2f / C %.2f units; crossings P %.2f / C %.2f s)", gate.number,
                           gate.step.turret ? "turret" : "gate", gate.depth(timing), Double(gate.beamH[.left] ?? 0), Double(gate.beamH[.right] ?? 0),
                           gate.crossings[.left] ?? 0, gate.crossings[.right] ?? 0))
        }
        if gate.step.turret, gate.revealed, !gate.clamped, r >= TurretSweep.clampAt {
            gate.clamped = true
            audio.play(.hydraulic, dB: -12)
            audio.play(.clunk, dB: -8)
            gameLog(String(format: "laser #%d: turrets clamped to the rail %.1f units ahead of the players", gate.number, TurretSweep.ahead))
        }
        if gate.step.iris, gate.revealed, !gate.irisOpened, r >= LaserGate.irisOpenAt {
            gate.irisOpened = true
            audio.play(.hydraulic, dB: -10)
            gameLog("laser #\(gate.number): iris aperture open")
        }
        if gate.step.iris, gate.revealed, !gate.podsLocked, r >= LaserGate.irisLockAt {
            gate.podsLocked = true
            audio.play(.clunk, dB: -7)
            gameLog(String(format: "laser #%d: iris pods locked at P %.2f / C %.2f units", gate.number, Double(gate.beamH[.left] ?? 0), Double(gate.beamH[.right] ?? 0)))
            captureEvent("l-\(gate.number)-b1-iris-locked", after: 0.1)
        }
        if gate.revealed, !gate.deployed, r >= gate.deployR {
            gate.deployed = true
            audio.play(.deploy, dB: gate.step.turret ? -8 : -12)
        }
        if gate.revealed, !gate.charging, r >= gate.chargeR {
            gate.charging = true
            let high = Zone.allCases.contains { gate.pattern.action(for: $0) == .duck }
            audio.play(high ? .chargeHigh : .chargeLow, dB: -11)
            if !high || gate.pattern.isSplit { audio.play(.chargeLow, dB: -13) }
        }
        if gate.revealed, !gate.armed, r >= gate.fireR {
            // FIRE: the lens snaps, the beam draws across from the emitter.
            gate.armed = true
            audio.play(.ignite, dB: -7)
            if gate.step.sweep { audio.play(.sweepScan, dB: -10) }
            rt.alarm = min(1, rt.alarm + 0.15)   // the corridor lights kick with the ignition
            heistReact(.armed)
            captureEvent("l-\(gate.number)-b-armed", after: 0.3)
        }
        if gate.step.turret, gate.armed, !gate.rotating, r >= TurretSweep.rotateAt {
            gate.rotating = true
            audio.play(.servo, dB: -6)
            audio.play(.sweepScan, dB: -9)
            gameLog(String(format: "laser #%d: turrets rotating toward the players (%.0f°/s)", gate.number, TurretSweep.omega * 180 / .pi))
            captureEvent("l-\(gate.number)-b2-rotating", after: 0.6)
        }
        if gate.step.sweep, gate.armed, !gate.locked, gate.t >= sweepLockTime(timing) {
            gate.locked = true
            audio.play(.clunk, dB: -10)
            gameLog(String(format: "laser #%d: sweep locked at the judged height (%.2f units) %.2f s before judging opens", gate.number,
                           Double(gate.beamH[.left] ?? 0), timing.judgeOpen - gate.t))
        }
        // Cues per lane (a turret wave cues the Child's lane later, at its own crossing − cue lead).
        let participants = gate.encounter?.participants ?? []
        for zone in participants where !gate.cuedLanes.contains(zone) && gate.t >= gate.cueAt[zone] ?? .infinity {
            gate.cuedLanes.insert(zone)
            showCue(zone, up: gate.pattern.action(for: zone) == .jump)
        }
        if !gate.cued, gate.t >= gate.firstCue {
            gate.cued = true
            let sameAction = Set(participants.map { gate.pattern.action(for: $0) }).count == 1
            let word = gate.pattern.isSplit ? "SPLIT!" : (gate.pattern == .floorSweep ? "JUMP!" : "DUCK!")
            let color = gate.pattern.isSplit ? VaultPalette.cyan : (gate.pattern == .floorSweep ? VaultPalette.gold : VaultPalette.laser)
            // The lanes carry each player's own move (chevrons over the head, the preview badge); the shared call is
            // short and sits high, smaller inside a sequence.
            if gate.seqCount > 1 {
                showBanner(word, sub: nil, color: color, hold: 0.8, size: 48)
                audio.play(.comboStep, dB: -8, variant: gate.seqIndex)
            } else if gate.step.turret, gate.step.stagger > 0 {
                showBanner(word, sub: "\(role(for: .left)) first, then \(role(for: .right))", color: color, hold: 1.2, size: 56)
            } else {
                showBanner(word, sub: sameAction ? nil : "Your own move, your own lane", color: color, hold: 0.9, size: 56)
            }
            showTeamLock(participants: participants)
            audio.play(.whoosh, dB: -11)
            planLaserBots(gate)
            rt.script?.laserCued(gate, scene: self)
            gameLog(String(format: "laser #%d: cue, crossing in %.2f s", gate.number, gate.firstCrossing - gate.t))
            captureEvent("l-\(gate.number)-c-cue", after: 0.6)
        }
        if gate.cued, gate.ticks < 3, gate.firstCrossing - gate.t <= [1.05, 0.7, 0.35][gate.ticks] {
            gate.ticks += 1
            audio.play(.tick, dB: -10 + Float(gate.ticks) * 2)
        }
        for zone in Zone.allCases where !gate.passedLanes.contains(zone) && gate.t >= gate.crossings[zone] ?? .infinity {
            gate.passedLanes.insert(zone)
            // Pass-by: one whoosh per crossing (a turret wave gives two, one per lane).
            if !gate.shorted, gate.step.turret || gate.passedLanes.count == 1 { audio.play(.passBy, dB: -8) }
        }
        if !gate.passed, gate.passedLanes.count == Zone.allCases.count { gate.passed = true }
        let shutdownAt = gate.step.turret ? TurretSweep.endTime(timing: timing, stagger: gate.step.stagger) : gate.lastCrossing + 0.12
        if gate.passed, !gate.poweredDown, gate.t >= shutdownAt {
            gate.poweredDown = true
            if !gate.shorted { audio.play(.powerDown, dB: -12) }
            if gate.step.turret { audio.play(.servo, dB: -12) }
        }
        // Planned simulated moves (scripts and autoplay) on the encounter clock.
        for plan in gate.plannedSquats where gate.t >= plan.at {
            if var slot = slots[plan.zone] { slot.sim = SimulatedSquat(start: gameTime, holdDuration: plan.hold); slots[plan.zone] = slot }
        }
        gate.plannedSquats.removeAll { gate.t >= $0.at }
        for plan in gate.plannedJumps where gate.t >= plan.at { simulateJump(plan.zone, manual: false) }
        gate.plannedJumps.removeAll { gate.t >= $0.at }

        if gate.cued, var enc = gate.encounter {
            let airborne = Dictionary(uniqueKeysWithValues: Zone.allCases.map { ($0, slots[$0]?.jump.isAirborne ?? false) })
            let low = Dictionary(uniqueKeysWithValues: Zone.allCases.map { z in (z, [.down, .rising].contains(slots[z]?.detector.phase ?? .standing)) })
            let events = enc.update(at: gate.t, airborne: airborne, low: low, freshness: &rt.freshness)
            gate.encounter = enc
            if !events.isEmpty { handleLaserEvents(gate, events: events) }
        }
        let endAt = max(timing.endTime, gate.lastCrossing + timing.window.clearAfter * rt.difficulty.childWindowScale + timing.window.lateLabelWindow + 0.2)
        if gate.t >= endAt, gate.encounter.map({ !$0.isOpen }) ?? true, gate.depth(timing) < 0.3 {
            for node in gate.worldNodes { node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()])) }
            rt.gates.removeAll { $0 === gate }
            rt.script?.laserFinished(scene: self)
            if rt.gates.isEmpty, rt.seqNext >= (rt.sequence?.steps.count ?? 0) { finishHazardBeat() }
        }
    }

    /// The child's lane (the right lane unless the players swapped sides).
    private func isChildLane(_ zone: Zone) -> Bool { (zone == .right) != swapped }

    private func finishHazardBeat() {
        let rt = laserRuntime
        for zone in Zone.allCases { hideCue(zone) }
        clearSequenceStrip()
        rt.sequence = nil
        rt.beatGates = []
        rt.beat = nil
        rt.nextBeatAt = gameTime + rt.timing.recovery
    }

    /// Sequence-level outcome (after its last gate resolves): every step cleared by everyone = COMBO CLEARED, a shared
    /// system response (all the remaining hardware shorts out) and a team bonus.
    private func resolveSequence() {
        let rt = laserRuntime
        guard let seq = rt.sequence, seq.steps.count > 1, rt.beatGates.count == seq.steps.count else { return }
        let outcomes = rt.beatGates.map(\.outcome)
        let perfect = outcomes.allSatisfy { if case .team? = $0 { true } else { false } }
        let perLane = Dictionary(uniqueKeysWithValues: Zone.allCases.map { zone in
            (zone, rt.beatGates.filter { $0.encounter?.results[zone] == .cleared }.count)
        })
        if perfect {
            rt.combos += 1
            rt.flash = reduceMotion ? 0.5 : 1
            for g in rt.gates { g.shorted = true }
            let title = seq.name == "GAUNTLET" ? "SECURITY BROKEN!" : (seq.name == "CROSSFIRE" ? "CROSSFIRE CLEARED!" : "COMBO CLEARED!")
            showBanner(title, sub: "\(seq.steps.count) for \(seq.steps.count) — together!", color: VaultPalette.cyan, hold: 1.4)
            audio.play(.team, dB: -1)
            audio.play(.alarmOff, dB: -12)
            audio.duckMusic(for: 1.0, now: now)
            heistReact(.perfectSplit)
            addTeamPower(seq.steps.count)
            for zone in Zone.allCases { burstSparks(at: slots[zone]?.footPoint ?? .zero, color: VaultPalette.cyan, count: reduceMotion ? 4 : 10) }
            gameLog("laser sequence \(seq.name): COMBO CLEARED (+\(seq.steps.count) team bonus)")
            captureEvent("l-seq-\(seq.name.lowercased().replacingOccurrences(of: " ", with: "-"))-cleared", after: 0.3)
        } else {
            let parts = Zone.allCases.map { "\(role(for: $0)) \(perLane[$0] ?? 0)/\(seq.steps.count)" }.joined(separator: " · ")
            floatText(parts, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.2))
            gameLog("laser sequence \(seq.name): \(parts)")
            captureEvent("l-seq-\(seq.name.lowercased().replacingOccurrences(of: " ", with: "-"))-partial", after: 0.3)
        }
    }

    /// Standing head height above the deck for a lane (world units), from the player's own body.
    private func standingHeadHeight(_ zone: Zone) -> CGFloat {
        guard let slot = slots[zone] else { return 1 }
        let ppu = proj.ppu(proj.zp)
        if slot.driver == .live, let pose = slot.livePose, let span = pose.standingSpan {
            return max(0.6, CGFloat(span) * bodyRect.height / ppu)
        }
        let isChild = (zone == .right) != swapped
        return isChild ? 0.82 : 1.18
    }

    private func handleLaserEvents(_ gate: LaserGate, events: [JumpJudgeEvent]) {
        let rt = laserRuntime
        let timing = rt.timing
        let inSequence = gate.seqCount > 1
        for event in events {
            switch event {
            case .cleared(let zone, let power):
                lockContributed(zone)
                rt.heist.dodges[zone, default: 0] += 1
                addTeamPower(power)
                hideCue(zone)
                let duck = gate.pattern.action(for: zone) == .duck
                let wait = max(0, timing.crossingTime - gate.t)
                run(.wait(forDuration: wait)) { [weak self] in
                    guard let self else { return }
                    self.popRating(zone, text: duck ? "DUCKED!" : "CLEARED!", color: VaultPalette.cyan, at: self.slots[zone]?.headPoint ?? .zero)
                    self.audio.play(.pop, dB: -8)
                    self.laneFlash(zone, color: VaultPalette.cyan)
                }
                rt.stats.dodges += 1
                gameLog("laser #\(gate.number): \(role(for: zone)) \(duck ? "ducked" : "jumped") clear (+\(power))")
                captureEvent("l-\(gate.number)-d-clear-\(role(for: zone))", after: wait + 0.05)
            case .nipped(let zone):
                // The beam connects: a bright zap on that player, a jolt, the alarm notices. No power is lost.
                let early = events.contains(.labelled(zone, .tooEarly))
                // Low, but in a squat that already cleared a beam (or began before the warning): holding earns nothing.
                let held = gate.pattern.action(for: zone) == .duck && [.down, .rising].contains(slots[zone]?.detector.phase ?? .standing)
                popRating(zone, text: early ? "TOO EARLY!" : (held ? "STAND · DUCK AGAIN!" : "ZAPPED!"), color: early ? VaultPalette.gold : VaultPalette.laser, at: slots[zone]?.headPoint ?? .zero)
                slots[zone]?.nippedAt = now
                if var slot = slots[zone] { slot.combo = 0; slots[zone] = slot }
                hideCue(zone)
                audio.play(.zap, dB: -4)
                burstSparks(at: slots[zone]?.headPoint ?? .zero, color: gate.color(zone), count: reduceMotion ? 3 : 8)
                laneFlash(zone, color: VaultPalette.laser)
                gate.flaredAt = now
                laser?.cameraDetect = 1          // the cameras flash red: detected
                heistReact(.zapped)
                gameLog("laser #\(gate.number): \(role(for: zone)) ZAPPED\(early ? " (too early)" : "")\(held ? " (still holding an earlier squat: no credit)" : "")")
                captureEvent("l-\(gate.number)-e-zap-\(role(for: zone))", after: 0.1)
            case .labelled(let zone, let result):
                if result == .tooLate { popRating(zone, text: "TOO LATE!", color: VaultPalette.gold, at: slots[zone]?.headPoint ?? .zero) }
                gameLog("laser #\(gate.number): \(role(for: zone)) label \(result)")
            case .resolved(let outcome, let bonus):
                gate.resolved = true
                gate.outcome = outcome
                switch outcome {
                case .team(let zones):
                    rt.stats.teamDodges += 1
                    rt.stats.chances += zones.count
                    // The system glitches: this gate's hardware shorts out, the corridor flashes cyan — a beat, not a stop.
                    gate.shorted = true
                    if !reduceMotion { for rig in gate.rigs.values where rig.node.alpha > 0.1 { burstSparks(at: rig.lens, color: VaultPalette.cyan, count: 5) } }
                    rt.flash = reduceMotion ? 0.3 : (inSequence ? 0.5 : 1)
                    if inSequence {
                        floatText("TEAM ✓ \(gate.seqIndex + 1)/\(gate.seqCount)", color: VaultPalette.cyan, at: CGPoint(x: size.width / 2, y: size.height * 0.30))
                        audio.play(.comboStep, dB: -4, variant: gate.seqIndex)
                        audio.play(.zap, dB: -16)
                    } else {
                        showBanner(gate.pattern.isSplit ? "PERFECT SPLIT!" : "TEAM DODGE!", sub: gate.pattern.isSplit ? "Two moves, one team!" : "Security can't touch you!",
                                   color: VaultPalette.cyan, hold: 1.0)
                        heistReact(gate.pattern.isSplit ? .perfectSplit : .teamDodge)
                        audio.play(.team, dB: -2)
                        audio.play(.zap, dB: -14)
                    }
                    addTeamPower(bonus)
                    resolveTeamLock(team: true)
                    for zone in zones { burstSparks(at: slots[zone]?.footPoint ?? .zero, color: VaultPalette.cyan, count: inSequence ? 4 : 6) }
                    for e in rt.alert.record(missed: 0, team: true, cleared: zones.count) { alertEvent(e) }
                    gameLog("laser #\(gate.number): TEAM (+\(bonus) bonus); alert \(String(format: "%.2f", rt.alert.level))")
                    captureEvent("l-\(gate.number)-f-team", after: 0.25)
                case .partial(let done, let missing):
                    rt.stats.chances += done.count + missing.count
                    // Partial: no big banner over the action — the lanes already show who made it; the alarm reacts.
                    if !done.isEmpty { audio.play(.chime, dB: -6) }
                    if !inSequence || gate.seqIndex < gate.seqCount - 1 {
                        floatText(done.isEmpty ? "ALARM RISING" : "ONE MADE IT — TOGETHER NEXT!", color: done.isEmpty ? VaultPalette.laser : .white,
                                  at: CGPoint(x: size.width / 2, y: size.height * 0.30))
                    }
                    resolveTeamLock(team: false)
                    for e in rt.alert.record(missed: missing.count, team: false, cleared: done.count) { alertEvent(e) }
                    gameLog("laser #\(gate.number): partial: clear [\(done.map { role(for: $0) }.sorted().joined(separator: ","))] zapped [\(missing.map { role(for: $0) }.sorted().joined(separator: ","))]; alert \(String(format: "%.2f", rt.alert.level))")
                    captureEvent("l-\(gate.number)-f-partial", after: 0.25)
                case .cancelled:
                    hideTeamLock()
                }
                if inSequence, gate.seqIndex == gate.seqCount - 1 { resolveSequence() }
            }
        }
    }

    /// Reactive light on a lane's floor: cyan when a move beats the beam, red when it connects.
    private func laneFlash(_ zone: Zone, color: UIColor) {
        let flash = SKSpriteNode(texture: Art.glow)
        flash.color = color
        flash.colorBlendFactor = 1
        flash.blendMode = .add
        let ppu = proj.ppu(proj.zp)
        flash.position = proj.screen(x: CGFloat(Corridor.laneX(zone)), h: 0, z: proj.zp)
        flash.size = CGSize(width: ppu * 1.3, height: ppu * 0.45)
        flash.zPosition = proj.depthZ(proj.zp) - 0.3
        flash.alpha = reduceMotion ? 0.35 : 0.7
        laser?.root.addChild(flash)
        flash.run(.sequence([.group([.fadeOut(withDuration: 0.45), .scale(by: 1.25, duration: 0.45)]), .removeFromParent()]))
    }

    private func alertEvent(_ event: SecurityAlert.Event) {
        switch event {
        case .crossedHigh:
            floatText("ALERT RISING", color: VaultPalette.laser, at: CGPoint(x: size.width / 2, y: 96))
            audio.play(.siren, dB: -6)
        case .maxed:
            floatText("FULL ALERT!", color: VaultPalette.laser, at: CGPoint(x: size.width / 2, y: 96))
        }
        gameLog("security alert: \(event)")
    }

    private func planLaserBots(_ gate: LaserGate) {
        guard laserRuntime.script == nil, model?.autoplay == true, let enc = gate.encounter else { return }
        let crouch = SimulatedJump(start: 0).crouch
        for zone in enc.participants {
            guard let slot = slots[zone], slot.driver == .simulated, now - slot.lastManualSim > 20 else { continue }
            let crossing = gate.crossings[zone] ?? laserRuntime.timing.crossingTime
            let roll = Double.random(in: 0...1)
            switch gate.pattern.action(for: zone) {
            case .duck: gate.plannedSquats.append((zone, crossing - (roll < 0.88 ? Double.random(in: 0.45...0.7) : -0.2), 0.25))
            case .jump: gate.plannedJumps.append((zone, crossing + (roll < 0.88 ? Double.random(in: -0.45 ... -0.2) : 0.35) - crouch))
            }
        }
    }

    // MARK: - Gate visuals (every frame)

    private func updateLaserGates(dt: CGFloat) {
        let rt = laserRuntime
        Shaders.laserBeam.uniformNamed("u_clock")?.floatValue = Float(reduceMotion ? 0 : now.truncatingRemainder(dividingBy: 1000))
        var debug: [LaserWorld.DebugBeam] = []
        var hum: (high: Float, low: Float) = (0, 0)
        for gate in rt.gates { updateLaserGate(gate, debug: &debug, hum: &hum) }
        // Security cameras turn toward the lane that must act next (the earliest unjudged crossing).
        var look: CGFloat = 0
        if let g = rt.leadGate, g.armed, let enc = g.encounter,
           let next = enc.participants.filter({ enc.results[$0] == nil }).min(by: { (g.crossings[$0] ?? 0) < (g.crossings[$1] ?? 0) }) {
            look = next == .left ? -1 : 1
        }
        laser?.cameraLook = look
        laser?.drawDebugBeams(debug, proj: proj, timing: rt.timing)
        audio.setLaserHum(high: flow.isHalted ? 0 : hum.high, low: flow.isHalted ? 0 : hum.low, dt: Double(dt))
        updateSequenceStrip()
    }

    private static func rgba(_ c: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    /// Every element is placed with the shared projection at the gate's depth, so the beam drawn is the beam judged:
    /// it reaches the players' plane exactly at the crossing, and a beam that looks far away is far away.
    private func updateLaserGate(_ gate: LaserGate, debug: inout [LaserWorld.DebugBeam], hum: inout (high: Float, low: Float)) {
        if gate.step.turret { updateTurret(gate, debug: &debug, hum: &hum); return }
        let timing = laserRuntime.timing
        let z = CGFloat(timing.gateZ(at: gate.t))
        let visible = gate.revealed && z > 0.25
        let ppu = proj.ppu(max(z, 0.25))
        let r = gate.t - timing.revealTime
        let past = CGFloat(gate.t - timing.crossingTime)
        let fadeIn = CGFloat(min(1, max(0, r / 0.6)))
        let depth = proj.depthZ(z)
        gate.frame.position = proj.screen(x: 0, h: CGFloat(Corridor.floorH), z: z)
        gate.frame.setScale(ppu / 100)
        gate.frame.zPosition = depth - 0.05
        gate.frame.alpha = visible ? fadeIn : 0
        // The frame's light edge: cyan while idle, the beam colour once armed, dark after the team shorts it out.
        gate.frame.color = gate.shorted ? VaultPalette.navy : (gate.armed ? gate.color(.left) : VaultPalette.cyan)
        gate.frame.colorBlendFactor = gate.shorted ? 0.6 : 0.35
        if gate.step.iris { updateIris(gate, z: z, r: r, visible: visible, fadeIn: fadeIn); gate.frame.alpha = 0 }

        // Emitter state from the encounter clock.
        let deployT = CGFloat(max(0, min(1, (r - LaserGate.deployAt) / 0.45)))
        var deploy = deployT >= 1 ? 1 : 1 + 2.2 * pow(deployT - 1, 3) + 1.2 * pow(deployT - 1, 2)   // ease-out-back: overshoot, settle
        deploy *= 1 - smoothstep(0.2, 0.55, past)                                                      // RETRACT once past
        let charge = CGFloat(max(0, min(1, (r - LaserGate.chargeAt) / (LaserGate.fireAt - LaserGate.chargeAt))))
        let recoil: CGFloat = gate.armed ? CGFloat(max(0, 1 - (r - LaserGate.fireAt) / 0.25)) : 0
        let shutdown: CGFloat = gate.shorted ? 1 : smoothstep(0.12, 0.4, past)
        let blink = !reduceMotion && r < LaserGate.chargeAt && Int(max(0, r) * 8) % 2 == 0
        let drawT: CGFloat = gate.armed ? easeOutCG(CGFloat(min(1, (r - LaserGate.fireAt) / 0.22))) : 0
        let flare: CGFloat = gate.flaredAt.map { now - $0 < 0.25 ? 1 : 0 } ?? 0
        let W = CGFloat(Corridor.halfWidth)
        let reach: CGFloat = 0.49 * max(0, deploy)      // wall → lens (arm + half the head)

        for zone in Zone.allCases {
            guard let rig = gate.rigs[zone], let beam = gate.beams[zone], let cap = gate.caps[zone], let glow = gate.floorGlow[zone] else { continue }
            let side: CGFloat = zone == .left ? -1 : 1
            let h = gate.beamH[zone] ?? 0.9
            let fires = !gate.sharedBeam || zone == .left       // a shared beam: the left emitter fires, the right rig receives
            let color = gate.color(zone)
            // SWEEP: the head swings the beam's far end in (from the ceiling for a high beam, from waist height for a low
            // one), oscillating down to the judged height; it LOCKS there before the cue — never moving while judged.
            var endH = h
            if gate.step.sweep, fires {
                let lockR = sweepLockTime(timing) - timing.revealTime
                let s = CGFloat(max(0, min(1, (r - LaserGate.sweepFrom) / (lockR - LaserGate.sweepFrom))))
                let start: CGFloat = gate.pattern.action(for: zone) == .duck ? CGFloat(Corridor.ceilingH) - 0.1 : 0.85
                endH = h + (start - h) * (1 - smoothstep(0, 1, s)) + (reduceMotion ? 0 : 0.3 * sin(s * .pi * 3) * (1 - s))
                endH = min(CGFloat(Corridor.ceilingH) - 0.05, max(CGFloat(Corridor.floorH) + 0.05, endH))
            }
            let farX: CGFloat = gate.sharedBeam ? W - reach : side * (gate.pattern.isSplit ? 0.06 : 0.01)
            let far = proj.screen(x: farX, h: endH, z: z)
            // Mount: the wall, or (iris) the pod's place on the ring as it orbits to the lane height.
            var mountX = side * W, mountH = h
            if gate.step.iris {
                let p = irisPod(zone, h: h, r: r)
                mountX = p.x; mountH = p.h
            }
            let headPt = proj.screen(x: mountX - side * 0.28 * max(0, deploy), h: mountH, z: z)
            let aim: CGFloat = fires ? atan2(far.y - headPt.y, abs(far.x - headPt.x)) : 0
            let receiving = !fires && gate.armed && drawT >= 1
            rig.layout(side: side, wallX: mountX, h: mountH, z: z, proj: proj,
                       state: .init(deploy: deploy, charge: fires ? charge : (receiving ? 1 : charge * 0.4), firing: fires ? gate.armed : receiving,
                                    shutdown: shutdown, recoil: fires ? recoil : 0, aim: aim, warningBlink: blink, color: color),
                       depth: depth, visible: visible ? fadeIn : 0)
            guard fires else { beam.isHidden = true; cap.alpha = receiving && visible ? (1 - shutdown) * 0.8 : 0; cap.position = rig.lens
                cap.size = CGSize(width: ppu * 0.32, height: ppu * 0.32); cap.color = color; cap.zPosition = depth + 0.02; glow.alpha = 0; continue }
            let a = rig.lens
            let b = CGPoint(x: a.x + (far.x - a.x) * drawT, y: a.y + (far.y - a.y) * drawT)
            let len = hypot(b.x - a.x, b.y - a.y)
            var intensity: CGFloat = visible && gate.armed ? (1 - shutdown) * (1 + 0.35 * recoil + 0.6 * flare) : 0
            if gate.shorted {
                // A team short-out: the live beam stutters and dies (one already off stays off).
                let decayed = max(0, (gate.level[zone] ?? 0) - 0.08)
                gate.level[zone] = decayed
                intensity = visible ? decayed * (reduceMotion ? 1 : 0.4 + 0.6 * abs(sin(CGFloat(now) * 60))) : 0
            } else {
                gate.level[zone] = intensity
            }
            beam.isHidden = intensity <= 0.01
            beam.position = a
            beam.zRotation = atan2(b.y - a.y, b.x - a.x)
            beam.xScale = max(0.01, len / 64)
            // Each hardware type has its own beam: the high beam thin and fast, the floor laser thick and slow, the
            // scanner jittery until it locks. Colour still means the move (magenta duck, amber jump).
            let low = gate.pattern.action(for: zone) == .jump
            beam.yScale = ppu * ((low ? 0.55 : 0.4) + 0.2 * flare) / 32
            beam.zPosition = depth + (z < proj.zp ? 0.5 : -0.02)
            let instability: Float = gate.step.sweep && !gate.locked ? 0.45 : (low ? 0.05 : 0.1)
            beam.setValue(SKAttributeValue(vectorFloat4: SIMD4(1, 1, gate.step.sweep ? 24 : (low ? 9 : 16), instability)), forAttribute: "a_shape")
            beam.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(len), Float(intensity), Float(flare), gate.phaseSeed + (zone == .left ? 0 : 1.3))),
                          forAttribute: "a_params")
            beam.setValue(SKAttributeValue(vectorFloat4: Self.rgba(color)), forAttribute: "a_color")
            // Terminus: a hot flare where the beam ends (on the receiver lens for a shared beam).
            cap.position = b
            cap.color = color
            cap.size = CGSize(width: ppu * (0.3 + 0.2 * flare), height: ppu * (0.3 + 0.2 * flare))
            cap.alpha = beam.isHidden ? 0 : min(1, intensity) * 0.85
            cap.zPosition = beam.zPosition + 0.01
            // Reactive light: the beam lights the floor under it (strongest for the low beam).
            let mid = proj.screen(x: (side * (W - reach) + farX) / 2, h: CGFloat(Corridor.floorH), z: z)
            glow.position = mid
            glow.color = color
            glow.size = CGSize(width: max(1, abs(far.x - a.x)) * 1.1, height: ppu * (h < 0.4 ? 0.7 : 0.45))
            glow.alpha = beam.isHidden ? 0 : min(1, intensity) * (h < 0.4 ? 0.65 : 0.3)
            glow.zPosition = depth - 0.06
            // Hum: louder as the beam closes in; the high and low beams have their own timbres.
            if visible, gate.armed, !gate.shorted {
                let near = Float(pow(max(0, min(1, 1 - (z - proj.zp) / 18)), 1.5) * min(1, intensity))
                if gate.pattern.action(for: zone) == .duck { hum.high = max(hum.high, near) } else { hum.low = max(hum.low, near) }
            }
            if visible, gate.armed {
                let judging = gate.t >= timing.judgeOpen && gate.t <= timing.judgeClose
                let state = gate.step.sweep ? (gate.locked ? " LOCKED" : " SWEEP") : ""
                debug.append(.init(x0: side * W, h0: h, x1: farX, h1: endH, z: z, z1: z, state: judging ? .judging : (z > proj.zp + 0.5 ? .far : .near),
                                   label: String(format: "#%d %@ z%.1f h%.2f %+.2fs%@", gate.number, role(for: zone), z, endH, gate.t - timing.crossingTime, state)))
            }
        }
    }

    /// Where an iris pod sits on the ring: it orbits from the top of the ring down to the angle whose height is the lane's
    /// beam height, and locks there (before the pods fire; never moving while judged).
    private func irisPod(_ zone: Zone, h: CGFloat, r: Double) -> (x: CGFloat, h: CGFloat) {
        let side: CGFloat = zone == .left ? -1 : 1
        let R = LaserGate.irisPodRadius, hc = LaserGate.irisCentreH
        let target = asin(max(-0.95, min(0.95, (h - hc) / R)))        // elevation of the lane height on the ring
        let start: CGFloat = 1.2                                         // near the top
        let s = smoothstep(CGFloat(LaserGate.irisPodsFrom), CGFloat(LaserGate.irisLockAt), CGFloat(r))
        let settle: CGFloat = reduceMotion ? 0 : 0.06 * sin(min(1, max(0, CGFloat(r - LaserGate.irisLockAt) / 0.3)) * .pi)
        let elev = start + (target - start) * s - settle
        return (side * R * cos(elev), hc + R * sin(elev))
    }

    /// IRIS SECURITY GATE: the ring arrives with its aperture shut (a wall), the blades twist open, the chase lamps run
    /// round the ring while the pods orbit to the lane heights, every lamp turns red when they fire, and a team short-out
    /// turns them cyan and dark.
    private func updateIris(_ gate: LaserGate, z: CGFloat, r: Double, visible: Bool, fadeIn: CGFloat) {
        guard let ring = gate.irisRing else { return }
        let ppu = proj.ppu(max(z, 0.25))
        let depth = proj.depthZ(z)
        let hc = LaserGate.irisCentreH
        let centre = proj.screen(x: 0, h: hc, z: z)
        let open = smoothstep(CGFloat(LaserGate.irisOpenFrom), CGFloat(LaserGate.irisOpenAt), CGFloat(r))
        let spin: CGFloat = reduceMotion ? 0 : open * 1.05 + smoothstep(CGFloat(LaserGate.irisPodsFrom), CGFloat(LaserGate.irisLockAt), CGFloat(r)) * 0.5
        gate.irisCrop.zPosition = depth - 0.05
        gate.irisMask.position = CGPoint(x: centre.x, y: proj.screen(x: 0, h: CGFloat(Corridor.floorH), z: z).y)
        ring.position = centre
        ring.setScale(ppu / 100)
        ring.zRotation = spin
        ring.alpha = visible ? fadeIn : 0
        ring.color = gate.shorted ? VaultPalette.cyan : VaultPalette.laser
        ring.colorBlendFactor = gate.armed && !gate.shorted ? 0.15 : 0
        for (i, blade) in gate.blades.enumerated() {
            let a = CGFloat(i) / 6 * 2 * .pi + spin
            blade.position = CGPoint(x: centre.x + cos(a) * 1.95 * ppu, y: centre.y + sin(a) * 1.95 * ppu)
            blade.zRotation = a + .pi - open * 0.6
            blade.xScale = ppu / 100 * max(0.05, 1 - 0.92 * open)
            blade.yScale = ppu / 100
            blade.alpha = visible ? fadeIn * (1 - smoothstep(0.85, 1, open)) : 0
        }
        // Lamps: warning blink (amber) → chase while the pods orbit (charging) → all red when armed → off once passed.
        let chase = Int(max(0, r) * 14)
        for (i, lamp) in gate.lamps.enumerated() {
            let a = CGFloat(i) / 12 * 2 * .pi + spin
            lamp.position = CGPoint(x: centre.x + cos(a) * 2.05 * ppu, y: centre.y + sin(a) * 2.05 * ppu)
            lamp.setScale(ppu * 0.14 / 18)
            var on: CGFloat = 0
            var color = VaultPalette.gold
            if gate.shorted { color = VaultPalette.cyan; on = reduceMotion ? 0.6 : CGFloat(abs(sin(now * 30 + Double(i)))) * 0.8 }
            else if gate.passed { on = 0.15 }
            else if gate.armed { color = VaultPalette.laser; on = 1 }
            else if r >= LaserGate.irisPodsFrom { color = VaultPalette.laser; on = (chase - i) % 12 < 3 && chase >= i ? 1 : 0.25 }
            else { on = !reduceMotion && Int(max(0, r) * 8) % 2 == 0 ? 1 : 0.3 }
            lamp.color = color
            lamp.alpha = visible ? fadeIn * on : 0
        }
    }

    /// Points a beam sprite from `a` to `b` (screen), its thickness following depth at each end (taper in the shader).
    private func placeBeam(_ beam: SKSpriteNode, from a: CGPoint, to b: CGPoint, ppuA: CGFloat, ppuB: CGFloat, width: CGFloat,
                           intensity: CGFloat, flare: CGFloat, phase: Float, color: UIColor, pulse: Float, instability: Float, zPosition: CGFloat) {
        let len = hypot(b.x - a.x, b.y - a.y)
        beam.isHidden = intensity <= 0.01 || len < 1
        guard !beam.isHidden else { return }
        let thick = max(ppuA, ppuB)
        beam.position = a
        beam.zRotation = atan2(b.y - a.y, b.x - a.x)
        beam.xScale = max(0.01, len / 64)
        beam.yScale = thick * (width + 0.2 * flare) / 32
        beam.zPosition = zPosition
        beam.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(len), Float(intensity), Float(flare), phase)), forAttribute: "a_params")
        beam.setValue(SKAttributeValue(vectorFloat4: Self.rgba(color)), forAttribute: "a_color")
        beam.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(ppuA / thick), Float(ppuB / thick), pulse, instability)), forAttribute: "a_shape")
    }

    /// ROTATING TURRET SWEEP. Each lane's turret runs up its wall rail, clamps just ahead of the players (riding with the
    /// cart), deploys, charges, fires straight across — harmless, in front of them — then rotates toward the camera at a
    /// constant rate. The beam is a world-space line from the pivot (TurretSweep, the same function the judge's crossing
    /// times come from); it is split at the players' plane so the far part draws behind them and the near part in front.
    private func updateTurret(_ gate: LaserGate, debug: inout [LaserWorld.DebugBeam], hum: inout (high: Float, low: Float)) {
        let timing = laserRuntime.timing
        let r = gate.t - timing.revealTime
        let endR = TurretSweep.endTime(timing: timing, stagger: gate.step.stagger) - timing.revealTime
        let z = CGFloat(gate.depth(timing))
        let visible = gate.revealed && z > 0.35 && z < 20
        let ppu = proj.ppu(max(z, 0.35))
        let depth = proj.depthZ(z)
        let fadeIn = CGFloat(min(1, max(0, r / 0.4)))
        gate.frame.alpha = 0
        let W = CGFloat(Corridor.halfWidth), zp = proj.zp
        let deployT = CGFloat(max(0, min(1, (r - gate.deployR) / 0.4)))
        var deploy = deployT >= 1 ? 1 : 1 + 2.2 * pow(deployT - 1, 3) + 1.2 * pow(deployT - 1, 2)
        deploy *= 1 - smoothstep(CGFloat(endR + 0.3), CGFloat(endR + 0.75), CGFloat(r))      // RETRACT before it unclamps
        let charge = CGFloat(max(0, min(1, (r - gate.chargeR) / (gate.fireR - gate.chargeR))))
        let recoil: CGFloat = gate.armed ? CGFloat(max(0, 1 - (r - gate.fireR) / 0.25)) : 0
        let flare: CGFloat = gate.flaredAt.map { now - $0 < 0.25 ? 1 : 0 } ?? 0
        let blink = !reduceMotion && r < gate.chargeR && Int(max(0, r) * 8) % 2 == 0
        let drawT: CGFloat = gate.armed ? easeOutCG(CGFloat(min(1, (r - gate.fireR) / 0.22))) : 0
        for zone in Zone.allCases {
            guard let rig = gate.rigs[zone], let far = gate.beams[zone], let near = gate.nearBeams[zone], let cap = gate.caps[zone],
                  let glow = gate.floorGlow[zone], let rail = gate.rails[zone] else { continue }
            let side: CGFloat = zone == .left ? -1 : 1, inward = -side
            let h = gate.beamH[zone] ?? 0.9
            let color = gate.color(zone)
            let lag = zone == .right ? gate.step.stagger : 0
            let theta = CGFloat(TurretSweep.angle(at: r, stagger: lag))
            let laneEnd = TurretSweep.rotateAt + lag + TurretSweep.endAngle / TurretSweep.omega
            let shutdown: CGFloat = gate.shorted ? 1 : smoothstep(CGFloat(laneEnd), CGFloat(laneEnd + 0.3), CGFloat(r))
            // Rail on the wall above the beam (a perspective strip, fixed to the corridor wall).
            let railH = h + 0.32
            let rp = CGMutablePath()
            rp.addLines(between: [proj.screen(x: side * W, h: railH, z: 0.7), proj.screen(x: side * W, h: railH, z: 18),
                                  proj.screen(x: side * W, h: railH + 0.06, z: 18), proj.screen(x: side * W, h: railH + 0.06, z: 0.7)])
            rp.closeSubpath()
            rail.path = rp
            rail.zPosition = proj.depthZ(18) + 0.1
            rail.alpha = gate.revealed && r < endR + 1.5 ? min(fadeIn, 1) * 0.9 : max(0, rail.alpha - 0.05)
            // World geometry: pivot at the wall, direction rotated toward the camera; lens and tip on that line.
            let dir = (x: inward * cos(theta), z: -sin(theta))
            let lensDist: CGFloat = 0.49 * max(0, deploy)
            let S = (x: side * W + dir.x * lensDist, z: z + dir.z * lensDist)
            // The beam reaches the corridor centre line (its own lane only) and stops short of the camera.
            var sEnd = W / max(0.05, cos(theta)) * drawT
            if dir.z < 0 { sEnd = min(sEnd, (z - 0.45) / -dir.z) }
            let E = (x: side * W + dir.x * sEnd, z: z + dir.z * sEnd)
            let sP = dir.z < 0 ? (z - zp) / -dir.z : .infinity             // where the line crosses the players' plane
            let headPt = proj.screen(x: side * (W - 0.28 * max(0, deploy)), h: h, z: z)
            let ePt = proj.screen(x: E.x, h: h, z: max(0.45, E.z))
            let aim = atan2(ePt.y - headPt.y, max(1, abs(ePt.x - headPt.x)))
            rig.layout(side: side, wallX: side * W, h: h, z: z, proj: proj,
                       state: .init(deploy: deploy, charge: charge, firing: gate.armed, shutdown: shutdown, recoil: recoil, aim: aim,
                                    warningBlink: blink, color: color),
                       depth: depth, visible: visible ? fadeIn : 0)
            var intensity: CGFloat = visible && gate.armed ? (1 - shutdown) * (1 + 0.35 * recoil + 0.6 * flare) : 0
            if gate.shorted {
                let decayed = max(0, (gate.level[zone] ?? 0) - 0.08)
                gate.level[zone] = decayed
                intensity = visible ? decayed * (reduceMotion ? 1 : 0.4 + 0.6 * abs(sin(CGFloat(now) * 60))) : 0
            } else {
                gate.level[zone] = intensity
            }
            let a = rig.lens
            let phase = gate.phaseSeed + (zone == .left ? 0 : 1.3)
            let splitS = min(max(sP, lensDist), sEnd)
            let mid = (x: side * W + dir.x * splitS, z: z + dir.z * splitS)
            let midPt = proj.screen(x: mid.x, h: h, z: max(0.45, mid.z))
            // Far part (behind the players) and near part (in front of them).
            placeBeam(far, from: a, to: midPt, ppuA: ppu, ppuB: proj.ppu(max(0.45, mid.z)), width: 0.4, intensity: intensity, flare: flare,
                      phase: phase, color: color, pulse: 30, instability: 0.18, zPosition: proj.depthZ(max(zp + 0.05, mid.z)) - 0.02)
            if sEnd > splitS + 0.01 {
                placeBeam(near, from: midPt, to: ePt, ppuA: proj.ppu(max(0.45, mid.z)), ppuB: proj.ppu(max(0.45, E.z)), width: 0.4, intensity: intensity,
                          flare: flare, phase: phase, color: color, pulse: 30, instability: 0.18, zPosition: proj.depthZ(min(zp - 0.05, E.z)) + 0.5)
            } else {
                near.isHidden = true
            }
            cap.position = ePt
            cap.color = color
            let tipPPU = proj.ppu(max(0.45, E.z))
            cap.size = CGSize(width: tipPPU * 0.3, height: tipPPU * 0.3)
            cap.alpha = far.isHidden ? 0 : min(1, intensity) * 0.8
            cap.zPosition = proj.depthZ(max(0.45, E.z)) + 0.6
            // Reactive light on the wall around the turret.
            glow.position = proj.screen(x: side * (W - 0.05), h: h, z: z)
            glow.color = color
            glow.size = CGSize(width: ppu * 0.9, height: ppu * 1.2)
            glow.alpha = far.isHidden ? 0 : min(1, intensity) * 0.35
            glow.zPosition = depth - 0.06
            if visible, gate.armed, !gate.shorted {
                let level = Float(min(1, intensity))
                if gate.pattern.action(for: zone) == .duck { hum.high = max(hum.high, level) } else { hum.low = max(hum.low, level) }
            }
            if visible, gate.armed {
                let tc = gate.crossings[zone] ?? 0
                let w = gate.encounter?.window(zone) ?? timing.window
                let judging = gate.t >= tc - w.clearBefore && gate.t <= tc + w.clearAfter
                debug.append(.init(x0: S.x, h0: h, x1: E.x, h1: h, z: S.z, z1: E.z, state: judging ? .judging : (sP > sEnd ? .far : .near),
                                   label: String(format: "#%d %@ TURRET θ%.0f° %+.2fs", gate.number, role(for: zone), theta * 180 / .pi, gate.t - tc)))
            }
        }
    }

    private func easeOutCG(_ x: CGFloat) -> CGFloat { 1 - (1 - x) * (1 - x) * (1 - x) }

    // MARK: - Escape finale

    private func startEscape() {
        let rt = laserRuntime
        rt.beat = .escape
        showBanner("EXIT AHEAD!", sub: "The doors are opening — hold on!", color: UIColor(red: 0.3, green: 0.95, blue: 0.5, alpha: 1), hold: 2.0)
        laser?.startDoors(z: 30, open: 0, mode: .exit)
        setDroneMood(.panic, for: 99)
        gameLog("laser: escape — exit doors ahead")
        captureEvent("l-escape-a-exit-ahead", after: 1.2)
    }

    private func updateFinale(dt: Double) {
        let rt = laserRuntime
        guard rt.beat == .escape, let world = laser else { return }
        if var d = world.doors, d.mode == .exit {
            if d.z < 16 { d.open = min(1, d.open + CGFloat(dt) / 1.4) }
            if d.open > 0, d.open < 0.05 { audio.play(.doorSlam, dB: -6) }
            world.doors = d
            rt.exit = min(1, max(rt.exit, 1 - (d.z - 2) / 26))
            if rt.finaleAt == nil, d.z < proj.zp - 0.4 {
                // Through the exit: alarms off, the cart coasts out into the light, the diamond rises.
                rt.finaleAt = gameTime
                audio.play(.alarmOff, dB: -3)
                audio.play(.team, dB: -1)
                rt.flash = 1
                showBanner("WE GOT AWAY!", sub: "The diamond is ours!", color: VaultPalette.gold, hold: 3.5)
                rt.phaseLabel.attributedText = arcadeText("ESCAPED!", size: 22, color: VaultPalette.gold, strokeWidth: -5)
                let stats = rt.stats
                run(.wait(forDuration: 1.2)) { [weak self] in
                    guard let self else { return }
                    self.floatText("DODGES \(stats.dodges)/\(max(stats.chances, stats.dodges)) · TEAM \(stats.teamDodges)", color: .white,
                                   at: CGPoint(x: self.size.width / 2, y: self.size.height * 0.52))
                }
                addTeamPower(2)
                gameLog("laser: ESCAPED — dodges \(stats.dodges)/\(stats.chances), team dodges \(stats.teamDodges), alert \(String(format: "%.2f", rt.alert.level))")
                captureEvent("l-escape-b-through", after: 0.4)
                captureEvent("l-escape-c-celebration", after: 2.0)
            }
        }
        guard let t0 = rt.finaleAt else { return }
        let k = gameTime - t0
        rt.speedScale = max(0.05, 1 - CGFloat(k / 2.5))
        world.diamondLift = CGFloat(min(1, k / 1.6))
        if k > 0.6, k < 3.0, Int(k * 3) != Int((k - dt) * 3), !reduceMotion {
            let p = world.diamond.position
            burstSparks(at: CGPoint(x: p.x, y: p.y + world.diamond.frame.height * 0.6), color: VaultPalette.gold, count: 5)
        }
        if k > 7, !rt.finaleDone {
            rt.finaleDone = true
            gameLog("laser: getaway complete")
            if let script = rt.script { script.escaped(scene: self) } else { replay(source: "getaway complete") }
        }
    }

    // MARK: - Input, halt, replay

    /// Movement events in Laser Breakout. Ducks are judged from the squat state at the crossing (fresh squats only);
    /// descents count the squat serial so a held squat can't clear two beams.
    func handleLaser(_ event: SquatEvent, zone: Zone) {
        let rt = laserRuntime
        switch event {
        case .descentStarted:
            rt.freshness.descentStarted(zone)
            if rt.awaiting(zone, .duck) != nil {
                lockProvisional(zone)
            } else {
                padPulse(zone)
            }
        case .repCompleted:
            if rt.heist.override != nil { crankOverride(zone) } else { repCompleted(zone) }
        case .aborted:
            if rt.awaiting(zone, .duck) != nil {
                popRating(zone, text: "GO LOWER!", color: VaultPalette.gold, at: slots[zone]?.headPoint ?? .zero)
            }
        default:
            break
        }
    }

    func laserAwaitsJump(from zone: Zone) -> Bool {
        laserRuntime.awaiting(zone, .jump) != nil
    }

    func withdrawLaserHazards() {
        let rt = laserRuntime
        if let beat = rt.beat, !rt.gates.isEmpty || rt.sequence != nil {
            // A halt withdraws the whole laser or sequence; it plays again, from its first step, after the resume.
            let unfinished = rt.seqNext < (rt.sequence?.steps.count ?? 0) || rt.gates.contains { !$0.resolved }
            if unfinished, case .laser = beat { rt.retry = beat }
            if unfinished, case .sequence = beat { rt.retry = beat }
            for g in rt.gates {
                g.encounter?.cancel()
                for node in g.worldNodes { node.removeAllActions(); node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])) }
                gameLog("laser #\(g.number): withdrawn (game halted)")
            }
            rt.gates = []
            rt.beatGates = []
            rt.sequence = nil
            rt.seqNext = 0
            clearSequenceStrip()
        }
        if rt.beat != .escape { rt.beat = nil }
        rt.nextBeatAt = gameTime + 2.5
        laser?.drawDebugBeams([], proj: proj, timing: rt.timing)
        audio.setLaserHum(high: 0, low: 0, dt: 1)
        for zone in Zone.allCases { hideCue(zone) }
        hideTeamLock()
    }

    func resetLaser() {
        let rt = laserRuntime
        resetHeist()
        withdrawLaserHazards()
        rt.beat = nil
        rt.retry = nil
        rt.director.reset()
        rt.alert.reset()
        rt.phase = nil
        rt.laserIndex = 0
        rt.hazardCounter = 0
        rt.exit = 0
        rt.speedScale = 1
        rt.finaleAt = nil
        rt.finaleDone = false
        rt.stats = (0, 0, 0)
        rt.combos = 0
        rt.phaseLabel.attributedText = nil
        laser?.removeDoors()
        laser?.diamondLift = 0
        rt.nextBeatAt = gameTime + SessionFlow.countdownDuration + 1.0
    }

    func startLaserScript() {
        let rt = laserRuntime
        if rt.script == nil { autoplayBeforeScript = model?.autoplay ?? false }
        rt.script = LaserScript()
        model?.scriptRunning = true
        model?.autoplay = false
        for zone in Zone.allCases { slots[zone]?.simLost = false }
        replay(source: "laser script start")
    }

    func toggleLaserDebug() {
        guard let world = laser else { return }
        world.debugOn.toggle()
        gameLog("laser: perspective debug \(world.debugOn ? "on" : "off")")
    }
}

/// Deterministic Laser Breakout test script: one step per laser of the getaway (in order), then a replay and the first
/// laser of the new run. Times are relative to the crossing. Simulated input only; never evidence of tracking accuracy.
@MainActor
final class LaserScript {
    struct Plan {
        var name: String
        /// Squat start offsets from the crossing (seconds; ~−0.55 is on time), with how long to hold the bottom.
        var squat: [Zone: (offset: Double, hold: Double)] = [:]
        /// Jump takeoff offsets from the crossing (~−0.3 is on time; −1.2 too early; +0.35 too late).
        var jump: [Zone: Double] = [:]
        var control: Control = .none
    }
    enum Control { case none, pauseInWarning(Double, resume: Double), loseTracking(Zone, afterWarning: Double, recover: Double, resume: Double) }

    static let steps: [Plan] = [
        Plan(name: "HIGH BEAM (single duck): both duck → TEAM DODGE", squat: [.left: (-0.6, 0.25), .right: (-0.5, 0.25)]),
        Plan(name: "FLOOR LASER: Child's tracking lost on the approach → withdrawn → READY → resume",
             control: .loseTracking(.right, afterWarning: 3.0, recover: 2.0, resume: 1.5)),
        Plan(name: "FLOOR LASER again (single jump, retried): both jump → TEAM DODGE", jump: [.left: -0.3, .right: -0.25]),
        Plan(name: "SCANNER SWEEP (high): the beam swings in and locks; nobody moves → MISSED, alert rises"),
        Plan(name: "TURRET SWEEP wave (high): Parent's lane first, Child's 0.9 s later; each ducks as it passes → TEAM",
             squat: [.left: (-0.55, 0.25), .right: (-0.55, 0.25)]),
        Plan(name: "DOUBLE PULSE 1/2: both duck; Parent HOLDS the squat for 3 s", squat: [.left: (-0.6, 3.0), .right: (-0.5, 0.25)]),
        Plan(name: "DOUBLE PULSE 2/2: Parent still in the same squat → no credit; Child stands and ducks again → partial",
             squat: [.right: (-0.55, 0.25)]),
        Plan(name: "SPLIT GRID (Parent high): pause during the WARNING → withdrawn, resume", control: .pauseInWarning(0.9, resume: 2.0)),
        Plan(name: "SPLIT GRID again (retried after the pause): Parent ducks, Child jumps → PERFECT SPLIT",
             squat: [.left: (-0.55, 0.25)], jump: [.right: -0.3]),
        Plan(name: "COMBO 1/3 (DUCK): both duck → team", squat: [.left: (-0.55, 0.25), .right: (-0.6, 0.25)]),
        Plan(name: "COMBO 2/3 (JUMP): both jump → team", jump: [.left: -0.3, .right: -0.3]),
        Plan(name: "COMBO 3/3 (DUCK): Parent ducks, Child squats TOO EARLY → partial (combo 2/3)",
             squat: [.left: (-0.55, 0.25), .right: (-1.4, 0.0)]),
        Plan(name: "CROSSFIRE 1/2 (Parent high): Parent DUCKS, Child JUMPS", squat: [.left: (-0.55, 0.25)], jump: [.right: -0.3]),
        Plan(name: "CROSSFIRE 2/2 (Child high): Parent JUMPS, Child DUCKS → CROSSFIRE CLEARED", squat: [.right: (-0.55, 0.25)], jump: [.left: -0.3]),
        Plan(name: "GAUNTLET 1/3 (turret sweep, high): both duck", squat: [.left: (-0.6, 0.25), .right: (-0.55, 0.25)]),
        Plan(name: "GAUNTLET 2/3 (floor laser): both jump", jump: [.left: -0.3, .right: -0.28]),
        Plan(name: "GAUNTLET 3/3 (split, Child high): Parent jumps, Child ducks → SECURITY BROKEN → lockdown gate",
             squat: [.right: (-0.5, 0.25)], jump: [.left: -0.3]),
        Plan(name: "new run: HIGH BEAM both duck → fresh ids and counters", squat: [.left: (-0.55, 0.25), .right: (-0.6, 0.25)]),
    ]

    private(set) var index = 0
    /// Each gate keeps the plan it was given at its warning (in a sequence the next gate is warned before the previous
    /// one's cue).
    private var plans: [ObjectIdentifier: Plan] = [:]
    private var timers: [(fireAt: Double, real: Bool, action: (WorldScene) -> Void)] = []
    private var replayed = false
    var isFinished: Bool { index >= Self.steps.count && timers.isEmpty && leversPulled }

    func laserWarned(_ gate: LaserGate, scene: WorldScene) {
        guard index < Self.steps.count else { return }
        let step = Self.steps[index]
        index += 1
        plans[ObjectIdentifier(gate)] = step
        scene.gameLog("laser script step \(index)/\(Self.steps.count): \(step.name)")
        switch step.control {
        case .pauseInWarning(let at, let resume):
            schedule(at: scene.gameTime + at, real: false) { scene in
                scene.pauseGame(source: "laser script")
                self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "laser script") }
            }
        case .loseTracking(let zone, let after, let recover, let resume):
            schedule(at: scene.gameTime + after, real: false) { scene in
                scene.setSimulatedTrackingLost(zone, lost: true)
                self.schedule(at: scene.now + recover + 0.6, real: true) { scene in
                    scene.setSimulatedTrackingLost(zone, lost: false)
                    self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "laser script") }
                }
            }
        case .none:
            break
        }
    }

    func laserCued(_ gate: LaserGate, scene: WorldScene) {
        guard let step = plans.removeValue(forKey: ObjectIdentifier(gate)) else { return }
        let crouch = SimulatedJump(start: 0).crouch
        func crossing(_ zone: Zone) -> Double { gate.crossings[zone] ?? scene.laserRuntime.timing.crossingTime }
        for (zone, s) in step.squat { gate.plannedSquats.append((zone, crossing(zone) + s.offset, s.hold)) }
        for (zone, offset) in step.jump { gate.plannedJumps.append((zone, crossing(zone) + offset - crouch)) }
    }

    func laserFinished(scene: WorldScene) {}

    func escaped(scene: WorldScene) {
        guard !replayed else { return }
        replayed = true
        scene.replay(source: "laser script (after the escape)")
    }

    private var leversPulled = false

    func tick(scene: WorldScene) {
        // Lockdown gate: each agent pulls their lever twice (Parent then Child, never in sync — no timing pressure).
        let h = scene.laserRuntime.heist
        if !leversPulled, h.overrideStoppedAt != nil, h.overrideOpenedAt == nil {
            leversPulled = true
            scene.gameLog("laser script: lockdown gate — Parent pulls ×2, Child pulls ×2 (one held squat counts once)")
            for (at, zone, hold) in [(0.6, Zone.left, 0.25), (1.2, .right, 3.0), (2.6, .left, 0.25), (5.4, .right, 0.25)] {
                schedule(at: scene.gameTime + at, real: false) { scene in
                    guard var slot = scene.slots[zone] else { return }
                    slot.sim = SimulatedSquat(start: scene.gameTime, holdDuration: hold)
                    scene.slots[zone] = slot
                }
            }
        }
        let due = timers.enumerated().filter { $0.element.fireAt <= ($0.element.real ? scene.now : scene.gameTime) }
        guard !due.isEmpty else { return }
        timers = timers.enumerated().filter { item in !due.contains { $0.offset == item.offset } }.map(\.element)
        for item in due { item.element.action(scene) }
    }

    private func schedule(at time: Double, real: Bool, _ action: @escaping (WorldScene) -> Void) {
        timers.append((time, real, action))
    }
}
