import QuartzCore
import SpriteKit

/// Jungle Drift environment: an endless river built from pooled, world-anchored scenery on the shared projection.
/// Scenery is land-fixed and streams from the horizon past the camera; the raft (in the scene) rides the current.
@MainActor
final class JungleWorld {
    enum PropKind { case tree, palm, fern, reeds, rock, log, lily, backTree, heliconia, egret, midRock }

    final class Prop {
        let node = SKSpriteNode()
        var kind: PropKind = .tree
        var side: CGFloat = 1
        var x: CGFloat = 0
        var h: CGFloat = 0
        var z: CGFloat = 0
        var heightUnits: CGFloat = 1
        var inWater = false
        var swayPhase: CGFloat = 0
        var bankMargin: CGFloat = 0
        var born: TimeInterval = 0
        /// Foam wake behind a midstream rock (water props only).
        var wake: SKSpriteNode?
        init() { node.anchorPoint = CGPoint(x: 0.5, y: 0) }
    }

    struct Biome {
        let name: String
        let treeDensity: Double       // chance a bank slot holds a big tree (else fern/reeds/empty)
        let palmShare: Double
        let mist: CGFloat
        let shafts: Float
        let fog: SIMD3<Float>
        let haze: SIMD3<Float>
    }

    static let biomes: [Biome] = [
        Biome(name: "Open River", treeDensity: 0.45, palmShare: 0.35, mist: 0.15, shafts: 0.6,
              fog: SIMD3(0.42, 0.66, 0.55), haze: SIMD3(0.93, 0.82, 0.55)),
        Biome(name: "Deep Canopy", treeDensity: 0.85, palmShare: 0.15, mist: 0.35, shafts: 1.4,
              fog: SIMD3(0.20, 0.42, 0.36), haze: SIMD3(0.62, 0.78, 0.50)),
        Biome(name: "Lost Ruins", treeDensity: 0.55, palmShare: 0.30, mist: 0.25, shafts: 1.0,
              fog: SIMD3(0.48, 0.58, 0.52), haze: SIMD3(0.95, 0.72, 0.48)),
        Biome(name: "Misty Backwater", treeDensity: 0.65, palmShare: 0.20, mist: 0.7, shafts: 0.5,
              fog: SIMD3(0.58, 0.72, 0.70), haze: SIMD3(0.80, 0.86, 0.78)),
    ]
    static let biomeLength: CGFloat = 230

    let root = SKNode()
    let sky = SKSpriteNode(texture: Art.white)
    let river = SKSpriteNode(texture: Art.white)
    let riverShader = Shaders.river()
    let skyShader = Shaders.jungleSky()
    let treelines = [SKSpriteNode(texture: Art.treeline[0]), SKSpriteNode(texture: Art.treeline[1])]
    let horizonGlow = SKSpriteNode(texture: Art.glow)
    var props: [Prop] = []
    var mists: [SKSpriteNode] = []
    var ambientBirds: [(node: SKSpriteNode, x: CGFloat, h: CGFloat, z: CGFloat, vx: CGFloat)] = []
    let canopyLeft = SKSpriteNode(texture: Art.canopyCorner)
    let canopyRight = SKSpriteNode(texture: Art.canopyCorner)
    var vines: [SKSpriteNode] = []
    var landmark: (node: SKSpriteNode, z: CGFloat, x: CGFloat, h: CGFloat, heightUnits: CGFloat, overhead: Bool)?
    var landmarkFrames: [SKTexture]?
    let landmarkMist = SKSpriteNode(texture: Art.glow)
    var landmarkCycle = 0
    /// Incidental landmarks between calm stretches, so the endless journey keeps changing.
    var nextIncidentalAt: CGFloat = 120
    /// Shade as the raft passes under the stone arch (0 … 1).
    let shade = SKSpriteNode(texture: Art.white)
    let life: JungleLife
    var rng = SeededRandom(seed: 2027)
    var biomeBlend: CGFloat = 0
    private(set) var fogColor = SIMD3<Float>(0.42, 0.66, 0.55)
    let waterDrop: CGFloat = 0.22

    init() {
        life = JungleLife(root: root)
        root.zPosition = 0
        sky.anchorPoint = .zero
        sky.shader = skyShader
        sky.zPosition = Layer.sky
        river.anchorPoint = .zero
        river.shader = riverShader
        river.zPosition = Layer.floor
        root.addChild(sky)
        root.addChild(river)
        for (i, line) in treelines.enumerated() {
            line.anchorPoint = CGPoint(x: 0.5, y: 0)
            line.zPosition = Layer.skyline - CGFloat(i)
            root.addChild(line)
        }
        horizonGlow.color = UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)
        horizonGlow.colorBlendFactor = 1
        horizonGlow.blendMode = .add
        horizonGlow.alpha = 0.35
        horizonGlow.zPosition = Layer.horizonGlow
        root.addChild(horizonGlow)

        // Bank scenery: 24 slots per side, 4 units apart, recycled far away with fresh, biome-dependent picks.
        for side in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<24 {
                let prop = Prop()
                prop.side = side
                respawnBankProp(prop, z: CGFloat(i) * 4 + 2 + (side > 0 ? 2 : 0), distance: 0, now: 0, fadeIn: false)
                root.addChild(prop.node)
                props.append(prop)
            }
        }
        // The forest wall: a back row of tall, darker trees behind the bank, so the river runs through a corridor
        // of jungle instead of a strip of lawn.
        for side in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<16 {
                let prop = Prop()
                prop.side = side
                prop.kind = .backTree
                respawnBackTree(prop, z: CGFloat(i) * 6 + 3 + (side > 0 ? 3 : 0), now: 0, fadeIn: false)
                root.addChild(prop.node)
                props.append(prop)
            }
        }
        // River clutter: logs, lily pads, reed islands and rocks, kept out of the raft's lane.
        for i in 0..<10 {
            let prop = Prop()
            prop.inWater = true
            let wake = SKSpriteNode(texture: Art.rockWake)
            wake.anchorPoint = CGPoint(x: 0.5, y: 30 / Art.rockWake.size().height)
            wake.isHidden = true
            root.addChild(wake)
            prop.wake = wake
            respawnWaterProp(prop, z: CGFloat(i) * 9 + 6, distance: 0, now: 0, fadeIn: false)
            root.addChild(prop.node)
            props.append(prop)
        }
        for i in 0..<7 {
            let mist = SKSpriteNode(texture: Art.glow)
            mist.color = .white
            mist.colorBlendFactor = 1
            mist.alpha = 0
            mist.userData = ["z": CGFloat(i) * 9 + 8, "x": CGFloat(i % 2 == 0 ? -1 : 1) * CGFloat(2 + i % 3 * 2)]
            mist.zPosition = Layer.floor + 5
            root.addChild(mist)
            mists.append(mist)
        }
        for i in 0..<6 {
            let bird = SKSpriteNode(texture: Art.macawTexture(.glide, palette: i % 2))
            bird.anchorPoint = Art.macawAnchor
            bird.zPosition = Layer.skyline + 10
            bird.isHidden = true
            root.addChild(bird)
            ambientBirds.append((bird, 0, 0, 0, 0))
        }
        for (node, flip) in [(canopyLeft, false), (canopyRight, true)] {
            node.anchorPoint = CGPoint(x: 0, y: 1)
            node.xScale = flip ? -1 : 1
            node.zPosition = Layer.flash - 50
            root.addChild(node)
        }
        landmarkMist.color = .white
        landmarkMist.colorBlendFactor = 1
        landmarkMist.alpha = 0
        root.addChild(landmarkMist)
        shade.color = UIColor(red: 0.02, green: 0.08, blue: 0.08, alpha: 1)
        shade.colorBlendFactor = 1
        shade.alpha = 0
        shade.anchorPoint = .zero
        shade.zPosition = Layer.body + 40   // over the world and the riders, under the HUD
        root.addChild(shade)
        for i in 0..<3 {
            let vine = SKSpriteNode(texture: Art.vine)
            vine.anchorPoint = CGPoint(x: 0.5, y: 1)
            vine.zPosition = Layer.flash - 51
            vine.userData = ["fx": [0.08, 0.86, 0.95][i], "phase": Double(i) * 1.7]
            root.addChild(vine)
            vines.append(vine)
        }
    }

    // MARK: - Layout

    func layout(size: CGSize, proj: Projection) {
        sky.position = CGPoint(x: 0, y: proj.horizonY - 2)
        sky.size = CGSize(width: size.width, height: size.height - proj.horizonY + 2)
        river.position = .zero
        river.size = CGSize(width: size.width, height: proj.horizonY)
        treelines[0].size = CGSize(width: size.width * 1.5, height: size.height * 0.16)
        treelines[1].size = CGSize(width: size.width * 1.4, height: size.height * 0.11)
        horizonGlow.size = CGSize(width: size.width * 1.4, height: size.height * 0.12)
        horizonGlow.position = CGPoint(x: proj.cx, y: proj.horizonY)
        let canopyW = size.width * 0.42
        canopyLeft.size = CGSize(width: canopyW, height: canopyW * 360 / 700)
        canopyRight.size = canopyLeft.size
        canopyLeft.position = CGPoint(x: -10, y: size.height + 10)
        canopyRight.position = CGPoint(x: size.width + 10, y: size.height + 10)
        for vine in vines {
            let fx = vine.userData?["fx"] as? Double ?? 0.1
            vine.position = CGPoint(x: size.width * CGFloat(fx), y: size.height + 6)
            vine.size = CGSize(width: size.height * 0.05, height: size.height * 0.32)
        }
        life.layout(size: size, proj: proj)
        shade.size = size
        let res = SIMD2<Float>(Float(river.size.width), Float(river.size.height))
        riverShader.uniformNamed("u_res")?.vectorFloat2Value = res
        riverShader.uniformNamed("u_horizon")?.floatValue = Float(proj.horizonY)
        riverShader.uniformNamed("u_cx")?.floatValue = Float(proj.cx)
        riverShader.uniformNamed("u_camH")?.floatValue = Float(proj.camH)
        riverShader.uniformNamed("u_waterDrop")?.floatValue = Float(waterDrop)
        skyShader.uniformNamed("u_res")?.vectorFloat2Value = SIMD2<Float>(Float(sky.size.width), Float(sky.size.height))
        skyShader.uniformNamed("u_cx")?.floatValue = Float(proj.cx)
    }

    // MARK: - Spawning

    func biome(atDistance d: CGFloat) -> Biome {
        Self.biomes[Int(max(0, d) / Self.biomeLength) % Self.biomes.count]
    }

    private func respawnBankProp(_ prop: Prop, z: CGFloat, distance: CGFloat, now: TimeInterval, fadeIn: Bool) {
        let b = biome(atDistance: distance + z)
        let roll = rng.next()
        let node = prop.node
        node.isHidden = false
        if roll < b.treeDensity {
            if rng.next() < b.palmShare {
                prop.kind = .palm; node.texture = Art.palm; prop.heightUnits = CGFloat(4.5 + rng.next() * 2.5)
            } else {
                prop.kind = .tree; node.texture = Art.jungleTrees[Int(rng.next() * 3) % 3]; prop.heightUnits = CGFloat(6 + rng.next() * 6)
            }
            prop.bankMargin = CGFloat(1.2 + rng.next() * 5)
        } else if roll < b.treeDensity + 0.3 {
            if rng.next() < 0.3 {
                // A flowering heliconia: the bank's one warm colour accent.
                prop.kind = .heliconia; node.texture = Art.heliconia; prop.heightUnits = CGFloat(1.5 + rng.next() * 0.6); prop.bankMargin = CGFloat(0.2 + rng.next() * 1.0)
            } else {
                prop.kind = .fern; node.texture = Art.fern; prop.heightUnits = CGFloat(1.0 + rng.next() * 0.8); prop.bankMargin = CGFloat(0.3 + rng.next() * 1.2)
            }
        } else if roll < b.treeDensity + 0.36, b.mist < 0.3 || b.name == "Misty Backwater" {
            // An egret fishing in the shallows (head up watching, head down striking, now and then).
            prop.kind = .egret; node.texture = Art.egretFrames[0]; prop.heightUnits = 1.25; prop.bankMargin = CGFloat(-0.35 + rng.next() * 0.2)
        } else if roll < b.treeDensity + 0.45 {
            prop.kind = .rock; node.texture = Art.mossyRock; prop.heightUnits = CGFloat(0.8 + rng.next() * 0.9); prop.bankMargin = CGFloat(0.0 + rng.next() * 0.6)
        } else {
            prop.kind = .reeds; node.texture = Art.reeds; prop.heightUnits = CGFloat(1.0 + rng.next() * 0.6); prop.bankMargin = CGFloat(-0.3 + rng.next() * 0.5)
        }
        prop.z = z
        prop.h = -waterDrop
        prop.swayPhase = CGFloat(rng.next() * 6.28)
        prop.born = fadeIn ? now : -10
        // Reset scale first: SKSpriteNode stores `size` divided by the current scale, so a recycled (tiny, far)
        // sprite would otherwise balloon to many times its size.
        node.setScale(1)
        node.zRotation = 0
        if let t = node.texture { node.size = t.size() }
    }

    private func respawnBackTree(_ prop: Prop, z: CGFloat, now: TimeInterval, fadeIn: Bool) {
        let node = prop.node
        node.texture = rng.next() < 0.25 ? Art.palm : Art.jungleTrees[Int(rng.next() * 3) % 3]
        prop.heightUnits = CGFloat(9 + rng.next() * 6)
        prop.bankMargin = CGFloat(6 + rng.next() * 4)
        prop.z = z
        prop.h = -waterDrop
        prop.swayPhase = CGFloat(rng.next() * 6.28)
        prop.born = fadeIn ? now : -10
        node.isHidden = false
        node.setScale(1)
        node.zRotation = 0
        if let t = node.texture { node.size = t.size() }
    }

    private func respawnWaterProp(_ prop: Prop, z: CGFloat, distance: CGFloat, now: TimeInterval, fadeIn: Bool) {
        let roll = rng.next()
        let node = prop.node
        if roll < 0.38 { prop.kind = .lily; node.texture = Art.lilyPad; prop.heightUnits = 0.22 }
        else if roll < 0.62 { prop.kind = .log; node.texture = Art.floatingLog; prop.heightUnits = 0.3 }
        else if roll < 0.78 { prop.kind = .reeds; node.texture = Art.reeds; prop.heightUnits = 0.9 }
        else { prop.kind = .midRock; node.texture = Art.mossyRock; prop.heightUnits = 0.55 }
        prop.wake?.isHidden = prop.kind != .midRock
        prop.side = rng.next() < 0.5 ? -1 : 1
        prop.x = prop.side * CGFloat(2.3 + rng.next() * 2.2)   // never in the raft's lane (|x| < 1.6)
        prop.z = z
        prop.h = -waterDrop - 0.03
        prop.born = fadeIn ? now : -10
        // Reset scale first: SKSpriteNode stores `size` divided by the current scale, so a recycled (tiny, far)
        // sprite would otherwise balloon to many times its size.
        node.setScale(1)
        node.zRotation = 0
        if let t = node.texture { node.size = t.size() }
    }

    enum LandmarkKind { case temple, kapok, arch, fallen, waterfall }
    static let landmarkOrder: [LandmarkKind] = [.temple, .arch, .kapok, .waterfall, .fallen]

    func spawnLandmark(z: CGFloat) -> String {
        landmark?.node.removeFromParent()
        landmarkFrames = nil
        let kind = Self.landmarkOrder[landmarkCycle % Self.landmarkOrder.count]
        landmarkCycle += 1
        let side: CGFloat = landmarkCycle % 2 == 0 ? 1 : -1
        let node = SKSpriteNode()
        node.alpha = 0
        root.addChild(node)
        let name: String
        switch kind {
        case .temple:
            node.texture = Art.ruinTemple; node.anchorPoint = CGPoint(x: 0.5, y: 0)
            landmark = (node, z, side * 11, -waterDrop, 9, false); name = "Lost temple"
        case .kapok:
            node.texture = Art.giantKapok; node.anchorPoint = CGPoint(x: 0.5, y: 0)
            landmark = (node, z, side * 11, -waterDrop, 18, false); name = "Giant kapok tree"
        case .fallen:
            node.texture = Art.fallenTree; node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            landmark = (node, z, 0, 3.4, 2.6, true); name = "Fallen giant"
        case .arch:
            // Spans the river; the raft passes underneath (its shade falls across the deck).
            node.texture = Art.stoneArch; node.anchorPoint = CGPoint(x: 0.5, y: 0)
            landmark = (node, z, 0, -waterDrop, 7.4, true); name = "Stone gateway"
        case .waterfall:
            landmarkFrames = Art.waterfallFrames
            node.texture = Art.waterfallFrames[0]; node.anchorPoint = CGPoint(x: 0.5, y: 0)
            landmark = (node, z, side * 10.5, -waterDrop, 11, false); name = "Hidden falls"
        }
        if let t = node.texture { node.size = t.size() }
        return name
    }

    func spawnAmbientFlock(proj: Projection) {
        // Wildlife: a small flock crossing the river between the trees, far ahead (never a hazard).
        let z = CGFloat(30 + rng.next() * 30)
        let h = CGFloat(4 + rng.next() * 4)
        let dir: CGFloat = rng.next() < 0.5 ? -1 : 1
        for i in ambientBirds.indices {
            ambientBirds[i] = (ambientBirds[i].node, -dir * CGFloat(14 + Double(i) * 1.4), h + CGFloat(i % 3) * 0.7, z + CGFloat(i) * 0.8, dir * CGFloat(6 + rng.next() * 3))
            ambientBirds[i].node.isHidden = false
        }
    }

    // MARK: - Per frame

    func update(dt: CGFloat, travel: CGFloat, distance: CGFloat, now: TimeInterval, proj: Projection, size: CGSize, reduceMotion: Bool, celebrate: CGFloat) {
        // Something new on the horizon every so often, even between calm stretches.
        if landmark == nil, distance >= nextIncidentalAt {
            _ = spawnLandmark(z: 90)
            nextIncidentalAt = distance + 150
        }
        let clock = Float(reduceMotion ? 0 : now.truncatingRemainder(dividingBy: 1000))
        // Biome atmosphere crossfades over the last 40 units of each stretch.
        let b0 = biome(atDistance: distance)
        let b1 = biome(atDistance: distance + 40)
        let local = distance.truncatingRemainder(dividingBy: Self.biomeLength)
        let blend = Float(smoothstep(Self.biomeLength - 40, Self.biomeLength, local))
        fogColor = b0.fog + (b1.fog - b0.fog) * blend
        let haze = b0.haze + (b1.haze - b0.haze) * blend
        let mistLevel = b0.mist + (b1.mist - b0.mist) * CGFloat(blend)
        let shafts = b0.shafts + (b1.shafts - b0.shafts) * blend

        let pan = -proj.curve * 26000
        riverShader.uniformNamed("u_f")?.floatValue = Float(proj.f)
        riverShader.uniformNamed("u_zp")?.floatValue = Float(proj.zp)
        riverShader.uniformNamed("u_offset")?.floatValue = Float(distance.truncatingRemainder(dividingBy: 10000))
        riverShader.uniformNamed("u_curve")?.floatValue = Float(proj.curve)
        riverShader.uniformNamed("u_clock")?.floatValue = clock
        riverShader.uniformNamed("u_fogColor")?.vectorFloat3Value = fogColor
        riverShader.uniformNamed("u_skyRefl")?.vectorFloat3Value = haze
        skyShader.uniformNamed("u_pan")?.floatValue = Float(pan * 0.5)
        skyShader.uniformNamed("u_clock")?.floatValue = clock
        skyShader.uniformNamed("u_shafts")?.floatValue = shafts * (1 + Float(celebrate) * 1.5)
        skyShader.uniformNamed("u_hazeColor")?.vectorFloat3Value = haze
        treelines[0].position = CGPoint(x: proj.cx + pan * 0.55, y: proj.horizonY - 4)
        treelines[1].position = CGPoint(x: proj.cx + pan * 0.8, y: proj.horizonY - 6)
        let fogUI = UIColor(red: CGFloat(fogColor.x), green: CGFloat(fogColor.y), blue: CGFloat(fogColor.z), alpha: 1)
        treelines[0].color = fogUI; treelines[0].colorBlendFactor = 0.35
        horizonGlow.color = UIColor(red: CGFloat(haze.x), green: CGFloat(haze.y), blue: CGFloat(haze.z), alpha: 1)
        life.update(dt: dt, travel: travel, distance: distance, now: now, proj: proj, size: size, pan: pan, haze: haze, fog: fogColor,
                    reduceMotion: reduceMotion)
        let wallUI = fogUI.mixed(with: JunglePalette.canopyDark, amount: 0.55)

        for prop in props {
            prop.z -= travel
            if prop.z < (prop.inWater ? 0.4 : -1.5) {
                if prop.inWater { respawnWaterProp(prop, z: prop.z + 90, distance: distance, now: now, fadeIn: true) }
                else if prop.kind == .backTree { respawnBackTree(prop, z: prop.z + 96, now: now, fadeIn: true) }
                else { respawnBankProp(prop, z: prop.z + 96, distance: distance, now: now, fadeIn: true) }
            }
            if !prop.inWater {
                let world = Double(distance + prop.z)
                prop.x = prop.side * (CGFloat(riverHalfWidth(atWorld: world)) + prop.bankMargin)
            }
            let node = prop.node
            let ppu = proj.ppu(prop.z)
            guard let tex = node.texture else { continue }
            let s = ppu * prop.heightUnits / tex.size().height
            node.setScale(s)
            if prop.kind == .lily || prop.kind == .log {
                node.yScale = s * 0.45   // lying on the water
            }
            node.position = proj.screen(x: prop.x, h: prop.h, z: prop.z)
            node.zPosition = proj.depthZ(prop.z)
            let fadeIn = min(1, CGFloat(now - prop.born) / 0.8)
            node.alpha = fadeIn * (1 - smoothstep(72, 92, prop.z)) * smoothstep(-1.5, 0.6, prop.z)
            if prop.kind == .backTree {
                // The forest wall: darker and hazier than the bank in front of it (depth by value and colour).
                node.color = wallUI
                node.colorBlendFactor = 0.45 + smoothstep(10, 80, prop.z) * 0.45
                node.zPosition = proj.depthZ(prop.z) - 0.5
            } else {
                node.color = fogUI
                node.colorBlendFactor = smoothstep(10, 80, prop.z) * 0.85
            }
            if prop.kind == .egret {
                // Watches for a few seconds, strikes at the water, looks up again.
                let cycle = (now * 0.25 + Double(prop.swayPhase)).truncatingRemainder(dividingBy: 1)
                node.texture = Art.egretFrames[cycle > 0.78 ? 1 : 0]
                node.xScale = abs(node.xScale) * (prop.side > 0 ? -1 : 1)   // facing the river
            }
            if let wake = prop.wake, prop.kind == .midRock {
                // Water piles against the rock and streams away downstream (ahead: the river flows the raft's way).
                wake.position = node.position
                wake.setScale(ppu * 1.1 / 220)
                wake.yScale = wake.xScale * 0.55 * (reduceMotion ? 1 : 1 + 0.06 * sin(CGFloat(now) * 5 + prop.swayPhase))
                wake.zPosition = node.zPosition - 0.01
                wake.alpha = node.alpha * 0.85
                wake.color = fogUI
                wake.colorBlendFactor = node.colorBlendFactor
            }
            // Sway, slower for big trees, harder as a gust passes through (the wind moves through the scene).
            let swaying = prop.kind != .rock && prop.kind != .log && prop.kind != .lily && prop.kind != .midRock && prop.kind != .egret
            if !reduceMotion, swaying {
                let big = prop.kind == .tree || prop.kind == .backTree || prop.kind == .palm
                let speed: CGFloat = big ? 0.8 : 1.6
                let gust = CGFloat(jungleGust(worldZ: Double(distance + prop.z), time: now))
                node.zRotation = sin(CGFloat(now) * speed + prop.swayPhase) * (big ? 0.012 : 0.04) * (1 + 2.5 * gust) - prop.side * gust * (big ? 0.02 : 0.05)
            } else {
                node.zRotation = 0
            }
        }

        if var lm = landmark {
            lm.z -= travel
            landmark = lm
            if lm.z < -2 {
                lm.node.removeFromParent()
                landmark = nil
            } else {
                let ppu = proj.ppu(lm.z)
                if lm.node.texture === Art.stoneArch {
                    lm.node.size = CGSize(width: 16 * ppu, height: 7.4 * ppu)
                    // Passing under it: shade falls across the raft and the riders for a moment.
                    shade.alpha = reduceMotion ? 0 : 0.22 * smoothstep(-0.5, 0.6, lm.z) * (1 - smoothstep(1.6, 3.4, lm.z))
                } else if lm.overhead {
                    lm.node.size = CGSize(width: 22 * ppu, height: 22 * ppu * 320 / 1800)
                } else if let t = lm.node.texture {
                    lm.node.setScale(ppu * lm.heightUnits / t.size().height)
                }
                lm.node.position = proj.screen(x: lm.x, h: lm.h, z: lm.z)
                lm.node.zPosition = proj.depthZ(lm.z) + (lm.overhead ? 0.5 : 0)
                lm.node.alpha = (1 - smoothstep(80, 95, lm.z)) * smoothstep(-1, 1.5, lm.z)
                lm.node.color = fogUI
                lm.node.colorBlendFactor = smoothstep(14, 85, lm.z) * 0.8
                if let frames = landmarkFrames {
                    // The falls: water moving down the sheet, spray rising off the plunge pool.
                    lm.node.texture = frames[Int(now * (reduceMotion ? 4 : 10)) % frames.count]
                    landmarkMist.position = proj.screen(x: lm.x, h: 0.6, z: lm.z)
                    landmarkMist.size = CGSize(width: 4.5 * ppu, height: 2.2 * ppu * (1 + 0.08 * sin(CGFloat(now) * 2)))
                    landmarkMist.zPosition = lm.node.zPosition + 0.1
                    landmarkMist.alpha = lm.node.alpha * 0.5
                } else {
                    landmarkMist.alpha = 0
                }
            }
        } else {
            landmarkMist.alpha = 0
            shade.alpha = 0
        }

        for mist in mists {
            guard var z = mist.userData?["z"] as? CGFloat, let x = mist.userData?["x"] as? CGFloat else { continue }
            z -= travel
            if z < 1 { z += 64 }
            mist.userData?["z"] = z
            let ppu = proj.ppu(z)
            mist.position = proj.screen(x: x, h: 0.2, z: z)
            mist.size = CGSize(width: 9 * ppu, height: 2.4 * ppu)
            mist.zPosition = proj.depthZ(z) + 0.2
            mist.alpha = mistLevel * 0.35 * smoothstep(1, 6, z) * (1 - smoothstep(50, 64, z))
        }

        for i in ambientBirds.indices where !ambientBirds[i].node.isHidden {
            ambientBirds[i].x += ambientBirds[i].vx * dt
            ambientBirds[i].z -= travel
            let b = ambientBirds[i]
            let ppu = proj.ppu(b.z)
            b.node.position = proj.screen(x: b.x, h: b.h, z: b.z)
            b.node.setScale(ppu * 0.75 / Art.macawCanvas.width)
            b.node.zRotation = b.vx < 0 ? 0.25 : -0.25   // banked into the crossing
            b.node.zPosition = proj.depthZ(b.z)
            // Same macaw flap cycle as the hazard flock, each bird on its own rhythm.
            let stroke = birdStroke(fromPhase: now * (4.2 + Double(i) * 0.3) + Double(i) * 0.37)
            b.node.texture = Art.macawTexture(.flap(stroke), palette: i % 2)
            b.node.alpha = 0.9 * (1 - smoothstep(55, 70, b.z))
            if abs(b.x) > 18 || b.z < 2 { ambientBirds[i].node.isHidden = true }
        }

        if !reduceMotion {
            let t = CGFloat(now)
            // The canopy frame catches the same gusts as the banks when they reach the raft.
            let gust = CGFloat(jungleGust(worldZ: Double(distance + 1.5), time: now))
            canopyLeft.zRotation = sin(t * 0.6) * 0.02 - celebrate * 0.03 - gust * 0.03
            canopyRight.zRotation = -sin(t * 0.55 + 1) * 0.02 + celebrate * 0.03 + gust * 0.03
            for vine in vines {
                let phase = vine.userData?["phase"] as? Double ?? 0
                vine.zRotation = sin(t * 0.9 + CGFloat(phase)) * 0.05 * (1 + 2 * gust)
            }
        }
    }

    /// Canopy rustle: the bird warning's first, physical cue.
    func rustle() {
        for node in [canopyLeft, canopyRight] {
            node.run(.sequence([.rotate(byAngle: 0.05, duration: 0.08), .rotate(byAngle: -0.09, duration: 0.12), .rotate(byAngle: 0.04, duration: 0.12)]))
        }
    }
}
