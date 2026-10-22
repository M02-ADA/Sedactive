import SpriteKit
import UIKit

/// Jungle palette: rich greens and deep teal water, warm wood, with the shared coral / yellow / teal cues.
enum JunglePalette {
    static let canopyDark = UIColor(red: 0.04, green: 0.16, blue: 0.13, alpha: 1)
    static let leaf = UIColor(red: 0.10, green: 0.50, blue: 0.30, alpha: 1)
    static let leafLight = UIColor(red: 0.36, green: 0.78, blue: 0.36, alpha: 1)
    static let leafLime = UIColor(red: 0.70, green: 0.90, blue: 0.30, alpha: 1)
    static let trunk = UIColor(red: 0.36, green: 0.22, blue: 0.16, alpha: 1)
    static let wood = UIColor(red: 0.70, green: 0.44, blue: 0.24, alpha: 1)
    static let woodLight = UIColor(red: 0.90, green: 0.64, blue: 0.36, alpha: 1)
    static let rope = UIColor(red: 0.95, green: 0.84, blue: 0.56, alpha: 1)
    static let stone = UIColor(red: 0.50, green: 0.55, blue: 0.52, alpha: 1)
    static let gator = UIColor(red: 0.28, green: 0.44, blue: 0.20, alpha: 1)
    static let outline = UIColor(red: 0.03, green: 0.10, blue: 0.10, alpha: 1)
}

@MainActor
extension Art {
    private static func blob(_ ctx: CGContext, _ rect: CGRect, _ color: UIColor) {
        color.setFill(); ctx.fillEllipse(in: rect)
    }

    /// Rainforest tree: dark trunk with a lit, layered canopy and an outline (three silhouettes).
    static let jungleTrees: [SKTexture] = (0..<3).map { (variant: Int) -> SKTexture in
        drawn(CGSize(width: 360, height: 520)) { ctx, size in
            var rng = SeededRandom(seed: UInt64(77 + variant * 31))
            let w = size.width, h = size.height
            let trunkTop = h * (variant == 1 ? 0.30 : 0.42)
            JunglePalette.outline.setFill()
            ctx.fill(CGRect(x: w / 2 - 22, y: trunkTop, width: 44, height: h - trunkTop))
            JunglePalette.trunk.setFill()
            ctx.fill(CGRect(x: w / 2 - 16, y: trunkTop, width: 32, height: h - trunkTop))
            // Buttress roots.
            for dx in [-1.0, 1.0] {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: w / 2, y: h - 70)); p.addLine(to: CGPoint(x: w / 2 + dx * 70, y: h)); p.addLine(to: CGPoint(x: w / 2, y: h))
                p.close(); ctx.addPath(p.cgPath); ctx.fillPath()
            }
            let blobs = 9 + variant * 2
            var rects: [CGRect] = []
            for _ in 0..<blobs {
                let bw = CGFloat(110 + rng.next() * 120)
                let x = CGFloat(rng.next()) * (w - bw)
                let y = CGFloat(rng.next()) * trunkTop * 0.95
                rects.append(CGRect(x: x, y: y, width: bw, height: bw * 0.78))
            }
            for r in rects { blob(ctx, r.insetBy(dx: -7, dy: -7), JunglePalette.outline) }
            for r in rects { blob(ctx, r, variant == 2 ? JunglePalette.leaf.mixed(with: Palette.teal, amount: 0.25) : JunglePalette.leaf) }
            for r in rects { blob(ctx, CGRect(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.08, width: r.width * 0.55, height: r.height * 0.45), JunglePalette.leafLight) }
            for r in rects.prefix(4) { blob(ctx, CGRect(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.12, width: r.width * 0.2, height: r.height * 0.16), JunglePalette.leafLime) }
        }
    }

    static let palm = drawn(CGSize(width: 340, height: 520)) { ctx, size in
        let w = size.width, h = size.height
        let trunk = UIBezierPath()
        trunk.move(to: CGPoint(x: w * 0.48, y: h)); trunk.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.2), controlPoint: CGPoint(x: w * 0.38, y: h * 0.55))
        ctx.setLineCap(.round)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(34); ctx.addPath(trunk.cgPath); ctx.strokePath()
        ctx.setStrokeColor(JunglePalette.wood.cgColor); ctx.setLineWidth(24); ctx.addPath(trunk.cgPath); ctx.strokePath()
        let top = CGPoint(x: w * 0.55, y: h * 0.2)
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * 2 * .pi + 0.2
            let tip = CGPoint(x: top.x + cos(a) * 160, y: top.y + sin(a) * 90 + 40)
            let frond = UIBezierPath()
            frond.move(to: top)
            frond.addQuadCurve(to: tip, controlPoint: CGPoint(x: top.x + cos(a) * 90, y: top.y + sin(a) * 30 - 40))
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(30); ctx.addPath(frond.cgPath); ctx.strokePath()
            ctx.setStrokeColor((i % 2 == 0 ? JunglePalette.leaf : JunglePalette.leafLight).cgColor); ctx.setLineWidth(20); ctx.addPath(frond.cgPath); ctx.strokePath()
        }
        Palette.coral.setFill()
        for dx in [-12.0, 10.0] { ctx.fillEllipse(in: CGRect(x: top.x + dx - 9, y: top.y + 8, width: 18, height: 18)) }
    }

    static let fern = drawn(CGSize(width: 300, height: 180)) { ctx, size in
        var rng = SeededRandom(seed: 5)
        for i in 0..<11 {
            let base = CGPoint(x: size.width / 2 + CGFloat(rng.next() - 0.5) * 60, y: size.height)
            let tip = CGPoint(x: CGFloat(i) / 10 * size.width, y: CGFloat(rng.next()) * 60 + 10)
            let p = UIBezierPath(); p.move(to: base); p.addQuadCurve(to: tip, controlPoint: CGPoint(x: (base.x + tip.x) / 2, y: tip.y - 20))
            ctx.setLineCap(.round)
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(22); ctx.addPath(p.cgPath); ctx.strokePath()
            ctx.setStrokeColor((i % 3 == 0 ? JunglePalette.leafLime : JunglePalette.leafLight).cgColor); ctx.setLineWidth(13); ctx.addPath(p.cgPath); ctx.strokePath()
        }
    }

    static let reeds = drawn(CGSize(width: 160, height: 260)) { ctx, size in
        var rng = SeededRandom(seed: 9)
        ctx.setLineCap(.round)
        for i in 0..<9 {
            let x = CGFloat(10 + i * 16)
            let lean = CGFloat(rng.next() - 0.5) * 50
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(9)
            ctx.move(to: CGPoint(x: x, y: size.height)); ctx.addLine(to: CGPoint(x: x + lean, y: CGFloat(20 + rng.next() * 70))); ctx.strokePath()
            ctx.setStrokeColor(JunglePalette.leafLime.mixed(with: JunglePalette.leaf, amount: CGFloat(rng.next())).cgColor); ctx.setLineWidth(5)
            ctx.move(to: CGPoint(x: x, y: size.height)); ctx.addLine(to: CGPoint(x: x + lean, y: CGFloat(24 + rng.next() * 70))); ctx.strokePath()
        }
        JunglePalette.trunk.setFill()
        for i in 0..<3 { ctx.fill(CGRect(x: CGFloat(30 + i * 45), y: CGFloat(30 + i * 10), width: 10, height: 34)) }
    }

    static let mossyRock = drawn(CGSize(width: 260, height: 160)) { ctx, size in
        let r = CGRect(x: 10, y: 30, width: size.width - 20, height: size.height - 34)
        blob(ctx, r.insetBy(dx: -6, dy: -6), JunglePalette.outline)
        blob(ctx, r, JunglePalette.stone)
        blob(ctx, CGRect(x: r.minX + 20, y: r.minY, width: r.width * 0.7, height: r.height * 0.42), JunglePalette.leaf)
        blob(ctx, CGRect(x: r.minX + 40, y: r.minY + 4, width: r.width * 0.3, height: r.height * 0.16), JunglePalette.leafLime)
    }

    static let floatingLog = drawn(CGSize(width: 300, height: 80)) { ctx, size in
        let r = CGRect(x: 6, y: 12, width: size.width - 12, height: size.height - 24)
        JunglePalette.outline.setFill(); ctx.addPath(UIBezierPath(roundedRect: r.insetBy(dx: -5, dy: -5), cornerRadius: 30).cgPath); ctx.fillPath()
        JunglePalette.trunk.setFill(); ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: 26).cgPath); ctx.fillPath()
        JunglePalette.wood.setFill(); ctx.fill(CGRect(x: r.minX + 20, y: r.minY + 8, width: r.width - 40, height: 8))
        JunglePalette.leaf.setFill(); ctx.fillEllipse(in: CGRect(x: r.midX - 30, y: r.minY - 6, width: 60, height: 22))
    }

    static let lilyPad = drawn(CGSize(width: 120, height: 60)) { ctx, size in
        let r = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
        JunglePalette.leaf.setFill(); ctx.fillEllipse(in: r)
        JunglePalette.leafLight.setFill(); ctx.fillEllipse(in: r.insetBy(dx: 12, dy: 8))
        Palette.coral.setFill(); ctx.fillEllipse(in: CGRect(x: r.midX + 8, y: r.minY + 6, width: 18, height: 14))
    }

    /// Far treeline silhouettes (two depths) for the horizon.
    static let treeline: [SKTexture] = ([0, 1] as [Int]).map { (layer: Int) -> SKTexture in
        drawn(CGSize(width: 2400, height: 320)) { ctx, size in
            var rng = SeededRandom(seed: UInt64(300 + layer))
            let color = layer == 0 ? UIColor(red: 0.10, green: 0.30, blue: 0.30, alpha: 1) : UIColor(red: 0.06, green: 0.20, blue: 0.18, alpha: 1)
            color.setFill()
            ctx.fill(CGRect(x: 0, y: size.height * 0.7, width: size.width, height: size.height * 0.3))
            var x: CGFloat = 0
            while x < size.width {
                let r = CGFloat(40 + rng.next() * (layer == 0 ? 70 : 110))
                ctx.fillEllipse(in: CGRect(x: x, y: size.height * 0.7 - r * CGFloat(0.8 + rng.next() * 0.8), width: r * 2, height: r * 2))
                x += r * CGFloat(1.0 + rng.next() * 0.6)
            }
        }
    }

    // MARK: Landmarks

    static let ruinTemple = drawn(CGSize(width: 700, height: 620)) { ctx, size in
        let w = size.width, h = size.height
        let tiers = 5
        for i in 0..<tiers {
            let tw = w * (1 - CGFloat(i) * 0.16), th = h * 0.15
            let r = CGRect(x: (w - tw) / 2, y: h - CGFloat(i + 1) * th, width: tw, height: th)
            JunglePalette.outline.setFill(); ctx.fill(r.insetBy(dx: -5, dy: -3))
            JunglePalette.stone.mixed(with: JunglePalette.leaf, amount: CGFloat(i) * 0.05).setFill(); ctx.fill(r)
            UIColor(white: 1, alpha: 0.18).setFill(); ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 10))
            JunglePalette.outline.withAlphaComponent(0.5).setFill()
            var bx = r.minX + 10
            while bx < r.maxX - 30 { ctx.fill(CGRect(x: bx, y: r.minY + th * 0.5, width: 26, height: 3)); bx += 46 }
        }
        // Doorway and a carved face.
        JunglePalette.outline.setFill()
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: w / 2 - 50, y: h - 140, width: 100, height: 140), cornerRadius: 40).cgPath); ctx.fillPath()
        Palette.yellow.setFill()
        ctx.fillEllipse(in: CGRect(x: w / 2 - 40, y: h - h * 0.15 * 4 + 20, width: 22, height: 22))
        ctx.fillEllipse(in: CGRect(x: w / 2 + 18, y: h - h * 0.15 * 4 + 20, width: 22, height: 22))
        // Vines.
        ctx.setLineCap(.round)
        for x in stride(from: w * 0.15, to: w * 0.9, by: 90) {
            ctx.setStrokeColor(JunglePalette.leaf.cgColor); ctx.setLineWidth(10)
            ctx.move(to: CGPoint(x: x, y: h * 0.25)); ctx.addQuadCurve(to: CGPoint(x: x + 20, y: h * 0.8), control: CGPoint(x: x - 40, y: h * 0.5)); ctx.strokePath()
        }
    }

    static let giantKapok = drawn(CGSize(width: 900, height: 1100)) { ctx, size in
        let w = size.width, h = size.height
        JunglePalette.outline.setFill()
        let trunk = UIBezierPath()
        trunk.move(to: CGPoint(x: w * 0.28, y: h)); trunk.addLine(to: CGPoint(x: w * 0.44, y: h * 0.32))
        trunk.addLine(to: CGPoint(x: w * 0.56, y: h * 0.32)); trunk.addLine(to: CGPoint(x: w * 0.72, y: h)); trunk.close()
        ctx.addPath(trunk.cgPath); ctx.fillPath()
        JunglePalette.trunk.mixed(with: JunglePalette.wood, amount: 0.3).setFill()
        ctx.addPath(UIBezierPath(rect: CGRect(x: w * 0.45, y: h * 0.33, width: w * 0.1, height: h * 0.67)).cgPath); ctx.fillPath()
        var rng = SeededRandom(seed: 808)
        for _ in 0..<16 {
            let bw = CGFloat(180 + rng.next() * 220)
            let r = CGRect(x: CGFloat(rng.next()) * (w - bw), y: CGFloat(rng.next()) * h * 0.3, width: bw, height: bw * 0.6)
            blob(ctx, r.insetBy(dx: -8, dy: -8), JunglePalette.outline)
            blob(ctx, r, JunglePalette.leaf.mixed(with: Palette.teal, amount: 0.2))
            blob(ctx, CGRect(x: r.minX + 30, y: r.minY + 10, width: r.width * 0.5, height: r.height * 0.4), JunglePalette.leafLight)
        }
        // Hanging flowers: the landmark's signature colour.
        for _ in 0..<14 {
            Palette.coral.setFill()
            ctx.fillEllipse(in: CGRect(x: CGFloat(rng.next()) * w * 0.9, y: CGFloat(rng.next()) * h * 0.32, width: 26, height: 26))
        }
    }

    /// A fallen giant tree spanning the river: the raft drifts beneath it.
    static let fallenTree = drawn(CGSize(width: 1800, height: 320)) { ctx, size in
        let w = size.width
        let log = UIBezierPath(roundedRect: CGRect(x: 0, y: 90, width: w, height: 110), cornerRadius: 50)
        JunglePalette.outline.setFill(); ctx.addPath(log.cgPath); ctx.fillPath()
        JunglePalette.trunk.setFill(); ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 8, y: 98, width: w - 16, height: 94), cornerRadius: 44).cgPath); ctx.fillPath()
        JunglePalette.wood.setFill(); ctx.fill(CGRect(x: 40, y: 112, width: w - 80, height: 14))
        ctx.setLineCap(.round)
        var rng = SeededRandom(seed: 41)
        for x in stride(from: 60.0, to: Double(w - 40), by: 70) {
            let len = 60 + rng.next() * 160
            ctx.setStrokeColor(JunglePalette.leaf.cgColor); ctx.setLineWidth(9)
            ctx.move(to: CGPoint(x: x, y: 190)); ctx.addQuadCurve(to: CGPoint(x: x + 10, y: 190 + len), control: CGPoint(x: x - 30, y: 190 + len / 2)); ctx.strokePath()
            if rng.next() < 0.3 { Palette.yellow.setFill(); ctx.fillEllipse(in: CGRect(x: x - 4, y: 186 + len, width: 20, height: 20)) }
        }
        for _ in 0..<14 { blob(ctx, CGRect(x: CGFloat(rng.next()) * (w - 160), y: 30 + CGFloat(rng.next()) * 70, width: 160, height: 90), JunglePalette.leaf) }
    }

    // MARK: Raft

    /// Raft deck seen from above: lashed logs, rope bindings, worn centre. Warped into perspective at runtime.
    static let raftDeck = drawn(CGSize(width: 640, height: 480)) { ctx, size in
        let logs = 7
        let lw = size.width / CGFloat(logs)
        for i in 0..<logs {
            let r = CGRect(x: CGFloat(i) * lw + 3, y: 0, width: lw - 6, height: size.height)
            JunglePalette.outline.setFill(); ctx.fill(r.insetBy(dx: -3, dy: 0))
            (i % 2 == 0 ? JunglePalette.wood : JunglePalette.wood.mixed(with: JunglePalette.trunk, amount: 0.25)).setFill(); ctx.fill(r)
            JunglePalette.woodLight.setFill(); ctx.fill(CGRect(x: r.minX + 8, y: 0, width: 7, height: size.height))
            for k in 0..<3 {
                JunglePalette.trunk.withAlphaComponent(0.6).setFill()
                ctx.fillEllipse(in: CGRect(x: r.midX - 6, y: CGFloat(60 + k * 150 + i * 13 % 40), width: 12, height: 22))
            }
        }
        for y in [size.height * 0.12, size.height * 0.88] {
            JunglePalette.outline.setFill(); ctx.fill(CGRect(x: 0, y: y - 12, width: size.width, height: 24))
            JunglePalette.rope.setFill(); ctx.fill(CGRect(x: 0, y: y - 8, width: size.width, height: 16))
            JunglePalette.trunk.withAlphaComponent(0.5).setFill()
            var x: CGFloat = 0
            while x < size.width { ctx.fill(CGRect(x: x, y: y - 8, width: 4, height: 16)); x += 14 }
        }
    }

    /// The front faces of the logs (their round ends), shown along the raft's far edge.
    static let raftEdge = drawn(CGSize(width: 640, height: 70)) { ctx, size in
        let logs = 7
        let lw = size.width / CGFloat(logs)
        for i in 0..<logs {
            let r = CGRect(x: CGFloat(i) * lw + 2, y: 2, width: lw - 4, height: size.height - 4)
            JunglePalette.outline.setFill(); ctx.fillEllipse(in: r.insetBy(dx: -2, dy: -2))
            JunglePalette.woodLight.setFill(); ctx.fillEllipse(in: r)
            JunglePalette.wood.setFill(); ctx.fillEllipse(in: r.insetBy(dx: lw * 0.2, dy: 14))
            JunglePalette.trunk.setFill(); ctx.fillEllipse(in: r.insetBy(dx: lw * 0.38, dy: 26))
        }
    }

    static let flag = drawn(CGSize(width: 160, height: 100)) { ctx, size in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2)); p.addLine(to: CGPoint(x: 0, y: size.height - 6)); p.close()
        Palette.coral.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
        Palette.yellow.setFill(); ctx.fillEllipse(in: CGRect(x: 18, y: size.height / 2 - 14, width: 28, height: 28))
    }

    // MARK: Hazards and wildlife

    static let bubble = drawn(CGSize(width: 40, height: 40)) { ctx, size in
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(4)
        ctx.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
        UIColor.white.withAlphaComponent(0.8).setFill(); ctx.fillEllipse(in: CGRect(x: 10, y: 10, width: 8, height: 8))
    }

    static let droplet = drawn(CGSize(width: 32, height: 48)) { ctx, size in
        UIColor.white.setFill()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: size.width / 2, y: 0)); p.addQuadCurve(to: CGPoint(x: size.width - 2, y: size.height - 16), controlPoint: CGPoint(x: size.width, y: 18))
        p.addArc(withCenter: CGPoint(x: size.width / 2, y: size.height - 16), radius: size.width / 2 - 2, startAngle: 0, endAngle: .pi, clockwise: false)
        p.addQuadCurve(to: CGPoint(x: size.width / 2, y: 0), controlPoint: CGPoint(x: 0, y: 18)); p.close()
        ctx.addPath(p.cgPath); ctx.fillPath()
    }

    static let feather = drawn(CGSize(width: 40, height: 90)) { ctx, size in
        UIColor.white.setFill()
        ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8))
        ctx.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor); ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: size.width / 2, y: 6)); ctx.addLine(to: CGPoint(x: size.width / 2, y: size.height)); ctx.strokePath()
    }

    /// Foreground canopy leaves for the top corners (sway). Kept to the top band so players stay clear.
    static let canopyCorner = drawn(CGSize(width: 700, height: 360)) { ctx, size in
        var rng = SeededRandom(seed: 61)
        for i in 0..<14 {
            let base = CGPoint(x: 0, y: 0)
            let len = CGFloat(220 + rng.next() * 380)
            let a = CGFloat(0.12 + Double(i) / 14 * 1.1)
            let tip = CGPoint(x: base.x + cos(a) * len, y: base.y + sin(a) * len * 0.6)
            let leaf = UIBezierPath()
            leaf.move(to: base)
            leaf.addQuadCurve(to: tip, controlPoint: CGPoint(x: (base.x + tip.x) / 2 + 30, y: (base.y + tip.y) / 2 - 50))
            leaf.addQuadCurve(to: base, controlPoint: CGPoint(x: (base.x + tip.x) / 2 - 10, y: (base.y + tip.y) / 2 + 40))
            (i % 2 == 0 ? JunglePalette.canopyDark : JunglePalette.canopyDark.mixed(with: JunglePalette.leaf, amount: 0.3)).setFill()
            ctx.addPath(leaf.cgPath); ctx.fillPath()
        }
    }

    static let vine = drawn(CGSize(width: 60, height: 420)) { ctx, size in
        ctx.setLineCap(.round)
        ctx.setStrokeColor(JunglePalette.canopyDark.cgColor); ctx.setLineWidth(8)
        ctx.move(to: CGPoint(x: size.width / 2, y: 0)); ctx.addQuadCurve(to: CGPoint(x: size.width / 2, y: size.height - 20), control: CGPoint(x: 0, y: size.height / 2)); ctx.strokePath()
        var y: CGFloat = 40
        var flip = false
        while y < size.height - 30 {
            JunglePalette.leaf.mixed(with: JunglePalette.canopyDark, amount: 0.4).setFill()
            ctx.fillEllipse(in: CGRect(x: flip ? size.width / 2 : 4, y: y, width: 26, height: 16))
            y += 34; flip.toggle()
        }
    }

    /// Balance gauge: an arc, green centre → yellow → coral edges.
    static let balanceArc = drawn(CGSize(width: 420, height: 130)) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height + 160)
        let r: CGFloat = 270
        let span: CGFloat = 0.6
        let segments: [(CGFloat, CGFloat, UIColor)] = [
            (-span, -span * 0.5, Palette.coral), (-span * 0.5, -span * 0.25, Palette.yellow), (-span * 0.25, span * 0.25, Palette.mint),
            (span * 0.25, span * 0.5, Palette.yellow), (span * 0.5, span, Palette.coral),
        ]
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(Palette.deepNavy.withAlphaComponent(0.85).cgColor); ctx.setLineWidth(38)
        ctx.addArc(center: c, radius: r, startAngle: -.pi / 2 - span - 0.03, endAngle: -.pi / 2 + span + 0.03, clockwise: false); ctx.strokePath()
        for (a0, a1, color) in segments {
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(22)
            ctx.addArc(center: c, radius: r, startAngle: -.pi / 2 + a0, endAngle: -.pi / 2 + a1, clockwise: false); ctx.strokePath()
        }
    }

    static let gaugeNeedle = drawn(CGSize(width: 40, height: 80)) { ctx, size in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: size.width / 2, y: 0)); p.addLine(to: CGPoint(x: size.width - 4, y: size.height)); p.addLine(to: CGPoint(x: 4, y: size.height)); p.close()
        ctx.setLineWidth(6); ctx.setStrokeColor(Palette.deepNavy.cgColor); ctx.addPath(p.cgPath); ctx.strokePath()
        UIColor.white.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
    }

    static let leanArrow = drawn(CGSize(width: 150, height: 110)) { ctx, size in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 6, y: 38)); p.addLine(to: CGPoint(x: 86, y: 38)); p.addLine(to: CGPoint(x: 86, y: 6))
        p.addLine(to: CGPoint(x: size.width - 6, y: size.height / 2)); p.addLine(to: CGPoint(x: 86, y: size.height - 6))
        p.addLine(to: CGPoint(x: 86, y: size.height - 38)); p.addLine(to: CGPoint(x: 6, y: size.height - 38)); p.close()
        ctx.setLineWidth(10); ctx.setStrokeColor(Palette.deepNavy.cgColor); ctx.addPath(p.cgPath); ctx.strokePath()
        UIColor.white.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
    }
}
