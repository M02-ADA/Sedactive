import SpriteKit

/// The vault corridor for Laser Breakout. One spatial model (Corridor + Projection) drives everything:
///   • the corridor surfaces (shader, fixed in the world, streaming toward the camera),
///   • the fixtures and set pieces (sprites fixed in the world at their own x / h / z),
///   • the getaway cart (fixed relative to the players — it carries them),
///   • and an optional debug overlay that draws the same geometry as lines, so shader, sprites and debug can be checked
///     against each other on screen.
@MainActor
final class LaserWorld {
    let root = SKNode()
    let corridor = SKSpriteNode(texture: Art.white)
    let shader = Shaders.corridor()

    // Fixtures streaming past (pooled, recycled to the far end).
    var cameras: [(node: SKSpriteNode, side: CGFloat, z: CGFloat, phase: CGFloat)] = []
    var beacons: [(node: SKSpriteNode, fan: SKSpriteNode, side: CGFloat, z: CGFloat, phase: CGFloat)] = []
    static let fixtureSpan: CGFloat = 56

    // Set pieces.
    struct Doors {
        let left = SKSpriteNode(texture: Art.blastDoor)
        let right = SKSpriteNode(texture: Art.blastDoor)
        let frame = SKSpriteNode(texture: Art.gateFrame)
        var z: CGFloat
        /// 0 shut … 1 fully open (gap = the whole corridor).
        var open: CGFloat
        var mode: Mode
        var slammed = false
        enum Mode { case closingAhead, exit }
    }
    var doors: Doors?
    let exitSign = SKSpriteNode(texture: Art.exitSign)

    // The cart (travels with the players).
    let deck = SKSpriteNode(texture: Art.cartDeck)
    let nose = SKSpriteNode(texture: Art.cartNose)
    let diamond = SKSpriteNode(texture: Art.diamond)
    let diamondGlow = SKSpriteNode(texture: Art.glow)
    var glints: [SKSpriteNode] = []
    /// The diamond lifts for the finale (0 … 1).
    var diamondLift: CGFloat = 0
    static let quadSource = WarpQuad.sourceGrid(columns: 1, rows: 1)

    // Debug overlay.
    let debug = SKShapeNode()
    let debugBeams = SKShapeNode()
    let debugFar = SKShapeNode()
    let debugJudge = SKShapeNode()
    let debugPlane = SKShapeNode()
    let debugBody = SKShapeNode()
    var debugLabels: [SKLabelNode] = []
    var debugOn = UserDefaults.standard.bool(forKey: "laserDebug")
    /// Security response: the cameras turn to the lane under threat (−1 left, +1 right, 0 none) and flash red when
    /// they catch someone (1 → decays).
    var cameraLook: CGFloat = 0
    var cameraDetect: CGFloat = 0
    private var cameraLookSmoothed: CGFloat = 0

    init() {
        corridor.anchorPoint = .zero
        corridor.shader = shader
        corridor.zPosition = Layer.floor
        root.addChild(corridor)
        for i in 0..<6 {
            let cam = SKSpriteNode(texture: Art.securityCamera)
            cam.anchorPoint = CGPoint(x: 0.5, y: 1)
            root.addChild(cam)
            cameras.append((cam, i % 2 == 0 ? -1 : 1, 6 + CGFloat(i) * Self.fixtureSpan / 6, CGFloat(i) * 1.3))
        }
        for i in 0..<8 {
            let b = SKSpriteNode(texture: Art.beacon)
            b.anchorPoint = CGPoint(x: 0.5, y: 0)
            let fan = SKSpriteNode(texture: Art.beaconFan)
            fan.anchorPoint = CGPoint(x: 0, y: 0.5)
            fan.blendMode = .add
            fan.colorBlendFactor = 1
            fan.color = VaultPalette.laser
            fan.alpha = 0
            root.addChild(b)
            root.addChild(fan)
            beacons.append((b, fan, i % 2 == 0 ? 1 : -1, 3 + CGFloat(i) * Self.fixtureSpan / 8, CGFloat(i) * 0.9))
        }
        for node in [deck, nose] {
            node.anchorPoint = .zero
            node.size = CGSize(width: WarpQuad.unit, height: WarpQuad.unit)
            root.addChild(node)
        }
        deck.zPosition = Layer.pad - 2
        nose.zPosition = Layer.pad - 2.1   // behind the diamond, which sits on the deck in front of it
        diamondGlow.color = VaultPalette.gold
        diamondGlow.colorBlendFactor = 1
        diamondGlow.blendMode = .add
        diamondGlow.alpha = 0.45
        for node in [diamondGlow, diamond] { root.addChild(node) }
        diamond.anchorPoint = CGPoint(x: 0.5, y: 0)
        for _ in 0..<3 {
            let g = SKSpriteNode(texture: Art.glintStar)
            g.color = VaultPalette.goldLight
            g.colorBlendFactor = 1
            g.alpha = 0
            root.addChild(g)
            glints.append(g)
        }
        exitSign.isHidden = true
        root.addChild(exitSign)
        debug.strokeColor = UIColor.yellow.withAlphaComponent(0.8)
        debug.lineWidth = 1.5
        debug.zPosition = Layer.flash - 20
        debugBeams.strokeColor = UIColor.green
        debugBeams.lineWidth = 3
        debugBeams.zPosition = Layer.flash - 19
        root.addChild(debug)
        root.addChild(debugBeams)
        // Far beams (blue: cannot collide), beams inside the judging window (red), the interaction plane (magenta).
        for (node, color, width) in [(debugFar, UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1), CGFloat(2)), (debugJudge, UIColor.red, 5),
                                     (debugPlane, UIColor.magenta.withAlphaComponent(0.8), 2), (debugBody, UIColor.cyan, 3)] {
            node.strokeColor = color
            node.lineWidth = width
            node.zPosition = Layer.flash - 19
            root.addChild(node)
        }
        for _ in 0..<8 {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.fontSize = 13
            label.fontColor = .white
            label.horizontalAlignmentMode = .left
            label.zPosition = Layer.flash - 18
            label.isHidden = true
            root.addChild(label)
            debugLabels.append(label)
        }
    }

    func layout(size: CGSize, proj: Projection) {
        corridor.position = .zero
        corridor.size = size
        shader.uniformNamed("u_res")?.vectorFloat2Value = SIMD2(Float(size.width), Float(size.height))
        shader.uniformNamed("u_cx")?.floatValue = Float(proj.cx)
        shader.uniformNamed("u_horizon")?.floatValue = Float(proj.horizonY)
        shader.uniformNamed("u_f")?.floatValue = Float(proj.f)
        shader.uniformNamed("u_camH")?.floatValue = Float(proj.camH)
    }

    // MARK: - Set pieces

    func startDoors(z: CGFloat, open: CGFloat, mode: Doors.Mode) {
        removeDoors()
        let d = Doors(z: z, open: open, mode: mode)
        for node in [d.frame, d.left, d.right] { root.addChild(node) }
        d.left.anchorPoint = CGPoint(x: 0, y: 0)
        d.right.anchorPoint = CGPoint(x: 0, y: 0)
        d.right.xScale = -1
        d.frame.anchorPoint = CGPoint(x: 0.5, y: 0)
        d.frame.color = mode == .exit ? UIColor(red: 0.3, green: 0.95, blue: 0.5, alpha: 1) : VaultPalette.laser
        d.frame.colorBlendFactor = 0.25
        doors = d
        exitSign.isHidden = mode != .exit
    }

    func removeDoors() {
        if let d = doors { for node in [d.frame, d.left, d.right] { node.removeFromParent() } }
        doors = nil
        exitSign.isHidden = true
    }

    // MARK: - Per frame

    func update(dt: CGFloat, travel: CGFloat, distance: CGFloat, now: TimeInterval, proj: Projection, size: CGSize,
                alarm: CGFloat, beam: SIMD3<Float>, flash: CGFloat, exit: CGFloat, reduceMotion: Bool, gameTime: Double) {
        let clock = Float(reduceMotion ? 0 : now.truncatingRemainder(dividingBy: 1000))
        shader.uniformNamed("u_offset")?.floatValue = Float(distance.truncatingRemainder(dividingBy: 4000))
        shader.uniformNamed("u_clock")?.floatValue = clock
        shader.uniformNamed("u_alarm")?.floatValue = Float(alarm)
        shader.uniformNamed("u_beam")?.vectorFloat3Value = beam
        shader.uniformNamed("u_flash")?.floatValue = Float(flash)
        shader.uniformNamed("u_exit")?.floatValue = Float(exit)
        shader.uniformNamed("u_exitGold")?.floatValue = Float(min(1, exit * 2))

        // Fixtures: fixed in the world, recycled to the far end.
        cameraLookSmoothed += (cameraLook - cameraLookSmoothed) * min(1, dt * 5)
        cameraDetect = max(0, cameraDetect - dt * 1.5)
        for i in cameras.indices {
            cameras[i].z -= travel
            if cameras[i].z < 0.6 { cameras[i].z += Self.fixtureSpan }
            let c = cameras[i]
            let ppu = proj.ppu(c.z)
            c.node.position = proj.screen(x: c.side * 1.75, h: Corridor.ceilingH, z: c.z)
            c.node.setScale(ppu * 0.5 / 120)
            c.node.xScale = abs(c.node.xScale) * (c.side < 0 ? 1 : -1)
            // Idle: slow patrol sweep. Alarm: snaps round to stare at the cart and tracks it.
            let sweep = reduceMotion ? 0 : sin(CGFloat(now) * 0.8 + c.phase) * 0.25
            // A threat: every camera turns toward that lane (more for the cameras on the opposite wall).
            let look = cameraLookSmoothed * (0.25 + 0.2 * abs(cameraLookSmoothed * c.side - 1) / 2) * c.side
            c.node.zRotation = (1 - alarm) * sweep + alarm * -c.side * 0.35 - look
            c.node.color = VaultPalette.laser
            c.node.colorBlendFactor = cameraDetect * 0.8
            c.node.zPosition = proj.depthZ(c.z)
            c.node.alpha = smoothstep(0.6, 1.4, c.z) * (1 - smoothstep(40, 52, c.z))
        }
        for i in beacons.indices {
            beacons[i].z -= travel
            if beacons[i].z < 0.6 { beacons[i].z += Self.fixtureSpan }
            let b = beacons[i]
            let ppu = proj.ppu(b.z)
            let p = proj.screen(x: b.side * 1.98, h: 1.75, z: b.z)
            b.node.position = p
            b.node.setScale(ppu * 0.28 / 60)
            b.node.zRotation = b.side * .pi / 2   // mounted on the wall, dome toward the corridor
            b.node.zPosition = proj.depthZ(b.z)
            let fade = smoothstep(0.6, 1.4, b.z) * (1 - smoothstep(40, 52, b.z))
            b.node.alpha = fade
            b.node.color = alarm > 0.05 ? VaultPalette.laser : .white
            b.node.colorBlendFactor = 0.8
            // Rotating light: sweeps around while the alarm is on.
            b.fan.position = CGPoint(x: p.x - b.side * ppu * 0.05, y: p.y)
            b.fan.setScale(ppu * 1.1 / 256)
            b.fan.zRotation = reduceMotion ? (b.side > 0 ? .pi : 0) : CGFloat(now) * 4 + b.phase
            b.fan.zPosition = b.node.zPosition + 0.01
            b.fan.alpha = alarm * 0.35 * fade
        }

        if var d = doors { d.z -= travel; doors = d }   // fixed to the corridor
        updateDoors(proj: proj, now: now)
        updateCart(proj: proj, now: now, reduceMotion: reduceMotion)
        if debugOn { drawDebug(proj: proj, size: size, distance: distance) } else { debug.path = nil }
    }

    private func updateDoors(proj: Projection, now: TimeInterval) {
        guard let d = doors else { return }
        let ppu = proj.ppu(d.z)
        let gap = Corridor.halfWidth * Double(d.open)
        let panelWidth = CGFloat(Corridor.halfWidth - gap)
        let h = CGFloat(Corridor.ceilingH - Corridor.floorH)
        d.left.position = proj.screen(x: -CGFloat(Corridor.halfWidth), h: CGFloat(Corridor.floorH), z: d.z)
        d.right.position = proj.screen(x: CGFloat(Corridor.halfWidth), h: CGFloat(Corridor.floorH), z: d.z)
        for panel in [d.left, d.right] {
            panel.yScale = h * ppu / 265
            panel.xScale = max(0.001, panelWidth * ppu / 200) * (panel === d.right ? -1 : 1)
            panel.zPosition = proj.depthZ(d.z) + 0.2
            panel.isHidden = panelWidth < 0.01 || d.z < 0.3
        }
        d.frame.position = proj.screen(x: 0, h: CGFloat(Corridor.floorH), z: d.z)
        d.frame.setScale(ppu / 100)
        d.frame.zPosition = proj.depthZ(d.z) + 0.1
        d.frame.isHidden = d.z < 0.3
        if d.mode == .exit {
            exitSign.position = proj.screen(x: 0, h: CGFloat(Corridor.ceilingH) - 0.15, z: d.z)
            exitSign.setScale(ppu * 0.9 / 180)
            exitSign.zPosition = d.frame.zPosition + 0.1
            exitSign.isHidden = d.z < 0.3
        }
        doors = d
    }

    private func updateCart(proj: Projection, now: TimeInterval, reduceMotion: Bool) {
        let hw = CGFloat(Corridor.deckHalfWidth), zn = CGFloat(Corridor.deckNearZ), zf = CGFloat(Corridor.deckFarZ)
        let c = [proj.screen(x: -hw, h: 0, z: zn), proj.screen(x: hw, h: 0, z: zn), proj.screen(x: -hw, h: 0, z: zf), proj.screen(x: hw, h: 0, z: zf)]
        deck.position = c[0]
        deck.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: Self.quadSource, destinationPositions: WarpQuad.normalized(c, origin: c[0]))
        // The front rail: a low bulkhead rising from the deck's far edge (its inside face is what the camera sees).
        let e = [c[2], c[3], proj.screen(x: -hw, h: 0.2, z: zf), proj.screen(x: hw, h: 0.2, z: zf)]
        nose.position = e[0]
        nose.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: Self.quadSource, destinationPositions: WarpQuad.normalized(e, origin: e[0]))
        // The diamond rides on the cart's front, between and behind the players.
        let dz: CGFloat = zf - 0.25
        let ppu = proj.ppu(dz)
        let bob = reduceMotion ? 0 : sin(CGFloat(now) * 2.2) * 0.02
        let lift = diamondLift * 0.55 + bob
        let base = proj.screen(x: 0, h: 0.05 + lift, z: dz)
        diamond.position = base
        diamond.setScale(ppu * (0.34 + 0.12 * diamondLift) / 140)
        diamond.zRotation = reduceMotion ? 0 : sin(CGFloat(now) * 1.3) * 0.05
        diamond.zPosition = Layer.pad - 1.8   // on the deck, in front of the rail, behind the players
        diamondGlow.position = CGPoint(x: base.x, y: base.y + ppu * 0.15)
        diamondGlow.size = CGSize(width: ppu * (0.9 + diamondLift), height: ppu * (0.9 + diamondLift))
        diamondGlow.zPosition = diamond.zPosition - 0.01
        diamondGlow.alpha = 0.35 + 0.15 * sin(CGFloat(now) * 3) + diamondLift * 0.4
        for (i, g) in glints.enumerated() {
            // Glints twinkle across the facets in turn (one at a time, never a cloud).
            let k = CGFloat((now * 0.9 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1))
            g.position = CGPoint(x: base.x + ppu * CGFloat([-0.08, 0.06, 0.0][i]), y: base.y + ppu * CGFloat([0.2, 0.26, 0.12][i]) * (1 + diamondLift))
            g.setScale(ppu * 0.12 / 48 * sin(.pi * k) * (1 + diamondLift))
            g.zPosition = diamond.zPosition + 0.01
            g.alpha = k < 0.5 || diamondLift > 0 ? 1 : 0
        }
    }

    // MARK: - Perspective debug overlay (`-laserDebug YES`, or the panel button)

    private func drawDebug(proj: Projection, size: CGSize, distance: CGFloat) {
        let path = CGMutablePath()
        let W = CGFloat(Corridor.halfWidth), F = CGFloat(Corridor.floorH), C = CGFloat(Corridor.ceilingH)
        func line(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) {
            path.move(to: proj.screen(x: a.0, h: a.1, z: a.2)); path.addLine(to: proj.screen(x: b.0, h: b.1, z: b.2))
        }
        // Corridor edges (floor/wall, wall/ceiling) to the far end.
        for (x, h) in [(-W, F), (W, F), (-W, C), (W, C)] { line((x, h, 0.6), (x, h, 80)) }
        // Cross-sections fixed in the world every 4 units (they move with the shader's seams and ceiling bars).
        let phase = distance.truncatingRemainder(dividingBy: 4)
        var z = 4 - phase
        while z < 60 {
            if z > 0.6 {
                line((-W, F, z), (W, F, z)); line((W, F, z), (W, C, z)); line((W, C, z), (-W, C, z)); line((-W, C, z), (-W, F, z))
            }
            z += 4
        }
        // Player plane, feet, lanes, the deck, horizon and vanishing point.
        let zp = proj.zp
        line((-W, 0, zp), (W, 0, zp))
        for lane in [-Corridor.laneX, Corridor.laneX] { line((CGFloat(lane), 0, zp), (CGFloat(lane), 1.2, zp)) }
        let hw = CGFloat(Corridor.deckHalfWidth)
        let zn = CGFloat(Corridor.deckNearZ), zf = CGFloat(Corridor.deckFarZ), ground: CGFloat = 0
        line((-hw, ground, zn), (hw, ground, zn))
        line((-hw, ground, zf), (hw, ground, zf))
        line((-hw, ground, zn), (-hw, ground, zf))
        line((hw, ground, zn), (hw, ground, zf))
        path.move(to: CGPoint(x: 0, y: proj.horizonY)); path.addLine(to: CGPoint(x: size.width, y: proj.horizonY))
        path.move(to: CGPoint(x: proj.cx, y: proj.horizonY - 14)); path.addLine(to: CGPoint(x: proj.cx, y: proj.horizonY + 14))
        debug.path = path
    }

    /// The active beams as debug lines (drawn exactly where gameplay says they are).
    struct DebugBeam {
        enum State { case far, near, judging, body }
        var x0: CGFloat, h0: CGFloat, x1: CGFloat, h1: CGFloat, z: CGFloat, z1: CGFloat
        var state: State
        var label: String
    }

    /// Beams as the judge sees them (world coordinates through the shared projection), coloured by whether they can
    /// interact yet, with the players' interaction plane and the judging window's depth band on the floor.
    func drawDebugBeams(_ beams: [DebugBeam], proj: Projection, timing: LaserTiming) {
        guard debugOn else {
            for node in [debugBeams, debugFar, debugJudge, debugPlane, debugBody] { node.path = nil }
            debugLabels.forEach { $0.isHidden = true }
            return
        }
        let paths = [DebugBeam.State.far: CGMutablePath(), .near: CGMutablePath(), .judging: CGMutablePath(), .body: CGMutablePath()]
        let F = CGFloat(Corridor.floorH)
        for b in beams {
            guard let path = paths[b.state] else { continue }
            path.move(to: proj.screen(x: b.x0, h: b.h0, z: b.z)); path.addLine(to: proj.screen(x: b.x1, h: b.h1, z: max(0.45, b.z1)))
            // A drop line to the floor shows the beam's depth against the corridor.
            path.move(to: proj.screen(x: b.x0, h: b.h0, z: b.z)); path.addLine(to: proj.screen(x: b.x0, h: F, z: b.z))
        }
        debugFar.path = paths[.far]; debugBeams.path = paths[.near]; debugJudge.path = paths[.judging]; debugBody.path = paths[.body]
        // Interaction plane (z = player plane) wall to wall, and the window's depth band (beam depth while judging).
        let plane = CGMutablePath()
        let W = CGFloat(Corridor.halfWidth), C = CGFloat(Corridor.ceilingH), zp = CGFloat(Corridor.playerZ)
        let corners = [(-W, F), (W, F), (W, C), (-W, C), (-W, F)].map { proj.screen(x: $0.0, h: $0.1, z: zp) }
        plane.addLines(between: corners)
        let zNear = zp - CGFloat(timing.speed * timing.window.clearAfter), zFar = zp + CGFloat(timing.speed * timing.window.clearBefore)
        plane.addLines(between: [(-W, zFar), (W, zFar), (W, zNear), (-W, zNear), (-W, zFar)].map { proj.screen(x: $0.0, h: F, z: max(0.3, $0.1)) })
        debugPlane.path = beams.isEmpty ? nil : plane
        for (i, label) in debugLabels.enumerated() {
            guard i < beams.count else { label.isHidden = true; continue }
            let b = beams[i]
            label.isHidden = false
            label.text = b.label
            let p = proj.screen(x: b.x0, h: b.h0, z: b.z)
            label.position = CGPoint(x: max(8, p.x + (b.x0 < 0 ? 4 : -260)), y: p.y + 10 + CGFloat(i % 2) * 14)
        }
    }
}
