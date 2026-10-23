import SpriteKit
import UIKit

// Laser Breakout security hardware: the energy-beam shader and the articulated wall emitter.

@MainActor
extension Shaders {
    /// Energy beam, one shared shader for every beam (per-beam values come in through attributes):
    ///   • a thin white-hot core and a coloured glow that falls off across the beam (thickness follows depth: the
    ///     sprite's height is set from the projection, so near beams are thick and far ones thin);
    ///   • energy pulses travelling along the beam from the emitter, a fast shimmer, soft ends.
    /// a_params = (length in points, intensity 0…1.6, flare 0…1, phase); a_color = beam colour;
    /// a_shape = (thickness at the start, thickness at the end — perspective taper —, pulse speed, instability 0…1).
    static let laserBeam: SKShader = {
        let source = """
        void main() {
            vec2 uv = v_tex_coord;
            float taper = max(mix(a_shape.x, a_shape.y, uv.x), 0.05);
            // Instability: the core wavers a little and the beam drops out for single frames (a live, unstable field).
            float wob = a_shape.w * 0.1 * sin(uv.x * 37.0 + u_clock * 31.0 + a_params.w) * sin(u_clock * 7.0 + a_params.w);
            float d = abs(uv.y - 0.5 - wob) * 2.0 / taper;
            float drop = 1.0 - a_shape.w * 0.4 * step(0.86, fract(sin(floor(u_clock * 24.0) + a_params.w) * 43758.5));
            float core = 1.0 - smoothstep(0.03, 0.09 + 0.06 * a_params.z, d);
            float glow = 0.7 * exp(-d * d * mix(12.0, 5.0, a_params.z)) + 0.42 * exp(-d * mix(3.6, 2.4, a_params.z));
            float len = max(a_params.x, 1.0);
            float flow = 0.62 + 0.38 * pow(0.5 + 0.5 * sin(uv.x * len / 22.0 - u_clock * a_shape.z + a_params.w), 3.0);
            float shimmer = 0.88 + 0.12 * sin(u_clock * 57.0 + uv.x * 31.0 + a_params.w);
            float ends = smoothstep(0.0, 0.025, uv.x) * (1.0 - smoothstep(0.985, 1.0, uv.x));
            float i = a_params.y;
            vec3 col = a_color.rgb * glow * flow + vec3(1.0, 0.97, 0.95) * core * shimmer;
            float a = clamp(glow * 0.85 * flow + core, 0.0, 1.0) * ends * min(i, 1.0) * drop * step(d, 1.0);
            gl_FragColor = vec4(col * a * max(i, 1.0), a);
        }
        """
        let shader = SKShader(source: source, uniforms: [SKUniform(name: "u_clock", float: 0)])
        shader.attributes = [SKAttribute(name: "a_params", type: .vectorFloat4), SKAttribute(name: "a_color", type: .vectorFloat4),
                             SKAttribute(name: "a_shape", type: .vectorFloat4)]
        return shader
    }()
}

@MainActor
extension Art {
    private static func fxInk(_ ctx: CGContext, _ path: UIBezierPath, fill: UIColor, line: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        fill.setFill(); ctx.addPath(path.cgPath); ctx.fillPath()
        guard line > 0 else { return }
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(line); ctx.addPath(path.cgPath); ctx.strokePath()
    }

    /// Wall hatch: the armoured panel that slides open to let the emitter out (0.5 × 0.5 units at 100 pt/unit).
    static let emitterHatch = drawnHi(CGSize(width: 50, height: 50), scale: 2) { ctx, size in
        fxInk(ctx, UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4), cornerRadius: 6), fill: VaultPalette.metal, line: 3)
        VaultPalette.metalLight.setFill(); ctx.fill(CGRect(x: 8, y: 8, width: size.width - 16, height: 4))
        for y in stride(from: CGFloat(18), to: size.height - 8, by: 8) { VaultPalette.navy.setFill(); ctx.fill(CGRect(x: 10, y: y, width: size.width - 20, height: 3)) }
    }

    /// The hinged arm (stretched between the wall mount and the head).
    static let emitterArm = drawnHi(CGSize(width: 60, height: 14), scale: 2) { ctx, size in
        fxInk(ctx, UIBezierPath(roundedRect: CGRect(x: 1, y: 2, width: size.width - 2, height: size.height - 4), cornerRadius: 4), fill: VaultPalette.metalLight, line: 2.5)
        VaultPalette.navy.setFill(); ctx.fill(CGRect(x: 6, y: size.height / 2 - 1, width: size.width - 12, height: 2))
    }

    /// The emitter head: housing, cooling fins and the lens (white: tinted from cold to hot).
    static let emitterHead = drawnHi(CGSize(width: 64, height: 44), scale: 2) { ctx, size in
        for x in [10.0, 18, 26] as [CGFloat] { fxInk(ctx, UIBezierPath(rect: CGRect(x: x, y: 4, width: 4, height: size.height - 8)), fill: VaultPalette.metal, line: 1.5) }
        fxInk(ctx, UIBezierPath(roundedRect: CGRect(x: 14, y: 8, width: 36, height: 28), cornerRadius: 8), fill: VaultPalette.metalLight, line: 3)
        fxInk(ctx, UIBezierPath(ovalIn: CGRect(x: 42, y: 10, width: 20, height: 24)), fill: .white, line: 3)
    }

    /// Charging ring around the lens (additive, white: tinted).
    static let chargeRing = drawnHi(CGSize(width: 64, height: 64), scale: 2) { ctx, size in
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6))
        ctx.setLineWidth(2); ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        ctx.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14))
    }

    /// Iris security gate ring (2 units radius at 100 pt/unit → 400 pt; 1.5× for detail): a heavy segmented ring with
    /// hazard bands and bolt heads. White inner rim lit by the shader-free tint.
    static let irisRing = drawnHi(CGSize(width: 440, height: 440), scale: 1.5) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer: CGFloat = 214, inner: CGFloat = 186
        let ring = UIBezierPath(arcCenter: c, radius: outer, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        ring.append(UIBezierPath(arcCenter: c, radius: inner, startAngle: 0, endAngle: 2 * .pi, clockwise: false))
        ring.usesEvenOddFillRule = true
        VaultPalette.metal.setFill(); ring.fill()
        // Hazard bands: alternating gold/ink segments on the ring's face.
        for k in 0..<24 where k % 2 == 0 {
            let a0 = CGFloat(k) / 24 * 2 * .pi, a1 = CGFloat(k + 1) / 24 * 2 * .pi
            let seg = UIBezierPath(arcCenter: c, radius: outer - 5, startAngle: a0, endAngle: a1, clockwise: true)
            seg.addArc(withCenter: c, radius: inner + 14, startAngle: a1, endAngle: a0, clockwise: false)
            seg.close()
            (k % 4 == 0 ? VaultPalette.gold : VaultPalette.metalLight).setFill(); seg.fill()
        }
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
        ctx.strokeEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
        UIColor.white.withAlphaComponent(0.85).setStroke(); ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: c.x - inner - 5, y: c.y - inner - 5, width: (inner + 5) * 2, height: (inner + 5) * 2))
    }

    /// One iris aperture blade: a curved wedge from the rim to the centre (anchored at the rim end).
    static let irisBlade = drawnHi(CGSize(width: 200, height: 120), scale: 1.5) { ctx, size in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 10))
        p.addQuadCurve(to: CGPoint(x: size.width - 6, y: size.height / 2), controlPoint: CGPoint(x: size.width * 0.6, y: 0))
        p.addLine(to: CGPoint(x: 0, y: size.height - 10))
        p.close()
        fxInk(ctx, p, fill: VaultPalette.metal, line: 4)
        VaultPalette.gold.setFill(); ctx.fill(CGRect(x: 8, y: size.height / 2 - 4, width: size.width * 0.55, height: 8))
    }

    /// Indicator lamp on the hatch frame.
    static let indicatorLamp = drawnHi(CGSize(width: 18, height: 18), scale: 2) { ctx, size in
        fxInk(ctx, UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)), fill: .white, line: 2)
    }
}

/// A wall-mounted laser emitter with real states, all driven from the encounter clock (never on its own timer):
/// DORMANT (hatch shut) → WARNING (lamp blinks amber) → DEPLOY (hatch slides, arm swings out, slight overshoot) →
/// CHARGE (lens heats, ring builds) → FIRE (recoil kick, lamp red) → SWEEP/APPROACH (head aims; on a sweep the head
/// swings the beam into its lane) → SHUTDOWN (lamp green, lens cools) → RETRACT (arm folds back into the wall).
@MainActor
final class EmitterRig {
    let node = SKNode()
    let hatch = SKSpriteNode(texture: Art.emitterHatch)
    let arm = SKSpriteNode(texture: Art.emitterArm)
    let head = SKSpriteNode(texture: Art.emitterHead)
    let ring = SKSpriteNode(texture: Art.chargeRing)
    let lamp = SKSpriteNode(texture: Art.indicatorLamp)
    /// Lens position on screen (the beam starts here).
    private(set) var lens: CGPoint = .zero
    /// Iris pods ride the ring (no wall hatch).
    var showsHatch = true

    init() {
        arm.anchorPoint = CGPoint(x: 0, y: 0.5)
        head.colorBlendFactor = 0
        ring.blendMode = .add
        ring.colorBlendFactor = 1
        lamp.colorBlendFactor = 1
        for (i, n) in [hatch, arm, head, ring, lamp].enumerated() {
            n.zPosition = CGFloat(i) * 0.002
            node.addChild(n)
        }
    }

    struct State {
        var deploy: CGFloat       // 0 in the wall … 1 out (may overshoot)
        var charge: CGFloat       // 0 cold … 1 ready
        var firing: Bool
        var shutdown: CGFloat     // 0 live … 1 off
        var recoil: CGFloat       // 0 … 1 kick just after firing
        var aim: CGFloat          // radians, 0 = straight across the corridor (+ up)
        var warningBlink: Bool
        var color: UIColor
    }

    /// `side`: −1 left wall, +1 right wall. Geometry from the shared projection at the gate's depth.
    func layout(side: CGFloat, wallX: CGFloat, h: CGFloat, z: CGFloat, proj: Projection, state s: State, depth: CGFloat, visible: CGFloat) {
        let ppu = proj.ppu(max(z, 0.25))
        let inward = -side                                    // toward the corridor centre
        let armLen: CGFloat = 0.28 * s.deploy - 0.05 * s.recoil
        let mount = proj.screen(x: wallX, h: h, z: z)
        let headWorldX = wallX + inward * max(0, armLen)
        let headPt = proj.screen(x: headWorldX, h: h, z: z)
        node.zPosition = depth + 0.01
        node.alpha = visible
        // Hatch: slides up off the mount as the arm comes out.
        hatch.position = CGPoint(x: mount.x, y: mount.y + ppu * 0.42 * min(1, s.deploy))
        hatch.setScale(ppu * 0.55 / 50)
        hatch.isHidden = !showsHatch
        // Arm between the mount and the head.
        let dx = headPt.x - mount.x
        arm.position = mount
        arm.xScale = max(0.01, abs(dx)) / 60 * (dx >= 0 ? 1 : -1)
        arm.yScale = ppu * 0.12 / 14
        arm.isHidden = s.deploy < 0.02
        // Head: aims across the corridor (mirrored on the right wall), turns with the sweep.
        head.position = headPt
        head.setScale(ppu * 0.5 / 64)
        head.xScale = abs(head.xScale) * inward
        head.zRotation = s.aim * inward
        let hot = s.firing && s.shutdown < 1 ? 1 : s.charge
        head.color = s.color
        head.colorBlendFactor = 0.25 + 0.6 * hot * (1 - s.shutdown)
        let lensOffset = ppu * 0.5 * 0.42
        lens = CGPoint(x: headPt.x + inward * cos(s.aim) * lensOffset, y: headPt.y + sin(s.aim) * lensOffset)
        // Charge ring: grows and brightens while charging, snaps tight when firing, fades at shutdown.
        ring.position = lens
        let ringScale = ppu * (0.42 - 0.16 * s.charge + (s.firing ? 0.08 * s.recoil : 0)) / 64
        ring.setScale(max(0.01, ringScale))
        ring.color = s.color
        ring.alpha = (s.charge * 0.9 + (s.firing ? 0.3 : 0)) * (1 - s.shutdown)
        // Lamp: amber blink (warning) → red (live) → green (shut down).
        lamp.position = CGPoint(x: mount.x + inward * ppu * 0.08, y: mount.y + ppu * 0.32)
        lamp.setScale(ppu * 0.1 / 18)
        lamp.color = s.shutdown > 0.5 ? UIColor(red: 0.35, green: 1, blue: 0.5, alpha: 1) : (s.firing || s.charge > 0.5 ? VaultPalette.laser : VaultPalette.gold)
        lamp.alpha = s.warningBlink && !s.firing && s.charge < 0.5 ? 0.25 : 1
    }
}
