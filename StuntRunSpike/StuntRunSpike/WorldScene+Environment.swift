import QuartzCore
import SpriteKit

/// A building with real volume: a camera-facing front billboard plus a side face that is perspective-warped
/// (SKWarpGeometryGrid) along its depth, so the wall facing the track converges to the vanishing point.
final class VolumeBuilding {
    let front: SKSpriteNode
    let side: SKSpriteNode
    let sideSign: CGFloat
    var x: CGFloat
    var z: CGFloat
    var width: CGFloat
    var depth: CGFloat
    var height: CGFloat

    init(texture: SKTexture, side sign: CGFloat, x: CGFloat, z: CGFloat, width: CGFloat, depth: CGFloat, height: CGFloat) {
        front = SKSpriteNode(texture: texture)
        front.anchorPoint = CGPoint(x: 0.5, y: 0)
        side = SKSpriteNode(texture: texture)
        side.anchorPoint = .zero
        side.size = CGSize(width: WarpQuad.unit, height: WarpQuad.unit)
        sideSign = sign
        self.x = x
        self.z = z
        self.width = width
        self.depth = depth
        self.height = height
    }
}

/// Helpers for drawing world-space quads as warped sprites.
enum WarpQuad {
    static let unit: CGFloat = 100

    /// Grid of `columns + 1` × `rows + 1` source positions, row-major from the bottom-left.
    static func sourceGrid(columns: Int, rows: Int) -> [SIMD2<Float>] {
        var positions: [SIMD2<Float>] = []
        for r in 0...rows {
            for c in 0...columns { positions.append(SIMD2(Float(c) / Float(columns), Float(r) / Float(rows))) }
        }
        return positions
    }

    /// Converts screen points to the node-normalized destination space of a sprite anchored at `origin`.
    static func normalized(_ points: [CGPoint], origin: CGPoint) -> [SIMD2<Float>] {
        points.map { SIMD2(Float(($0.x - origin.x) / unit), Float(($0.y - origin.y) / unit)) }
    }
}

/// A soft dark band projected onto the roof under an overhead structure: it reaches the players before
/// the structure does, which is an honest physical anticipation cue.
final class RoofShadow {
    let node = SKSpriteNode(texture: Art.shadowBand)
    static let source = WarpQuad.sourceGrid(columns: 1, rows: 2)

    init() {
        node.anchorPoint = .zero
        node.size = CGSize(width: WarpQuad.unit, height: WarpQuad.unit)
        node.color = .black
        node.colorBlendFactor = 1
        node.zPosition = Layer.floor + 1
    }

    func update(_ proj: Projection, zNear: CGFloat, zFar: CGFloat, halfWidth: CGFloat, alpha: CGFloat) {
        let near = max(zNear, 0.3)
        guard zFar > near else { node.isHidden = true; return }
        node.isHidden = false
        let mid = (near + zFar) / 2
        let corners = [near, mid, zFar].flatMap { z in
            [proj.screen(x: -halfWidth, h: 0, z: z), proj.screen(x: halfWidth, h: 0, z: z)]
        }
        let origin = corners[0]
        node.position = origin
        node.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 2, sourcePositions: Self.source,
                                               destinationPositions: WarpQuad.normalized(corners, origin: origin))
        node.alpha = alpha
    }
}

/// Large, slow set pieces that approach from far beyond the fog line. Something enormous should move slowly
/// at a distance and quickly when near (game-feel: size comes from speed and contrast).
final class Landmark {
    enum Kind: CaseIterable { case ferrisWheel, signTower, bridge }
    static let unit: CGFloat = 100

    let kind: Kind
    let root = SKNode()
    var x: CGFloat
    var z: CGFloat
    var parts: [SKSpriteNode] = []
    var spinner: SKSpriteNode?
    var shadow: RoofShadow?
    var born: TimeInterval = 0

    init(kind: Kind, side: CGFloat, z: CGFloat) {
        self.kind = kind
        self.z = z
        let u = Landmark.unit
        switch kind {
        case .ferrisWheel:
            // Rim (radius 10.5 units at 1.5× scale) stays clear of the track and pylons.
            x = side * 15.5
            let support = SKSpriteNode(texture: Art.ferrisSupport)
            support.anchorPoint = CGPoint(x: 0.5, y: 0)
            support.size = CGSize(width: 9 * u, height: 7.8 * u)
            let wheel = SKSpriteNode(texture: Art.ferrisWheel)
            wheel.size = CGSize(width: 14 * u, height: 14 * u)
            wheel.position = CGPoint(x: 0, y: 8 * u)
            wheel.zPosition = 0.1
            parts = [support, wheel]
            spinner = wheel
        case .signTower:
            x = side * 12
            let tower = SKSpriteNode(texture: Art.signTower)
            tower.anchorPoint = CGPoint(x: 0.5, y: 0)
            tower.size = CGSize(width: 2 * u, height: 15 * u)
            let sign = SKSpriteNode(texture: Art.stuntRunSign)
            sign.size = CGSize(width: 10 * u, height: 4.6 * u)
            sign.position = CGPoint(x: 0, y: 16.5 * u)
            sign.zPosition = 0.1
            parts = [tower, sign]
            spinner = sign
        case .bridge:
            x = 0
            let bridge = SKSpriteNode(texture: Art.bridge)
            bridge.anchorPoint = CGPoint(x: 0.5, y: 0)
            bridge.size = CGSize(width: 20 * u, height: 11.25 * u)
            parts = [bridge]
            shadow = RoofShadow()
        }
        for part in parts { root.addChild(part) }
    }
}

extension WorldScene {
    // MARK: - Build

    func buildEnvironment() {
        var rng = SeededRandom(seed: 314)
        for sign in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<10 {
                let texture = Art.buildings[Int(rng.next() * Double(Art.buildings.count)) % Art.buildings.count]
                let building = VolumeBuilding(texture: texture, side: sign, x: sign * CGFloat(8 + rng.next() * 5),
                                              z: CGFloat(i) * 10 + CGFloat(rng.next() * 4) + 3,
                                              width: CGFloat(2.6 + rng.next() * 2), depth: CGFloat(3 + rng.next() * 4),
                                              height: CGFloat(4.5 + rng.next() * 6))
                worldRoot.addChild(building.side)
                worldRoot.addChild(building.front)
                buildings.append(building)
            }
        }

        for i in 0..<14 {
            let ring = SKSpriteNode(texture: Art.ring)
            ring.blendMode = .add
            ring.colorBlendFactor = 1
            ring.color = [Palette.teal, Palette.violet, Palette.coral][i % 3]
            ring.isHidden = true
            worldRoot.addChild(ring)
            tunnelRings.append(ring)
        }

        for (i, color) in [Palette.teal, Palette.violet, Palette.coral].enumerated() {
            let beam = SKSpriteNode(texture: Art.searchlight)
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.blendMode = .add
            beam.color = color
            beam.colorBlendFactor = 1
            beam.alpha = 0.16
            beam.zPosition = Layer.sky + 20
            beam.userData = ["phase": Double(i) * 2.1, "fx": [0.18, 0.52, 0.83][i]]
            worldRoot.addChild(beam)
            searchlights.append(beam)
        }

        for _ in 0..<48 {
            let spark = SKSpriteNode(texture: Art.glow)
            spark.blendMode = .add
            spark.colorBlendFactor = 1
            spark.isHidden = true
            spark.zPosition = Layer.sky + 40
            worldRoot.addChild(spark)
            fireworks.append(spark)
        }

        // Cast shadows tie the players to the roof: a sheared copy of the live cutout, plus contact shadows.
        bodyShadow.anchorPoint = CGPoint(x: 0.5, y: 0)
        bodyShadow.color = .black
        bodyShadow.colorBlendFactor = 1
        bodyShadow.alpha = 0.3
        bodyShadow.zPosition = Layer.pad - 0.3
        bodyShadow.isHidden = true
        addChild(bodyShadow)
        for zone in Zone.allCases {
            let shadow = SKSpriteNode()
            shadow.anchorPoint = CGPoint(x: 0.5, y: 0)
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0.3
            shadow.zPosition = Layer.pad - 0.3
            addChild(shadow)
            placeholderShadows[zone] = shadow

            let contact = SKSpriteNode(texture: Art.glow)
            contact.color = .black
            contact.colorBlendFactor = 1
            contact.alpha = 0.55
            contact.zPosition = Layer.pad - 0.2
            addChild(contact)
            contactShadows[zone] = contact
        }
    }

    func setEnvironmentHidden(_ hidden: Bool) {
        for building in buildings { building.front.isHidden = hidden; building.side.isHidden = hidden }
        for beam in searchlights { beam.isHidden = hidden }
        landmark?.root.isHidden = hidden
        landmark?.shadow?.node.isHidden = hidden
        if hidden { for ring in tunnelRings { ring.isHidden = true } }
        bodyShadow.isHidden = hidden || bodySprite.isHidden
        for zone in Zone.allCases {
            placeholderShadows[zone]?.isHidden = hidden
            contactShadows[zone]?.isHidden = hidden
        }
    }

    // MARK: - Per frame

    func updateEnvironment(dt: CGFloat, travel: CGFloat, fogColor: UIColor) {
        updateBuildings(travel: travel, fogColor: fogColor)
        updateLandmark(dt: dt, travel: travel, fogColor: fogColor)
        updateTunnel(travel: travel)
        updateSearchlights()
    }

    private func updateBuildings(travel: CGFloat, fogColor: UIColor) {
        let shade = Palette.deepNavy
        let source = Self.sideSource
        for b in buildings {
            b.z -= travel
            if b.z + b.depth < 0.4 { b.z += 100 }
            let h0 = -groundDrop
            let fog = smoothstep(14, 90, b.z)
            let fadeIn = 1 - smoothstep(farZ * 0.72, farZ * 0.97, b.z)

            // Front face: camera-facing billboard, hidden once it passes the near clip.
            b.front.isHidden = b.z < 0.6
            if !b.front.isHidden {
                let ppu = proj.ppu(b.z)
                b.front.position = proj.screen(x: b.x, h: h0, z: b.z)
                b.front.size = CGSize(width: b.width * ppu, height: b.height * ppu)
                b.front.zPosition = proj.depthZ(b.z)
                b.front.alpha = fadeIn
                b.front.color = fogColor
                b.front.colorBlendFactor = fog * 0.85
            }

            // Side face toward the track, clipped at the near plane so it slides past instead of popping.
            let inner = b.x - b.sideSign * b.width / 2
            let zNear = max(b.z, 0.35)
            let zFar = b.z + b.depth
            guard zFar > zNear + 0.05 else { b.side.isHidden = true; continue }
            b.side.isHidden = false
            var corners: [CGPoint] = []
            for r in 0...1 {
                for c in 0...4 {
                    let zc = zNear + (zFar - zNear) * CGFloat(c) / 4
                    corners.append(proj.screen(x: inner, h: h0 + CGFloat(r) * b.height, z: zc))
                }
            }
            let origin = corners[0]
            b.side.position = origin
            b.side.warpGeometry = SKWarpGeometryGrid(columns: 4, rows: 1, sourcePositions: source,
                                                     destinationPositions: WarpQuad.normalized(corners, origin: origin))
            b.side.zPosition = proj.depthZ(b.z + b.depth * 0.5) - 0.5
            b.side.alpha = fadeIn
            // Side walls sit in shade, then fade into the same fog as everything else.
            b.side.color = shade.mixed(with: fogColor, amount: fog)
            b.side.colorBlendFactor = 0.55 + 0.3 * fog
        }
    }

    static let sideSource = WarpQuad.sourceGrid(columns: 4, rows: 1)

    private func updateLandmark(dt: CGFloat, travel: CGFloat, fogColor: UIColor) {
        if landmark == nil, distance >= nextLandmarkAt {
            // Side landmarks stream in on their own; the overhead bridge is staged between challenges.
            let kinds: [Landmark.Kind] = [.ferrisWheel, .signTower]
            let kind = kinds[landmarkCycle % kinds.count]
            landmarkCycle += 1
            spawnLandmark(kind, z: 150)
        }
        guard let mark = landmark else { return }
        mark.z -= travel
        if mark.z < 0.5 {
            mark.root.removeFromParent()
            mark.shadow?.node.removeFromParent()
            landmark = nil
            nextLandmarkAt = distance + 60
            return
        }
        let ppu = proj.ppu(mark.z)
        mark.root.position = proj.screen(x: mark.x, h: -groundDrop, z: mark.z)
        mark.root.setScale(ppu * (mark.kind == .bridge ? 1 : 1.5) / Landmark.unit)
        mark.root.zPosition = proj.depthZ(mark.z)
        mark.root.alpha = (1 - smoothstep(120, 148, mark.z)) * smoothstep(0.5, 1.5, mark.z) * smoothstep(0, 0.8, CGFloat(now - mark.born))
        let fog = smoothstep(20, 130, mark.z) * 0.8
        for part in mark.parts {
            part.color = fogColor
            part.colorBlendFactor = fog
        }
        let spinRate: CGFloat = reduceMotion ? 0 : 1
        switch mark.kind {
        case .ferrisWheel:
            mark.spinner?.zRotation += 0.18 * dt * spinRate
        case .signTower:
            // A sign turning on its vertical axis: the cheapest convincing "rotation in depth".
            signAngle += 0.9 * dt * spinRate
            let c = cos(signAngle)
            mark.spinner?.xScale = max(0.04, abs(c))
            mark.spinner?.colorBlendFactor = max(fog, c < 0 ? 0.55 : 0)
            mark.spinner?.color = c < 0 ? Palette.deepNavy : fogColor
        case .bridge:
            // The deck (h ≈ 3.4–4.2 units) casts a band onto the roof just below it.
            mark.shadow?.update(proj, zNear: mark.z - 0.6, zFar: mark.z + 0.9, halfWidth: roofHalf,
                                alpha: 0.42 * smoothstep(0.5, 2, mark.z) * (1 - smoothstep(30, 60, mark.z)))
        }
    }

    func spawnLandmark(_ kind: Landmark.Kind, z: CGFloat) {
        let side: CGFloat = landmarkCycle % 2 == 0 ? 1 : -1
        let mark = Landmark(kind: kind, side: side, z: z)
        mark.born = now
        mark.root.alpha = 0
        mark.root.isHidden = mode != .immersive
        worldRoot.addChild(mark.root)
        if let shadow = mark.shadow { worldRoot.addChild(shadow.node) }
        landmark = mark
    }

    /// Recovery beat after a challenge: every third gate is followed by a tunnel ride, every fifth (offset) by
    /// the bridge. Gates wait until the set piece has passed (`setPieceBlocksGates`).
    func stageSetPieceAfterResolution() {
        guard mode == .immersive else { return }
        if resolvedCount % 3 == 0, !tunnelActive {
            tunnelActive = true
            for (i, ring) in tunnelRings.enumerated() {
                ring.userData = ["z": 34 + CGFloat(i) * 2.6, "i": i, "born": now]
                ring.isHidden = false
            }
        } else if resolvedCount % 5 == 2, landmark == nil {
            spawnLandmark(.bridge, z: 55)
        }
    }

    private func updateTunnel(travel: CGFloat) {
        guard tunnelActive else {
            tunnelDim += (0 - tunnelDim) * 0.05
            return
        }
        var anyActive = false
        var inside: CGFloat = 0
        for ring in tunnelRings {
            guard var z = ring.userData?["z"] as? CGFloat, let i = ring.userData?["i"] as? Int else { continue }
            z -= travel
            ring.userData?["z"] = z
            if z < 0.25 { ring.isHidden = true; continue }
            anyActive = true
            ring.isHidden = false
            let ppu = proj.ppu(z)
            ring.position = proj.screen(x: 0, h: 1.0, z: z)
            ring.size = CGSize(width: 7.2 * ppu, height: 7.2 * ppu)
            // Each ring is offset in rotation so the tunnel reads as a twisting vortex.
            ring.zRotation = CGFloat(i) * 0.2 + (reduceMotion ? 0 : CGFloat(now) * 0.5)
            ring.zPosition = proj.depthZ(z)
            // Rings fade in over 0.6 s (no pop when staged mid-distance) and fade out before reaching the players.
            let age = CGFloat(now - ((ring.userData?["born"] as? TimeInterval) ?? 0))
            ring.alpha = (1 - smoothstep(50, 75, z)) * smoothstep(proj.zp + 1.5, proj.zp + 6, z) * smoothstep(0, 0.6, age) * 0.95
            if z < 20 { inside = 1 }
        }
        tunnelDim += (inside - tunnelDim) * 0.06
        if !anyActive {
            tunnelActive = false
        }
    }

    private func updateSearchlights() {
        let pan = skyPan
        for beam in searchlights {
            guard let phase = beam.userData?["phase"] as? Double, let fx = beam.userData?["fx"] as? Double else { continue }
            beam.position = CGPoint(x: CGFloat(fx) * size.width + pan * 0.6, y: proj.horizonY - 4)
            beam.size = CGSize(width: size.height * 0.16, height: size.height * 0.62)
            let sweep = reduceMotion ? 0 : sin(CGFloat(now) * 0.35 + CGFloat(phase))
            beam.zRotation = (CGFloat(fx) - 0.5) * -0.6 + sweep * 0.35
            beam.alpha = 0.13 + 0.06 * palettePhase
        }
    }

    // MARK: - Player shadows

    func updatePlayerShadows() {
        let immersive = mode == .immersive
        let shear: CGFloat = -0.32, squash: CGFloat = 0.38
        // Live cutout: shear everything above the foot line back and to the left, pivoting at the feet.
        bodyShadow.isHidden = !immersive || bodySprite.isHidden
        if !bodyShadow.isHidden {
            let feet = Zone.allCases.compactMap { slots[$0]?.livePose?.footY }.min() ?? 0.06
            let fy = Float(max(0.01, min(0.6, feet)))
            bodyShadow.texture = bodyTexture
            bodyShadow.size = bodySprite.size
            bodyShadow.position = bodySprite.position
            let widthRatio = Float(bodySprite.size.height / max(1, bodySprite.size.width))
            let top = fy + (1 - fy) * Float(squash)
            let dx = Float(shear) * (1 - fy) * widthRatio
            bodyShadow.warpGeometry = SKWarpGeometryGrid(
                columns: 1, rows: 2,
                sourcePositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, fy), SIMD2(1, fy), SIMD2(0, 1), SIMD2(1, 1)],
                destinationPositions: [SIMD2(0, fy), SIMD2(1, fy), SIMD2(0, fy), SIMD2(1, fy), SIMD2(dx, top), SIMD2(1 + dx, top)])
        }
        for zone in Zone.allCases {
            guard let placeholder = placeholders[zone], let shadow = placeholderShadows[zone], let contact = contactShadows[zone],
                  let slot = slots[zone] else { continue }
            contact.isHidden = !immersive || (slot.driver == .absent && placeholder.isHidden)
            let padWidth = 1.25 * proj.ppu(proj.zp)
            contact.position = slot.footPoint
            contact.size = CGSize(width: padWidth * 0.55, height: padWidth * 0.12)

            shadow.isHidden = !immersive || placeholder.isHidden
            guard !shadow.isHidden else { continue }
            shadow.texture = placeholder.texture
            shadow.size = placeholder.size
            shadow.position = placeholder.position
            let ratio = Float(placeholder.size.height / max(1, placeholder.size.width))
            let height = Float(placeholder.yScale * squash)
            let dx = Float(shear) * ratio * Float(placeholder.yScale)
            shadow.warpGeometry = SKWarpGeometryGrid(
                columns: 1, rows: 1,
                sourcePositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
                destinationPositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(dx, height), SIMD2(1 + dx, height)])
        }
    }

    // MARK: - Fireworks

    /// Sky bursts for big co-op moments. Pooled sprites; Reduce Motion gets a single small burst.
    func launchFireworks(bursts: Int) {
        let count = reduceMotion ? 1 : bursts
        for b in 0..<count {
            run(.wait(forDuration: Double(b) * 0.28)) { [weak self] in
                guard let self else { return }
                let center = CGPoint(x: size.width * CGFloat.random(in: 0.2...0.8),
                                     y: proj.horizonY + (size.height - proj.horizonY) * CGFloat.random(in: 0.35...0.75))
                let color = [Palette.yellow, Palette.coral, Palette.teal, Palette.violet].randomElement()!
                let particles = reduceMotion ? 8 : 16
                for i in 0..<particles {
                    let spark = fireworks[nextFirework]
                    nextFirework = (nextFirework + 1) % fireworks.count
                    spark.removeAllActions()
                    spark.isHidden = false
                    spark.position = center
                    spark.color = i % 4 == 0 ? .white : color
                    spark.size = CGSize(width: 26, height: 26)
                    spark.alpha = 1
                    let angle = CGFloat(i) / CGFloat(particles) * 2 * .pi
                    let radius = CGFloat.random(in: 90...150) * (reduceMotion ? 0.6 : 1)
                    spark.run(.sequence([
                        .group([.moveBy(x: cos(angle) * radius, y: sin(angle) * radius - 30, duration: 0.9).easeOut(),
                                .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.45)]),
                                .scale(to: 0.4, duration: 0.9)]),
                        .hide(), .scale(to: 1, duration: 0),
                    ]))
                }
                audio.play(.pop, dB: -14)
            }
        }
    }
}
