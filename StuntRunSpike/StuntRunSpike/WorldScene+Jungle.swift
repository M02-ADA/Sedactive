import QuartzCore
import SpriteKit

nonisolated enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case stuntRun = "Stunt Run"
    case jungleDrift = "Jungle Drift"
    var id: String { rawValue }
}

/// Bird flock hazard (DUCK). Same phase model as Stunt Run gates (EncounterTiming) and the same TeamChallenge.
@MainActor
final class BirdHazard {
    var t: Double = 0
    var revealed = false
    var cued = false
    var resolved = false
    var challenge: TeamChallenge?
    /// Each bird: its rig, its flight plan (lane, height offset, depth offset) and how it reacts once resolved.
    var birds: [(rig: BirdRig, flight: BirdFlight, zOffset: CGFloat, reaction: BirdReaction)] = []
    var ticks = 0
    var fluttered = false
}

/// Alligator hazard (LEAN). Its rules live in GatorChallenge; its performance in CrocAnimator; this holds the clock.
@MainActor
final class GatorHazard {
    var t: Double = 0
    let side: Zone
    var challenge: GatorChallenge
    let rig = CrocRig()
    let animator: CrocAnimator
    var lastState: CrocPose.State = .lurking
    var bubbles: [SKSpriteNode] = []
    var struck = false
    var released = false
    var finished = false
    /// A combo beat: another hazard starts while the raft is still settling (its window opens after this one's closes).
    enum FollowUp { case birds, piranhas, tail }
    let followUp: FollowUp?
    var followUpStarted = false
    /// Encounter time when the ram's challenge was resolved (the TEAM STEADY / STEADY / SPLASH moment).
    var finishedAt: Double?
    /// Shapes the croc's recovery acting: shaken off (beaten) or pleased (won).
    var outcome: CrocOutcome = .pending

    init(id: Int, side: Zone, participants: Set<Zone>, timing: GatorTiming, followUp: FollowUp?) {
        self.side = side
        self.followUp = followUp
        challenge = GatorChallenge(id: id, side: side, participants: participants, timing: timing)
        animator = CrocAnimator(timing: timing)
    }
}

/// Everything Jungle Drift needs at runtime (scene extensions cannot store properties).
@MainActor
final class JungleRuntime {
    var raft = RaftBalance()
    var director = JungleDirector()
    let birdTiming = EncounterTiming.fromDefaults()
    let gatorTiming = GatorTiming.fromDefaults()
    let piranhaTiming = PiranhaTiming.fromDefaults()
    let logTiming = LogSweepTiming.fromDefaults()
    let tailTiming = TailSweepTiming.fromDefaults()
    var log: LogHazard?
    var tail: TailHazard?
    /// A jump beat waiting for the raft to steady (never a jump while it is still rocking).
    var heldBeat: JungleBeat?
    /// The bow riding up the log's standing wave (0 … 1): the deck pitches about the players' feet.
    var bowLift: CGFloat = 0
    var bowLiftTarget: CGFloat = 0
    var beat: JungleBeat?
    var beatTime: Double = 0
    var nextBeatAt: TimeInterval = 4.5
    var birds: BirdHazard?
    var gator: GatorHazard?
    var piranhas: PiranhaHazard?
    var calmUntil: Double?
    var leans: [Zone: Double] = [.left: 0, .right: 0]
    var simLeans: [Zone: SimulatedLean] = [:]
    var botLeanEffort: [Zone: Double] = [.left: 0.6, .right: 0.6]
    var botLeanFrom: [Zone: Double] = [:]
    var celebrate: CGFloat = 0
    var splashFlashUntil: TimeInterval = 0
    var lastRippleAt: TimeInterval = 0
    var nextAmbientFlock: Double = 6
    var script: JungleScript?
    var hazardCounter = 0
    /// Crocs whose encounter is over but whose retreat is still playing (gameplay has already moved on).
    var crocExits: [GatorHazard] = []
    /// Expanding water rings fed to the river shader: (world x, world z, start time, strength).
    var waterRings: [(x: Float, z: Float, t0: TimeInterval, strength: Float)] = [(0, 0, -100, 0), (0, 0, -100, 0)]
    var nextWaterRing = 0
    var lastDunkAt: TimeInterval = 0
    var splashCrowns: [SKSpriteNode] = []
    var nextCrown = 0

    // Raft rig: rotates about the raft centre; `inner` cancels the offset so children keep scene coordinates.
    let rig = SKNode()
    let inner = SKNode()
    let deck = SKSpriteNode(texture: Art.raftDeck)
    let edge = SKSpriteNode(texture: Art.raftEdge)
    let mast = SKSpriteNode(texture: Art.white)
    let flag = SKSpriteNode(texture: Art.flag)
    var contactShadows: [Zone: SKSpriteNode] = [:]
    var ripples: [SKSpriteNode] = []
    var nextRipple = 0
    var droplets: [SKSpriteNode] = []
    var nextDroplet = 0
    var feathers: [SKSpriteNode] = []
    var nextFeather = 0
    // HUD.
    let gauge = SKSpriteNode(texture: Art.balanceArc)
    let needle = SKSpriteNode(texture: Art.gaugeNeedle)
    let gaugeLabel = SKLabelNode()
    let leanArrow = SKSpriteNode(texture: Art.leanArrow)
    let leanLabel = SKLabelNode()
    let edgeWarning = SKSpriteNode(texture: Art.glow)
    let splashOverlay = SKSpriteNode(texture: Art.white)
    let incoming = SKLabelNode()
    var pivot: CGPoint = .zero
    static let deckSource = WarpQuad.sourceGrid(columns: 1, rows: 1)
    /// Narrow enough that open water stays visible either side of the raft.
    static let raftHalfWidth: CGFloat = 1.1
    /// Where the croc bites the raft's side: toward the far end, so the whole head stays on screen beside the riders.
    static let biteZ: CGFloat = 2.5
}

extension WorldScene {
    var jungleCruise: CGFloat { 6.5 * (reduceMotion ? 0.7 : 1) }

    // MARK: - Build

    func buildJungle() {
        // Generate every jungle texture up front so a landmark or the first alligator never hitches on first use.
        let artStart = CACurrentMediaTime()
        let preload: [SKTexture] = Art.jungleTrees + Art.treeline + [Art.palm, Art.fern, Art.reeds, Art.mossyRock,
            Art.floatingLog, Art.lilyPad, Art.ruinTemple, Art.giantKapok, Art.fallenTree, Art.raftDeck, Art.raftEdge, Art.flag,
            Art.bubble, Art.droplet, Art.feather, Art.canopyCorner, Art.vine,
            Art.balanceArc, Art.gaugeNeedle, Art.leanArrow] + Art.creatureTextures + Art.piranhaTextures + Art.jumpSweepTextures
            + Art.jungleLifeTextures
        SKTexture.preload(preload) {}
        gameLog(String(format: "jungle art generated in %.0f ms (%d textures)", (CACurrentMediaTime() - artStart) * 1000, preload.count))
        run(.wait(forDuration: 1.0)) { [weak self] in self?.exportArtSheetIfRequested() }   // once the model is attached
        let world = JungleWorld()
        if worldRoot.parent == nil { addChild(worldRoot) }   // Stunt Run adds it in buildWorld()
        worldRoot.addChild(world.root)
        jungle = world
        let rt = jungleRuntime
        addChild(rt.rig)
        rt.rig.addChild(rt.inner)
        for node in [rt.deck, rt.edge] {
            node.anchorPoint = .zero
            node.size = CGSize(width: WarpQuad.unit, height: WarpQuad.unit)
            rt.inner.addChild(node)
        }
        rt.deck.zPosition = Layer.pad - 2
        rt.edge.zPosition = Layer.pad - 1.9
        rt.mast.color = JunglePalette.trunk
        rt.mast.colorBlendFactor = 1
        rt.mast.anchorPoint = CGPoint(x: 0.5, y: 0)
        rt.mast.zPosition = Layer.pad - 1.5
        rt.inner.addChild(rt.mast)
        rt.flag.anchorPoint = CGPoint(x: 0, y: 0.5)
        rt.flag.zPosition = Layer.pad - 1.4
        rt.inner.addChild(rt.flag)
        for zone in Zone.allCases {
            let shadow = SKSpriteNode(texture: Art.glow)
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0.55
            shadow.zPosition = Layer.pad - 0.6
            rt.inner.addChild(shadow)
            rt.contactShadows[zone] = shadow
        }
        for _ in 0..<6 {
            let ripple = SKSpriteNode(texture: Art.rippleRing)
            ripple.alpha = 0
            ripple.zPosition = Layer.pad - 3
            addChild(ripple)
            rt.ripples.append(ripple)
        }
        for _ in 0..<30 {
            let drop = SKSpriteNode(texture: Art.droplet)
            drop.isHidden = true
            drop.color = UIColor(red: 0.75, green: 0.98, blue: 0.95, alpha: 1)
            drop.colorBlendFactor = 1
            drop.zPosition = 40
            addChild(drop)
            rt.droplets.append(drop)
        }
        for _ in 0..<3 {
            let crown = SKSpriteNode(texture: Art.splashCrown[0])
            crown.anchorPoint = CGPoint(x: 0.5, y: 24 / Art.splashCrown[0].size().height)
            crown.isHidden = true
            addChild(crown)
            rt.splashCrowns.append(crown)
        }
        for _ in 0..<24 {
            let f = SKSpriteNode(texture: Art.feather)
            f.isHidden = true
            f.colorBlendFactor = 1
            f.zPosition = 45
            addChild(f)
            rt.feathers.append(f)
        }
        // Players ride the raft: their cutout, stand-ins, pads and labels move with it.
        for node in [bodySprite] + Array(placeholders.values) + Array(pads.values) + Array(padLabels.values) as [SKNode] {
            node.removeFromParent()
            rt.inner.addChild(node)
        }
        // HUD: balance gauge at the bottom centre (on the static deck, between the players' feet).
        rt.gauge.zPosition = 5
        rt.needle.anchorPoint = CGPoint(x: 0.5, y: 0)
        rt.needle.zPosition = 6
        rt.gaugeLabel.zPosition = 6
        rt.gaugeLabel.attributedText = arcadeText("BALANCE", size: 18, color: .white, strokeWidth: -5)
        rt.leanArrow.zPosition = 7
        rt.leanArrow.alpha = 0
        rt.leanLabel.zPosition = 7
        rt.leanLabel.alpha = 0
        rt.leanLabel.verticalAlignmentMode = .center
        for node in [rt.gauge, rt.needle, rt.gaugeLabel, rt.leanArrow, rt.leanLabel] as [SKNode] { hud.addChild(node) }
        rt.edgeWarning.color = Palette.coral
        rt.edgeWarning.colorBlendFactor = 1
        rt.edgeWarning.blendMode = .add
        rt.edgeWarning.alpha = 0
        rt.edgeWarning.zPosition = Layer.flash - 5
        addChild(rt.edgeWarning)
        rt.splashOverlay.color = UIColor(red: 0.7, green: 0.95, blue: 1.0, alpha: 1)
        rt.splashOverlay.colorBlendFactor = 1
        rt.splashOverlay.alpha = 0
        rt.splashOverlay.zPosition = Layer.flash - 4
        addChild(rt.splashOverlay)
        rt.incoming.attributedText = arcadeText("!", size: 64, color: Palette.yellow, strokeWidth: -5)
        rt.incoming.verticalAlignmentMode = .center
        rt.incoming.zPosition = Layer.flash - 10
        rt.incoming.isHidden = true
        addChild(rt.incoming)
        audio.startAmbience()
        gameLog("mode: Jungle Drift")
    }

    /// Evidence harness only (`-artSheet YES` with `-evidenceDir`): writes every creature texture as a PNG for a
    /// contact-sheet review. Generated art only; no camera images.
    private func exportArtSheetIfRequested() {
        guard UserDefaults.standard.bool(forKey: "artSheet"), let dir = model?.evidenceDirectory else { return }
        let folder = dir.appendingPathComponent("art", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var named: [(String, SKTexture)] = [("croc-upper", Art.crocUpper), ("croc-lower", Art.crocLower), ("croc-throat", Art.crocThroat),
            ("croc-body", Art.crocBody), ("croc-tail", Art.crocTail), ("croc-leg", Art.crocLeg), ("croc-eye", Art.crocEye),
            ("croc-lid", Art.crocLid), ("croc-brow", Art.crocBrow), ("croc-front", Art.crocFront), ("croc-shadow", Art.crocShadow),
            ("foam-collar", Art.foamCollar), ("ripple", Art.rippleRing)]
        named += Art.splashCrown.enumerated().map { ("splash-\($0.offset)", $0.element) }
        named += [("ridge-far", Art.farRidges[0]), ("ridge-near", Art.farRidges[1]), ("cloud", Art.cloudWisp), ("leaning-tree", Art.leaningTree),
                  ("fish", Art.leapingFish), ("heliconia", Art.heliconia), ("blossom", Art.blossom), ("rock-wake", Art.rockWake),
                  ("stone-arch", Art.stoneArch), ("waterfall", Art.waterfallFrames[0]), ("egret-up", Art.egretFrames[0]),
                  ("egret-down", Art.egretFrames[1]), ("mouth-smug", Art.crocMouthFrames[0]), ("mouth-bared", Art.crocMouthFrames[1])]
        named += Art.morphoFrames.enumerated().map { ("morpho-\($0.offset)", $0.element) }
        named += Art.dragonflyFrames.enumerated().map { ("dragonfly-\($0.offset)", $0.element) }
        named += Art.logFrames.enumerated().map { ("log-roll-\($0.offset)", $0.element) }
        named += [("log-roots", Art.logRoots), ("log-branch", Art.logBranch), ("leaf", Art.floatingLeaf), ("log-sign", Art.logSign),
                  ("tail-sign", Art.tailSign), ("tail-segment", Art.tailSegment), ("tail-tip", Art.tailTip)]
        named += [("piranha-body", Art.piranhaBody), ("piranha-jaw", Art.piranhaJaw), ("piranha-tail", Art.piranhaTail),
                  ("piranha-fin", Art.piranhaFinTex), ("piranha-sign", Art.piranhaSign)]
        for (p, set) in Art.macaws.enumerated() {
            named += set.flap.enumerated().map { ("macaw\(p)-flap\($0.offset)", $0.element) }
            named += [("macaw\(p)-glide", set.glide), ("macaw\(p)-tuck", set.tuck), ("macaw\(p)-flare", set.flare), ("macaw\(p)-startled", set.startled)]
        }
        for (name, texture) in named {
            let image = UIImage(cgImage: texture.cgImage())
            try? image.pngData()?.write(to: folder.appendingPathComponent("\(name).png"))
        }
        gameLog("art sheet: \(named.count) textures written")
    }

    func layoutJungle() {
        guard let world = jungle else { return }
        let rt = jungleRuntime
        world.layout(size: size, proj: proj)
        rt.gauge.size = CGSize(width: 360, height: 112)
        rt.gauge.position = CGPoint(x: size.width / 2, y: 74)
        rt.needle.size = CGSize(width: 24, height: 64)
        rt.needle.position = CGPoint(x: size.width / 2, y: 36)
        rt.gaugeLabel.position = CGPoint(x: size.width / 2, y: 16)
        rt.splashOverlay.size = size
        rt.splashOverlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Frame

    func updateJungle(dt rawDT: CGFloat, motionDT: CGFloat) {
        guard let world = jungle else { return }
        let rt = jungleRuntime
        let dt = Double(rawDT)
        let travel = worldSpeed * motionDT
        distance += travel
        let curveTarget: CGFloat = reduceMotion ? 0 : 0.0055 * sin(distance * 2 * .pi / 210) + 0.002 * sin(distance * 2 * .pi / 90)
        proj.curve += (curveTarget - proj.curve) * min(1, motionDT * 1.5)
        rt.celebrate = max(0, rt.celebrate - motionDT * 0.5)
        world.root.isHidden = mode != .immersive
        rt.rig.isHidden = false
        world.update(dt: motionDT, travel: travel, distance: distance, now: now, proj: proj, size: size,
                     reduceMotion: reduceMotion, celebrate: rt.celebrate)
        if gameTime >= rt.nextAmbientFlock, mode == .immersive {
            world.spawnAmbientFlock(proj: proj)
            rt.nextAmbientFlock = gameTime + Double.random(in: 9...15)
        }

        updateLeans(dt: dt)
        let halted = flow.isHalted
        // Balance: river current + an alligator hanging on + both players' leans. Halted → the raft settles level.
        let current = halted ? 0 : RiverCurrent.torque(atDistance: Double(distance))
        let gatorPull = halted ? 0 : gatorTorque()
        let crouched = Zone.allCases.filter { (slots[$0]?.detector.depth ?? 0) > 0.5 }.count
        let leanValues = halted ? [0, 0] : Zone.allCases.map { rt.leans[$0] ?? 0 }
        let events = rt.raft.step(dt: dt, leans: leanValues, crouched: crouched, externalTorque: current + gatorPull)
        for event in events { raftEvent(event) }
        world.riverShader.uniformNamed("u_currentSide")?.floatValue = Float(current > 0 ? 1 : -1)
        world.riverShader.uniformNamed("u_currentShow")?.floatValue = Float(min(1, abs(current) / RiverCurrent.amplitude))

        if !halted { runDirector(dt: Double(motionDT) * Double(worldSpeed / max(jungleCruise, 0.01))) }
        updateBirds()
        updateGator(dt: dt)
        updatePiranhas(dt: dt)
        updateLogSweep(dt: dt)
        updateTailSweep(dt: dt)
        if rt.log == nil { rt.bowLiftTarget = 0 }
        rt.bowLift += (rt.bowLiftTarget - rt.bowLift) * min(1, CGFloat(dt) * 10)
        updateRaftVisuals()
        updateBalanceHUD()
        rt.script?.tick(scene: self)
        if let s = rt.script, s.isFinished, rt.beat == nil {
            rt.script = nil
            rt.director.lap = JungleDirector.cycle
            rt.director.setPlaylist(nil)
            model?.scriptRunning = false
            model?.autoplay = autoplayBeforeScript
            gameLog("jungle script finished")
        }
    }

    // MARK: - Input: leaning

    func simulateLean(_ zone: Zone, direction: Double) {
        guard slots[zone]?.driver != .live else { return }
        jungleRuntime.simLeans[zone] = SimulatedLean(start: gameTime, direction: direction)
        slots[zone]?.lastManualSim = now
        gameLog("debug: \(role(for: zone)) lean \(direction > 0 ? "RIGHT" : "LEFT") (simulated)")
    }

    private func updateLeans(dt: Double) {
        let rt = jungleRuntime
        for zone in Zone.allCases {
            guard let slot = slots[zone] else { continue }
            var target = 0.0
            if slot.driver == .live, let pose = slot.livePose, let lean = LeanEstimator().lean(for: pose) {
                target = lean
            } else if slot.driver == .simulated, !slot.simLost {
                if let plan = rt.simLeans[zone], gameTime <= plan.end {
                    target = plan.value(at: gameTime)
                } else if let from = rt.botLeanFrom[zone], gameTime >= from {
                    // Responsive simulated player: leans toward the high side in proportion to the tilt.
                    target = responsiveLean(raftAngle: rt.raft.angle, effort: rt.botLeanEffort[zone] ?? 0.6)
                }
            }
            rt.leans[zone, default: 0] += (target - (rt.leans[zone] ?? 0)) * min(1, dt * 8)
        }
    }

    /// Bots (autoplay / script) keep gently balancing during calm stretches, as real players are expected to.
    func setAmbientBalancing(_ on: Bool, effort: Double = 0.5) {
        let rt = jungleRuntime
        for zone in Zone.allCases {
            rt.botLeanFrom[zone] = on ? gameTime + 0.4 : nil
            rt.botLeanEffort[zone] = effort
        }
    }

    // MARK: - Director: WARNING → REVEAL → APPROACH → ACTION → CONSEQUENCE → REWARD → CONTINUE

    private func runDirector(dt: Double) {
        let rt = jungleRuntime
        if rt.beat == nil, gameTime >= rt.nextBeatAt, flow.state == .running {
            let beat = rt.heldBeat ?? rt.director.next()
            if beat.waitsForSteadyRaft, rt.raft.zone != .steady {
                rt.heldBeat = beat   // the raft is still rocking: no jump yet
            } else {
                rt.heldBeat = nil
                rt.beat = beat
                rt.beatTime = 0
                startBeat(beat)
            }
        }
        guard let beat = rt.beat else { return }
        rt.beatTime += dt
        if let birds = rt.birds { birds.t += dt; stepBirds(birds) }
        if let piranhas = rt.piranhas { piranhas.t += dt; stepPiranhas(piranhas) }
        if let log = rt.log { log.t += dt; stepLogSweep(log) }
        if let tail = rt.tail { tail.t += dt; stepTailSweep(tail) }
        if let gator = rt.gator {
            gator.t += dt
            stepGator(gator, dt: dt)
            switch gator.followUp {
            case .birds? where !gator.followUpStarted && gator.t >= rt.gatorTiming.strikeTime + rt.director.comboBirdDelay:
                gator.followUpStarted = true
                startBirds()
            case .tail? where !gator.followUpStarted && gator.t >= rt.gatorTiming.strikeTime + rt.director.comboTailDelay
                && gator.finishedAt.map({ gator.t >= $0 + 1.0 }) == true
                && (rt.raft.zone == .steady || gator.t >= rt.gatorTiming.strikeTime + rt.director.comboTailDelay + 3):
                // It comes back round for the tail only after the ram's result has landed and the raft has steadied
                // (never a jump mid-wobble, and the warning never competes with the TEAM STEADY reward).
                gator.followUpStarted = true
                startTailSweep(side: gator.side)
            case .piranhas? where !gator.followUpStarted && gator.t >= rt.gatorTiming.strikeTime + rt.director.comboPiranhaDelay:
                gator.followUpStarted = true
                startPiranhas(from: JungleDirector.comboPiranhaSide(gatorSide: gator.side), count: 1)
            default:
                break
            }
        }
        var done = false
        switch beat {
        case .birds: done = rt.birds == nil
        case .gator: done = rt.gator == nil
        case .gatorThenBirds: done = rt.gator == nil && rt.birds == nil && (rt.beatTime > 1)
        case .piranhas: done = rt.piranhas == nil
        case .gatorThenPiranhas: done = rt.gator == nil && rt.piranhas == nil && (rt.beatTime > 1)
        case .logSweep: done = rt.log == nil
        case .tailSweep: done = rt.tail == nil
        case .gatorThenTail: done = rt.gator == nil && rt.tail == nil && (rt.beatTime > 1)
        case .calm: done = rt.beatTime >= (rt.calmUntil ?? 0)
        }
        if done {
            gameLog("beat done: \(beat)")
            rt.script?.beatFinished(scene: self)
            rt.beat = nil
            rt.calmUntil = nil
            rt.nextBeatAt = gameTime + rt.director.recovery
            setAmbientBalancing(rt.script != nil || (model?.autoplay ?? false))
        }
    }

    private func startBeat(_ beat: JungleBeat) {
        let rt = jungleRuntime
        gameLog("beat: \(beat)")
        rt.script?.beatStarted(beat, scene: self)
        switch beat {
        case .birds:
            startBirds()
        case .gator(let side):
            startGator(side: side, followUp: nil)
        case .gatorThenBirds(let side):
            startGator(side: side, followUp: .birds)
        case .piranhas(let side, let count):
            startPiranhas(from: side, count: count)
        case .gatorThenPiranhas(let side):
            startGator(side: side, followUp: .piranhas)
        case .logSweep:
            startLogSweep()
        case .tailSweep(let side):
            startTailSweep(side: side)
        case .gatorThenTail(let side):
            startGator(side: side, followUp: .tail)
        case .calm(let landmark):
            rt.calmUntil = rt.director.calmDuration
            if landmark, let world = jungle {
                let name = world.spawnLandmark(z: 64)
                gameLog("calm stretch: landmark ahead (\(name))")
                showBanner("CALM WATERS", sub: name, color: Palette.mint, hold: 1.6)
            } else {
                gameLog("calm stretch")
            }
            captureEvent("j-calm", after: 2.5)
        }
    }

    // MARK: Birds (DUCK)

    private func startBirds() {
        let rt = jungleRuntime
        let hazard = BirdHazard()
        rt.birds = hazard
        jungle?.rustle()
        showBanner("BIRDS INCOMING!", sub: "Get ready to duck together", color: Palette.yellow, hold: rt.birdTiming.warningDuration - 0.2)
        audio.play(.caw, dB: -6)
        rt.incoming.isHidden = false
        rt.incoming.alpha = 1
        rt.script?.birdsWarned(scene: self)
        gameLog("birds: warning (flock not yet visible)")
        captureEvent("j-birds-a-warning", after: 0.5)
    }

    private func stepBirds(_ hazard: BirdHazard) {
        let rt = jungleRuntime
        let timing = rt.birdTiming
        let phase = timing.phase(at: hazard.t)
        if !hazard.revealed, phase != .warning {
            hazard.revealed = true
            rt.incoming.run(.sequence([.fadeOut(withDuration: 0.3), .hide()]))
            // Lead birds fly the players' lanes at head height; the rest fill in higher and further back.
            let layout: [(CGFloat, CGFloat, CGFloat)] = [(-playerX, 0, 0), (playerX, 0.1, 0.4), (-playerX - 0.5, 0.35, 1.1), (playerX + 0.5, 0.3, 0.9), (0, 0.55, 1.6)]
            let seed = UInt64(rt.hazardCounter + 17)
            for (i, (x, h, z)) in layout.enumerated() {
                let traits = BirdTraits.make(index: i, seed: seed)
                let rig = BirdRig(traits: traits)
                rig.node.alpha = 0
                addChild(rig.node)
                addChild(rig.shadow)
                hazard.birds.append((rig, BirdFlight(timing: timing, traits: traits, laneX: Double(x), hOffset: Double(h)), z, .none))
            }
            audio.play(.caw, dB: -9)
            gameLog("birds: flock revealed above the canopy ahead")
            captureEvent("j-birds-b-reveal", after: 1.0)
        }
        if !hazard.cued, phase == .action {
            hazard.cued = true
            rt.hazardCounter += 1
            let participants = Set(activeZones())
            hazard.challenge = TeamChallenge(id: rt.hazardCounter, participants: participants)
            showBanner("DUCK!", sub: participants.count >= 2 ? "Both duck under the birds" : "Duck under the birds", color: Palette.yellow, hold: 1.2)
            showTeamLock(participants: participants)
            for zone in participants { showCue(zone, up: false) }
            audio.play(.whoosh, dB: -9)
            planBotDucks()
            rt.script?.birdsCued(scene: self)
            gameLog("birds: DUCK cue, window open (#\(rt.hazardCounter))")
            captureEvent("j-birds-c-duck", after: 0.8)
        }
        if !hazard.fluttered, hazard.revealed, hazard.t >= timing.arrivalTime - 0.5 {
            // The flare: wings thrown up before the rush past — heard as a burst of wingbeats.
            hazard.fluttered = true
            audio.play(.flutter, dB: -5)
        }
        if hazard.cued, !hazard.resolved {
            let tta = timing.arrivalTime - hazard.t
            let ticks: [Double] = [1.5, 1.0, 0.5]
            if hazard.ticks < ticks.count, tta <= ticks[hazard.ticks] {
                hazard.ticks += 1
                audio.play(.tick, dB: -9 + Float(hazard.ticks) * 2)
            }
            let everyone = hazard.challenge.map { !$0.participants.isEmpty && $0.contributed == $0.participants } ?? false
            if (everyone && hazard.t >= timing.arrivalTime - timing.impactLead) || hazard.t >= timing.windowCloseTime {
                resolveBirds(hazard)
            }
        }
    }

    private func updateBirds() {
        guard let hazard = jungleRuntime.birds else { return }
        let timing = jungleRuntime.birdTiming
        for b in hazard.birds {
            let tta = CGFloat(timing.arrivalTime - hazard.t)
            let z = proj.baseZp + jungleCruise * tta + b.zOffset
            let sample = b.flight.sample(at: hazard.t, reaction: b.reaction)
            let x = CGFloat(b.flight.laneX + sample.xOffset)
            let position = proj.screen(x: x, h: CGFloat(sample.h), z: z)
            b.rig.apply(sample, position: position, ppu: proj.ppu(max(z, 0.25)), reduceMotion: reduceMotion,
                        close: 1 - smoothstep(0.5, 2.0, z))
            b.rig.node.alpha *= smoothstep(0.25, 0.7, z)
            b.rig.node.zPosition = proj.depthZ(z) + 20
            b.rig.node.isHidden = z < 0.25
            // Its shadow crosses the deck as it flies over the raft (fainter and wider the higher it is).
            if z > 1.15, z < 2.85, abs(x) < 1.2, mode == .immersive {
                let hh = CGFloat(max(0, sample.h))
                let w = proj.ppu(z) * 0.55 * (1 + 0.3 * min(1, hh / 3))
                b.rig.shadow.position = proj.screen(x: x, h: 0, z: z)
                b.rig.shadow.size = CGSize(width: w, height: w * 0.3)
                b.rig.shadow.zPosition = Layer.pad + 0.04
                b.rig.shadow.alpha = 0.3 * (1 - min(1, hh / 4)) * b.rig.node.alpha
            } else {
                b.rig.shadow.alpha = 0
            }
        }
        if hazard.resolved, hazard.birds.allSatisfy({ $0.rig.node.isHidden || $0.rig.node.alpha <= 0.01 }) {
            for b in hazard.birds { b.rig.node.removeFromParent(); b.rig.shadow.removeFromParent() }
            jungleRuntime.birds = nil
        }
    }

    private func resolveBirds(_ hazard: BirdHazard) {
        let rt = jungleRuntime
        hazard.resolved = true
        for zone in Zone.allCases { hideCue(zone) }
        guard var challenge = hazard.challenge else { return }
        let (outcome, bonus) = challenge.resolve()
        hazard.challenge = challenge
        switch outcome {
        case .team(let zones):
            // The flock sails over the ducked heads and pulls up and away over the camera.
            for i in hazard.birds.indices { hazard.birds[i].reaction = .teamDucked(at: hazard.t) }
            for zone in zones { featherBurst(at: slots[zone]?.headPoint ?? .zero, count: 5) }
            showBanner("TEAM DUCK!", sub: "The flock sailed right over you!", color: Palette.mint, hold: 1.1)
            audio.play(.team, dB: -2)
            addTeamPower(bonus)
            resolveTeamLock(team: true)
            celebrateWorld()
            gameLog("birds: TEAM (+\(bonus) bonus); power \(teamPower)/\(teamPowerMax)")
            captureEvent("j-birds-e-team", after: 0.15)
        case .partial(let done, let missing):
            // The lead bird in a standing player's lane clips them and tumbles; the rest sail over.
            let hitLanes = Set(missing.map { $0 == .left ? -playerX : playerX })
            for i in hazard.birds.indices {
                let lane = CGFloat(hazard.birds[i].flight.laneX)
                hazard.birds[i].reaction = hitLanes.contains(lane) && i < 2 ? .hit(at: hazard.t) : .missedOver(at: hazard.t)
            }
            for zone in done { popRating(zone, text: "GREAT!", color: .white, at: slots[zone]?.headPoint ?? .zero) }
            for zone in missing {
                // Consequence: a bird clips the standing player — feathers fly and the raft wobbles toward them.
                featherBurst(at: slots[zone]?.headPoint ?? .zero, count: 8)
                popRating(zone, text: "BONK!", color: Palette.coral, at: slots[zone]?.headPoint ?? .zero)
                rt.raft.impulse(zone == .left ? -14 : 14)
                if var slot = slots[zone] { slot.combo = 0; slots[zone] = slot }
            }
            audio.play(.bonk, dB: -6)
            resolveTeamLock(team: false)
            if !done.isEmpty { showBanner("NICE!", sub: "Duck together for the TEAM bonus", color: Palette.color(for: done.first!, swapped: swapped), hold: 1.0) }
            gameLog("birds: partial: done [\(done.map { role(for: $0) }.sorted().joined(separator: ","))] missing [\(missing.map { role(for: $0) }.sorted().joined(separator: ","))] → raft wobble")
            captureEvent("j-birds-e-partial", after: 0.25)
        case .cancelled:
            break
        }
    }

    private func planBotDucks() {
        guard jungleRuntime.script == nil, model?.autoplay == true else { return }
        for zone in Zone.allCases {
            guard var slot = slots[zone], slot.driver == .simulated, now - slot.lastManualSim > 20 else { continue }
            slot.botPlanned = Double.random(in: 0...1) < 0.9 ? gameTime + Double.random(in: 0.25...1.3) : nil
            slot.botPeak = 0.85
            slots[zone] = slot
        }
    }

    // MARK: Alligators (LEAN)

    private func startGator(side: Zone, followUp: GatorHazard.FollowUp?) {
        let rt = jungleRuntime
        rt.hazardCounter += 1
        let hazard = GatorHazard(id: rt.hazardCounter, side: side, participants: Set(activeZones()), timing: rt.gatorTiming, followUp: followUp)
        rt.gator = hazard
        hazard.rig.setSide(side)
        hazard.rig.hideBody()
        hazard.rig.add(to: self)
        for _ in 0..<5 {
            let b = SKSpriteNode(texture: Art.bubble)
            b.alpha = 0
            addChild(b)
            hazard.bubbles.append(b)
        }
        let sideName = side == .left ? "LEFT" : "RIGHT"
        showBanner("GATOR — \(sideName)!", sub: "When it bites, lean the other way", color: Palette.coral, hold: rt.gatorTiming.warningDuration)
        audio.play(.growl, dB: -6)
        audio.play(.gurgle, dB: -10)
        rt.script?.gatorWarned(hazard, scene: self)
        gameLog("gator: warning, \(sideName) side (bubbles; not yet visible)")
        captureEvent("j-gator-a-warning", after: 0.6)
    }

    private func gatorTorque() -> Double {
        guard let g = jungleRuntime.gator, g.struck, !g.released else { return 0 }
        return -g.challenge.correctDirection * jungleRuntime.gatorTiming.clingTorque
    }

    private func stepGator(_ hazard: GatorHazard, dt: Double) {
        let rt = jungleRuntime
        let timing = rt.gatorTiming
        let phase = timing.phase(at: hazard.t)
        if phase == .approach, hazard.lastState == .lurking {
            gameLog("gator: eyes surface, swimming at the raft")
            captureEvent("j-gator-b-reveal", after: 1.4)
        }
        if !hazard.struck, hazard.t >= timing.strikeTime {
            hazard.struck = true
            rt.raft.impulse(-hazard.challenge.correctDirection * timing.strikeImpulse)
            // Impact: the jaws snap shut on the edge (CrocAnimator times the snap to this moment).
            let sideX: CGFloat = hazard.side == .left ? -1 : 1
            splashAt(edge: hazard.side, count: 8, strength: 1.0)
            splashCrown(x: sideX * (JungleRuntime.raftHalfWidth + 0.55), z: JungleRuntime.biteZ + 0.1, size: 1.0)
            waterRing(x: sideX * (JungleRuntime.raftHalfWidth + 0.3), z: JungleRuntime.biteZ, strength: 1)
            rt.rig.run(.sequence([.moveBy(x: 0, y: -10, duration: 0.05), .moveBy(x: 0, y: 10, duration: 0.25).easeOutBack()]))
            audio.play(.chomp, dB: -1)
            audio.play(.impact, dB: -4)
            audio.play(.splash, dB: -5)
            audio.play(.creak, dB: -6)
            showTeamLock(participants: hazard.challenge.team.participants)
            let away = hazard.side == .left ? "RIGHT" : "LEFT"
            showBanner("LEAN \(away)!", sub: "Lean away from the gator together", color: Palette.yellow, hold: 1.4)
            rt.script?.gatorStruck(hazard, scene: self)
            if rt.script == nil, model?.autoplay == true { setAmbientBalancing(true, effort: 1.0) }
            gameLog("gator: STRIKE on the \(hazard.side == .left ? "left" : "right") edge — raft dragged down")
            captureEvent("j-gator-c-strike", after: 0.15)
            captureEvent("j-gator-d-lean", after: 1.0)
        }
        if hazard.struck, !hazard.released, hazard.t >= timing.releaseTime {
            hazard.released = true
            // The croc reads the result as it lets go (the formal result lands a moment later): the team pushed
            // back → it's been shaken off; nobody did → it leaves pleased. A splash later still makes it pleased.
            if hazard.outcome == .pending { hazard.outcome = hazard.challenge.team.contributed.isEmpty ? .won : .beaten }
            gameLog("gator: lets go and sinks")
        }
        if hazard.struck, hazard.challenge.isOpen {
            for zone in Zone.allCases {
                let banked = hazard.challenge.record(zone, lean: rt.leans[zone] ?? 0, dt: dt, at: hazard.t)
                if banked > 0 {
                    lockContributed(zone)
                    addTeamPower(banked)
                    popRating(zone, text: "HOLD!", color: Palette.mint, at: slots[zone]?.headPoint ?? .zero)
                    gameLog("gator: \(role(for: zone)) leaned away (+\(banked) power)")
                }
            }
            if let (outcome, bonus) = hazard.challenge.observe(angle: rt.raft.angle, steadyAngle: rt.raft.params.steadyAngle,
                                                              splashed: false, dt: dt, at: hazard.t) {
                resolveGator(hazard, outcome: outcome, bonus: bonus)
            }
        }
        if hazard.finished || (!hazard.challenge.isOpen && hazard.released) {
            if hazard.t > timing.releaseTime + 0.6, hazard.followUp == nil || hazard.followUpStarted {
                // Gameplay moves on; the retreat keeps playing until the croc is gone.
                hazard.bubbles.forEach { $0.removeFromParent() }
                hazard.bubbles = []
                rt.crocExits.append(hazard)
                rt.gator = nil
            }
        }
    }

    private func resolveGator(_ hazard: GatorHazard, outcome: GatorChallenge.Outcome, bonus: Int) {
        hazard.finished = true
        hazard.finishedAt = hazard.t
        // A splash always pleases it; otherwise keep what it read at the release (no change of mood mid-retreat).
        switch outcome {
        case .splashed: hazard.outcome = .won
        case .cancelled: break
        default: if hazard.outcome == .pending { hazard.outcome = .beaten }
        }
        switch outcome {
        case .teamSteady:
            showBanner("TEAM STEADY!", sub: "You held the raft together!", color: Palette.mint, hold: 1.2)
            audio.play(.team, dB: -2)
            addTeamPower(bonus)
            resolveTeamLock(team: true)
            burstSparks(at: CGPoint(x: size.width / 2, y: proj.screen(x: 0, h: 0.4, z: proj.zp).y + 60), color: Palette.mint, count: 12)
            celebrateWorld()
            gameLog("gator: TEAM STEADY (+\(bonus) bonus); power \(teamPower)/\(teamPowerMax)")
            captureEvent("j-gator-e-team", after: 0.2)
        case .steady(let done, _):
            showBanner("STEADY!", sub: "Lean together for the TEAM bonus", color: Palette.color(for: done.first ?? .left, swapped: swapped), hold: 1.0)
            audio.play(.chime, dB: -4)
            resolveTeamLock(team: false)
            gameLog("gator: steady (partial: \(done.map { role(for: $0) }.sorted().joined(separator: ",")))")
            captureEvent("j-gator-e-steady", after: 0.2)
        case .wobbly:
            showBanner("PHEW!", sub: "The raft is still rocking", color: .white, hold: 0.9)
            resolveTeamLock(team: false)
            gameLog("gator: wobbly (window ran out, no splash)")
        case .splashed:
            resolveTeamLock(team: false)
            gameLog("gator: SPLASHED")
        case .cancelled:
            hideTeamLock()
        }
        if jungleRuntime.script == nil, model?.autoplay == true { setAmbientBalancing(true) }
    }

    private func updateGator(dt: Double) {
        let rt = jungleRuntime
        if let hazard = rt.gator { animateCroc(hazard, dt: dt) }
        for exit in rt.crocExits {
            exit.t += dt
            animateCroc(exit, dt: dt)
        }
        rt.crocExits.removeAll { exit in
            let over = exit.t > rt.gatorTiming.releaseTime + exit.animator.retreatTime + 1.0
            if over { exit.rig.remove() }
            return over
        }
        if rt.gator == nil, rt.crocExits.isEmpty { setRiverCroc(.zero) }
    }

    /// Applies the croc's pose for this frame: lurking shadow → head-on approach → side attack → retreat.
    /// The water answers what it does (wake, rings, splash crowns) and so does the sound.
    private func animateCroc(_ hazard: GatorHazard, dt: Double) {
        let rt = jungleRuntime
        let timing = rt.gatorTiming
        let sideX: CGFloat = hazard.side == .left ? -1 : 1
        // Players lift the bitten edge by leaning away: the croc is hauled up and struggles harder.
        let liftDeg = hazard.side == .left ? rt.raft.angle : -rt.raft.angle
        let pose = hazard.animator.pose(at: hazard.t, lift: liftDeg / 8, outcome: hazard.outcome)
        let k = CGFloat(pose.approach)
        // Head-on approach ends in open water just off the raft's side, level with where it will bite.
        let edgeZ = JungleRuntime.biteZ
        let zA = 16 - (16 - (edgeZ + 0.5)) * k
        let xA = sideX * (2.4 - 0.45 * k) + CGFloat(pose.yaw) * 1.2

        if pose.state != hazard.lastState {
            switch pose.state {
            case .surfacing:
                waterRing(x: xA, z: zA, strength: 0.8)
                audio.play(.gurgle, dB: -9)
            case .anticipation:
                audio.play(.hiss, dB: -7)
            case .lunging:
                waterRing(x: sideX * (JungleRuntime.raftHalfWidth + 0.4), z: edgeZ, strength: 0.9)
                splashCrown(x: sideX * (JungleRuntime.raftHalfWidth + 0.5), z: edgeZ + 0.1, size: 0.9)
                audio.play(.whoosh, dB: -4)
            case .retreat:
                // It lets go, then falls back into the river: the entry splash lands as the body hits the water.
                run(.wait(forDuration: 0.38)) { [weak self] in
                    guard let self else { return }
                    self.splashCrown(x: sideX * (JungleRuntime.raftHalfWidth + 0.7), z: edgeZ - 0.1, size: 1.0)
                    self.waterRing(x: sideX * (JungleRuntime.raftHalfWidth + 0.7), z: edgeZ, strength: 1)
                    self.splashAt(edge: hazard.side, count: 6, strength: 0.6)
                    self.audio.play(.splash, dB: -4)
                }
            default:
                break
            }
            gameLog("croc: \(pose.state.rawValue)")
            hazard.lastState = pose.state
        }

        // Bubbles: the lurking warning, a little ahead on the attack side.
        for (i, b) in hazard.bubbles.enumerated() {
            let z: CGFloat = 9 + CGFloat(i) * 0.9
            let rise = CGFloat((now * 1.3 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1))
            let p = proj.screen(x: sideX * (2.0 + CGFloat(i % 2) * 0.4), h: -0.2 + rise * 0.3, z: z - CGFloat(hazard.t) * jungleCruise * 0.3)
            b.position = p
            b.setScale(proj.ppu(z) * 0.12 / 40)
            b.alpha = hazard.t < timing.revealTime + 0.6 ? (1 - rise) * 0.9 : max(0, b.alpha - 0.05)
            b.zPosition = proj.depthZ(z)
        }

        switch pose.view {
        case .hidden:
            hazard.rig.hideBody()
        case .headOn:
            let water = proj.screen(x: xA, h: -0.22, z: zA)
            hazard.rig.applyHeadOn(pose, waterPoint: water, ppu: proj.ppu(zA) * 0.85, z: proj.depthZ(zA) + 1,
                                   lookX: -sideX * 3, reduceMotion: reduceMotion)
            if Int(now * 6) % 3 == 0, CACurrentMediaTime() - rt.lastRippleAt > 0.25, pose.rise > 0.3 {
                rt.lastRippleAt = CACurrentMediaTime()
                ripple(at: water, width: proj.ppu(zA) * 1.3)
            }
        case .side:
            let edgePoint = proj.screen(x: sideX * JungleRuntime.raftHalfWidth, h: 0.05, z: edgeZ)
            let bite = rt.rig.convert(rt.inner.convert(edgePoint, to: rt.rig), to: self)
            let waterY = proj.screen(x: sideX * (JungleRuntime.raftHalfWidth + 0.3), h: -0.22, z: edgeZ).y
            hazard.rig.applySide(pose, bite: bite, waterY: waterY, ppu: proj.ppu(edgeZ), sideSign: -sideX,
                                 raftRoll: rt.rig.zRotation, frontZ: Layer.pad - 0.8, underZ: Layer.pad - 2.5,
                                 dt: dt, reduceMotion: reduceMotion)
        }

        // The submerged silhouette: gliding in under the surface, then sliding away after the retreat.
        if pose.shadow > 0.01 {
            let lz: CGFloat, lx: CGFloat
            switch pose.state {
            case .lurking: lz = 25 - 9 * CGFloat(pose.lurk); lx = sideX * 2.5
            case .surfacing: lz = zA + 0.4; lx = xA
            default: lz = edgeZ + 0.4 + CGFloat(pose.back) * 2.2; lx = sideX * (1.7 + CGFloat(pose.back) * 0.6)
            }
            hazard.rig.applyShadow(at: proj.screen(x: lx, h: -0.32, z: lz), ppu: proj.ppu(lz), alpha: pose.shadow, heading: 0)
        } else {
            hazard.rig.shadow.alpha = 0
        }

        // River: a V-wake behind the swimming head, a faint pressure wave over the lurking body, thrash foam.
        switch pose.state {
        case .lurking: setRiverCroc(SIMD4(Float(sideX * 2.5), Float(25 - 9 * pose.lurk), 0.35, 0))
        case .surfacing, .swimming, .anticipation:
            setRiverCroc(SIMD4(Float(xA), Float(zA), Float(max(0, min(1, pose.rise))), Float(0.6 + pose.bulge)))
        case .clinging: setRiverCroc(SIMD4(Float(sideX * (JungleRuntime.raftHalfWidth + 0.5)), Float(edgeZ), 0, Float(0.5 + abs(pose.shake) * 6)))
        default: setRiverCroc(.zero)
        }
    }

    // MARK: - Raft visuals

    private func updateRaftVisuals() {
        let rt = jungleRuntime
        let roll = CGFloat(rt.raft.angle)
        let maxVisual: CGFloat = reduceMotion ? 4 : 9
        let visual = max(-maxVisual, min(maxVisual, roll * 0.45)) * .pi / 180
        // Camera stays level; only the raft and riders roll (less disorienting than rolling the world).
        rt.pivot = proj.screen(x: 0, h: -0.1, z: proj.zp + 0.25)
        let bob = reduceMotion ? 0 : sin(CGFloat(now) * 1.4) * 3 + sin(CGFloat(now) * 2.3) * 1.2
        rt.rig.position = CGPoint(x: rt.pivot.x, y: rt.pivot.y + bob)
        rt.inner.position = CGPoint(x: -rt.pivot.x, y: -rt.pivot.y)
        rt.rig.zRotation = mode == .immersive ? -visual : 0

        // Deck: a perspective-warped log platform, plus the logs' round ends along the far edge.
        let hw = JungleRuntime.raftHalfWidth, zNear: CGFloat = 1.2, zFar: CGFloat = 2.75
        // Bow lift (the log's standing wave): the deck pitches about the players' feet, far edge up, near edge down.
        let bow = Double(rt.bowLift) * (reduceMotion ? 0.4 : 1)
        let hNear = CGFloat(LogPath.deckH(z: Double(zNear), bowLift: bow)), hFar = CGFloat(LogPath.deckH(z: Double(zFar), bowLift: bow))
        let c = [proj.screen(x: -hw, h: hNear, z: zNear), proj.screen(x: hw, h: hNear, z: zNear), proj.screen(x: -hw, h: hFar, z: zFar), proj.screen(x: hw, h: hFar, z: zFar)]
        rt.deck.position = c[0]
        rt.deck.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: JungleRuntime.deckSource,
                                                  destinationPositions: WarpQuad.normalized(c, origin: c[0]))
        let e = [proj.screen(x: -hw, h: -0.26 + hFar, z: zFar), proj.screen(x: hw, h: -0.26 + hFar, z: zFar), c[2], c[3]]
        rt.edge.position = e[0]
        rt.edge.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: JungleRuntime.deckSource,
                                                  destinationPositions: WarpQuad.normalized(e, origin: e[0]))
        let mastBase = proj.screen(x: 0, h: hFar * 0.9, z: zFar - 0.1)
        let ppu = proj.ppu(zFar)
        rt.mast.position = mastBase
        rt.mast.size = CGSize(width: max(3, 0.05 * ppu), height: 1.7 * ppu)
        rt.flag.position = CGPoint(x: mastBase.x, y: mastBase.y + 1.55 * ppu)
        rt.flag.size = CGSize(width: 0.5 * ppu, height: 0.3 * ppu)
        rt.flag.xScale = reduceMotion ? 1 : 0.85 + 0.15 * sin(CGFloat(now) * 9)
        for zone in Zone.allCases {
            guard let shadow = rt.contactShadows[zone], let slot = slots[zone] else { continue }
            shadow.position = slot.footPoint
            // Airborne: the contact shadow stays on the deck and shrinks — the gap under the feet reads as height.
            let air = min(1, max(0, CGFloat(slot.jump.lift) / 0.35))
            let w = 0.75 * proj.ppu(proj.zp) * (1 - 0.45 * air)
            shadow.size = CGSize(width: w, height: w * 0.22)
            shadow.alpha = 0.55 * (1 - 0.5 * air)
            shadow.isHidden = mode != .immersive
        }
        // The river answers the raft: the bob drives the lapping foam along the logs (shader), and when the raft
        // rolls hard the low edge plunges into the water — a ring spreads from it, with spray only when it's tipping.
        let tilt = Float(max(-1, min(1, rt.raft.angle / rt.raft.params.dangerAngle)))
        let bobSpeed = reduceMotion ? 0 : abs(cos(CGFloat(now) * 1.4) * 4.2 + cos(CGFloat(now) * 2.3) * 2.8)
        let lap = Float(min(1, bobSpeed / 7 * 0.5 + CGFloat(abs(rt.raft.velocity)) / 40))
        jungle?.riverShader.uniformNamed("u_raft")?.vectorFloat4Value = SIMD4(tilt, lap, 0, 0)
        let plunging = abs(rt.raft.velocity) > 14 && (rt.raft.velocity > 0) == (rt.raft.angle > 0) && abs(rt.raft.angle) > 4
        if plunging, now - rt.lastDunkAt > 0.7 {
            rt.lastDunkAt = now
            let low: CGFloat = rt.raft.angle > 0 ? 1 : -1
            waterRing(x: low * (JungleRuntime.raftHalfWidth + 0.1), z: proj.zp + 0.6, strength: Float(min(1, abs(rt.raft.velocity) / 40)))
            if rt.raft.zone == .danger || rt.raft.zone == .warning { splashAt(edge: low > 0 ? .right : .left, count: 3, strength: 0.5) }
        }
        updateWaterRings()
        rt.splashOverlay.alpha = max(0, rt.splashOverlay.alpha - 0.04)
    }

    /// An expanding ring in the river shader (two slots, round-robin): something hit or left the water here.
    func waterRing(x: CGFloat, z: CGFloat, strength: Float) {
        let rt = jungleRuntime
        rt.waterRings[rt.nextWaterRing] = (Float(x), Float(z), now, strength)
        rt.nextWaterRing = (rt.nextWaterRing + 1) % rt.waterRings.count
    }

    private func updateWaterRings() {
        guard let shader = jungle?.riverShader else { return }
        for (i, r) in jungleRuntime.waterRings.enumerated() {
            shader.uniformNamed("u_ring\(i)")?.vectorFloat4Value = SIMD4(r.x, r.z, Float(min(now - r.t0, 99)), r.strength)
        }
    }

    func setRiverCroc(_ v: SIMD4<Float>) { jungle?.riverShader.uniformNamed("u_croc")?.vectorFloat4Value = v }

    /// The authored splash crown (six frames) standing on the water at a world point.
    func splashCrown(x: CGFloat, z: CGFloat, size: CGFloat) {
        let rt = jungleRuntime
        let crown = rt.splashCrowns[rt.nextCrown]
        rt.nextCrown = (rt.nextCrown + 1) % rt.splashCrowns.count
        crown.removeAllActions()
        crown.position = proj.screen(x: x, h: -0.22, z: z)
        crown.setScale(proj.ppu(z) * size / 280)
        crown.zPosition = Layer.pad - 0.9   // behind the croc: it bursts through its own splash
        crown.isHidden = false
        crown.alpha = 1
        crown.texture = Art.splashCrown[0]
        crown.run(.sequence([.animate(with: Art.splashCrown, timePerFrame: 0.065), .fadeOut(withDuration: 0.15), .hide()]))
    }

    func ripple(at point: CGPoint, width: CGFloat) {
        let rt = jungleRuntime
        let r = rt.ripples[rt.nextRipple]
        rt.nextRipple = (rt.nextRipple + 1) % rt.ripples.count
        r.removeAllActions()
        r.position = point
        r.size = CGSize(width: width * 0.4, height: width * 0.4 * 0.28)
        r.alpha = 0.35
        r.run(.group([.scaleX(to: 2.5, y: 2.5, duration: 1.2), .fadeOut(withDuration: 1.2)]))
    }

    func splashAt(edge: Zone, count: Int, strength: CGFloat) {
        let rt = jungleRuntime
        let sideX: CGFloat = edge == .left ? -1 : 1
        let origin = proj.screen(x: sideX * (JungleRuntime.raftHalfWidth + 0.05), h: -0.1, z: proj.zp + 0.3)
        for _ in 0..<count {
            let d = rt.droplets[rt.nextDroplet]
            rt.nextDroplet = (rt.nextDroplet + 1) % rt.droplets.count
            d.removeAllActions()
            d.isHidden = false
            d.alpha = 0.95
            d.position = CGPoint(x: origin.x + CGFloat.random(in: -40...40), y: origin.y)
            d.setScale(CGFloat.random(in: 0.6...1.2) * (0.6 + strength * 0.5))
            let dx = sideX * CGFloat.random(in: 20...140) * strength
            let dy = CGFloat.random(in: 80...240) * strength
            d.run(.sequence([.group([.moveBy(x: dx, y: dy, duration: 0.28).easeOut(), .fadeAlpha(to: 0.8, duration: 0.28)]),
                             .group([.moveBy(x: dx * 0.4, y: -dy * 0.9, duration: 0.32), .fadeOut(withDuration: 0.32)]), .hide()]))
        }
    }

    private func featherBurst(at point: CGPoint, count: Int) {
        let rt = jungleRuntime
        for i in 0..<count {
            let f = rt.feathers[rt.nextFeather]
            rt.nextFeather = (rt.nextFeather + 1) % rt.feathers.count
            f.removeAllActions()
            f.isHidden = false
            f.alpha = 1
            f.color = [Palette.yellow, Palette.coral, .white, Palette.teal][i % 4]
            f.position = point
            f.setScale(0.5)
            let a = CGFloat.random(in: 0...(2 * .pi))
            f.run(.sequence([.group([.moveBy(x: cos(a) * 90, y: sin(a) * 60 + 40, duration: 0.9).easeOut(),
                                     .rotate(byAngle: CGFloat.random(in: -4...4), duration: 0.9),
                                     .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]), .hide()]))
        }
    }

    /// The jungle answers a shared success: light breaks through, the canopy stirs, a bright flock lifts off.
    func celebrateWorld() {
        let rt = jungleRuntime
        rt.celebrate = reduceMotion ? 0.4 : 1
        jungle?.rustle()
        if !reduceMotion { jungle?.spawnAmbientFlock(proj: proj) }
    }

    private func raftEvent(_ event: RaftEvent) {
        let rt = jungleRuntime
        switch event {
        case .enteredDanger:
            audio.play(.creak, dB: -5)
            gameLog(String(format: "raft: DANGER (%.0f°)", rt.raft.angle))
        case .splash:
            let low: Zone = rt.raft.angle > 0 ? .right : .left
            splashAt(edge: low, count: 18, strength: 1.4)
            if !reduceMotion { rt.splashOverlay.alpha = 0.35 }
            audio.play(.splash, dB: 0)
            showBanner("SPLASH!", sub: "Keep the raft level — lean to the high side", color: Palette.coral, hold: 1.2)
            teamPower = max(0, teamPower - 2)
            updateMeter(animated: true)
            for zone in Zone.allCases { if var slot = slots[zone] { slot.combo = 0; slots[zone] = slot } }
            if let g = rt.gator, g.challenge.isOpen,
               let (outcome, bonus) = g.challenge.observe(angle: rt.raft.angle, steadyAngle: rt.raft.params.steadyAngle,
                                                         splashed: true, dt: 0, at: max(g.t, rt.gatorTiming.strikeTime)) {
                resolveGator(g, outcome: outcome, bonus: bonus)
            }
            gameLog("raft: SPLASH (−2 power); power \(teamPower)/\(teamPowerMax)")
            captureEvent("j-raft-splash", after: 0.15)
        case .steadyStreak:
            // Rewarded only in calm moments (no hazard demanding attention) and never while halted.
            var calm = rt.beat == nil
            if case .calm? = rt.beat { calm = true }
            guard calm, !flow.isHalted else { return }
            addTeamPower(1)
            floatText("STEADY RAFT +1", color: Palette.mint, at: CGPoint(x: size.width / 2, y: 150))
            audio.play(.chime, dB: -12)
            gameLog("raft: steady streak (+1 power)")
        }
    }

    private func updateBalanceHUD() {
        let rt = jungleRuntime
        let a = CGFloat(rt.raft.angle)
        let span: CGFloat = 0.6
        rt.needle.zRotation = -max(-span, min(span, a / rt.raft.params.dangerAngle * span * 0.95))
        let zone = rt.raft.zone
        let dir = rt.raft.recoverDirection
        let show = zone != .steady && dir != 0 && mode == .immersive
        let target: CGFloat = show ? (zone == .danger ? 1 : zone == .warning ? 0.9 : 0.6) : 0
        rt.leanArrow.alpha += (target - rt.leanArrow.alpha) * 0.25
        rt.leanLabel.alpha = rt.leanArrow.alpha
        if show {
            let x = size.width / 2 + CGFloat(dir) * 250
            rt.leanArrow.position = CGPoint(x: x + (reduceMotion ? 0 : CGFloat(dir) * sin(CGFloat(now) * 10) * 8), y: 70)
            rt.leanArrow.xScale = CGFloat(dir) * 0.9
            rt.leanArrow.yScale = 0.9
            rt.leanArrow.color = zone == .danger ? Palette.coral : Palette.yellow
            rt.leanArrow.colorBlendFactor = 0.8
            let text = dir > 0 ? "LEAN RIGHT" : "LEAN LEFT"
            if rt.leanLabel.userData?["t"] as? String != text {
                rt.leanLabel.attributedText = arcadeText(text, size: 22, color: .white, strokeWidth: -5)
                rt.leanLabel.userData = ["t": text]
            }
            rt.leanLabel.position = CGPoint(x: x, y: 128)
        }
        // Edge danger: the low side of the screen glows coral, brighter the closer to a splash.
        let low: CGFloat = a > 0 ? 1 : -1
        rt.edgeWarning.size = CGSize(width: size.width * 0.35, height: size.height * 1.2)
        rt.edgeWarning.position = CGPoint(x: size.width / 2 + low * size.width * 0.55, y: size.height * 0.35)
        let danger = zone == .danger ? 0.35 + 0.35 * CGFloat(rt.raft.dangerTime / rt.raft.params.splashAfter) : zone == .warning ? 0.12 : 0
        rt.edgeWarning.alpha += (danger - rt.edgeWarning.alpha) * 0.2
    }

    // MARK: - Halt / replay

    func withdrawJungleHazards() {
        let rt = jungleRuntime
        if let b = rt.birds {
            b.challenge?.cancel()
            for bird in b.birds {
                bird.rig.node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
                bird.rig.shadow.removeFromParent()
            }
            rt.birds = nil
            gameLog("birds: withdrawn (game halted)")
        }
        if let g = rt.gator {
            g.challenge.cancel()
            for node in [g.rig.crop, g.rig.underCrop, g.rig.shadow, g.rig.collar] + g.bubbles {
                node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
            rt.gator = nil
            gameLog("gator: withdrawn (game halted)")
        }
        if let p = rt.piranhas {
            withdrawPiranhas(p)
            rt.piranhas = nil
            gameLog("piranhas: withdrawn (game halted)")
        }
        if let l = rt.log {
            withdrawLogSweep(l)
            rt.log = nil
            gameLog("log: withdrawn (game halted)")
        }
        if let t = rt.tail {
            withdrawTailSweep(t)
            rt.tail = nil
            gameLog("tail: withdrawn (game halted)")
        }
        for exit in rt.crocExits { exit.rig.remove() }
        rt.crocExits = []
        setRiverCroc(.zero)
        rt.incoming.isHidden = true
        rt.beat = nil
        rt.calmUntil = nil
        rt.nextBeatAt = gameTime + 2.5
        for zone in Zone.allCases { hideCue(zone) }
        hideTeamLock()
    }

    func resetJungle() {
        let rt = jungleRuntime
        withdrawJungleHazards()
        rt.director.reset()
        rt.raft.reset()
        rt.simLeans = [:]
        rt.hazardCounter = 0
        rt.nextBeatAt = gameTime + SessionFlow.countdownDuration + 1.5
    }

    func startJungleScript(sweeps: Bool = UserDefaults.standard.string(forKey: "scenario") == "sweeps") {
        let rt = jungleRuntime
        if rt.script == nil { autoplayBeforeScript = model?.autoplay ?? false }
        rt.script = JungleScript(sweeps: sweeps)
        // The coop script follows the Revision 9 lap (so its 16 steps stay comparable); the sweeps script a playlist.
        rt.director.lap = sweeps ? JungleDirector.cycle : JungleDirector.revision9Cycle
        rt.director.setPlaylist(sweeps ? JungleScript.sweepBeats : nil)
        rt.heldBeat = nil
        model?.scriptRunning = true
        model?.autoplay = false
        for zone in Zone.allCases { slots[zone]?.simLost = false }
        replay(source: "jungle script start")
        setAmbientBalancing(true)
    }

    /// The cue over a player's head: chevrons pointing down (DUCK) or up (JUMP).
    func showCue(_ zone: Zone, up: Bool) {
        guard let cue = hudNodes.cues[zone] else { return }
        cue.removeAllActions()
        cue.alpha = 1
        cue.color = Palette.color(for: zone, swapped: swapped)
        cue.zRotation = up ? .pi : 0
        cue.setScale(0.2)
        cue.isHidden = false
        cue.run(.scale(to: 1, duration: 0.25).easeOutBack())
    }
}

/// Deterministic Jungle Drift test script — one step per director beat. Times are relative to that beat's DUCK cue
/// (birds) or the alligator's strike (leans). Simulated input only; never evidence of tracking accuracy.
@MainActor
final class JungleScript {
    enum Lean { case none, respond(delay: Double, effort: Double), wrongWay(delay: Double) }
    enum Control {
        case none, pauseAfterCue(Double, resume: Double), loseTracking(Zone, afterStart: Double, recover: Double, resume: Double), replayAfter(Double)
        /// Piranhas: pause this long into the WARNING (before anything leaps), resume `resume` s later.
        case pauseInPiranhaWarning(Double, resume: Double)
        /// Piranhas: start a new session while the first fish is in the air.
        case replayMidLeap(afterLaunch: Double)
        /// Pause this long after the beat starts (inside its WARNING), resume `resume` s later.
        case pauseInWarning(Double, resume: Double)
    }
    struct Step {
        var name: String
        var duckLeft: Double? = nil
        var duckRight: Double? = nil
        var leanLeft: Lean = .none
        var leanRight: Lean = .none
        /// Piranhas: per leap, each player's takeoff relative to the fish reaching their lane (nil = no jump).
        /// Around −0.3 is on time; −1.1 lands before the fish arrives (TOO EARLY); +0.3 is TOO LATE.
        var jumpLeft: [Double?] = []
        var jumpRight: [Double?] = []
        var control: Control = .none
    }

    /// One step per director beat, in cycle order (see JungleDirector.cycle), then a second lap with mirrored sides
    /// and one more fish per burst, then a replay and the first two beats of the new session.
    static let steps: [Step] = [
        Step(name: "birds: both duck", duckLeft: 0.3, duckRight: 1.1),
        Step(name: "piranhas LEFT ×1 right after the birds: both jump on time → TEAM JUMP", jumpLeft: [-0.3], jumpRight: [-0.35]),
        Step(name: "gator LEFT: both lean away", leanLeft: .respond(delay: 0.2, effort: 1), leanRight: .respond(delay: 0.6, effort: 1)),
        Step(name: "calm stretch with a landmark (both keep balancing)"),
        Step(name: "gator RIGHT, then piranhas from the LEFT as the raft settles: both lean; Parent jumps on time, Child TOO EARLY",
             leanLeft: .respond(delay: 0.2, effort: 1), leanRight: .respond(delay: 0.5, effort: 1), jumpLeft: [-0.3], jumpRight: [-1.1]),
        Step(name: "birds: Child late → bonk wobble, then rebalance", duckLeft: 0.4, duckRight: 2.8),
        Step(name: "piranhas RIGHT ×2: leap 1 Parent TOO LATE + Child no jump → CHOMP; leap 2 both clear → TEAM",
             jumpLeft: [0.3, -0.3], jumpRight: [nil, -0.25]),
        Step(name: "gator LEFT + birds: only Parent leans; then both duck", duckLeft: 0.4, duckRight: 0.9,
             leanLeft: .respond(delay: 0.3, effort: 1), leanRight: .none),
        Step(name: "calm: Child's tracking lost and recovered", control: .loseTracking(.right, afterStart: 1.0, recover: 2.0, resume: 1.5)),
        Step(name: "lap 2 — birds: pause inside the DUCK window", duckLeft: 0.4, control: .pauseAfterCue(0.9, resume: 2.0)),
        Step(name: "piranhas RIGHT ×2: pause during the WARNING → withdrawn, resume cleanly", control: .pauseInPiranhaWarning(0.9, resume: 2.0)),
        Step(name: "gator RIGHT: nobody leans → SPLASH", leanLeft: .none, leanRight: .none),
        Step(name: "calm stretch with a landmark"),
        Step(name: "gator LEFT, then piranhas from the RIGHT: both lean, then replay with the fish in the air",
             leanLeft: .respond(delay: 0.2, effort: 1), leanRight: .respond(delay: 0.4, effort: 1), jumpLeft: [-0.3], jumpRight: [-0.3],
             control: .replayMidLeap(afterLaunch: 0.3)),
        Step(name: "new session: birds, both duck", duckLeft: 0.4, duckRight: 0.7),
        Step(name: "new session: piranhas LEFT ×1, both jump → fresh ids and counters", jumpLeft: [-0.3], jumpRight: [-0.3]),
    ]

    /// The River Log Sweep / Crocodile Tail Sweep script (`-scenario sweeps`): a fixed playlist of beats.
    static let sweepBeats: [JungleBeat] = [.logSweep, .calm(landmark: false), .tailSweep(.right), .birds, .logSweep, .tailSweep(.left),
                                           .gatorThenTail(.right), .logSweep, .tailSweep(.right), .piranhas(from: .left, count: 1),
                                           .logSweep, .tailSweep(.left), .logSweep]
    static let sweepSteps: [Step] = [
        Step(name: "LOG: both jump on time → TEAM JUMP (warning, reveal, drift, the wave lifts it, roll, exit)", jumpLeft: [-0.3], jumpRight: [-0.3]),
        Step(name: "calm: the bow settles, the river carries on"),
        Step(name: "TAIL RIGHT: both jump on time → TEAM; the croc overshoots and is dizzy", jumpLeft: [-0.3], jumpRight: [-0.3]),
        Step(name: "birds: both duck (DUCK still works between jumps)", duckLeft: 0.3, duckRight: 0.8),
        Step(name: "LOG: Parent TOO EARLY, Child TOO LATE → both bumped, no power lost", jumpLeft: [-1.2], jumpRight: [0.35]),
        Step(name: "TAIL LEFT: only the Child jumps → partial; the Parent is swept, the croc is pleased", jumpLeft: [nil], jumpRight: [-0.3]),
        Step(name: "COMBO: gator RIGHT rams (both lean), the raft steadies, it comes back with the TAIL → both jump",
             leanLeft: .respond(delay: 0.2, effort: 1), leanRight: .respond(delay: 0.4, effort: 1), jumpLeft: [-0.3], jumpRight: [-0.25]),
        Step(name: "LOG: pause during the WARNING → withdrawn, resume cleanly", control: .pauseInWarning(1.0, resume: 2.0)),
        Step(name: "TAIL RIGHT: Child's tracking lost during the coil → withdrawn → READY → resume",
             control: .loseTracking(.right, afterStart: 3.0, recover: 2.0, resume: 1.5)),
        Step(name: "piranhas LEFT ×1: both jump (piranhas unchanged)", jumpLeft: [-0.3], jumpRight: [-0.35]),
        Step(name: "LOG: nobody jumps → both bumped"),
        Step(name: "TAIL LEFT: both jump, then replay", jumpLeft: [-0.3], jumpRight: [-0.3], control: .replayAfter(1.5)),
        Step(name: "new session: LOG, both jump → fresh ids and counters", jumpLeft: [-0.35], jumpRight: [-0.25]),
    ]

    let steps: [Step]
    init(sweeps: Bool = false) { steps = sweeps ? Self.sweepSteps : Self.steps }

    private(set) var index = 0
    private var current: Step?
    private var timers: [(fireAt: Double, real: Bool, action: (WorldScene) -> Void)] = []
    var isFinished: Bool { index >= steps.count && timers.isEmpty }

    func beatStarted(_ beat: JungleBeat, scene: WorldScene) {
        guard index < steps.count else { current = nil; return }
        let step = steps[index]
        index += 1
        current = step
        scene.gameLog("jungle script step \(index)/\(steps.count): \(step.name)")
        scene.setAmbientBalancing(true)
        if case .pauseInWarning(let at, let resume) = step.control {
            schedule(at: scene.gameTime + at, real: false) { scene in
                scene.pauseGame(source: "jungle script")
                self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "jungle script") }
            }
        }
        if case .loseTracking(let zone, let after, let recover, let resume) = step.control {
            schedule(at: scene.gameTime + after, real: false) { scene in
                scene.setSimulatedTrackingLost(zone, lost: true)
                self.schedule(at: scene.now + recover + 0.6, real: true) { scene in
                    scene.setSimulatedTrackingLost(zone, lost: false)
                    self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "jungle script") }
                }
            }
        }
    }

    func birdsWarned(scene: WorldScene) {}

    func birdsCued(scene: WorldScene) {
        guard let step = current else { return }
        for (zone, t) in [(Zone.left, step.duckLeft), (.right, step.duckRight)] {
            guard var slot = scene.slots[zone] else { continue }
            slot.botPlanned = t.map { scene.gameTime + $0 }
            slot.botPeak = 0.85
            scene.slots[zone] = slot
        }
        if case .pauseAfterCue(let at, let resume) = step.control {
            schedule(at: scene.gameTime + at, real: false) { scene in
                scene.pauseGame(source: "jungle script")
                self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "jungle script") }
            }
        }
    }

    func piranhasWarned(_ hazard: PiranhaHazard, scene: WorldScene) {
        guard let step = current, case .pauseInPiranhaWarning(let at, let resume) = step.control else { return }
        schedule(at: scene.gameTime + at, real: false) { scene in
            scene.pauseGame(source: "jungle script")
            self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "jungle script") }
        }
    }

    /// Plans each player's takeoff on the encounter clock: `offset` from the fish reaching their lane, minus the
    /// simulated crouch so the feet leave the deck exactly at that moment.
    func piranhasCued(_ hazard: PiranhaHazard, scene: WorldScene) {
        guard let step = current else { return }
        let crouch = SimulatedJump(start: 0).crouch
        for (zone, plan) in [(Zone.left, step.jumpLeft), (.right, step.jumpRight)] {
            for (i, offset) in plan.enumerated() where i < hazard.leaps.count {
                guard let offset else { continue }
                hazard.plannedJumps.append((zone, hazard.leaps[i].crossing(zone) + offset - crouch))
            }
        }
        if case .replayMidLeap(let after) = step.control {
            let at = scene.gameTime + (scene.jungleRuntime.piranhaTiming.launchTime(0) - hazard.t) + after
            schedule(at: at, real: false) { $0.replay(source: "jungle script (mid-leap)") }
        }
    }

    func leapResolved(_ hazard: PiranhaHazard, leap: Int, scene: WorldScene) {}

    func sweepWarned(_ hazard: SweepHazard, scene: WorldScene) {}

    /// Log / tail: each player's takeoff `offset` from the hazard reaching their lane, minus the simulated crouch.
    func sweepCued(_ hazard: SweepHazard, crossings: [Zone: Double], scene: WorldScene) {
        guard let step = current else { return }
        let crouch = SimulatedJump(start: 0).crouch
        for (zone, plan) in [(Zone.left, step.jumpLeft), (.right, step.jumpRight)] {
            guard let first = plan.first, let offset = first, let crossing = crossings[zone] else { continue }
            hazard.plannedJumps.append((zone, crossing + offset - crouch))
        }
    }

    func gatorWarned(_ hazard: GatorHazard, scene: WorldScene) {
        // Until the strike, players are just riding (gentle balancing only).
    }

    func gatorStruck(_ hazard: GatorHazard, scene: WorldScene) {
        guard let step = current else { return }
        let rt = scene.jungleRuntime
        for (zone, plan) in [(Zone.left, step.leanLeft), (.right, step.leanRight)] {
            switch plan {
            case .none:
                rt.botLeanFrom[zone] = nil
            case .respond(let delay, let effort):
                rt.botLeanFrom[zone] = scene.gameTime + delay
                rt.botLeanEffort[zone] = effort
            case .wrongWay(let delay):
                rt.botLeanFrom[zone] = nil
                rt.simLeans[zone] = SimulatedLean(start: scene.gameTime + delay, direction: -hazard.challenge.correctDirection, hold: 2)
            }
        }
    }

    func beatFinished(scene: WorldScene) {
        if case .replayAfter(let delay)? = current?.control {
            schedule(at: scene.now + delay, real: true) { $0.replay(source: "jungle script") }
        }
    }

    func tick(scene: WorldScene) {
        let due = timers.enumerated().filter { $0.element.fireAt <= ($0.element.real ? scene.now : scene.gameTime) }
        guard !due.isEmpty else { return }
        timers = timers.enumerated().filter { item in !due.contains { $0.offset == item.offset } }.map(\.element)
        for item in due { item.element.action(scene) }
    }

    private func schedule(at time: Double, real: Bool, _ action: @escaping (WorldScene) -> Void) {
        timers.append((time, real, action))
    }
}

extension WorldScene {
    /// Movement events in Jungle Drift. Same separation as Stunt Run: descent = provisional, bottom inside the bird
    /// window = the contribution (once), standing up = the counted rep. Leaning is read continuously (updateLeans).
    func handleJungle(_ event: SquatEvent, zone: Zone) {
        let rt = jungleRuntime
        let birds = rt.birds.flatMap { $0.cued && !$0.resolved ? $0 : nil }
        switch event {
        case .descentStarted:
            if let birds, birds.challenge?.movementStarted(zone) == true {
                lockProvisional(zone)
            } else {
                padPulse(zone)
            }
        case .bottomReached:
            if let birds, let banked = birds.challenge?.contribute(zone, at: gameTime), banked > 0 {
                lockContributed(zone)
                addTeamPower(banked)
                popRating(zone, text: "DUCKED!", color: Palette.mint, at: slots[zone]?.headPoint ?? .zero)
                gameLog("birds: \(role(for: zone)) ducked (+\(banked) power)")
                captureEvent("j-birds-d-duck-\(role(for: zone))", after: 0.15)
            }
        case .repCompleted:
            repCompleted(zone)
            gameLog("\(role(for: zone)) rep completed (total \(slots[zone]?.squats ?? 0))")
        case .aborted:
            if let birds, let c = birds.challenge, c.isOpen, c.started.contains(zone), !c.contributed.contains(zone) {
                popRating(zone, text: "GO DEEPER!", color: Palette.yellow, at: slots[zone]?.headPoint ?? .zero)
            }
        case .found, .lost:
            break
        }
    }
}
