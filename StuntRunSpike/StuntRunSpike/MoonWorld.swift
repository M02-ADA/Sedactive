import SpriteKit

/// One player's race lane: their rocket, its exhaust, the deck lip in front of their feet, and (added by the scene)
/// their live body half or simulator stand-in. Everything in `node` moves together, so the player always stands on
/// their own rocket: the lane rises with its race lead, kicks on every thrust and settles, without the body ever
/// leaving the deck.
@MainActor
final class RaceLane {
    let zone: Zone
    let node = SKNode()
    let rocket = SKNode()           // pod + band + flames; tilts about the deck (the feet don't)
    let pod = SKSpriteNode(texture: Art.racePod)
    let band = SKSpriteNode(texture: Art.racePodBand)
    let lip = SKSpriteNode(texture: Art.raceDeckLip)
    var flames: [SKSpriteNode] = []
    let glow = SKSpriteNode(texture: Art.glow)
    let flash = SKSpriteNode(texture: Art.glow)
    var color: UIColor = .white
    /// Screen x of this lane's deck centre (the player's feet are pulled onto it).
    var screenX: CGFloat = 0
    /// Vertical race offset (points; the leader rides higher) and the thrust kick spring on top of it.
    var raceOffset: CGFloat = 0
    var kick: CGFloat = 0
    var kickVelocity: CGFloat = 0
    var tilt: CGFloat = 0
    var tiltVelocity: CGFloat = 0
    /// 0 … ~1.6 extra burn after a rep; anticipation 0 … 1 while the player squats down.
    var flare: CGFloat = 0
    var charge: CGFloat = 0
    var slipstream: CGFloat = 0
    var feet: CGPoint = .zero

    init(zone: Zone) {
        self.zone = zone
        pod.anchorPoint = CGPoint(x: 0.5, y: 1 - 37.0 / 300)
        band.anchorPoint = pod.anchorPoint
        band.colorBlendFactor = 1
        lip.anchorPoint = CGPoint(x: 0.5, y: 1 - 37.0 / 80)
        rocket.addChild(pod)
        rocket.addChild(band)
        for i in 0..<3 {
            let f = SKSpriteNode(texture: Art.flame)
            f.anchorPoint = CGPoint(x: 0.5, y: 1)
            f.blendMode = .add
            f.colorBlendFactor = 0
            f.zPosition = -0.2 - CGFloat(i) * 0.01
            rocket.addChild(f)
            flames.append(f)
        }
        glow.blendMode = .add
        glow.colorBlendFactor = 1
        glow.color = MoonPalette.flame
        glow.zPosition = -0.3
        rocket.addChild(glow)
        flash.blendMode = .add
        flash.alpha = 0
        flash.zPosition = -0.15
        rocket.addChild(flash)
        pod.zPosition = -2
        band.zPosition = -1.99
        node.addChild(rocket)
        lip.zPosition = 0.6        // in front of the player's ankles
        node.addChild(lip)
    }
}

/// Moonbound's shared world. One camera model (Projection + AscentCamera):
///   • the world camera rides at the midpoint of the two rockets' altitudes; every world object has a fixed altitude
///     and depth and is drawn at height a − A above the deck, so all scenery falls past with 1/z parallax;
///   • the planet, cloud deck, sky and stars are ray-cast in a shader with the same camera;
///   • each player's lane (rocket + body) sits in this world with a capped vertical offset for its lead.
@MainActor
final class MoonWorld {
    let root = SKNode()
    let sky = SKSpriteNode(texture: Art.white)
    let shader = Shaders.ascentWorld()
    var lanes: [Zone: RaceLane] = [:]
    static let laneX: CGFloat = 0.78
    static let podWidth: CGFloat = 0.78

    final class Prop {
        let node: SKSpriteNode
        var x: CGFloat, a: CGFloat, z: CGFloat, width: CGFloat
        var vx: CGFloat = 0, spin: CGFloat = 0, tint: CGFloat = 0, flip: CGFloat = 1
        var anchorBottom = false
        init(_ texture: SKTexture, x: CGFloat, a: CGFloat, z: CGFloat, width: CGFloat) {
            node = SKSpriteNode(texture: texture)
            self.x = x; self.a = a; self.z = z; self.width = width
        }
    }
    var props: [Prop] = []
    var clouds: [Prop] = []
    var foreground: [Prop] = []
    var smoke: [(node: SKSpriteNode, x: CGFloat, a: CGFloat, z: CGFloat, vx: CGFloat, born: TimeInterval, size: CGFloat)] = []
    var smokeCursor = 0
    var streaks: [(node: SKSpriteNode, x: CGFloat, y: CGFloat, z: CGFloat)] = []
    static let cloudBand: ClosedRange<CGFloat> = 18...125
    static let cloudShellAltitude: CGFloat = 70

    // Set pieces.
    var gantries: [Zone: SKSpriteNode] = [.left: SKSpriteNode(texture: Art.gantry), .right: SKSpriteNode(texture: Art.gantry)]
    var clamps: [Zone: SKSpriteNode] = [:]
    var clampsOpen: CGFloat = 0
    let sun = SKSpriteNode(texture: Art.sunFlare)
    let moon = SKSpriteNode(texture: Art.moonDisc)
    let moonGlow = SKSpriteNode(texture: Art.glow)
    let gate = SKSpriteNode(texture: Art.moonGate)
    let earth = SKSpriteNode(texture: Art.earthDisc)
    let flag = SKSpriteNode(texture: Art.teamFlag)

    var landingAltitude: CGFloat?
    var moonSlide: CGFloat = 0
    var flash: CGFloat = 0

    let debug = SKShapeNode()
    let debugLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    var debugOn = UserDefaults.standard.bool(forKey: "moonDebug")

    init() {
        sky.anchorPoint = .zero
        sky.shader = shader
        sky.zPosition = Layer.floor
        root.addChild(sky)
        for zone in Zone.allCases { lanes[zone] = RaceLane(zone: zone) }

        // Launch site: a tower outside each rocket with a clamp arm gripping its hull, floodlights, distant hills.
        for g in gantries.values {
            g.anchorPoint = CGPoint(x: 0.375, y: 0)
            root.addChild(g)
        }
        for zone in Zone.allCases {
            let c = SKSpriteNode(texture: Art.clampArm)
            c.anchorPoint = CGPoint(x: 0, y: 0.5)
            root.addChild(c)
            clamps[zone] = c
        }
        addProp(Prop(Art.floodMast, x: 3.6, a: -0.4, z: 7.5, width: 0.9), bottom: true)
        addProp(Prop(Art.floodMast, x: -3.8, a: -0.4, z: 8.5, width: 0.9), bottom: true)
        addProp(Prop(Art.floodMast, x: 8, a: -0.4, z: 18, width: 1.2), bottom: true)
        for (i, x) in [-120.0, -55, 5, 65, 125].enumerated() {
            let p = Prop(Art.hills, x: CGFloat(x), a: -2, z: CGFloat(95 + (i % 2) * 12), width: 70)
            p.tint = 0.35
            addProp(p, bottom: true)
        }
        // Sky.
        addProp(Prop(Art.hotAirBalloon, x: -7.5, a: 21, z: 26, width: 2.8))
        let plane = Prop(Art.airliner, x: -70, a: 48, z: 75, width: 9)
        plane.vx = 11
        addProp(plane)
        addProp(Prop(Art.hotAirBalloon, x: 16, a: 34, z: 60, width: 4))
        // Upper atmosphere and space.
        addProp(Prop(Art.weatherBalloon, x: 6, a: 165, z: 30, width: 2.2))
        addProp(Prop(Art.skyWisp, x: -20, a: 135, z: 120, width: 60))
        addProp(Prop(Art.skyWisp, x: 30, a: 150, z: 160, width: 70))
        for (i, alt) in [330.0, 560, 900, 1350, 1800].enumerated() {
            let s = Prop(Art.satellite, x: CGFloat(i % 2 == 0 ? -1 : 1) * CGFloat(24 + i * 12), a: CGFloat(alt), z: CGFloat(170 + i * 60), width: 22)
            s.spin = CGFloat(i % 2 == 0 ? 0.15 : -0.12)
            s.vx = CGFloat(i % 2 == 0 ? 3 : -3)
            addProp(s)
        }
        addProp(Prop(Art.spaceStation, x: -60, a: 760, z: 320, width: 70))
        var rng = SeededGenerator(seed: 7)
        for i in 0..<10 {
            let r = Prop(Art.spaceRock, x: CGFloat(rng.next() * 80 - 40), a: CGFloat(420 + i * 160), z: CGFloat(60 + rng.next() * 100), width: CGFloat(2 + rng.next() * 3))
            r.spin = CGFloat(rng.next() * 2 - 1)
            addProp(r)
        }
        // Clouds streamed through the band, and a few big near clouds for the punch through the cloud deck.
        for i in 0..<16 {
            let z = CGFloat(22 + rng.next() * 158)
            let c = Prop(i % 4 == 3 ? Art.skyWisp : Art.cloudPuff, x: 0, a: 0, z: z, width: z * CGFloat(0.18 + rng.next() * 0.18))
            c.x = CGFloat(rng.next() * 1.6 - 0.8) * z * 0.8
            c.a = CGFloat(Self.cloudBand.lowerBound + rng.next() * (Self.cloudBand.upperBound - Self.cloudBand.lowerBound))
            c.flip = rng.next() < 0.5 ? 1 : -1
            clouds.append(c)
            root.addChild(c.node)
        }
        for i in 0..<6 {
            let z = CGFloat(2.4 + Double(i) * 0.25)
            let c = Prop(Art.cloudPuff, x: CGFloat([-1.6, 1.4, -0.4, 0.9, -1.1, 1.8][i]), a: Self.cloudShellAltitude + CGFloat([-3, 1, 4, -1, 6, 2][i]), z: z, width: 3.2)
            c.flip = i % 2 == 0 ? 1 : -1
            foreground.append(c)
            root.addChild(c.node)
        }
        for _ in 0..<48 {
            let s = SKSpriteNode(texture: Art.smokePuff)
            s.alpha = 0
            root.addChild(s)
            smoke.append((s, 0, -1000, 3, 0, -100, 1))
        }
        for _ in 0..<28 {
            let s = SKSpriteNode(texture: Art.white)
            s.anchorPoint = CGPoint(x: 0.5, y: 0)
            s.blendMode = .add
            s.alpha = 0
            s.colorBlendFactor = 1
            root.addChild(s)
            streaks.append((s, CGFloat(rng.next() * 2 - 1), CGFloat(rng.next()), CGFloat(2.5 + rng.next() * 6.5)))
        }
        sun.blendMode = .add
        sun.zPosition = Layer.floor + 8
        sun.alpha = 0
        for node in [sun, moonGlow, moon, gate, earth, flag] as [SKSpriteNode] { root.addChild(node) }
        moonGlow.color = UIColor(red: 0.85, green: 0.88, blue: 1, alpha: 1)
        moonGlow.colorBlendFactor = 1
        moonGlow.blendMode = .add
        moonGlow.zPosition = Layer.floor + 9
        moon.zPosition = Layer.floor + 10
        gate.zPosition = Layer.floor + 11
        gate.alpha = 0
        earth.zPosition = Layer.floor + 10
        earth.isHidden = true
        flag.anchorPoint = CGPoint(x: 0.07, y: 0)
        flag.isHidden = true
        debug.strokeColor = UIColor.yellow.withAlphaComponent(0.85)
        debug.lineWidth = 2
        debug.zPosition = Layer.flash - 20
        debugLabel.fontSize = 15
        debugLabel.fontColor = .yellow
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .top
        debugLabel.numberOfLines = 0
        debugLabel.zPosition = Layer.flash - 19
        root.addChild(debug)
        root.addChild(debugLabel)
    }

    private func addProp(_ p: Prop, bottom: Bool = false) {
        p.anchorBottom = bottom
        p.node.anchorPoint = bottom ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0.5, y: 0.5)
        props.append(p)
        root.addChild(p.node)
    }

    func layout(size: CGSize, proj: Projection) {
        sky.position = .zero
        sky.size = size
        shader.uniformNamed("u_res")?.vectorFloat2Value = SIMD2(Float(size.width), Float(size.height))
        shader.uniformNamed("u_cx")?.floatValue = Float(proj.cx)
        shader.uniformNamed("u_horizon")?.floatValue = Float(proj.horizonY)
        shader.uniformNamed("u_f")?.floatValue = Float(proj.f)
        debugLabel.position = CGPoint(x: 20, y: size.height - 200)
    }

    // MARK: - Thrust feedback (immediate; the climb itself is each player's ascent spring)

    /// IGNITION → THRUST: a white flash at the nozzles, the burn blasts long, the lane kicks upward (the spring then
    /// settles it: acceleration + follow-through), the rocket rocks a little, and exhaust is left behind.
    func fire(_ zone: Zone, strength: CGFloat, cameraAltitude: CGFloat, ppu: CGFloat, now: TimeInterval, reduceMotion: Bool) {
        guard let lane = lanes[zone] else { return }
        lane.flare = min(1.8, max(lane.flare, 0.5) + strength)
        lane.kickVelocity += (reduceMotion ? 140 : 300) * strength
        lane.tiltVelocity += (reduceMotion ? 0 : (Bool.random() ? 0.5 : -0.5)) * strength
        lane.charge = 0
        lane.flash.removeAllActions()
        lane.flash.alpha = 1
        lane.flash.run(.fadeOut(withDuration: 0.18))
        let a = cameraAltitude + lane.raceOffset / ppu
        for i in 0..<(strength > 1.1 ? 6 : 4) { emitSmoke(lane: lane, altitude: a, now: now, spread: CGFloat(i)) }
    }

    func sputter(_ zone: Zone, cameraAltitude: CGFloat, ppu: CGFloat, now: TimeInterval) {
        guard let lane = lanes[zone] else { return }
        lane.flare = max(lane.flare, 0.15)
        lane.charge = 0
        emitSmoke(lane: lane, altitude: cameraAltitude + lane.raceOffset / ppu, now: now, spread: 0, small: true)
    }

    /// The launch flood: smoke billows sideways off the pad from both rockets.
    func launchSmoke(cameraAltitude: CGFloat, now: TimeInterval) {
        for lane in lanes.values { for i in 0..<10 { emitSmoke(lane: lane, altitude: cameraAltitude, now: now, spread: CGFloat(i % 4), pad: true) } }
    }

    private func emitSmoke(lane: RaceLane, altitude: CGFloat, now: TimeInterval, spread: CGFloat, small: Bool = false, pad: Bool = false) {
        let side: CGFloat = lane.zone == .left ? -1 : 1
        let i = smokeCursor
        smokeCursor = (i + 1) % smoke.count
        var s = smoke[i]
        s.x = side * Self.laneX + CGFloat.random(in: -0.25...0.25)
        s.a = altitude - 0.75 - spread * 0.3
        s.z = 2.15 + CGFloat.random(in: 0...0.5)
        s.vx = pad ? (Bool.random() ? 1 : -1) * CGFloat.random(in: 2...5) : side * CGFloat.random(in: 0.05...0.5)
        s.born = now
        s.size = small ? 0.35 : (pad ? CGFloat.random(in: 1.0...1.6) : CGFloat.random(in: 0.55...0.9))
        smoke[i] = s
    }

    // MARK: - Per frame

    func update(dt: CGFloat, cameraAltitude A: CGFloat, climbRate: CGFloat, lead: CGFloat, now: TimeInterval, proj: Projection, size: CGSize, reduceMotion: Bool) {
        let landing = landingAltitude
        let pitch = landing == nil ? CGFloat(AscentCamera.worldPitch(altitude: Double(A))) : 0
        shader.uniformNamed("u_alt")?.floatValue = Float((landing ?? A) + 1)
        shader.uniformNamed("u_pitch")?.floatValue = Float(pitch)
        shader.uniformNamed("u_R")?.floatValue = landing == nil ? Float(AscentCamera.planetRadius) : 1500
        shader.uniformNamed("u_body")?.floatValue = landing == nil ? 0 : 1
        shader.uniformNamed("u_cloudAlt")?.floatValue = Float(Self.cloudShellAltitude)
        shader.uniformNamed("u_clock")?.floatValue = Float(reduceMotion ? 0 : now.truncatingRemainder(dividingBy: 1000))
        flash = max(0, flash - dt * 1.8)
        shader.uniformNamed("u_flash")?.floatValue = Float(flash)

        let R = CGFloat(AscentCamera.planetRadius)
        let hide = landing != nil
        for p in props {
            p.x += p.vx * dt
            place(p, A: A, R: R, proj: proj, size: size, hidden: hide)
            if p.spin != 0, !reduceMotion { p.node.zRotation += p.spin * dt }
        }
        updateClouds(A: A, R: R, proj: proj, size: size, hidden: hide)
        for c in foreground {
            place(c, A: A, R: R, proj: proj, size: size, hidden: hide)
            c.node.xScale = abs(c.node.xScale) * c.flip
        }
        updateLaunchSite(A: A, proj: proj, hidden: hide)
        updateSmoke(A: landing ?? A, proj: proj, now: now, dt: dt)
        updateStreaks(climbRate: landing == nil ? climbRate : 0, proj: proj, size: size, dt: dt, A: A)
        updateSkyBodies(lead: lead, A: A, proj: proj, size: size, now: now, reduceMotion: reduceMotion)
        updateLanes(dt: dt, A: A, climbRate: climbRate, proj: proj, now: now, reduceMotion: reduceMotion)
        if debugOn { drawDebug(A: A, climbRate: climbRate, pitch: pitch, proj: proj, size: size) } else { debug.path = nil; debugLabel.text = nil }
    }

    func worldPoint(x: CGFloat, a: CGFloat, z: CGFloat, A: CGFloat, R: CGFloat, proj: Projection) -> CGPoint {
        let drop = (x * x + z * z) / (2 * R)
        return proj.screen(x: x, h: a - A - drop, z: z)
    }

    private func place(_ p: Prop, A: CGFloat, R: CGFloat, proj: Projection, size: CGSize, hidden: Bool) {
        let pos = worldPoint(x: p.x, a: p.a, z: p.z, A: A, R: R, proj: proj)
        let tex = p.node.texture?.size() ?? CGSize(width: 1, height: 1)
        let scale = p.width * proj.ppu(p.z) / tex.width
        let h = tex.height * scale
        let onScreen = pos.y + h > -40 && pos.y - (p.anchorBottom ? 0 : h / 2) < size.height + 40 && pos.x > -scale * tex.width && pos.x < size.width + scale * tex.width
        p.node.isHidden = hidden || !onScreen
        guard !p.node.isHidden else { return }
        p.node.position = pos
        p.node.setScale(scale)
        p.node.zPosition = -1000 - min(p.z, 1400)
        if p.tint > 0 {
            p.node.color = UIColor(red: 0.62, green: 0.76, blue: 1, alpha: 1)
            p.node.colorBlendFactor = p.tint
        }
    }

    private func updateClouds(A: CGFloat, R: CGFloat, proj: Projection, size: CGSize, hidden: Bool) {
        let top = size.height + 60
        for c in clouds {
            var pos = worldPoint(x: c.x, a: c.a, z: c.z, A: A, R: R, proj: proj)
            let tex = c.node.texture?.size() ?? CGSize(width: 1, height: 1)
            let scale = c.width * proj.ppu(c.z) / tex.width
            if pos.y < -tex.height * scale {
                // Fell below the screen: re-seed above the top edge at an altitude in the band (same z, same parallax),
                // so the stream thins out and ends as the rockets leave the band.
                let need = A + 1 + (top - proj.horizonY) * c.z / proj.f + CGFloat.random(in: 2...20) * c.z / 40
                if need <= Self.cloudBand.upperBound {
                    c.a = need
                    c.x = CGFloat.random(in: -0.8...0.8) * c.z * 0.8
                    pos = worldPoint(x: c.x, a: c.a, z: c.z, A: A, R: R, proj: proj)
                }
            }
            let visible = !hidden && pos.y > -tex.height * scale && pos.y < top + tex.height * scale
            c.node.isHidden = !visible
            guard visible else { continue }
            c.node.position = pos
            c.node.setScale(scale)
            c.node.xScale = scale * c.flip
            c.node.zPosition = -1000 - c.z
            c.node.alpha = 1 - min(0.5, max(0, A - c.a) / 160)
        }
    }

    private func updateLaunchSite(A: CGFloat, proj: Projection, hidden: Bool) {
        // A tower stands on the pad outside each rocket; its clamp arm grips the hull until lift-off, then swings up
        // and away (`clampsOpen`). Both fall away with the ground as the rockets climb.
        let towerZ: CGFloat = 2.9, towerX: CGFloat = 2.15
        for (zone, g) in gantries {
            let side: CGFloat = zone == .left ? -1 : 1
            let base = proj.screen(x: side * towerX, h: -0.6 - A, z: towerZ)
            g.position = base
            g.setScale(proj.ppu(towerZ) * 0.55 / 70)
            g.xScale = abs(g.xScale) * -side
            g.zPosition = -1000 - towerZ
            g.isHidden = hidden || base.y > 4000
            guard let clamp = clamps[zone] else { continue }
            clamp.position = proj.screen(x: side * (towerX - 0.2), h: -0.35 - A, z: towerZ)
            let reach = proj.ppu(towerZ) * (towerX - 0.2 - Self.laneX - Self.podWidth * 0.42) / 260
            clamp.setScale(max(0.01, reach))
            clamp.xScale = max(0.01, reach) * -side
            clamp.zRotation = -side * clampsOpen * 1.1
            clamp.zPosition = -1000 - towerZ + 0.1
            clamp.isHidden = g.isHidden
        }
    }

    private func updateSmoke(A: CGFloat, proj: Projection, now: TimeInterval, dt: CGFloat) {
        for i in smoke.indices {
            var s = smoke[i]
            let age = CGFloat(now - s.born)
            guard age < 2.6 else { s.node.alpha = 0; continue }
            s.x += s.vx * dt
            s.vx *= 1 - min(1, dt * 0.8)
            smoke[i] = s
            s.node.position = proj.screen(x: s.x, h: s.a - A, z: s.z)
            s.node.setScale(s.size * (0.6 + age * 0.9) * proj.ppu(s.z) / 160)
            s.node.alpha = max(0, 0.85 * (1 - age / 2.6))
            s.node.zPosition = -900 - s.z
        }
    }

    private func updateStreaks(climbRate: CGFloat, proj: Projection, size: CGSize, dt: CGFloat, A: CGFloat) {
        let strength = min(1, max(0, (climbRate - 6) / 40))
        for i in streaks.indices {
            var s = streaks[i]
            let speed = proj.f * climbRate / s.z
            s.y -= speed * dt / size.height
            if s.y < -0.2 { s.y = 1.1; s.x = CGFloat.random(in: -1...1); s.z = CGFloat.random(in: 2.5...9) }
            streaks[i] = s
            s.node.position = CGPoint(x: size.width / 2 + s.x * size.width * 0.55, y: s.y * size.height)
            s.node.size = CGSize(width: max(1.5, 4 / s.z * 2), height: min(size.height * 0.22, speed * 0.04))
            s.node.zPosition = -1000 - s.z
            s.node.alpha = strength * (A > 160 ? 0.16 : 0.22)
            s.node.color = A > 160 ? UIColor(red: 0.8, green: 0.9, blue: 1, alpha: 1) : .white
        }
    }

    private func updateSkyBodies(lead: CGFloat, A: CGFloat, proj: Projection, size: CGSize, now: TimeInterval, reduceMotion: Bool) {
        // The sun shows once the rockets are above the cloud deck (the cloud-break reveal).
        let above = smoothstep(Self.cloudShellAltitude + 4, Self.cloudShellAltitude + 22, A)
        sun.alpha = landingAltitude != nil ? 0 : above * (1 - 0.4 * smoothstep(300, 600, A))
        sun.position = CGPoint(x: size.width * 0.16, y: size.height * 0.80)
        sun.setScale(size.height * 0.5 / 320)
        if !reduceMotion { sun.zRotation = CGFloat(now) * 0.03 }
        // The Moon: a pale day-moon at lift-off that grows with the leader's progress into the whole sky.
        let p = lead
        let grow = 40 + 1000 * pow(p, 4)
        let centre = smoothstep(0.7, 1.0, p)
        moon.size = CGSize(width: grow, height: grow)
        moon.position = CGPoint(x: size.width * (0.5 + 0.22 * (1 - centre)), y: size.height * (0.92 - 0.06 * centre) + grow * 0.15 - moonSlide * size.height * 1.4)
        moon.alpha = landingAltitude != nil ? 0 : 0.55 + 0.45 * smoothstep(40, 300, A)
        moonGlow.position = moon.position
        moonGlow.size = CGSize(width: grow * 1.6, height: grow * 1.6)
        moonGlow.alpha = moon.alpha * 0.35 * smoothstep(100, 400, A)
        // The Moon gate (finish line) descends toward the racers over the last stretch of the trip.
        let g = smoothstep(0.86, 1.0, p)
        gate.alpha = landingAltitude != nil ? 0 : smoothstep(0.84, 0.9, p)
        gate.position = CGPoint(x: size.width / 2, y: size.height * (1.15 - 0.42 * g))
        gate.setScale(size.width * (0.55 + 0.45 * g) / 600)
        earth.isHidden = landingAltitude == nil
        earth.size = CGSize(width: 140, height: 140)
        earth.position = CGPoint(x: size.width * 0.22, y: size.height * 0.80 + (reduceMotion ? 0 : sin(CGFloat(now) * 0.5) * 3))
    }

    private func updateLanes(dt: CGFloat, A: CGFloat, climbRate: CGFloat, proj: Projection, now: TimeInterval, reduceMotion: Bool) {
        let ppu = proj.ppu(proj.zp)
        let space = smoothstep(220, 420, A)
        for lane in lanes.values {
            // Kick spring (underdamped: a little overshoot = follow-through) and the rocket's rock.
            let k: CGFloat = 70, damping: CGFloat = 2 * 0.55 * sqrt(70)
            lane.kickVelocity += (-k * lane.kick - damping * lane.kickVelocity) * dt
            lane.kick += lane.kickVelocity * dt
            lane.tiltVelocity += (-60 * lane.tilt - 2 * 0.5 * sqrt(60) * lane.tiltVelocity) * dt
            lane.tilt += lane.tiltVelocity * dt
            // Compression while the player squats down (anticipation): the whole lane sinks a touch.
            let dip = -lane.charge * 10
            lane.node.position = CGPoint(x: 0, y: lane.raceOffset + lane.kick + dip)
            lane.rocket.zRotation = reduceMotion ? 0 : lane.tilt * 0.05
            let side: CGFloat = lane.zone == .left ? -1 : 1
            let feet = proj.screen(x: side * Self.laneX, h: 0, z: proj.zp)
            lane.screenX = feet.x
            lane.feet = feet
            let s = ppu * Self.podWidth / 300
            lane.rocket.position = feet
            lane.pod.setScale(s)
            lane.band.setScale(s)
            lane.band.color = lane.color
            lane.lip.position = feet
            lane.lip.setScale(s)
            // Burn: anticipation draws the flames in and brightens the core; a rep blasts them long; cruise follows
            // the climb rate; in vacuum they widen into blue-white plumes.
            lane.flare = max(0, lane.flare - dt * 1.4)
            let cruise: CGFloat = 0.32 + min(0.4, climbRate / 70)
            let flicker: CGFloat = reduceMotion ? 1 : 0.92 + 0.08 * sin(CGFloat(now) * 47 + side * 3)
            let nozzleY = -(292 - 37) * s
            for (i, f) in lane.flames.enumerated() {
                let x: CGFloat = [-58, 0, 58][i] * s
                let main: CGFloat = i == 1 ? 1 : 0.7
                let length = (cruise * (1 - 0.55 * lane.charge) + lane.flare * 1.2) * flicker * main * (1 + 0.4 * space)
                f.position = CGPoint(x: x, y: nozzleY + 6 * s)
                f.xScale = ppu * (0.20 + 0.10 * min(1, lane.flare) + 0.12 * space) * main / 128
                f.yScale = ppu * length / 420
                f.color = UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1)
                f.colorBlendFactor = space * 0.6
            }
            lane.glow.position = CGPoint(x: 0, y: nozzleY - 20 * s)
            let g = ppu * (0.6 + lane.flare * 0.5 + lane.charge * 0.3)
            lane.glow.size = CGSize(width: g, height: g)
            lane.glow.alpha = 0.22 + 0.3 * min(1, lane.flare) + 0.3 * lane.charge + 0.25 * lane.slipstream
            lane.glow.color = lane.charge > 0.05 || lane.slipstream > 0.1 ? lane.color : MoonPalette.flame
            lane.flash.position = CGPoint(x: 0, y: nozzleY)
            lane.flash.size = CGSize(width: ppu * 1.1, height: ppu * 0.7)
        }
    }

    // MARK: - Debug overlay: anchors, eye level, the limb, lane offsets, motion vectors

    private func drawDebug(A: CGFloat, climbRate: CGFloat, pitch: CGFloat, proj: Projection, size: CGSize) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: proj.feetY)); path.addLine(to: CGPoint(x: size.width, y: proj.feetY))
        path.move(to: CGPoint(x: 0, y: proj.horizonY)); path.addLine(to: CGPoint(x: size.width, y: proj.horizonY))
        let dip = CGFloat(AscentCamera.horizonDip(altitude: Double(A)))
        let limbY = proj.horizonY - proj.f * tan(dip - pitch)
        for x in stride(from: CGFloat(0), to: size.width, by: 24) { path.move(to: CGPoint(x: x, y: limbY)); path.addLine(to: CGPoint(x: x + 12, y: limbY)) }
        for lane in lanes.values {
            let y = lane.feet.y + lane.node.position.y
            path.addRect(CGRect(x: lane.feet.x - 20, y: y - 20, width: 40, height: 40))
            path.move(to: CGPoint(x: lane.feet.x, y: lane.feet.y)); path.addLine(to: CGPoint(x: lane.feet.x, y: y))
        }
        let R = CGFloat(AscentCamera.planetRadius)
        for p in props + clouds where !p.node.isHidden {
            let pos = worldPoint(x: p.x, a: p.a, z: p.z, A: A, R: R, proj: proj)
            let v = CGFloat(AscentCamera.screenVelocity(z: Double(p.z), climbRate: Double(climbRate), f: Double(proj.f)))
            path.move(to: CGPoint(x: pos.x - 8, y: pos.y)); path.addLine(to: CGPoint(x: pos.x + 8, y: pos.y))
            path.move(to: pos); path.addLine(to: CGPoint(x: pos.x, y: pos.y + max(-300, v * 0.25)))
        }
        debug.path = path
        let offsets = Zone.allCases.compactMap { lanes[$0] }.map { String(format: "%+.0f", $0.raceOffset) }.joined(separator: " / ")
        debugLabel.text = String(format: "CAMERA ALT %.1f u  CLIMB %.1f u/s\nlimb dip %.1f°  world pitch %.1f°  lane offsets %@ pt\nlayer speed (pt/s): z3 %.0f  z20 %.0f  z150 %.0f",
                                 A, climbRate, dip * 180 / .pi, pitch * 180 / .pi, offsets,
                                 AscentCamera.screenVelocity(z: 3, climbRate: Double(climbRate), f: Double(proj.f)),
                                 AscentCamera.screenVelocity(z: 20, climbRate: Double(climbRate), f: Double(proj.f)),
                                 AscentCamera.screenVelocity(z: 150, climbRate: Double(climbRate), f: Double(proj.f)))
    }
}
