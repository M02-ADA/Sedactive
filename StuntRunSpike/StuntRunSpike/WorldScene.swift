import QuartzCore
import SpriteKit

/// Pseudo-3D camera: everything is placed in world units (x right, h up from the train roof, z forward)
/// and projected with a pinhole model. Camera-facing billboards only need a position and a uniform scale,
/// so ordinary SKSpriteNodes get exact perspective and batch well.
struct Projection {
    var cx: CGFloat = 0
    var horizonY: CGFloat = 0
    var feetY: CGFloat = 0
    /// Camera height above the roof, in world units. Lower than an adult's head so overhead beams sweep up and out of frame.
    var camH: CGFloat = 1.0
    /// Depth of the plane where the players stand. Closer than before (2.5 → 1.9) for a wider ~70° field of view:
    /// the player plane looks identical, but everything beyond it gains stronger scale change as it approaches.
    let baseZp: CGFloat = 1.9
    var zp: CGFloat = 1.9
    var f: CGFloat = 1
    /// Dolly zoom: < 1 widens the field of view around the fixed player plane (used as a speed-boost FOV kick).
    var fovScale: CGFloat = 1
    /// Track curvature: world x shifts by curve·(z − zp)² beyond the players, so the far track bends while the
    /// roof under the players stays straight (the classic arcade-racer road curve).
    var curve: CGFloat = 0

    mutating func configure(size: CGSize) {
        cx = size.width / 2
        horizonY = size.height * 0.56
        feetY = size.height * 0.085
        recompute()
    }

    mutating func recompute() {
        zp = baseZp * fovScale
        f = (horizonY - feetY) * zp / camH
    }

    /// Points per world unit at depth z.
    func ppu(_ z: CGFloat) -> CGFloat { f / max(z, 0.05) }

    func bend(_ z: CGFloat) -> CGFloat {
        let d = max(0, z - zp)
        return curve * d * d
    }

    func screen(x: CGFloat, h: CGFloat, z: CGFloat) -> CGPoint {
        let zz = max(z, 0.05)
        return CGPoint(x: cx + f * (x + bend(z)) / zz, y: horizonY - f * (camH - h) / zz)
    }

    /// Draw order: nearer than the player plane draws in front of the bodies (zPosition 0).
    func depthZ(_ z: CGFloat) -> CGFloat { (zp - z) * 10 }
}

enum Layer {
    static let sky: CGFloat = -3000
    static let clouds: CGFloat = -2900
    static let mountains: CGFloat = -2800
    static let skyline: CGFloat = -2700
    static let horizonGlow: CGFloat = -2650
    static let floor: CGFloat = -2600
    static let camera: CGFloat = -1500
    static let pad: CGFloat = -0.5
    static let body: CGFloat = 0
    static let flash: CGFloat = 2900
    static let hud: CGFloat = 3000
}

/// A billboard that streams toward the camera and is recycled to the back when it passes.
final class Prop {
    enum Kind { case pylon, arch }
    let kind: Kind
    let node: SKSpriteNode
    var x: CGFloat
    var h: CGFloat
    var z: CGFloat
    var heightUnits: CGFloat

    init(kind: Kind, texture: SKTexture, x: CGFloat, h: CGFloat, z: CGFloat, heightUnits: CGFloat) {
        self.kind = kind
        node = SKSpriteNode(texture: texture)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        self.x = x
        self.h = h
        self.z = z
        self.heightUnits = heightUnits
    }
}

/// Free-flying world-space particle (team-success shards, speed lines).
final class Particle3D {
    let node: SKSpriteNode
    var x: CGFloat = 0, h: CGFloat = 0, z: CGFloat = 0
    var vx: CGFloat = 0, vh: CGFloat = 0, vz: CGFloat = 0
    var spin: CGFloat = 0
    var life: CGFloat = 0
    var sizeUnits: CGFloat = 0.2

    init(texture: SKTexture) {
        node = SKSpriteNode(texture: texture)
        node.isHidden = true
    }
}

final class WorldScene: SKScene {
    weak var model: GameModel?
    var pipeline: CameraPipeline?
    var inputSource: CameraPipeline.Source = .none
    let audio = AudioFX()

    var proj = Projection()
    let farZ: CGFloat = 100
    let roofHalf: CGFloat = 1.6
    let groundDrop: CGFloat = 1.8
    let playerX: CGFloat = 0.65
    let baseSpeed: CGFloat = 10
    /// The train is a fixed set of carriages carrying the players; its front (and the locomotive) sits this far ahead.
    let trainFront: CGFloat = 24
    let locomotive = SKSpriteNode(texture: Art.locomotiveRear)

    // World.
    let worldRoot = SKNode()
    let sky = SKSpriteNode(texture: Art.white)
    let floorNode = SKSpriteNode(texture: Art.white)
    let mountains = SKSpriteNode(texture: Art.mountains)
    let skyline = SKSpriteNode(texture: Art.skyline)
    let horizonGlow = SKSpriteNode(texture: Art.glow)
    var clouds: [SKSpriteNode] = []
    var props: [Prop] = []
    var streaks: [Particle3D] = []
    var shards: [Particle3D] = []
    var buildings: [VolumeBuilding] = []
    var landmark: Landmark?
    var nextLandmarkAt: CGFloat = 25
    var landmarkCycle = 0
    var signAngle: CGFloat = 0
    var tunnelRings: [SKSpriteNode] = []
    var tunnelActive = false
    var tunnelDim: CGFloat = 0
    var searchlights: [SKSpriteNode] = []
    var fireworks: [SKSpriteNode] = []
    var nextFirework = 0
    var skyPan: CGFloat = 0
    var laneWarn: CGFloat = 0
    let floorShader = Shaders.floor()
    let skyShader = Shaders.sky()

    // Players.
    let bodyTexture = SKMutableTexture(size: CGSize(width: CameraPipeline.outputWidth, height: CameraPipeline.outputHeight))
    lazy var bodySprite = SKSpriteNode(texture: bodyTexture)
    lazy var cameraSprite = SKSpriteNode(texture: bodyTexture)
    var bodyRect = CGRect.zero
    var cameraRect = CGRect.zero
    var placeholders: [Zone: SKSpriteNode] = [:]
    var pads: [Zone: SKSpriteNode] = [:]
    var padLabels: [Zone: SKLabelNode] = [:]
    lazy var bodyShadow = SKSpriteNode(texture: bodyTexture)
    var placeholderShadows: [Zone: SKSpriteNode] = [:]
    var contactShadows: [Zone: SKSpriteNode] = [:]
    var slots: [Zone: PlayerSlot] = [.left: PlayerSlot(zone: .left), .right: PlayerSlot(zone: .right)]
    var zoneTracker = ZoneTracker()

    // Gameplay.
    var gates: [Gate] = []
    var distance: CGFloat = 0
    /// Obstacle sequence timing (provisional; configurable with launch arguments, see EncounterTiming).
    let timing = EncounterTiming.fromDefaults()
    var encounter: Encounter?
    /// Game-time at which the next encounter's warning may begin.
    var nextWarningAt: TimeInterval = 4.5
    /// "Something is coming" marker pulsing at the far end of the track during the warning phase.
    let incomingMarker = SKLabelNode()
    var worldSpeed: CGFloat = 0
    var boostUntil: TimeInterval = 0
    var boostMultiplier: CGFloat = 1
    var teamPower = 0
    let teamPowerMax = 10
    var palettePhase: CGFloat = 0
    var palettePhaseTarget: CGFloat = 0
    /// Play state (running / paused / tracking lost / ready / countdown) and session number.
    var flow = SessionFlow(startingAt: 0)
    /// Gameplay clock: advances only while the world is not halted. Simulated input and scripts run on it.
    var gameTime: TimeInterval = 0
    var isWorldPaused: Bool { flow.isHalted }
    var challengeCounter = 0
    var resolvedCount = 0
    /// Players tracked at least once this run; losing one of them suspends the game.
    var roster: Set<Zone> = []
    var sessionDistanceStart: CGFloat = 0
    var script: ScenarioScript?
    var lastFlowState: PlayState?
    var lastCountdownShown: Int?
    var lockCount = 0
    var pendingTurbo = false
    var autoplayBeforeScript = false
    // Hero TEAM DUCK.
    lazy var teamDuckBake = TeamDuckBake()
    var hitStopUntil: TimeInterval = 0
    var heroStart: TimeInterval?
    var heroFrames: [Double] = []
    let logStart = CACurrentMediaTime()
    var lockTotal = 0
    var shakeUntil: TimeInterval = 0
    var shakeAmplitude: CGFloat = 0
    var skyClock: CGFloat = 0

    // HUD.
    let hud = SKNode()
    var hudNodes = HUDNodes()
    let flash = SKSpriteNode(texture: Art.white)
    var sparks: [SKSpriteNode] = []
    var nextSpark = 0

    // Frame and pipeline bookkeeping.
    var lastUpdate: TimeInterval = 0
    var now: TimeInterval = 0
    var lastSnapshotSequence: UInt64 = 0
    var lastSnapshot: VisionSnapshot?
    var lastMode: ViewMode?
    var lastSwap: Bool?
    var lastReduceMotion: Bool?
    var bodyLayoutTarget: (height: CGFloat, minY: CGFloat)?
    var meter = MetricsAccumulator()
    var lastEvidenceCapture: TimeInterval = 0
    var evidenceCount = 0

    /// Which game this scene plays. Set before the scene is presented (the dev panel recreates the scene to switch).
    var gameMode: GameMode = .stuntRun
    var jungle: JungleWorld?
    lazy var jungleRuntime = JungleRuntime()
    var anyScriptRunning: Bool { script != nil || (gameMode == .jungleDrift && jungleRuntime.script != nil) }

    var reduceMotion: Bool { model?.reduceMotion ?? false }
    var mode: ViewMode { model?.mode ?? .immersive }
    var swapped: Bool { model?.swapRoles ?? false }

    override func didMove(to view: SKView) {
        backgroundColor = Palette.deepNavy
        anchorPoint = .zero
        worldSpeed = baseSpeed
        flow = SessionFlow(startingAt: CACurrentMediaTime())
        if gameMode == .jungleDrift {
            buildPlayers()
            buildJungle()
        } else {
            _ = teamDuckBake   // load + preload the baked sheet before it is needed
            buildWorld()
            buildPlayers()
            buildEnvironment()
        }
        buildHUD()
        layoutForSize()
        if ["coop", "sweeps"].contains(UserDefaults.standard.string(forKey: "scenario")) {
            run(.wait(forDuration: 1.0)) { [weak self] in self?.startScript() }
        }
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        audio.stopAmbience()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, worldRoot.parent != nil else { return }
        layoutForSize()
    }

    // MARK: - Build

    private func buildWorld() {
        addChild(worldRoot)

        sky.anchorPoint = .zero
        sky.shader = skyShader
        sky.zPosition = Layer.sky
        worldRoot.addChild(sky)

        floorNode.anchorPoint = .zero
        floorNode.shader = floorShader
        floorNode.zPosition = Layer.floor
        worldRoot.addChild(floorNode)

        for (node, z) in [(mountains, Layer.mountains), (skyline, Layer.skyline)] {
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.zPosition = z
            worldRoot.addChild(node)
        }
        horizonGlow.zPosition = Layer.horizonGlow
        horizonGlow.color = Palette.coral
        horizonGlow.colorBlendFactor = 1
        horizonGlow.alpha = 0.55
        horizonGlow.blendMode = .add
        worldRoot.addChild(horizonGlow)

        var rng = SeededRandom(seed: 99)
        for i in 0..<5 {
            let cloud = SKSpriteNode(texture: Art.cloud)
            cloud.zPosition = Layer.clouds
            cloud.color = i % 2 == 0 ? Palette.coral : Palette.violet
            cloud.colorBlendFactor = 0.55
            cloud.alpha = 0.22 + 0.12 * CGFloat(rng.next())
            // Clouds drift outward from the vanishing point (forward travel), not sideways.
            cloud.userData = ["angle": 0.35 + 2.4 * rng.next(), "r": 0.15 + 0.8 * rng.next(), "base": 0.22 + 0.12 * rng.next()]
            worldRoot.addChild(cloud)
            clouds.append(cloud)
        }

        // Streaming props, evenly spaced along z so the rhythm reads as speed.
        for side in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<25 {
                let pylon = Prop(kind: .pylon, texture: Art.pylon, x: side * 2.35, h: -groundDrop, z: CGFloat(i) * 4 + 2, heightUnits: 3.5)
                props.append(pylon)
            }
        }
        for i in 0..<3 {
            props.append(Prop(kind: .arch, texture: Art.arch, x: 0, h: -groundDrop, z: CGFloat(i) * 33 + 20, heightUnits: 5.8))
        }
        for prop in props { worldRoot.addChild(prop.node) }

        locomotive.anchorPoint = CGPoint(x: 0.5, y: 0)
        worldRoot.addChild(locomotive)
        incomingMarker.attributedText = arcadeText("!", size: 64, color: Palette.yellow, strokeWidth: -5)
        incomingMarker.verticalAlignmentMode = .center
        incomingMarker.zPosition = Layer.flash - 10
        incomingMarker.isHidden = true
        worldRoot.addChild(incomingMarker)

        for _ in 0..<40 {
            let streak = Particle3D(texture: Art.streak)
            streak.node.blendMode = .add
            streak.node.color = Palette.teal
            streak.node.colorBlendFactor = 0.35
            respawnStreak(streak, anywhere: true)
            worldRoot.addChild(streak.node)
            streaks.append(streak)
        }
        for _ in 0..<36 {
            let shard = Particle3D(texture: Art.shard)
            shard.node.colorBlendFactor = 1
            addChild(shard.node)
            shards.append(shard)
        }
    }

    private func buildPlayers() {
        bodyTexture.filteringMode = .linear
        bodySprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        bodySprite.zPosition = Layer.body
        bodySprite.isHidden = true
        addChild(bodySprite)

        cameraSprite.zPosition = Layer.camera
        cameraSprite.isHidden = true
        addChild(cameraSprite)

        for zone in Zone.allCases {
            let placeholder = SKSpriteNode()
            placeholder.anchorPoint = CGPoint(x: 0.5, y: 0)
            placeholder.zPosition = Layer.body + 0.1
            addChild(placeholder)
            placeholders[zone] = placeholder

            let pad = SKSpriteNode(texture: Art.pad)
            pad.colorBlendFactor = 1
            pad.zPosition = Layer.pad
            pad.blendMode = .add
            addChild(pad)
            pads[zone] = pad

            let label = SKLabelNode()
            label.zPosition = Layer.pad + 0.1
            label.verticalAlignmentMode = .center
            addChild(label)
            padLabels[zone] = label
        }
        applyRoleStyling()
    }

    func applyRoleStyling() {
        for zone in Zone.allCases {
            let color = Palette.color(for: zone, swapped: swapped)
            let isChild = (zone == .right) != swapped
            placeholders[zone]?.texture = Art.placeholder(color: color, child: isChild)
            placeholders[zone]?.size = placeholders[zone]?.texture?.size() ?? .zero
            pads[zone]?.color = color
            padLabels[zone]?.attributedText = arcadeText(zone == .left ? "P1" : "P2", size: 22, color: .white, strokeWidth: -6)
            hudNodes.cards[zone]?.texture = Art.card(color: color)
            hudNodes.roleLabels[zone]?.attributedText = arcadeText(role(for: zone), size: 22, color: .white, strokeWidth: -5)
        }
        pipeline?.rimColorsSwapped = swapped
        layoutPlaceholders()
    }

    func role(for zone: Zone) -> String { (zone == .left) != swapped ? "PARENT" : "CHILD" }

    // MARK: - Layout

    private func layoutForSize() {
        proj.configure(size: size)
        sky.position = CGPoint(x: 0, y: proj.horizonY - 2)
        sky.size = CGSize(width: size.width, height: size.height - proj.horizonY + 2)
        floorNode.position = .zero
        floorNode.size = CGSize(width: size.width, height: proj.horizonY)

        mountains.size = CGSize(width: size.width * 1.35, height: size.height * 0.17)
        mountains.position = CGPoint(x: proj.cx, y: proj.horizonY - 3)
        skyline.size = CGSize(width: size.width * 1.25, height: size.height * 0.12)
        skyline.position = CGPoint(x: proj.cx, y: proj.horizonY - 3)
        horizonGlow.size = CGSize(width: size.width * 1.6, height: size.height * 0.1)
        horizonGlow.position = CGPoint(x: proj.cx, y: proj.horizonY)

        flash.size = size
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)

        // Mode A: aspect-fill the raw camera image.
        let aspect = CGFloat(CameraPipeline.outputWidth) / CGFloat(CameraPipeline.outputHeight)
        let fillSize = size.width / size.height > aspect
            ? CGSize(width: size.width, height: size.width / aspect)
            : CGSize(width: size.height * aspect, height: size.height)
        cameraSprite.size = fillSize
        cameraSprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cameraRect = CGRect(x: (size.width - fillSize.width) / 2, y: (size.height - fillSize.height) / 2,
                            width: fillSize.width, height: fillSize.height)

        // Default cutout placement until poses arrive: feet near the player plane.
        let defaultHeight = size.height * 0.95
        setBodyRect(height: defaultHeight, minY: proj.feetY - defaultHeight * 0.06)

        updateShaderUniforms()
        layoutPlaceholders()
        layoutHUD()
        if gameMode == .jungleDrift { layoutJungle() }
    }

    func setBodyRect(height: CGFloat, minY: CGFloat) {
        let width = height * CGFloat(CameraPipeline.outputWidth) / CGFloat(CameraPipeline.outputHeight)
        bodySprite.size = CGSize(width: width, height: height)
        bodySprite.position = CGPoint(x: proj.cx, y: minY)
        bodyRect = CGRect(x: proj.cx - width / 2, y: minY, width: width, height: height)
    }

    func layoutPlaceholders() {
        let ppu = proj.ppu(proj.zp)
        for zone in Zone.allCases {
            guard let placeholder = placeholders[zone], let texture = placeholder.texture else { continue }
            let isChild = (zone == .right) != swapped
            let heightUnits: CGFloat = isChild ? 0.82 : 1.18
            let scale = heightUnits * ppu / texture.size().height
            placeholder.size = CGSize(width: texture.size().width * scale, height: texture.size().height * scale)
            placeholder.position = proj.screen(x: zone == .left ? -playerX : playerX, h: 0, z: proj.zp)
        }
    }

    func updateShaderUniforms() {
        let res = SIMD2<Float>(Float(floorNode.size.width), Float(floorNode.size.height))
        floorShader.uniformNamed("u_res")?.vectorFloat2Value = res
        floorShader.uniformNamed("u_horizon")?.floatValue = Float(proj.horizonY)
        floorShader.uniformNamed("u_cx")?.floatValue = Float(proj.cx)
        floorShader.uniformNamed("u_f")?.floatValue = Float(proj.f)
        floorShader.uniformNamed("u_camH")?.floatValue = Float(proj.camH)
        floorShader.uniformNamed("u_drop")?.floatValue = Float(groundDrop)
        floorShader.uniformNamed("u_roofHalf")?.floatValue = Float(roofHalf)
        floorShader.uniformNamed("u_trainFront")?.floatValue = Float(trainFront)
        skyShader.uniformNamed("u_res")?.vectorFloat2Value = SIMD2<Float>(Float(sky.size.width), Float(sky.size.height))
        skyShader.uniformNamed("u_cx")?.floatValue = Float(proj.cx)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(0.1, currentTime - lastUpdate)
        lastUpdate = currentTime
        now = CACurrentMediaTime()
        meter.recordFrame(dt: dt)
        recordHeroFrame(dt: dt)
        // Hit-stop freezes world motion only; input, detectors and the game clock keep running.
        let motionDT = now < hitStopUntil ? 0 : dt

        syncSettings()
        updateFlow(dt: dt)
        pollPipeline()
        updateInputs(dt: dt)
        updateSpeed(dt: dt)
        if gameMode == .jungleDrift {
            updateJungle(dt: CGFloat(dt), motionDT: CGFloat(motionDT))
        } else {
            advanceWorld(dt: CGFloat(motionDT))
            updateGates(dt: CGFloat(motionDT))
        }
        updatePlayersVisuals(dt: CGFloat(dt))
        updatePlayerShadows()
        updateHUD(dt: CGFloat(dt))
        updateShake()
        publishMetricsIfNeeded()
    }

    private func syncSettings() {
        guard let model else { return }
        if lastMode != model.mode {
            lastMode = model.mode
            let immersive = model.mode == .immersive
            pipeline?.wantsCutout = immersive
            for node in [sky, floorNode, mountains, skyline, horizonGlow] as [SKNode] { node.isHidden = !immersive }
            for cloud in clouds { cloud.isHidden = !immersive }
            for prop in props { prop.node.isHidden = !immersive }
            locomotive.isHidden = !immersive
            if !immersive { bodySprite.isHidden = true }
            setEnvironmentHidden(!immersive)
        }
        // Checked every frame: the camera may start after the first mode sync.
        cameraSprite.isHidden = model.mode == .immersive || lastSnapshot == nil
        if lastSwap != model.swapRoles {
            lastSwap = model.swapRoles
            applyRoleStyling()
        }
        if lastReduceMotion != model.reduceMotion {
            lastReduceMotion = model.reduceMotion
            for streak in streaks { streak.node.isHidden = model.reduceMotion }
        }
        audio.isMuted = !model.soundOn
    }

    /// Picks up the newest processed camera frame, if any. Never waits on the processing queue.
    private func pollPipeline() {
        guard let pipeline, let snapshot = pipeline.store.latest(), snapshot.sequence != lastSnapshotSequence else { return }
        lastSnapshotSequence = snapshot.sequence
        lastSnapshot = snapshot
        bodyTexture.modifyPixelData(Self.makeCopier(pipeline.store))
        meter.recordSnapshot(snapshot, uploadedAt: now)

        if mode == .immersive {
            bodySprite.isHidden = !snapshot.hasCutout
        }
        if inputSource == .camera {
            applyLivePoses(snapshot)
        }
    }

    /// Built outside the main actor: SpriteKit may invoke the block on its render thread.
    nonisolated private static func makeCopier(_ store: FrameStore) -> @Sendable (UnsafeMutableRawPointer?, Int) -> Void {
        { pointer, length in
            guard let pointer else { return }
            store.copyFront(to: pointer, length: length)
        }
    }

    private func updateSpeed(dt: TimeInterval) {
        let reduce = reduceMotion
        let cruise = gameMode == .jungleDrift ? jungleCruise : baseSpeed * (reduce ? 0.7 : 1)
        var target = cruise
        // Boosts never run during an encounter: the obstacle's timing is defined at cruise speed.
        if now < boostUntil, !encounterActive { target *= reduce ? min(boostMultiplier, 1.25) : boostMultiplier }
        if isWorldPaused { target = 0 }
        worldSpeed += (target - worldSpeed) * CGFloat(min(1, dt * (isWorldPaused ? 2.5 : 2)))

        // FOV kick: widen the view while boosting so the world visibly rushes outward (game-feel speed cue).
        let boosting = now < boostUntil && !reduce && !isWorldPaused
        let fovTarget: CGFloat = boosting ? 0.8 : 1
        proj.fovScale += (fovTarget - proj.fovScale) * CGFloat(min(1, dt * (boosting ? 3 : 1.5)))
        proj.recompute()
    }

    private func advanceWorld(dt: CGFloat) {
        let travel = worldSpeed * dt
        distance += travel
        if !reduceMotion { skyClock += dt }
        palettePhase += (palettePhaseTarget - palettePhase) * min(1, dt * 0.8)

        // Gentle S-curves (two slow sines), off under Reduce Motion. The background pans against the bend.
        let curveTarget: CGFloat = reduceMotion ? 0 : 0.0045 * sin(distance * 2 * .pi / 320) + 0.0015 * sin(distance * 2 * .pi / 130)
        proj.curve += (curveTarget - proj.curve) * min(1, dt * 2)
        skyPan = -proj.curve * 26000
        mountains.position.x = proj.cx + skyPan * 0.7
        skyline.position.x = proj.cx + skyPan

        floorShader.uniformNamed("u_offset")?.floatValue = Float(distance.truncatingRemainder(dividingBy: 12))
        floorShader.uniformNamed("u_phase")?.floatValue = Float(palettePhase)
        floorShader.uniformNamed("u_f")?.floatValue = Float(proj.f)
        floorShader.uniformNamed("u_zp")?.floatValue = Float(proj.zp)
        floorShader.uniformNamed("u_curve")?.floatValue = Float(proj.curve)
        floorShader.uniformNamed("u_dim")?.floatValue = Float(tunnelDim)
        floorShader.uniformNamed("u_clock")?.floatValue = Float((reduceMotion ? 0 : now).truncatingRemainder(dividingBy: 1000))
        updateLocomotive()
        skyShader.uniformNamed("u_phase")?.floatValue = Float(palettePhase)
        skyShader.uniformNamed("u_t")?.floatValue = Float(skyClock)
        skyShader.uniformNamed("u_pan")?.floatValue = Float(skyPan * 0.5)
        skyShader.uniformNamed("u_dim")?.floatValue = Float(tunnelDim)
        horizonGlow.color = Palette.coral.mixed(with: Palette.electric, amount: palettePhase)

        guard mode == .immersive else { return }

        let vanishing = CGPoint(x: proj.cx + skyPan * 0.5, y: proj.horizonY)
        let skyHeight = size.height - proj.horizonY
        for cloud in clouds {
            guard let angle = cloud.userData?["angle"] as? Double, var r = cloud.userData?["r"] as? Double,
                  let base = cloud.userData?["base"] as? Double else { continue }
            // Accelerating outward drift: slow near the horizon, faster as it nears the frame edge.
            r += Double(dt) * (0.012 + r * 0.05) * Double(worldSpeed / baseSpeed) * (reduceMotion ? 0.3 : 1)
            var newAngle = angle
            if r > 1.25 { r = 0.08; newAngle = 0.35 + 2.4 * Double.random(in: 0...1) }
            cloud.userData?["r"] = r
            cloud.userData?["angle"] = newAngle
            cloud.position = CGPoint(x: vanishing.x + CGFloat(cos(newAngle) * r) * size.width * 0.62,
                                     y: vanishing.y + CGFloat(sin(newAngle) * r) * skyHeight * 0.95)
            cloud.setScale(0.25 + CGFloat(r) * 0.9)
            cloud.alpha = CGFloat(base) * smoothstep(0.05, 0.3, CGFloat(r))
        }

        let fogColor = Palette.coral.mixed(with: Palette.electric, amount: palettePhase)
        for prop in props {
            prop.z -= travel
            let near: CGFloat = prop.kind == .arch ? 0.4 : 0.6
            if prop.z < near {
                let span: CGFloat = prop.kind == .pylon ? 100 : 99
                prop.z += span
            }
            let node = prop.node
            let ppu = proj.ppu(prop.z)
            guard let texture = node.texture else { continue }
            node.setScale(ppu * prop.heightUnits / texture.size().height)
            node.position = proj.screen(x: prop.x, h: prop.h, z: prop.z)
            node.zPosition = proj.depthZ(prop.z)
            let fadeIn = 1 - smoothstep(farZ * 0.72, farZ * 0.97, prop.z)
            let fadeOut = prop.kind == .arch ? smoothstep(0.4, 1.6, prop.z) : 1
            node.alpha = fadeIn * fadeOut
            node.color = fogColor
            node.colorBlendFactor = smoothstep(14, 90, prop.z) * 0.85
        }

        updateEnvironment(dt: dt, travel: travel, fogColor: fogColor)

        if !reduceMotion {
            let intensity = min(1.8, max(0, (worldSpeed - baseSpeed * 0.3) / baseSpeed))
            for streak in streaks {
                streak.z -= travel * 1.15
                if streak.z < 0.5 { respawnStreak(streak, anywhere: false) }
                let p = proj.screen(x: streak.x, h: streak.h, z: streak.z)
                let dir = CGPoint(x: p.x - proj.cx, y: p.y - proj.horizonY)
                let ppu = proj.ppu(streak.z)
                streak.node.position = p
                streak.node.zRotation = atan2(dir.y, dir.x) - .pi / 2
                streak.node.yScale = max(0.05, ppu * worldSpeed * 0.035 / 128)
                streak.node.xScale = min(1.6, max(0.25, ppu * 0.012))
                streak.node.zPosition = proj.depthZ(streak.z)
                streak.node.alpha = 0.45 * intensity * (1 - smoothstep(22, 38, streak.z)) * smoothstep(0.5, 1.5, streak.z)
            }
        }

        updateShards(dt: dt)
    }

    /// The locomotive rides at the train front: it moves with the players (only curving with the track).
    func updateLocomotive() {
        let ppu = proj.ppu(trainFront)
        locomotive.position = proj.screen(x: 0, h: 0, z: trainFront)
        locomotive.size = CGSize(width: roofHalf * 2.05 * ppu, height: roofHalf * 2.05 * ppu * 300 / 640)
        locomotive.zPosition = proj.depthZ(trainFront)
        let fog = smoothstep(18, 95, trainFront)
        locomotive.color = Palette.coral.mixed(with: Palette.electric, amount: palettePhase)
        locomotive.colorBlendFactor = fog * 0.6
        locomotive.alpha = 1 - tunnelDim * 0.3
    }

    func respawnStreak(_ streak: Particle3D, anywhere: Bool) {
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let radius = CGFloat.random(in: 1.7...4.5)
        streak.x = cos(angle) * radius
        streak.h = proj.camH + sin(angle) * radius * 0.75
        streak.z = anywhere ? CGFloat.random(in: 2...38) : CGFloat.random(in: 28...40)
    }

    private func updateShards(dt: CGFloat) {
        for shard in shards where shard.life > 0 {
            shard.life -= dt
            shard.vh -= 9 * dt
            shard.x += shard.vx * dt
            shard.h += shard.vh * dt
            shard.z += shard.vz * dt
            if shard.life <= 0 || shard.z < 0.3 {
                shard.life = 0
                shard.node.isHidden = true
                continue
            }
            let ppu = proj.ppu(shard.z)
            shard.node.position = proj.screen(x: shard.x, h: shard.h, z: shard.z)
            shard.node.setScale(ppu * shard.sizeUnits / 48)
            shard.node.zRotation += shard.spin * dt
            shard.node.zPosition = proj.depthZ(shard.z) + 1
            shard.node.alpha = min(1, shard.life * 3)
        }
    }

    private func updateShake() {
        guard now < shakeUntil, !reduceMotion else {
            worldRoot.position = .zero
            return
        }
        let remaining = CGFloat((shakeUntil - now) / 0.3)
        worldRoot.position = CGPoint(x: CGFloat.random(in: -1...1) * shakeAmplitude * remaining,
                                     y: CGFloat.random(in: -1...1) * shakeAmplitude * remaining)
    }

    private func publishMetricsIfNeeded() {
        guard meter.shouldPublish(now: now) else { return }
        let thermal = ProcessInfo.processInfo.thermalState
        let degraded = thermal == .serious || thermal == .critical
        pipeline?.segmentationQuality = degraded ? .fast : .balanced
        var snapshot = meter.makeSnapshot(now: now, last: lastSnapshot)
        snapshot.thermal = DeviceStats.thermalLabel(thermal)
        snapshot.degraded = degraded
        snapshot.memoryMB = DeviceStats.memoryFootprintMB()
        snapshot.people = lastSnapshot?.people.count ?? 0
        model?.metrics = snapshot
        if let line = meter.logIfNeeded(snapshot, now: now), let directory = model?.evidenceDirectory {
            appendLine(line, to: directory.appendingPathComponent("metrics.log"))
        }
        captureEvidenceIfNeeded()
    }

    /// Verification-only: snapshot the scene shortly after a named game event (needs `-evidenceDir`).
    func captureEvent(_ name: String, after delay: TimeInterval) {
        guard model?.evidenceDirectory != nil, evidenceCount < 150 else { return }
        let session = flow.session
        run(.wait(forDuration: delay)) { [weak self] in
            guard let self, let directory = model?.evidenceDirectory, let view,
                  let image = view.texture(from: self)?.cgImage() else { return }
            evidenceCount += 1
            let file = String(format: "evt-%03d-s%d-%@.png", evidenceCount, session, name)
            if let data = UIImage(cgImage: image).pngData() { try? data.write(to: directory.appendingPathComponent(file)) }
        }
    }

    /// Verification-only snapshots of the rendered scene (see GameModel.evidenceDirectory).
    private func captureEvidenceIfNeeded() {
        guard let directory = model?.evidenceDirectory, let view, now - lastEvidenceCapture >= (model?.evidenceInterval ?? 3),
              evidenceCount < 120 else { return }
        lastEvidenceCapture = now
        evidenceCount += 1
        guard let image = view.texture(from: self)?.cgImage() else { return }
        let name = String(format: "%03d-%@-%@.png", evidenceCount, mode == .immersive ? "B" : "A",
                          Zone.allCases.map { slots[$0]?.driver == .live ? "L" : "-" }.joined())
        if let data = UIImage(cgImage: image).pngData() {
            try? data.write(to: directory.appendingPathComponent(name))
        }
    }

    private func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

extension UIColor {
    var rgb: SIMD3<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Float(r), Float(g), Float(b))
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
