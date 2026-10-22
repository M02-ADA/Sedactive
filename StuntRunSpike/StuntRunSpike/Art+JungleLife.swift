import SpriteKit
import UIKit

/// Environment depth and life (JUNGLE_ART_DIRECTION.md). Far layers are single-tone silhouettes tinted at runtime by
/// the biome's haze (atmospheric perspective: the farther, the paler and bluer); near layers carry ink outlines and
/// full colour. Wildlife shares the creature rules: rounded masses, one ink weight, flat cel shading.
@MainActor
extension Art {
    private static func ink(_ ctx: CGContext, _ path: UIBezierPath, fill: UIColor, line: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        fill.setFill(); ctx.addPath(path.cgPath); ctx.fillPath()
        guard line > 0 else { return }
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(line); ctx.addPath(path.cgPath); ctx.strokePath()
    }

    // MARK: - Far layers (white silhouettes, tinted at runtime)

    /// 0: distant tepui mesas (flat-topped cliffs) with a thread of waterfall; 1: nearer rolling forested hills.
    static let farRidges: [SKTexture] = ([0, 1] as [Int]).map { (layer: Int) -> SKTexture in
        drawnHi(CGSize(width: 2400, height: layer == 0 ? 460 : 300), scale: 0.6) { ctx, size in
            var rng = SeededRandom(seed: UInt64(41 + layer * 13))
            let w = size.width, h = size.height
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 0, y: h))
            if layer == 0 {
                // Tepuis: steep sides, flat tops at varied heights, low saddles between.
                var x: CGFloat = 0
                p.addLine(to: CGPoint(x: 0, y: h * 0.62))
                while x < w {
                    let base = CGFloat(rng.next())
                    let mesa = base > 0.45
                    let width = mesa ? 260 + CGFloat(rng.next()) * 260 : 180 + CGFloat(rng.next()) * 160
                    let top = mesa ? h * (0.12 + 0.18 * CGFloat(rng.next())) : h * (0.52 + 0.15 * CGFloat(rng.next()))
                    if mesa {
                        p.addLine(to: CGPoint(x: x + 30, y: top + 20)); p.addLine(to: CGPoint(x: x + 46, y: top))
                        p.addLine(to: CGPoint(x: x + width - 46, y: top + 4)); p.addLine(to: CGPoint(x: x + width - 26, y: top + 26))
                    } else {
                        p.addQuadCurve(to: CGPoint(x: x + width, y: h * 0.62), controlPoint: CGPoint(x: x + width / 2, y: top))
                    }
                    x += width
                    p.addLine(to: CGPoint(x: x, y: h * (0.55 + 0.1 * CGFloat(rng.next()))))
                }
            } else {
                var x: CGFloat = 0
                p.addLine(to: CGPoint(x: 0, y: h * 0.5))
                while x < w {
                    let width = 140 + CGFloat(rng.next()) * 220
                    let top = h * (0.12 + 0.3 * CGFloat(rng.next()))
                    // Forested crest: small bumps riding a broad hill.
                    let bumps = Int(width / 40)
                    for b in 0..<bumps {
                        let u = CGFloat(b + 1) / CGFloat(bumps)
                        let hill = top + (h * 0.5 - top) * pow(2 * u - 1, 2)
                        p.addQuadCurve(to: CGPoint(x: x + width * u, y: hill), controlPoint: CGPoint(x: x + width * (u - 0.5 / CGFloat(bumps)), y: hill - 14))
                    }
                    x += width
                }
            }
            p.addLine(to: CGPoint(x: w, y: h)); p.close()
            UIColor.white.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
            // Mist settles at the base (lighter toward the bottom: reads as distance even before tinting).
            ctx.saveGState(); ctx.addPath(p.cgPath); ctx.clip()
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(white: 0.82, alpha: 1).cgColor, UIColor.white.cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
            if layer == 0 {
                // Waterfall threads down two of the mesa faces.
                UIColor.white.setFill()
                for fx in [0.31, 0.74] as [CGFloat] { ctx.fill(CGRect(x: w * fx, y: h * 0.2, width: 7, height: h * 0.5)) }
            }
            ctx.restoreGState()
        }
    }

    /// A humid, low cloud: flat underside, soft puffs on top. White, tinted at runtime.
    static let cloudWisp = drawnHi(CGSize(width: 640, height: 170), scale: 0.6) { ctx, size in
        UIColor.white.setFill()
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(120, 110, 70), (230, 90, 95), (360, 100, 85), (470, 112, 70), (300, 120, 60), (540, 124, 48)]
        for (x, y, r) in puffs { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6)) }
        ctx.fill(CGRect(x: 70, y: 118, width: 520, height: 32))
        UIColor(white: 0.86, alpha: 1).setFill(); ctx.fill(CGRect(x: 70, y: 140, width: 520, height: 10))
    }

    // MARK: - Near foreground

    /// A tree leaning out over the river from the bank: trunk rising from the bank, a sagging bough reaching across
    /// the water, leaves in uneven clumps and a few hanging vines. Anchor: the trunk's base (bottom right).
    static let leaningTreeAnchor = CGPoint(x: 700, y: 900)
    static let leaningTree = drawnHi(CGSize(width: 780, height: 900), scale: 0.85) { ctx, _ in
        var rng = SeededRandom(seed: 515)
        let trunk = UIBezierPath()
        trunk.move(to: CGPoint(x: 660, y: 900)); trunk.addCurve(to: CGPoint(x: 560, y: 260), controlPoint1: CGPoint(x: 690, y: 640), controlPoint2: CGPoint(x: 600, y: 420))
        trunk.addCurve(to: CGPoint(x: 150, y: 300), controlPoint1: CGPoint(x: 460, y: 170), controlPoint2: CGPoint(x: 280, y: 250))   // the bough sags out
        trunk.addLine(to: CGPoint(x: 150, y: 326)); trunk.addCurve(to: CGPoint(x: 600, y: 300), controlPoint1: CGPoint(x: 300, y: 290), controlPoint2: CGPoint(x: 480, y: 220))
        trunk.addCurve(to: CGPoint(x: 740, y: 900), controlPoint1: CGPoint(x: 660, y: 450), controlPoint2: CGPoint(x: 760, y: 640)); trunk.close()
        ink(ctx, trunk, fill: JunglePalette.trunk, line: 8)
        ctx.saveGState(); ctx.addPath(trunk.cgPath); ctx.clip()
        JunglePalette.trunk.mixed(with: .white, amount: 0.18).setFill(); ctx.fill(CGRect(x: 600, y: 300, width: 40, height: 600))
        ctx.restoreGState()
        // Hanging vines from the bough.
        for (x, len) in [(250.0, 260.0), (360.0, 180.0), (470.0, 300.0)] as [(CGFloat, CGFloat)] {
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(9); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: x, y: 280)); ctx.addQuadCurve(to: CGPoint(x: x - 6, y: 280 + len), control: CGPoint(x: x + 20, y: 280 + len / 2)); ctx.strokePath()
            ctx.setStrokeColor(JunglePalette.leaf.cgColor); ctx.setLineWidth(5)
            ctx.move(to: CGPoint(x: x, y: 280)); ctx.addQuadCurve(to: CGPoint(x: x - 6, y: 280 + len), control: CGPoint(x: x + 20, y: 280 + len / 2)); ctx.strokePath()
            JunglePalette.leafLight.setFill(); ctx.fillEllipse(in: CGRect(x: x - 16, y: 270 + len, width: 22, height: 16))
        }
        // Leaf clumps: big rounded masses (the canopy style) at the bough's tip, its middle and the crown, uneven.
        let clumps: [(CGFloat, CGFloat, CGFloat)] = [(150, 270, 150), (300, 210, 120), (470, 170, 140), (600, 150, 170), (420, 260, 90)]
        var masses: [CGRect] = []
        for (cx, cy, r) in clumps {
            for _ in 0..<4 {
                let w = r * CGFloat(0.7 + rng.next() * 0.5)
                masses.append(CGRect(x: cx - w / 2 + CGFloat(rng.next() * 60 - 30), y: cy - w * 0.4 + CGFloat(rng.next() * 40 - 20), width: w, height: w * 0.75))
            }
        }
        JunglePalette.outline.setFill()
        for m in masses { ctx.fillEllipse(in: m.insetBy(dx: -7, dy: -7)) }
        for (i, m) in masses.enumerated() { (i % 3 == 0 ? JunglePalette.leaf.mixed(with: JunglePalette.canopyDark, amount: 0.3) : JunglePalette.leaf).setFill(); ctx.fillEllipse(in: m) }
        JunglePalette.leafLight.setFill()
        for m in masses.prefix(10) { ctx.fillEllipse(in: CGRect(x: m.minX + m.width * 0.15, y: m.minY + m.height * 0.1, width: m.width * 0.5, height: m.height * 0.38)) }
    }

    // MARK: - Wildlife

    /// Blue morpho: four wing positions (open → half → edge-on → half), seen from above-front.
    static let morphoFrames: [SKTexture] = (0..<4).map { (frame: Int) -> SKTexture in
        drawnHi(CGSize(width: 130, height: 100), scale: 1.0) { ctx, size in
            let open: [CGFloat] = [1, 0.6, 0.12, 0.6]
            let k = open[frame]
            let cx = size.width / 2, cy = size.height / 2
            for dir in [-1.0, 1.0] as [CGFloat] {
                let fore = UIBezierPath()
                fore.move(to: CGPoint(x: cx, y: cy - 4))
                fore.addCurve(to: CGPoint(x: cx + dir * 58 * k, y: cy - 30), controlPoint1: CGPoint(x: cx + dir * 20 * k, y: cy - 40), controlPoint2: CGPoint(x: cx + dir * 50 * k, y: cy - 44))
                fore.addQuadCurve(to: CGPoint(x: cx, y: cy + 2), controlPoint: CGPoint(x: cx + dir * 48 * k, y: cy + 6))
                let hind = UIBezierPath()
                hind.move(to: CGPoint(x: cx, y: cy + 2))
                hind.addCurve(to: CGPoint(x: cx + dir * 30 * k, y: cy + 40), controlPoint1: CGPoint(x: cx + dir * 46 * k, y: cy + 8), controlPoint2: CGPoint(x: cx + dir * 46 * k, y: cy + 34))
                hind.addQuadCurve(to: CGPoint(x: cx, y: cy + 6), controlPoint: CGPoint(x: cx + dir * 6 * k, y: cy + 30))
                for wing in [hind, fore] {
                    ink(ctx, wing, fill: Palette.electric.mixed(with: Palette.teal, amount: 0.25), line: 3.5)
                    ctx.saveGState(); ctx.addPath(wing.cgPath); ctx.clip()
                    UIColor(red: 0.45, green: 0.82, blue: 1.0, alpha: 1).setFill()
                    ctx.fillEllipse(in: CGRect(x: cx + dir * 12 * k - 12, y: cy - 22, width: 24, height: 30))
                    JunglePalette.outline.setFill(); ctx.fill(CGRect(x: cx + dir * 46 * k - (dir > 0 ? 0 : 20), y: cy - 50, width: 20, height: 100))
                    UIColor.white.setFill()
                    ctx.fillEllipse(in: CGRect(x: cx + dir * 50 * k - 3, y: cy - 30, width: 5, height: 5))
                    ctx.restoreGState()
                }
            }
            JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(x: cx - 4, y: cy - 16, width: 8, height: 34))
        }
    }

    /// Dragonfly seen from above: long abdomen, two wing positions (the blur alternates).
    static let dragonflyFrames: [SKTexture] = ([0, 1] as [Int]).map { (frame: Int) -> SKTexture in
        drawnHi(CGSize(width: 110, height: 70), scale: 1.0) { ctx, size in
            let cx: CGFloat = 40, cy = size.height / 2
            let spread: CGFloat = frame == 0 ? 1 : 0.55
            UIColor.white.withAlphaComponent(0.55).setFill()
            ctx.setStrokeColor(JunglePalette.outline.withAlphaComponent(0.6).cgColor); ctx.setLineWidth(2)
            for (dx, dy) in [(-4.0, -1.0), (6.0, -1.0), (-4.0, 1.0), (6.0, 1.0)] as [(CGFloat, CGFloat)] {
                ctx.fillEllipse(in: CGRect(x: cx + dx - 8, y: dy < 0 ? cy - 30 * spread : cy + 2, width: 14, height: 28 * spread))
            }
            let body = UIBezierPath(roundedRect: CGRect(x: cx - 8, y: cy - 5, width: 70, height: 10), cornerRadius: 5)
            ink(ctx, body, fill: Palette.teal, line: 3)
            ink(ctx, UIBezierPath(ovalIn: CGRect(x: cx - 18, y: cy - 8, width: 16, height: 16)), fill: Palette.mint, line: 3)
        }
    }

    /// A silver river fish mid-leap (side view, facing right).
    static let leapingFish = drawnHi(CGSize(width: 110, height: 56), scale: 1.0) { ctx, _ in
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 96, y: 28)); body.addQuadCurve(to: CGPoint(x: 26, y: 26), controlPoint: CGPoint(x: 62, y: 4))
        body.addLine(to: CGPoint(x: 8, y: 12)); body.addLine(to: CGPoint(x: 12, y: 28)); body.addLine(to: CGPoint(x: 8, y: 44)); body.addLine(to: CGPoint(x: 26, y: 30))
        body.addQuadCurve(to: CGPoint(x: 96, y: 28), controlPoint: CGPoint(x: 62, y: 50)); body.close()
        ink(ctx, body, fill: UIColor(red: 0.74, green: 0.84, blue: 0.86, alpha: 1), line: 3.5)
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: 44, y: 14, width: 34, height: 6))
        JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(x: 80, y: 22, width: 5, height: 5))
    }

    /// Great egret standing in the shallows: head up (watching) and head down (fishing). Anchor: feet.
    static let egretFrames: [SKTexture] = ([false, true] as [Bool]).map { (down: Bool) -> SKTexture in
        drawnHi(CGSize(width: 150, height: 230), scale: 1.0) { ctx, _ in
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
            for x in [66.0, 82.0] as [CGFloat] { ctx.move(to: CGPoint(x: x, y: 150)); ctx.addLine(to: CGPoint(x: x - 2, y: 226)); ctx.strokePath() }
            let body = UIBezierPath(ovalIn: CGRect(x: 40, y: 104, width: 74, height: 54))
            let neck = UIBezierPath()
            if down {
                neck.move(to: CGPoint(x: 96, y: 118)); neck.addQuadCurve(to: CGPoint(x: 126, y: 168), controlPoint: CGPoint(x: 132, y: 120))
                neck.addLine(to: CGPoint(x: 116, y: 170)); neck.addQuadCurve(to: CGPoint(x: 86, y: 126), controlPoint: CGPoint(x: 118, y: 130)); neck.close()
            } else {
                neck.move(to: CGPoint(x: 92, y: 116)); neck.addQuadCurve(to: CGPoint(x: 98, y: 40), controlPoint: CGPoint(x: 70, y: 80))
                neck.addLine(to: CGPoint(x: 108, y: 42)); neck.addQuadCurve(to: CGPoint(x: 104, y: 120), controlPoint: CGPoint(x: 84, y: 82)); neck.close()
            }
            let head = down ? UIBezierPath(ovalIn: CGRect(x: 112, y: 160, width: 22, height: 18)) : UIBezierPath(ovalIn: CGRect(x: 92, y: 28, width: 24, height: 20))
            for p in [body, neck, head] { ink(ctx, p, fill: .white, line: 4) }
            UIColor(white: 0.85, alpha: 1).setFill(); ctx.fillEllipse(in: CGRect(x: 48, y: 136, width: 60, height: 16))
            Palette.yellow.setFill()
            let beak = UIBezierPath()
            if down { beak.move(to: CGPoint(x: 126, y: 174)); beak.addLine(to: CGPoint(x: 134, y: 204)); beak.addLine(to: CGPoint(x: 120, y: 176)) }
            else { beak.move(to: CGPoint(x: 112, y: 34)); beak.addLine(to: CGPoint(x: 146, y: 42)); beak.addLine(to: CGPoint(x: 112, y: 42)) }
            beak.close(); ink(ctx, beak, fill: Palette.yellow, line: 3)
            JunglePalette.outline.setFill(); ctx.fillEllipse(in: down ? CGRect(x: 124, y: 164, width: 5, height: 5) : CGRect(x: 104, y: 33, width: 5, height: 5))
        }
    }

    /// Heliconia: banana-like leaves with a hanging chain of red-and-yellow bracts (the bank's colour accent).
    static let heliconia = drawnHi(CGSize(width: 260, height: 300), scale: 1.0) { ctx, _ in
        for (x, a, len) in [(90.0, -0.5, 230.0), (150.0, 0.35, 250.0), (120.0, -0.1, 270.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.saveGState(); ctx.translateBy(x: x, y: 300); ctx.rotate(by: a)
            let leaf = UIBezierPath()
            leaf.move(to: .zero); leaf.addQuadCurve(to: CGPoint(x: 0, y: -len), controlPoint: CGPoint(x: -46, y: -len * 0.55))
            leaf.addQuadCurve(to: .zero, controlPoint: CGPoint(x: 40, y: -len * 0.5))
            ink(ctx, leaf, fill: JunglePalette.leaf, line: 5)
            ctx.setStrokeColor(JunglePalette.leafLight.cgColor); ctx.setLineWidth(3); ctx.move(to: CGPoint(x: 0, y: -10)); ctx.addLine(to: CGPoint(x: -4, y: -len * 0.9)); ctx.strokePath()
            ctx.restoreGState()
        }
        // Hanging bracts: alternating red claws tipped yellow.
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(4)
        ctx.move(to: CGPoint(x: 176, y: 70)); ctx.addLine(to: CGPoint(x: 180, y: 210)); ctx.strokePath()
        for i in 0..<6 {
            let y = 86 + CGFloat(i) * 22, dir: CGFloat = i % 2 == 0 ? -1 : 1
            let b = UIBezierPath()
            b.move(to: CGPoint(x: 178, y: y)); b.addQuadCurve(to: CGPoint(x: 178 + dir * 30, y: y + 8), controlPoint: CGPoint(x: 178 + dir * 18, y: y - 8))
            b.addLine(to: CGPoint(x: 178, y: y + 14)); b.close()
            ink(ctx, b, fill: Palette.coral.mixed(with: .red, amount: 0.25), line: 3)
            Palette.yellow.setFill(); ctx.fillEllipse(in: CGRect(x: 178 + dir * 26 - 4, y: y + 3, width: 8, height: 7))
        }
    }

    /// A pink water-lily blossom drifting on the current.
    static let blossom = drawnHi(CGSize(width: 60, height: 40), scale: 1.0) { ctx, _ in
        ink(ctx, UIBezierPath(ovalIn: CGRect(x: 2, y: 16, width: 56, height: 22)), fill: JunglePalette.leaf, line: 2.5)
        for (x, w) in [(14.0, 14.0), (32.0, 14.0), (23.0, 14.0)] as [(CGFloat, CGFloat)] {
            let p = UIBezierPath(); p.move(to: CGPoint(x: x, y: 26)); p.addQuadCurve(to: CGPoint(x: x + w, y: 26), controlPoint: CGPoint(x: x + w / 2, y: 2)); p.close()
            ink(ctx, p, fill: UIColor(red: 1.0, green: 0.66, blue: 0.78, alpha: 1), line: 2.5)
        }
        Palette.yellow.setFill(); ctx.fillEllipse(in: CGRect(x: 25, y: 18, width: 10, height: 7))
    }

    /// Foam that piles against a midstream rock and streams away downstream (anchor: the rock's base, up = ahead).
    static let rockWake = drawnHi(CGSize(width: 220, height: 260), scale: 0.8) { ctx, size in
        var rng = SeededRandom(seed: 717)
        for i in 0..<26 {
            let u = CGFloat(i) / 25
            for side in [-1.0, 1.0] as [CGFloat] {
                let x = size.width / 2 + side * (40 + u * 60) + CGFloat(rng.next() * 10 - 5)
                let y = size.height - 30 - u * 220
                let r = (10 - u * 6) * CGFloat(0.8 + rng.next() * 0.4)
                CreaturePalette.foam.withAlphaComponent(0.85 * (1 - u * 0.7)).setFill()
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
            }
        }
        CreaturePalette.foam.withAlphaComponent(0.9).setFill()
        ctx.fillEllipse(in: CGRect(x: size.width / 2 - 58, y: size.height - 46, width: 116, height: 30))
    }

    // MARK: - Landmarks

    /// A ruined stone arch spanning the river: two pillars on the banks, a carved lintel draped in vines.
    /// Drawn at 1 unit = 100 pt: 16 units wide, 7.4 tall; the pillars' feet sit on the bottom edge.
    static let stoneArch = drawnHi(CGSize(width: 1600, height: 740), scale: 0.7) { ctx, size in
        let stone = JunglePalette.stone, shade = JunglePalette.stone.mixed(with: JunglePalette.outline, amount: 0.35)
        let light = JunglePalette.stone.mixed(with: .white, amount: 0.25)
        var rng = SeededRandom(seed: 333)
        for px in [60.0, 1360.0] as [CGFloat] {
            let pillar = UIBezierPath(rect: CGRect(x: px, y: 180, width: 180, height: 560))
            ink(ctx, pillar, fill: stone, line: 8)
            for row in 0..<7 {
                let y = 190 + CGFloat(row) * 78
                ctx.setStrokeColor(shade.cgColor); ctx.setLineWidth(4)
                ctx.move(to: CGPoint(x: px + 4, y: y + 70)); ctx.addLine(to: CGPoint(x: px + 176, y: y + 70)); ctx.strokePath()
                let off: CGFloat = row % 2 == 0 ? 60 : 110
                ctx.move(to: CGPoint(x: px + off, y: y)); ctx.addLine(to: CGPoint(x: px + off, y: y + 70)); ctx.strokePath()
            }
            light.setFill(); ctx.fill(CGRect(x: px + 10, y: 190, width: 26, height: 540))
            JunglePalette.leaf.setFill()
            ctx.fillEllipse(in: CGRect(x: px - 20, y: 640, width: 220, height: 110))
        }
        let lintel = UIBezierPath(roundedRect: CGRect(x: 30, y: 90, width: 1540, height: 130), cornerRadius: 16)
        ink(ctx, lintel, fill: stone, line: 8)
        light.setFill(); ctx.fill(CGRect(x: 44, y: 100, width: 1512, height: 18))
        shade.setFill(); ctx.fill(CGRect(x: 44, y: 192, width: 1512, height: 22))
        // Carved face in the keystone.
        let key = UIBezierPath(roundedRect: CGRect(x: 720, y: 60, width: 160, height: 190), cornerRadius: 22)
        ink(ctx, key, fill: light, line: 8)
        JunglePalette.outline.setFill()
        for x in [756.0, 822.0] as [CGFloat] { ctx.fill(CGRect(x: x, y: 116, width: 24, height: 16)) }
        ctx.fill(CGRect(x: 760, y: 186, width: 80, height: 14))
        // Vines and moss hanging off the lintel.
        for i in 0..<16 {
            let x = 70 + CGFloat(i) * 96 + CGFloat(rng.next() * 30)
            let len = 60 + CGFloat(rng.next()) * 180
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(9)
            ctx.move(to: CGPoint(x: x, y: 210)); ctx.addQuadCurve(to: CGPoint(x: x + 10, y: 210 + len), control: CGPoint(x: x - 18, y: 210 + len / 2)); ctx.strokePath()
            ctx.setStrokeColor(JunglePalette.leaf.cgColor); ctx.setLineWidth(5)
            ctx.move(to: CGPoint(x: x, y: 210)); ctx.addQuadCurve(to: CGPoint(x: x + 10, y: 210 + len), control: CGPoint(x: x - 18, y: 210 + len / 2)); ctx.strokePath()
            JunglePalette.leafLight.setFill(); ctx.fillEllipse(in: CGRect(x: x - 2, y: 204 + len, width: 22, height: 14))
        }
        JunglePalette.leaf.setFill()
        for i in 0..<10 { let x = 40 + CGFloat(i) * 160; ctx.fillEllipse(in: CGRect(x: x, y: 74, width: 120, height: 36)) }
    }

    /// Waterfall cliff on the bank: a mossy rock face with a falling sheet (three frames of the water moving down)
    /// and a foaming plunge pool. Anchor: bottom centre. 1 unit = 70 pt: 11 units tall.
    static let waterfallFrames: [SKTexture] = (0..<3).map { (frame: Int) -> SKTexture in
        drawnHi(CGSize(width: 700, height: 780), scale: 0.6) { ctx, size in
            let rock = JunglePalette.stone.mixed(with: JunglePalette.canopyDark, amount: 0.35)
            let cliff = UIBezierPath()
            cliff.move(to: CGPoint(x: 0, y: 780)); cliff.addLine(to: CGPoint(x: 30, y: 160)); cliff.addLine(to: CGPoint(x: 140, y: 80))
            cliff.addLine(to: CGPoint(x: 560, y: 60)); cliff.addLine(to: CGPoint(x: 680, y: 140)); cliff.addLine(to: CGPoint(x: 700, y: 780)); cliff.close()
            ink(ctx, cliff, fill: rock, line: 8)
            JunglePalette.leaf.setFill()
            for (x, y, w) in [(60.0, 50.0, 220.0), (300.0, 30.0, 260.0), (520.0, 60.0, 200.0), (20.0, 300.0, 90.0), (600.0, 360.0, 100.0)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: w * 0.45))
            }
            // The falling sheet: pale bands that move down one third of a band per frame.
            let sheet = CGRect(x: 270, y: 70, width: 160, height: 640)
            CreaturePalette.waterInner.setFill(); ctx.fill(sheet)
            CreaturePalette.foam.setFill()
            for band in -1..<8 {
                let y = sheet.minY + (CGFloat(band) + CGFloat(frame) / 3) * 86
                for k in 0..<4 {
                    let x = sheet.minX + 10 + CGFloat(k) * 38 + CGFloat((band + k) % 2) * 8
                    ctx.fill(CGRect(x: x, y: max(sheet.minY, y), width: 12, height: 52))
                }
            }
            // Plunge pool foam.
            for (i, x) in stride(from: CGFloat(220), through: 480, by: 32).enumerated() {
                let r: CGFloat = 26 + CGFloat((i + frame) % 3) * 6
                ctx.fillEllipse(in: CGRect(x: x - r, y: 700 - r * 0.6, width: r * 2, height: r * 1.2))
            }
        }
    }

    // MARK: - Croc head-on mouth (expressions)

    /// The head-on croc's mouth line at the front of the snout: 0 shut (a smug curve with tooth tips), 1 bared teeth.
    static let crocMouthFrames: [SKTexture] = ([0, 1] as [Int]).map { (open: Int) -> SKTexture in
        drawnHi(CGSize(width: 220, height: 70), scale: 1.25) { ctx, _ in
            if open == 1 {
                let mouth = UIBezierPath()
                mouth.move(to: CGPoint(x: 14, y: 18)); mouth.addQuadCurve(to: CGPoint(x: 206, y: 18), controlPoint: CGPoint(x: 110, y: 40))
                mouth.addQuadCurve(to: CGPoint(x: 14, y: 18), controlPoint: CGPoint(x: 110, y: 78)); mouth.close()
                ink(ctx, mouth, fill: CreaturePalette.throat, line: 5)
                ctx.saveGState(); ctx.addPath(mouth.cgPath); ctx.clip()
                CreaturePalette.mouth.setFill(); ctx.fillEllipse(in: CGRect(x: 70, y: 40, width: 80, height: 34))
                CreaturePalette.tooth.setFill()
                for i in 0..<9 {
                    let x = 24 + CGFloat(i) * 21
                    let top = 18 + 22 * sin(.pi * (x - 14) / 192) * 0.9
                    let t = UIBezierPath(); t.move(to: CGPoint(x: x - 7, y: top - 4)); t.addLine(to: CGPoint(x: x, y: top + 12)); t.addLine(to: CGPoint(x: x + 7, y: top - 4)); t.close()
                    ctx.addPath(t.cgPath); ctx.fillPath()
                }
                ctx.restoreGState()
            } else {
                ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(6); ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: 12, y: 14)); ctx.addQuadCurve(to: CGPoint(x: 208, y: 14), control: CGPoint(x: 110, y: 46)); ctx.strokePath()
                CreaturePalette.tooth.setFill()
                for x in [40.0, 70.0, 150.0, 180.0] as [CGFloat] {
                    let y = 14 + 32 * sin(.pi * (x - 12) / 196) * 0.5
                    let t = UIBezierPath(); t.move(to: CGPoint(x: x - 6, y: y - 3)); t.addLine(to: CGPoint(x: x, y: y + 11)); t.addLine(to: CGPoint(x: x + 6, y: y - 3)); t.close()
                    ctx.addPath(t.cgPath); ctx.fillPath()
                    ctx.setLineWidth(2.5); ctx.addPath(t.cgPath); ctx.strokePath()
                }
            }
        }
    }

    static var jungleLifeTextures: [SKTexture] {
        farRidges + [cloudWisp, leaningTree, leapingFish, heliconia, blossom, rockWake, stoneArch] + morphoFrames + dragonflyFrames
            + egretFrames + waterfallFrames + crocMouthFrames
    }
}
