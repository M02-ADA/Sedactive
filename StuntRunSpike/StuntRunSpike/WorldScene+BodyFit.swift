import SpriteKit
import UIKit

// Laser Breakout — the Body-Fit security gate. One opening per lane, shaped for that lane's move: the Parent's lane is
// a low gap under a descending shutter (DUCK through it), the Child's lane is a window over a rising laser sill (JUMP
// through it). Judging is the split-grid encounter with the contact window (BodyFitGate.window) and the physical
// body-clear check; this file is the hardware and its choreography.
//
// Depth is what sells it: up to the crossing the gate is behind the players (they are drawn over it); at the crossing
// it slams to a stop just in front of them (BodyFitGate.visualZ) and holds, so its solid parts now cover their bodies
// and each player is seen through their own opening — a ducked head under the shutter, airborne feet over the sill.

/// The articulated gate. All parts are placed in world units through the shared projection at the gate's depth.
@MainActor
final class BodyFitRig {
    let root = SKNode()
    let header = SKSpriteNode(texture: Art.fitHeader)
    let pillars = [SKSpriteNode(texture: Art.fitPillar), SKSpriteNode(texture: Art.fitPillar)]
    let divider = SKSpriteNode(texture: Art.fitDivider)
    let shutter = SKSpriteNode(texture: Art.fitShutter)       // Parent lane: comes down to the duck edge
    let sill = SKSpriteNode(texture: Art.fitSill)             // Child lane: comes up to the jump edge
    let window = SKSpriteNode(texture: Art.fitHeader)         // Child lane: header framing the jump gap
    let shutterStrip = SKSpriteNode(texture: Art.fitHazard)
    let sillStrip = SKSpriteNode(texture: Art.fitHazard)
    let shutterEdge = SKSpriteNode(color: .white, size: CGSize(width: 64, height: 32))
    let sillEdge = SKSpriteNode(color: .white, size: CGSize(width: 64, height: 32))
    let bolts: [Zone: SKSpriteNode] = [.left: SKSpriteNode(texture: Art.fitBolt), .right: SKSpriteNode(texture: Art.fitBolt)]
    let lamps: [Zone: SKSpriteNode] = [.left: SKSpriteNode(texture: Art.indicatorLamp), .right: SKSpriteNode(texture: Art.indicatorLamp)]
    let duckIcon = SKSpriteNode(texture: Art.duckBadge)
    let jumpIcon = SKSpriteNode(texture: Art.jumpBadge)

    var deployedShutter = false, deployedSill = false, ignited = false, locked = false, slammed = false
    /// Per lane: when its result was shown, and whether it got through.
    var shownAt: [Zone: Double] = [:]
    var through: [Zone: Bool] = [:]
    var bypassAt: Double?
    var shudder: [Zone: Double] = [:]

    init() {
        for (i, n) in ([header] + pillars + [divider, window, shutter, sill, shutterStrip, sillStrip] as [SKSpriteNode]).enumerated() {
            n.anchorPoint = .zero
            n.zPosition = CGFloat(i) * 0.001
            root.addChild(n)
        }
        for edge in [shutterEdge, sillEdge] {
            edge.anchorPoint = CGPoint(x: 0, y: 0.5)
            edge.shader = Shaders.laserBeam
            edge.blendMode = .add
            edge.isHidden = true
            edge.zPosition = 0.02
            root.addChild(edge)
        }
        for zone in Zone.allCases {
            bolts[zone]?.zPosition = 0.011
            lamps[zone]?.zPosition = 0.012
            lamps[zone]?.colorBlendFactor = 1
            root.addChild(bolts[zone]!)
            root.addChild(lamps[zone]!)
        }
        for icon in [duckIcon, jumpIcon] { icon.zPosition = 0.013; icon.alpha = 0; root.addChild(icon) }
        root.alpha = 0
    }
}

@MainActor
extension Art {
    private static func fitInk(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: UIColor, line: CGFloat = 4) {
        let p = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fill.setFill(); p.fill()
        VaultPalette.ink.setStroke(); p.lineWidth = line; p.stroke()
    }

    /// Shutter (Parent lane): heavy horizontal slats, drawn for a ~0.9 × 1.1 unit panel (little stretch in use).
    static let fitShutter = drawnHi(CGSize(width: 180, height: 220), scale: 2) { ctx, size in
        fitInk(ctx, CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6), radius: 6, fill: VaultPalette.metal)
        for k in 0..<7 {
            let y = 16 + CGFloat(k) * 28
            fitInk(ctx, CGRect(x: 12, y: y, width: size.width - 24, height: 20), radius: 4, fill: k % 2 == 0 ? VaultPalette.metalLight : VaultPalette.metal, line: 2.5)
        }
        UIColor.white.withAlphaComponent(0.45).setFill()
        for x in [10.0, size.width - 16] as [CGFloat] { for y in stride(from: CGFloat(12), to: size.height - 10, by: 28) { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 5, height: 5)) } }
    }

    /// Sill (Child lane): a low armoured barrier with chevrons pointing up (jump over me).
    static let fitSill = drawnHi(CGSize(width: 180, height: 90), scale: 2) { ctx, size in
        fitInk(ctx, CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6), radius: 6, fill: VaultPalette.metal)
        VaultPalette.gold.setFill()
        for k in 0..<5 {
            let cx = 24 + CGFloat(k) * 33
            let p = UIBezierPath()
            p.move(to: CGPoint(x: cx - 10, y: size.height * 0.62)); p.addLine(to: CGPoint(x: cx, y: size.height * 0.30)); p.addLine(to: CGPoint(x: cx + 10, y: size.height * 0.62))
            p.lineWidth = 6; p.lineCapStyle = .round; p.lineJoinStyle = .round
            VaultPalette.gold.setStroke(); p.stroke()
        }
    }

    /// Header / window frame beam.
    static let fitHeader = drawnHi(CGSize(width: 400, height: 70), scale: 2) { ctx, size in
        fitInk(ctx, CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6), radius: 6, fill: VaultPalette.metal)
        VaultPalette.metalLight.setFill(); ctx.fill(CGRect(x: 12, y: size.height - 22, width: size.width - 24, height: 8))
        UIColor.white.withAlphaComponent(0.5).setFill()
        for x in stride(from: CGFloat(20), to: size.width - 10, by: 40) { ctx.fillEllipse(in: CGRect(x: x, y: 14, width: 6, height: 6)) }
    }

    /// Side pillar (the gate's frame against the walls).
    static let fitPillar = drawnHi(CGSize(width: 110, height: 500), scale: 1.5) { ctx, size in
        fitInk(ctx, CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6), radius: 8, fill: VaultPalette.metal)
        for y in stride(from: CGFloat(30), to: size.height - 30, by: 60) {
            fitInk(ctx, CGRect(x: 16, y: y, width: size.width - 32, height: 34), radius: 5, fill: VaultPalette.navy, line: 2.5)
        }
        VaultPalette.gold.setFill(); ctx.fill(CGRect(x: size.width - 18, y: 10, width: 8, height: size.height - 20))
    }

    /// Centre divider: carries the two lock bolts and their status lamps.
    static let fitDivider = drawnHi(CGSize(width: 90, height: 520), scale: 1.5) { ctx, size in
        fitInk(ctx, CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6), radius: 8, fill: VaultPalette.metalLight)
        fitInk(ctx, CGRect(x: 18, y: size.height * 0.36, width: size.width - 36, height: size.height * 0.2), radius: 6, fill: VaultPalette.navy, line: 3)
        for k in 0..<12 where k % 2 == 0 { VaultPalette.gold.setFill(); ctx.fill(CGRect(x: 8, y: 20 + CGFloat(k) * 38, width: size.width - 16, height: 10)) }
    }

    /// Hazard strip along a moving edge.
    static let fitHazard = drawnHi(CGSize(width: 200, height: 22), scale: 2) { ctx, size in
        VaultPalette.ink.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        VaultPalette.gold.setFill()
        for k in stride(from: -2, to: 18, by: 2) {
            let x = CGFloat(k) * 12
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + 12, y: 0)); p.addLine(to: CGPoint(x: x + 34, y: size.height)); p.addLine(to: CGPoint(x: x + 22, y: size.height)); p.close()
            p.fill()
        }
    }

    /// Lock bolt (slides from the divider into a lane panel).
    static let fitBolt = drawnHi(CGSize(width: 80, height: 28), scale: 2) { ctx, size in
        fitInk(ctx, CGRect(x: 2, y: 4, width: size.width - 4, height: size.height - 8), radius: 8, fill: VaultPalette.metalLight, line: 3)
        VaultPalette.gold.setFill(); ctx.fill(CGRect(x: size.width - 20, y: 8, width: 8, height: size.height - 16))
    }

    static var bodyFitTextures: [SKTexture] { [fitShutter, fitSill, fitHeader, fitPillar, fitDivider, fitHazard, fitBolt] }
}

extension WorldScene {
    // Geometry (world units): lane openings ±0.44 around each lane centre; the divider between them.
    private static let fitInner: CGFloat = 0.22, fitOuter: CGFloat = 1.1, fitHeaderBottom: CGFloat = 2.0
    /// How long a successful fit is held (gate time) before that lane's panel releases.
    private static let fitBeat = 0.3

    /// Height of the Child's window top: room for a real jump over the sill (crown + a jump + margin), under the header.
    private func fitWindowTop(_ zone: Zone) -> CGFloat {
        min(Self.fitHeaderBottom - 0.1, standingNoseH(zone) * CGFloat(1 + Corridor.crownShare) + 0.5)
    }

    /// Places an anchor-(0,0) sprite over the world rectangle [x0,x1]×[h0,h1] at depth z (stretched to fit; each part's
    /// texture is drawn near its in-game aspect so the stretch stays small).
    private func fitPlace(_ s: SKSpriteNode, _ x0: CGFloat, _ h0: CGFloat, _ x1: CGFloat, _ h1: CGFloat, z: CGFloat) {
        let p0 = proj.screen(x: x0, h: h0, z: z), p1 = proj.screen(x: x1, h: h1, z: z)
        s.position = p0
        s.xScale = max(0.001, (p1.x - p0.x) / max(1, s.texture?.size().width ?? 1))
        s.yScale = max(0.001, (p1.y - p0.y) / max(1, s.texture?.size().height ?? 1))
        s.isHidden = p1.y - p0.y < 0.5
    }

    /// The gate's choreography on its encounter clock:
    /// WARNING (frame fades in, open) → DEPLOY (shutter drops, window frame drops, sill rises — rigid, no overshoot,
    /// a clunk at each stop) → ARM (edge lasers ignite, two lock bolts slam into the panels) → APPROACH → CONTACT (it
    /// slams to a stop just in front of the players and holds) → RESULT per lane (through: that lane's panel springs
    /// open and its edge goes cyan; blocked: the edge bites red and the panel shudders) → BYPASS when both are through
    /// (bolts retract, lamps cyan, a beat of slow motion) → RELEASE past the camera.
    func updateBodyFitGate(_ gate: LaserGate, debug: inout [LaserWorld.DebugBeam]) {
        guard let fit = gate.fit else { return }
        let rt = laserRuntime, timing = rt.timing
        let r = gate.t - timing.revealTime
        let z = CGFloat(gate.depth(timing))
        let visible = gate.revealed && z > 0.32
        let tc = timing.crossingTime
        fit.root.zPosition = proj.depthZ(z)
        fit.root.alpha = visible ? CGFloat(min(1, max(0, r / 0.5))) * (z < 0.9 ? max(0, (z - 0.32) / 0.58) : 1) : 0
        for n in [gate.frame] as [SKNode] { n.alpha = 0 }
        let W = CGFloat(Corridor.halfWidth), F = CGFloat(Corridor.floorH), C = CGFloat(Corridor.ceilingH)
        let inner = Self.fitInner, outer = Self.fitOuter, hb = Self.fitHeaderBottom
        let duckEdge = gate.beamH[.left] ?? 0.9, sillTop = gate.beamH[.right] ?? 0.1
        let windowTop = fitWindowTop(.right)
        // Deploy curves (rigid metal: ease-out, hard stop).
        func dep(_ a: Double, _ b: Double) -> CGFloat { let x = CGFloat(max(0, min(1, (r - a) / (b - a)))); return 1 - (1 - x) * (1 - x) * (1 - x) }
        var shutterD = dep(0.6, 1.5), sillD = dep(0.8, 1.6), windowD = dep(0.7, 1.4)
        // Lanes that got through spring their panel open (fast, slight overshoot — a release, not a slam).
        func open(_ zone: Zone) -> CGFloat {
            guard fit.through[zone] == true, let at = fit.shownAt[zone] else { return 0 }
            let x = CGFloat(min(1, (now - at) / 0.32))
            return x >= 1 ? 1 : 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2)
        }
        shutterD *= 1 - open(.left)
        sillD *= 1 - open(.right)
        windowD *= 1 - 0.5 * open(.right)
        if !fit.deployedShutter, r >= 1.5 { fit.deployedShutter = true; audio.play(.clunk, dB: -9); audio.play(.hydraulic, dB: -16) }
        if !fit.deployedSill, r >= 1.6 { fit.deployedSill = true; audio.play(.clunk, dB: -10) }
        if !fit.ignited, r >= 1.8 { fit.ignited = true; audio.play(.ignite, dB: -8) }
        if !fit.locked, r >= 2.0 { fit.locked = true; audio.play(.clunk, dB: -6); audio.play(.servo, dB: -14) }
        // Lateral shudder of a blocked lane (firm: three decaying oscillations, no overshoot).
        func shake(_ zone: Zone) -> CGFloat {
            guard let at = fit.shudder[zone], !reduceMotion else { return 0 }
            let k = now - at
            return k < 0.3 ? CGFloat(sin(k * 60) * (1 - k / 0.3)) * 0.03 : 0
        }
        // Frame.
        fitPlace(fit.header, -W, hb, W, C, z: z)
        fitPlace(fit.pillars[0], -W, F, -outer, hb, z: z)
        fitPlace(fit.pillars[1], outer, F, W, hb, z: z)
        fitPlace(fit.divider, -inner, F, inner, hb, z: z)
        // Parent lane: the shutter comes down from the header to the duck edge.
        let shL = shake(.left), shR = shake(.right)
        let shutterBottom = hb - (hb - duckEdge) * shutterD
        fitPlace(fit.shutter, -outer + shL, shutterBottom, -inner + shL, hb, z: z)
        fitPlace(fit.shutterStrip, -outer + shL, shutterBottom, -inner + shL, shutterBottom + 0.06, z: z)
        // Child lane: the sill rises to the jump edge; the window frame drops to frame the gap above it.
        let sillTopNow = F + (sillTop - F) * sillD
        fitPlace(fit.sill, inner + shR, F, outer + shR, sillTopNow, z: z)
        fitPlace(fit.sillStrip, inner + shR, sillTopNow - 0.05, outer + shR, sillTopNow, z: z)
        let windowBottom = hb - (hb - windowTop) * windowD
        fitPlace(fit.window, inner, windowBottom, outer, hb, z: z)
        // Lock bolts slide from the divider into each lane panel; they withdraw for a lane that got through.
        let ppu = proj.ppu(max(z, 0.3))
        for zone in Zone.allCases {
            guard let bolt = fit.bolts[zone], let lamp = fit.lamps[zone] else { continue }
            let side: CGFloat = zone == .left ? -1 : 1
            let engage = fit.locked ? (fit.through[zone] == true ? max(0, 1 - CGFloat(now - (fit.shownAt[zone] ?? now)) / 0.25) : 1) : 0
            let boltH: CGFloat = zone == .left ? max(duckEdge + 0.25, 1.35) : 1.0
            let p = proj.screen(x: side * (inner - 0.05 + 0.2 * engage), h: boltH, z: z)
            bolt.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bolt.position = p
            bolt.setScale(ppu * 0.32 / 80)
            bolt.xScale = abs(bolt.xScale) * side
            let lampP = proj.screen(x: 0, h: boltH + (zone == .left ? 0.18 : -0.18), z: z)
            lamp.position = CGPoint(x: lampP.x + side * ppu * 0.08, y: lampP.y)
            lamp.setScale(ppu * 0.1 / 18)
            let blink = !reduceMotion && !fit.locked && Int(max(0, r) * 8) % 2 == 0
            lamp.color = fit.through[zone] == true ? VaultPalette.cyan : (fit.through[zone] == false ? VaultPalette.laser : (fit.locked ? VaultPalette.laser : VaultPalette.gold))
            lamp.alpha = blink ? 0.3 : 1
        }
        // Lane icons on the panels: what this opening asks for, readable from far (pictogram, no text).
        let iconScale = ppu * 0.42 / 160
        let iconFade = smoothstep(3.2, 5.5, z)      // read from afar; out of the way up close
        fit.duckIcon.position = proj.screen(x: -(inner + outer) / 2, h: (hb + shutterBottom) / 2 + 0.05, z: z)
        fit.duckIcon.setScale(iconScale)
        fit.duckIcon.alpha = shutterD > 0.6 && fit.through[.left] == nil ? iconFade : max(0, fit.duckIcon.alpha - 0.1)
        fit.jumpIcon.position = proj.screen(x: (inner + outer) / 2, h: (hb + windowBottom) / 2, z: z)
        fit.jumpIcon.setScale(iconScale * min(1, max(0.5, (hb - windowBottom) / 0.75)))
        fit.jumpIcon.alpha = windowD > 0.6 && fit.through[.right] == nil ? iconFade : max(0, fit.jumpIcon.alpha - 0.1)
        // Edge lasers: magenta on the shutter's lower edge (DUCK under it), amber on the sill's top (JUMP over it).
        for (edge, zone, x0, x1, h) in [(fit.shutterEdge, Zone.left, -outer + shL, -inner + shL, shutterBottom), (fit.sillEdge, .right, inner + shR, outer + shR, sillTopNow)] {
            let a = proj.screen(x: x0, h: h, z: z), b = proj.screen(x: x1, h: h, z: z)
            let result = fit.through[zone]
            let since = fit.shownAt[zone].map { now - $0 } ?? 0
            var intensity: CGFloat = fit.ignited ? 1 : 0
            var color = gate.color(zone)
            if result == true { color = VaultPalette.cyan; intensity = CGFloat(max(0, 1 - since / 0.35)) }
            if result == false { color = VaultPalette.laser; intensity = since < 0.3 ? 1.8 : 1 }
            edge.isHidden = intensity < 0.02 || !visible
            edge.position = a
            edge.xScale = max(0.01, (b.x - a.x) / 64)
            edge.yScale = ppu * 0.3 / 32
            edge.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(b.x - a.x), Float(intensity), result == false && since < 0.3 ? 1 : 0, gate.phaseSeed)), forAttribute: "a_params")
            edge.setValue(SKAttributeValue(vectorFloat4: Self.fitRGBA(color)), forAttribute: "a_color")
            edge.setValue(SKAttributeValue(vectorFloat4: SIMD4(1, 1, 14, result == false ? 0.5 : 0.08)), forAttribute: "a_shape")
            // The edge light falls on that player as the gate closes in (subtle, rises with proximity).
            if visible, fit.ignited, result == nil, z < 8, gate.encounter?.participants.contains(zone) == true {
                bodyLight(zone, color, 0.05 + 0.15 * max(0, 1 - (z - proj.zp) / 6))
            }
        }
        // CONTACT: the slam at the players' plane.
        if !fit.slammed, gate.t >= tc {
            fit.slammed = true
            audio.play(.doorSlam, dB: -7)
            audio.play(.passBy, dB: -10)
            shakeUntil = now + 0.16
            shakeAmplitude = reduceMotion ? 0 : 5
            if !reduceMotion {
                for (x, h) in [(-outer, shutterBottom), (-inner, shutterBottom), (inner, sillTopNow), (outer, sillTopNow)] {
                    burstSparks(at: proj.screen(x: x, h: h, z: z), color: VaultPalette.goldLight, count: 3)
                }
            }
            gameLog(String(format: "laser #%d: body-fit gate in contact (z %.2f, holding %.2f s)", gate.number, Double(z), BodyFitGate.hold))
            captureEvent("l-\(gate.number)-fit-contact", after: 0.12)
        }
        // Results appear while the gate is in contact (never before it arrives). A lane that got through keeps the
        // gate closed around the body for a beat first — the FIT itself: head just under the shutter, feet over the
        // sill — then its panel releases. A blocked lane bites as soon as it is judged.
        if gate.t >= tc, let enc = gate.encounter {
            for zone in enc.participants where fit.shownAt[zone] == nil {
                let result = enc.results[zone]
                if result == .cleared {
                    if gate.t >= tc + Self.fitBeat { showFitResult(gate, fit, zone, through: true) }
                } else if result != nil || gate.t > tc + enc.window(zone).clearAfter {
                    // Blocked as soon as this lane's contact window closes — while the gate still holds at the body
                    // (the miss label itself comes later, after its late-move grace).
                    showFitResult(gate, fit, zone, through: false)
                }
            }
            if fit.bypassAt == nil, enc.participants.allSatisfy({ fit.through[$0] == true }), !enc.participants.isEmpty {
                fitBypass(gate, fit)
            }
        }
        // Debug: the two judged edges at the gate's real depth, and each body's crown / soles at the players' plane.
        if visible, fit.ignited {
            let judging = gate.t >= tc - BodyFitGate.window.clearBefore && gate.t <= tc + BodyFitGate.window.clearAfter * rt.difficulty.childWindowScale
            let state: LaserWorld.DebugBeam.State = judging ? .judging : (z > proj.zp + 0.3 ? .far : .near)
            debug.append(.init(x0: -outer, h0: shutterBottom, x1: -inner, h1: shutterBottom, z: z, z1: z, state: state,
                               label: String(format: "#%d DUCK EDGE h%.2f z%.2f %+.2fs", gate.number, Double(shutterBottom), Double(z), gate.t - tc)))
            debug.append(.init(x0: inner, h0: sillTopNow, x1: outer, h1: sillTopNow, z: z, z1: z, state: state,
                               label: String(format: "#%d JUMP SILL h%.2f", gate.number, Double(sillTopNow))))
            if let crown = bodyCrownH(.left) {
                debug.append(.init(x0: -outer, h0: crown, x1: -inner, h1: crown, z: proj.zp, z1: proj.zp, state: .body, label: String(format: "P crown %.2f", Double(crown))))
            }
            if let soles = bodyFeetH(.right) {
                debug.append(.init(x0: inner, h0: soles, x1: outer, h1: soles, z: proj.zp, z1: proj.zp, state: .body, label: String(format: "C soles %.2f", Double(soles))))
            }
        }
    }

    private static func fitRGBA(_ c: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    /// One lane's result, shown at the body: through → that panel springs open, cyan light on the player; blocked →
    /// the edge bites red at the head / shins, sparks at the contact point, the panel shudders.
    private func showFitResult(_ gate: LaserGate, _ fit: BodyFitRig, _ zone: Zone, through: Bool) {
        fit.shownAt[zone] = now
        fit.through[zone] = through
        let duck = gate.pattern.action(for: zone) == .duck
        if through {
            bodyLight(zone, VaultPalette.cyan, 0.26)
            audio.play(.hydraulic, dB: -12)
            audio.play(.chime, dB: -9, variant: zone == .left ? 0 : 1)
        } else {
            fit.shudder[zone] = now
            bodyLight(zone, VaultPalette.laser, 0.5)
            audio.play(.zap, dB: -5)
            let y = (duck ? displayedCrownY(zone) : displayedFeetY(zone)) ?? proj.feetY
            let x = proj.screen(x: CGFloat(Corridor.laneX(zone)), h: 0, z: proj.zp).x
            if !reduceMotion { burstSparks(at: CGPoint(x: x, y: y), color: VaultPalette.laser, count: 9) }
        }
        gameLog("laser #\(gate.number): body-fit \(role(for: zone)) \(through ? "THROUGH the \(duck ? "low gap" : "jump window")" : "BLOCKED by the \(duck ? "shutter" : "sill")")")
    }

    /// Both through: the shared system gives up — bolts withdraw, lamps go cyan, the corridor flashes, a short beat of
    /// slow motion while the open gate is still around them, then it releases.
    private func fitBypass(_ gate: LaserGate, _ fit: BodyFitRig) {
        let rt = laserRuntime
        fit.bypassAt = now
        audio.play(.alarmOff, dB: -8)
        audio.play(.clunk, dB: -6)
        audio.play(.servo, dB: -10)
        rt.flash = reduceMotion ? 0.35 : 0.8
        rt.heist.slowUntil = gameTime + 0.45
        for zone in Zone.allCases { bodyLight(zone, VaultPalette.cyan, 0.3) }
        if !reduceMotion { burstSparks(at: proj.screen(x: 0, h: 1.0, z: CGFloat(gate.depth(rt.timing))), color: VaultPalette.cyan, count: 12) }
        gameLog("laser #\(gate.number): body-fit BYPASS — both through, both locks withdrawn")
        captureEvent("l-\(gate.number)-fit-bypass", after: 0.15)
    }
}
