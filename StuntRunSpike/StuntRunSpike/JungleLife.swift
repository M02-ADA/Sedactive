import SpriteKit

/// Wind: a gust band travelling through the jungle (0 … 1). Trees, reeds, boughs and the canopy frame all sway harder
/// as it passes them, so the wind is seen moving through the scene rather than everything wobbling in sync.
nonisolated func jungleGust(worldZ: Double, time: Double) -> Double {
    pow(max(0, sin(2 * .pi * (worldZ / 46 + time * 0.11))), 6)
}

/// Depth and life around the river (JungleWorld owns it). Every element is caused by something in the world:
/// far ridges and clouds give the sky depth; overhanging boughs and butterflies pass close to the camera (speed and
/// scale); dragonflies ride along with the raft; fish break the surface; blossoms drift on the current and are pushed
/// aside by the raft's wake. Nothing here is a random particle, and nothing crosses the players' lanes.
@MainActor
final class JungleLife {
    let ridges = [SKSpriteNode(texture: Art.farRidges[0]), SKSpriteNode(texture: Art.farRidges[1])]
    var clouds: [(node: SKSpriteNode, fx: CGFloat, fy: CGFloat, speed: CGFloat)] = []
    var boughs: [(node: SKSpriteNode, side: CGFloat, z: CGFloat)] = []
    var morphos: [(node: SKSpriteNode, x: CGFloat, h: CGFloat, z: CGFloat, phase: Double)] = []
    var dragonflies: [Dragonfly] = []
    var debris: [(node: SKSpriteNode, x: CGFloat, z: CGFloat, spin: CGFloat, phase: Double)] = []
    let fish = SKSpriteNode(texture: Art.leapingFish)
    var fishJump: (x: CGFloat, z: CGFloat, dir: CGFloat, start: TimeInterval)?
    var nextFishAt: TimeInterval = 6
    var ripples: [SKSpriteNode] = []
    var nextRipple = 0
    var rng = SeededRandom(seed: 4242)

    /// A dragonfly keeps pace with the raft: it hovers, darts to a new spot, and sometimes dips to touch the water.
    final class Dragonfly {
        let node = SKSpriteNode(texture: Art.dragonflyFrames[0])
        var x: CGFloat, h: CGFloat, z: CGFloat
        var from = (x: CGFloat(0), h: CGFloat(0), z: CGFloat(0))
        var to = (x: CGFloat(0), h: CGFloat(0), z: CGFloat(0))
        var dartStart: TimeInterval = -10
        var nextDart: TimeInterval = 0
        var dipped = false
        init(x: CGFloat, h: CGFloat, z: CGFloat) { self.x = x; self.h = h; self.z = z; to = (x, h, z); from = to }
    }

    init(root: SKNode) {
        for (i, r) in ridges.enumerated() {
            r.anchorPoint = CGPoint(x: 0.5, y: 0)
            r.colorBlendFactor = 1
            r.zPosition = Layer.mountains + CGFloat(i) * 10
            root.addChild(r)
        }
        for (i, f) in [(0.18, 0.78, 3.0), (0.62, 0.86, 2.2), (0.9, 0.72, 3.6)].enumerated() {
            let c = SKSpriteNode(texture: Art.cloudWisp)
            c.colorBlendFactor = 1
            c.zPosition = Layer.clouds + CGFloat(i)
            root.addChild(c)
            clouds.append((c, CGFloat(f.0), CGFloat(f.1), CGFloat(f.2)))
        }
        for i in 0..<4 {
            let b = SKSpriteNode(texture: Art.leaningTree)
            let t = Art.leaningTree.size()
            b.anchorPoint = CGPoint(x: Art.leaningTreeAnchor.x / t.width, y: 1 - Art.leaningTreeAnchor.y / t.height)
            b.colorBlendFactor = 1
            b.alpha = 0
            root.addChild(b)
            boughs.append((b, i % 2 == 0 ? 1 : -1, 26 + CGFloat(i) * 17))
        }
        for i in 0..<3 {
            let m = SKSpriteNode(texture: Art.morphoFrames[0])
            m.alpha = 0
            root.addChild(m)
            morphos.append((m, 0, 0, 10 + CGFloat(i) * 9, Double(i) * 1.7))
            respawnMorpho(i, z: 10 + CGFloat(i) * 9)
        }
        for (x, z) in [(-1.9, 3.2), (2.2, 4.4)] as [(CGFloat, CGFloat)] {
            let d = Dragonfly(x: x, h: 0.4, z: z)
            root.addChild(d.node)
            dragonflies.append(d)
        }
        for i in 0..<10 {
            let d = SKSpriteNode(texture: i % 3 == 0 ? Art.blossom : Art.floatingLeaf)
            d.alpha = 0
            root.addChild(d)
            debris.append((d, 0, 0, 0, Double(i)))
            respawnDebris(i, z: 4 + CGFloat(i) * 3.4)
        }
        fish.alpha = 0
        root.addChild(fish)
        for _ in 0..<4 {
            let r = SKSpriteNode(texture: Art.rippleRing)
            r.alpha = 0
            root.addChild(r)
            ripples.append(r)
        }
    }

    // MARK: - Spawning

    private func respawnMorpho(_ i: Int, z: CGFloat) {
        let side: CGFloat = rng.next() < 0.5 ? -1 : 1
        morphos[i].x = side * CGFloat(2.3 + rng.next() * 1.8)   // over the river's edge, never over the raft
        morphos[i].h = CGFloat(1.0 + rng.next() * 1.6)
        morphos[i].z = z
        morphos[i].phase = rng.next() * 10
    }

    private func respawnDebris(_ i: Int, z: CGFloat) {
        let side: CGFloat = rng.next() < 0.5 ? -1 : 1
        debris[i].x = side * CGFloat(1.4 + rng.next() * 2.8)
        debris[i].z = z
        debris[i].spin = CGFloat(rng.next() - 0.5) * 0.8
        debris[i].node.zRotation = CGFloat(rng.next()) * 6.28
    }

    private func ripple(at p: CGPoint, width: CGFloat, z: CGFloat) {
        let r = ripples[nextRipple]
        nextRipple = (nextRipple + 1) % ripples.count
        r.removeAllActions()
        r.position = p
        r.size = CGSize(width: width * 0.3, height: width * 0.3 * 0.3)
        r.zPosition = z
        r.alpha = 0.55
        r.run(.group([.scaleX(to: 3, y: 3, duration: 1.0), .fadeOut(withDuration: 1.0)]))
    }

    // MARK: - Layout and frame

    func layout(size: CGSize, proj: Projection) {
        ridges[0].size = CGSize(width: size.width * 1.9, height: size.height * 0.2)
        ridges[1].size = CGSize(width: size.width * 1.8, height: size.height * 0.13)
        for c in clouds { c.node.size = CGSize(width: size.width * 0.42, height: size.width * 0.42 * 170 / 640) }
    }

    func update(dt: CGFloat, travel: CGFloat, distance: CGFloat, now: TimeInterval, proj: Projection, size: CGSize,
                pan: CGFloat, haze: SIMD3<Float>, fog: SIMD3<Float>, reduceMotion: Bool) {
        let hazeUI = UIColor(red: CGFloat(haze.x), green: CGFloat(haze.y), blue: CGFloat(haze.z), alpha: 1)
        let fogUI = UIColor(red: CGFloat(fog.x), green: CGFloat(fog.y), blue: CGFloat(fog.z), alpha: 1)

        // Far: tepuis paler and bluer than the nearer forested hills (atmospheric perspective), slower parallax.
        ridges[0].position = CGPoint(x: proj.cx + pan * 0.22, y: proj.horizonY - 2)
        ridges[0].color = hazeUI.mixed(with: UIColor(red: 0.55, green: 0.72, blue: 0.80, alpha: 1), amount: 0.5)
        ridges[0].alpha = 0.8
        ridges[1].position = CGPoint(x: proj.cx + pan * 0.38, y: proj.horizonY - 3)
        ridges[1].color = fogUI.mixed(with: JunglePalette.canopyDark, amount: 0.25)
        ridges[1].alpha = 0.9
        for i in clouds.indices {
            var fx = clouds[i].fx + (reduceMotion ? 0 : clouds[i].speed * dt / size.width)
            if fx > 1.25 { fx -= 1.5 }
            clouds[i].fx = fx
            let c = clouds[i]
            c.node.position = CGPoint(x: size.width * fx + pan * 0.12, y: proj.horizonY + (size.height - proj.horizonY) * (c.fy - 0.55) * 1.6)
            c.node.color = hazeUI.mixed(with: .white, amount: 0.45)
            c.node.alpha = 0.42
        }

        // Near: trees leaning out over the water from the banks, their boughs sweeping out past the top corners as
        // they pass (scale and speed in the foreground).
        for i in boughs.indices {
            boughs[i].z -= travel
            if boughs[i].z < 1.0 { boughs[i].z += 70 + CGFloat(rng.next()) * 20 }
            let b = boughs[i]
            let world = Double(distance + b.z)
            let x = b.side * (CGFloat(riverHalfWidth(atWorld: world)) + 0.4)
            let ppu = proj.ppu(b.z)
            b.node.position = proj.screen(x: x, h: -0.22, z: b.z)
            b.node.xScale = ppu * 6.5 / 900 * b.side
            b.node.yScale = ppu * 6.5 / 900
            let gust = CGFloat(jungleGust(worldZ: world, time: now))
            b.node.zRotation = reduceMotion ? 0 : b.side * (sin(CGFloat(now) * 0.9 + CGFloat(i)) * 0.03 + gust * 0.06)
            b.node.zPosition = proj.depthZ(b.z) + 1
            b.node.alpha = (1 - smoothstep(60, 80, b.z)) * smoothstep(1.0, 2.2, b.z)
            b.node.color = fogUI
            b.node.colorBlendFactor = smoothstep(8, 60, b.z) * 0.85
        }

        // Morpho butterflies: land-fixed, fluttering in loose figure-eights over the river's edges; open-close
        // flaps with short glides (wings held open), the flash of blue the eye catches as they pass.
        for i in morphos.indices {
            morphos[i].z -= travel
            if morphos[i].z < 1.4 { respawnMorpho(i, z: 26 + CGFloat(rng.next()) * 12) }
            let m = morphos[i]
            let t = now + m.phase
            let wob: CGFloat = reduceMotion ? 0.3 : 1
            let x = m.x + CGFloat(sin(t * 0.9)) * 0.5 * wob
            let h = m.h + CGFloat(sin(t * 1.8)) * 0.25 * wob + CGFloat(sin(t * 5.2)) * 0.05 * wob
            let p = proj.screen(x: x, h: h, z: m.z)
            m.node.position = p
            let ppu = proj.ppu(m.z)
            m.node.setScale(ppu * 0.42 / 130)
            let cycle = (t * 7).truncatingRemainder(dividingBy: 6)
            let frame = cycle < 4 ? Int(cycle) : 0   // four flap frames, then a two-beat glide wings-open
            m.node.texture = Art.morphoFrames[frame]
            m.node.zRotation = CGFloat(cos(t * 0.9)) * 0.25 * wob
            m.node.zPosition = proj.depthZ(m.z) + 2
            m.node.alpha = (1 - smoothstep(30, 38, m.z)) * smoothstep(1.4, 2.4, m.z)
        }

        // Dragonflies ride with the raft (raft frame): hover, dart, dip to the water.
        for d in dragonflies {
            if now >= d.nextDart {
                d.from = (d.x, d.h, d.z)
                let side: CGFloat = d.to.x < 0 ? -1 : 1
                let dip = rng.next() < 0.3
                d.to = (side * CGFloat(1.5 + rng.next() * 1.3), dip ? 0.03 : CGFloat(0.25 + rng.next() * 0.45), CGFloat(2.3 + rng.next() * 3))
                d.dartStart = now
                d.dipped = false
                d.nextDart = now + (reduceMotion ? 2.5 : 0.9) + rng.next() * 1.6
            }
            let k = CGFloat(min(1, (now - d.dartStart) / (reduceMotion ? 0.6 : 0.22)))
            let e = 1 - (1 - k) * (1 - k) * (1 - k)   // a dart: fast out, settles
            d.x = d.from.x + (d.to.x - d.from.x) * e
            d.h = d.from.h + (d.to.h - d.from.h) * e + (reduceMotion ? 0 : CGFloat(sin(now * 13 + Double(d.z))) * 0.015)
            d.z = d.from.z + (d.to.z - d.from.z) * e
            let p = proj.screen(x: d.x, h: d.h, z: d.z)
            if d.to.h < 0.05, k >= 1, !d.dipped {
                d.dipped = true
                ripple(at: proj.screen(x: d.x, h: -0.22, z: d.z), width: proj.ppu(d.z) * 0.5, z: proj.depthZ(d.z))
            }
            d.node.position = p
            d.node.setScale(proj.ppu(d.z) * 0.3 / 110)
            d.node.texture = Art.dragonflyFrames[Int(now * 30) % 2]
            let dx = d.to.x - d.from.x
            d.node.xScale = abs(d.node.xScale) * (dx < 0 ? -1 : 1)
            d.node.zPosition = proj.depthZ(d.z) + 3
            d.node.alpha = 0.95
        }

        // Debris on the current: drifts toward the camera at the water's pace, spins slowly, bobs; the raft's wake
        // pushes anything that comes alongside out of the way.
        for i in debris.indices {
            debris[i].z -= travel * 0.22
            if abs(debris[i].x) < 1.55, debris[i].z < 3.0 { debris[i].x += (debris[i].x < 0 ? -1 : 1) * 0.6 * dt }
            if debris[i].z < 0.7 { respawnDebris(i, z: 30 + CGFloat(rng.next()) * 10) }
            let d = debris[i]
            let bob = reduceMotion ? 0 : CGFloat(sin(now * 1.7 + d.phase)) * 0.012
            d.node.position = proj.screen(x: d.x, h: -0.21 + bob, z: d.z)
            let ppu = proj.ppu(d.z)
            d.node.xScale = ppu * 0.32 / 60
            d.node.yScale = ppu * 0.32 / 60 * 0.6   // lying on the water
            if !reduceMotion { d.node.zRotation += d.spin * dt }
            d.node.zPosition = proj.depthZ(d.z) + 0.1
            d.node.alpha = (1 - smoothstep(26, 36, d.z)) * smoothstep(0.7, 1.4, d.z)
            d.node.color = fogUI
            d.node.colorBlendFactor = smoothstep(6, 30, d.z) * 0.7
        }

        // A fish breaks the surface now and then, mid-river beyond the raft: ring, arc, ring.
        if fishJump == nil, now >= nextFishAt {
            let side: CGFloat = rng.next() < 0.5 ? -1 : 1
            fishJump = (side * CGFloat(2.2 + rng.next() * 2), CGFloat(6 + rng.next() * 7), rng.next() < 0.5 ? -1 : 1, now)
            nextFishAt = now + 5 + rng.next() * 5
            if let f = fishJump { ripple(at: proj.screen(x: f.x, h: -0.22, z: f.z), width: proj.ppu(f.z) * 0.6, z: proj.depthZ(f.z)) }
        }
        if var f = fishJump {
            f.z -= travel
            fishJump = f
            let u = CGFloat((now - f.start) / 0.62)
            if u > 1 {
                ripple(at: proj.screen(x: f.x + f.dir * 0.7, h: -0.22, z: f.z), width: proj.ppu(f.z) * 0.6, z: proj.depthZ(f.z))
                fish.alpha = 0
                fishJump = nil
            } else {
                let x = f.x + f.dir * 0.7 * u
                let h = -0.22 + 0.55 * 4 * u * (1 - u)
                let p = proj.screen(x: x, h: h, z: f.z)
                let q = proj.screen(x: x + f.dir * 0.02, h: -0.22 + 0.55 * 4 * (u + 0.02) * (1 - u - 0.02), z: f.z)
                fish.position = p
                fish.setScale(proj.ppu(f.z) * 0.36 / 110)
                fish.xScale = abs(fish.xScale) * f.dir
                let ang = atan2(q.y - p.y, abs(q.x - p.x))
                fish.zRotation = f.dir > 0 ? ang : -ang
                fish.zPosition = proj.depthZ(f.z) + 0.5
                fish.alpha = 1
            }
        }
    }
}
