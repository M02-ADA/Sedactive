import SpriteKit
import UIKit

/// Driftwood palette (JUNGLE_ART_DIRECTION.md: one base, one shadow tone, one highlight; ink outline).
enum DriftwoodPalette {
    static let bark = UIColor(red: 0.50, green: 0.32, blue: 0.19, alpha: 1)
    static let barkShade = UIColor(red: 0.33, green: 0.20, blue: 0.12, alpha: 1)
    static let barkLight = UIColor(red: 0.70, green: 0.49, blue: 0.29, alpha: 1)
    static let groove = UIColor(red: 0.21, green: 0.12, blue: 0.07, alpha: 1)
    static let heartwood = UIColor(red: 0.90, green: 0.74, blue: 0.50, alpha: 1)
    static let moss = UIColor(red: 0.36, green: 0.62, blue: 0.24, alpha: 1)
    static let mossLight = UIColor(red: 0.62, green: 0.84, blue: 0.33, alpha: 1)
}

@MainActor
extension Art {
    private static func inkFill(_ ctx: CGContext, _ path: UIBezierPath, _ color: UIColor, outline: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        color.setFill(); ctx.addPath(path.cgPath); ctx.fillPath()
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(outline); ctx.addPath(path.cgPath); ctx.strokePath()
    }

    // MARK: - River Log Sweep

    /// Log body canvas: the cylinder spans x 30 … 770 (740 pt = 2 × LogPath.halfLength) with diameter 100 (= 2r),
    /// axis at y = 70. Frames roll the bark toward the camera (features move *down* the visible face).
    static let logCanvas = CGSize(width: 800, height: 140)
    static let logLength: CGFloat = 740
    static let logDiameter: CGFloat = 100
    static let logFrameCount = 10

    private static func logSilhouette() -> UIBezierPath {
        let p = UIBezierPath()
        // Snapped left end (jagged splinters), slightly flared root end on the right.
        p.move(to: CGPoint(x: 44, y: 22))
        p.addCurve(to: CGPoint(x: 752, y: 16), controlPoint1: CGPoint(x: 300, y: 18), controlPoint2: CGPoint(x: 560, y: 22))
        p.addQuadCurve(to: CGPoint(x: 772, y: 70), controlPoint: CGPoint(x: 778, y: 30))
        p.addQuadCurve(to: CGPoint(x: 752, y: 124), controlPoint: CGPoint(x: 778, y: 112))
        p.addCurve(to: CGPoint(x: 44, y: 118), controlPoint1: CGPoint(x: 560, y: 118), controlPoint2: CGPoint(x: 300, y: 122))
        p.addLine(to: CGPoint(x: 36, y: 104)); p.addLine(to: CGPoint(x: 48, y: 92)); p.addLine(to: CGPoint(x: 28, y: 78))
        p.addLine(to: CGPoint(x: 44, y: 66)); p.addLine(to: CGPoint(x: 30, y: 50)); p.addLine(to: CGPoint(x: 46, y: 38))
        p.addLine(to: CGPoint(x: 34, y: 28)); p.close()
        return p
    }

    static let logFrames: [SKTexture] = (0..<logFrameCount).map { (frame: Int) -> SKTexture in
        drawnHi(logCanvas, scale: 1.4) { ctx, size in
            let cy: CGFloat = 70, r: CGFloat = 50
            let roll = 2 * CGFloat.pi * CGFloat(frame) / CGFloat(logFrameCount)
            let body = logSilhouette()
            ctx.saveGState(); ctx.addPath(body.cgPath); ctx.clip()
            DriftwoodPalette.bark.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            // Surface features live at angles around the axis; only the front half shows, foreshortened toward the
            // top and bottom silhouette (that compression is what makes it read as a turning cylinder).
            func y(_ theta: CGFloat) -> CGFloat { cy - r * sin(theta) }
            var rng = SeededRandom(seed: 808)
            let grooves = 11
            for j in 0..<grooves {
                let theta = 2 * .pi * CGFloat(j) / CGFloat(grooves) - roll
                let facing = cos(theta)
                guard facing > 0.05 else { _ = rng.next(); _ = rng.next(); continue }
                let gy = y(theta)
                ctx.setStrokeColor(DriftwoodPalette.groove.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(max(1.5, 4.5 * facing)); ctx.setLineCap(.round)
                var x: CGFloat = 50 + CGFloat(rng.next()) * 40
                while x < 750 {
                    let len = 60 + CGFloat(rng.next()) * 110
                    ctx.move(to: CGPoint(x: x, y: gy)); ctx.addQuadCurve(to: CGPoint(x: min(752, x + len), y: gy + 2), control: CGPoint(x: x + len / 2, y: gy - 3))
                    ctx.strokePath()
                    x += len + 14 + CGFloat(rng.next()) * 26
                }
            }
            // Knots (oval, with a dark centre) and moss patches, carried round with the roll.
            for (theta0, x) in [(0.7, 210.0), (2.6, 470.0), (4.4, 640.0), (5.6, 330.0)] as [(CGFloat, CGFloat)] {
                let theta = theta0 - roll, facing = cos(theta)
                guard facing > 0.15 else { continue }
                let ky = y(theta), h = 18 * facing
                DriftwoodPalette.barkShade.setFill(); ctx.fillEllipse(in: CGRect(x: x - 16, y: ky - h / 2, width: 32, height: h))
                DriftwoodPalette.groove.setFill(); ctx.fillEllipse(in: CGRect(x: x - 7, y: ky - h / 4, width: 14, height: h / 2))
            }
            for (theta0, x0, x1) in [(1.4, 120.0, 360.0), (3.9, 520.0, 700.0)] as [(CGFloat, CGFloat, CGFloat)] {
                let theta = theta0 - roll, facing = cos(theta)
                guard facing > 0.1 else { continue }
                let my = y(theta), h = 26 * facing
                let moss = UIBezierPath()
                moss.move(to: CGPoint(x: x0, y: my))
                var x = x0
                var k = 0
                while x < x1 { let w: CGFloat = 26 + CGFloat(k % 3) * 8; moss.addQuadCurve(to: CGPoint(x: x + w, y: my), controlPoint: CGPoint(x: x + w / 2, y: my - h)); x += w; k += 1 }
                moss.addQuadCurve(to: CGPoint(x: x0, y: my), controlPoint: CGPoint(x: (x0 + x) / 2, y: my + h * 0.6))
                DriftwoodPalette.moss.setFill(); ctx.addPath(moss.cgPath); ctx.fillPath()
                DriftwoodPalette.mossLight.setFill(); ctx.fillEllipse(in: CGRect(x: x0 + 20, y: my - h * 0.7, width: (x1 - x0) * 0.4, height: max(2, h * 0.35)))
            }
            // Fixed cylinder shading over the turning bark: highlight band toward the sky, shadow tone underneath.
            DriftwoodPalette.barkLight.withAlphaComponent(0.55).setFill(); ctx.fill(CGRect(x: 0, y: 26, width: size.width, height: 12))
            DriftwoodPalette.barkShade.withAlphaComponent(0.75).setFill(); ctx.fill(CGRect(x: 0, y: 96, width: size.width, height: 30))
            // The snapped end shows pale heartwood splinters.
            DriftwoodPalette.heartwood.setFill()
            let snap = UIBezierPath()
            snap.move(to: CGPoint(x: 28, y: 78)); snap.addLine(to: CGPoint(x: 62, y: 70)); snap.addLine(to: CGPoint(x: 44, y: 66)); snap.addLine(to: CGPoint(x: 66, y: 52))
            snap.addLine(to: CGPoint(x: 30, y: 50)); snap.close()
            ctx.addPath(snap.cgPath); ctx.fillPath()
            ctx.restoreGState()
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(5); ctx.setLineJoin(.round)
            ctx.addPath(body.cgPath); ctx.strokePath()
        }
    }

    /// Root ball at the log's right end: a tangle splayed out from the axis. Anchor: the attachment point (24, 130).
    static let logRootsAnchor = CGPoint(x: 24, y: 130)
    static let logRoots = drawnHi(CGSize(width: 230, height: 260), scale: 1.25) { ctx, _ in
        var rng = SeededRandom(seed: 919)
        let base = CGPoint(x: 24, y: 130)
        var roots: [UIBezierPath] = []
        for i in 0..<9 {
            let a = -1.25 + 2.5 * CGFloat(i) / 8 + CGFloat(rng.next() - 0.5) * 0.2
            let len = 120 + CGFloat(rng.next()) * 80
            let w = 14 - CGFloat(abs(i - 4)) * 1.2
            let tip = CGPoint(x: base.x + cos(a) * len, y: base.y + sin(a) * len)
            let bend = CGPoint(x: base.x + cos(a + 0.35) * len * 0.55, y: base.y + sin(a + 0.35) * len * 0.55)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: base.x, y: base.y - w)); p.addQuadCurve(to: tip, controlPoint: CGPoint(x: bend.x, y: bend.y - w * 0.6))
            p.addQuadCurve(to: CGPoint(x: base.x, y: base.y + w), controlPoint: CGPoint(x: bend.x, y: bend.y + w * 0.6)); p.close()
            roots.append(p)
        }
        let hub = UIBezierPath(ovalIn: CGRect(x: 0, y: 84, width: 70, height: 92))
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(9); ctx.setLineJoin(.round)
        for p in roots + [hub] { ctx.addPath(p.cgPath); ctx.strokePath() }
        for (i, p) in roots.enumerated() { (i % 2 == 0 ? DriftwoodPalette.bark : DriftwoodPalette.barkShade).setFill(); ctx.addPath(p.cgPath); ctx.fillPath() }
        DriftwoodPalette.bark.setFill(); ctx.addPath(hub.cgPath); ctx.fillPath()
        DriftwoodPalette.barkLight.setFill(); ctx.fillEllipse(in: CGRect(x: 10, y: 92, width: 34, height: 22))
        // A clump of river weed caught in the roots.
        DriftwoodPalette.moss.setFill(); ctx.fillEllipse(in: CGRect(x: 40, y: 150, width: 60, height: 26))
        DriftwoodPalette.mossLight.setFill(); ctx.fillEllipse(in: CGRect(x: 48, y: 152, width: 26, height: 10))
    }

    /// A snapped branch with three leaves, sticking out of the log (anchor at its base, pointing up).
    static let logBranch = drawnHi(CGSize(width: 150, height: 150), scale: 1.25) { ctx, _ in
        let stick = UIBezierPath()
        stick.move(to: CGPoint(x: 66, y: 150)); stick.addQuadCurve(to: CGPoint(x: 80, y: 40), controlPoint: CGPoint(x: 60, y: 90))
        stick.addLine(to: CGPoint(x: 90, y: 42)); stick.addQuadCurve(to: CGPoint(x: 84, y: 150), controlPoint: CGPoint(x: 74, y: 90)); stick.close()
        inkFill(ctx, stick, DriftwoodPalette.bark, outline: 5)
        for (cx, cy, a) in [(46.0, 52.0, -0.7), (110.0, 40.0, 0.6), (82.0, 18.0, 0.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.saveGState(); ctx.translateBy(x: cx, y: cy); ctx.rotate(by: a)
            let leaf = UIBezierPath()
            leaf.move(to: CGPoint(x: 0, y: 22)); leaf.addQuadCurve(to: CGPoint(x: 0, y: -22), controlPoint: CGPoint(x: -20, y: 0))
            leaf.addQuadCurve(to: CGPoint(x: 0, y: 22), controlPoint: CGPoint(x: 20, y: 0))
            inkFill(ctx, leaf, JunglePalette.leaf, outline: 4)
            JunglePalette.leafLight.setFill(); ctx.fillEllipse(in: CGRect(x: -6, y: -14, width: 7, height: 16))
            ctx.restoreGState()
        }
    }

    /// A small leaf floating on the rapids (the warning: debris swirling toward the log's line).
    static let floatingLeaf = drawnHi(CGSize(width: 48, height: 30), scale: 1.25) { ctx, _ in
        let leaf = UIBezierPath()
        leaf.move(to: CGPoint(x: 4, y: 15)); leaf.addQuadCurve(to: CGPoint(x: 44, y: 15), controlPoint: CGPoint(x: 24, y: -2))
        leaf.addQuadCurve(to: CGPoint(x: 4, y: 15), controlPoint: CGPoint(x: 24, y: 32))
        inkFill(ctx, leaf, JunglePalette.leafLight, outline: 3)
        ctx.setStrokeColor(JunglePalette.leaf.cgColor); ctx.setLineWidth(2); ctx.move(to: CGPoint(x: 8, y: 15)); ctx.addLine(to: CGPoint(x: 40, y: 15)); ctx.strokePath()
    }

    // MARK: - Warning badges (same family as the piranha badge: yellow disc, ink outline, icon + up arrow)

    private static func badgeBase(_ ctx: CGContext, _ size: CGSize) {
        let r = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 0, color: Palette.deepNavy.withAlphaComponent(0.55).cgColor)
        Palette.yellow.setFill(); ctx.fillEllipse(in: r)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(9); ctx.strokeEllipse(in: r.insetBy(dx: 2, dy: 2))
    }

    /// A little figure with knees tucked, clearing a log: "jump the log".
    private static func jumper(_ ctx: CGContext, x: CGFloat, y: CGFloat) {
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(7)
        JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(x: x - 9, y: y - 30, width: 18, height: 18))
        ctx.move(to: CGPoint(x: x, y: y - 10)); ctx.addLine(to: CGPoint(x: x, y: y + 8)); ctx.strokePath()                    // body
        ctx.move(to: CGPoint(x: x - 15, y: y - 18)); ctx.addLine(to: CGPoint(x: x, y: y - 6)); ctx.addLine(to: CGPoint(x: x + 15, y: y - 18)); ctx.strokePath()   // arms up
        ctx.move(to: CGPoint(x: x - 13, y: y + 12)); ctx.addLine(to: CGPoint(x: x, y: y + 8)); ctx.addLine(to: CGPoint(x: x + 13, y: y + 12)); ctx.strokePath()   // knees tucked
        ctx.move(to: CGPoint(x: x - 13, y: y + 12)); ctx.addLine(to: CGPoint(x: x - 9, y: y + 22)); ctx.strokePath()
        ctx.move(to: CGPoint(x: x + 13, y: y + 12)); ctx.addLine(to: CGPoint(x: x + 9, y: y + 22)); ctx.strokePath()
    }

    static let logSign = drawnHi(CGSize(width: 160, height: 160), scale: 1.25) { ctx, size in
        badgeBase(ctx, size)
        let log = UIBezierPath(roundedRect: CGRect(x: 30, y: 106, width: 100, height: 24), cornerRadius: 12)
        JunglePalette.outline.setFill(); ctx.addPath(log.cgPath); ctx.fillPath()
        Palette.yellow.setFill(); ctx.fillEllipse(in: CGRect(x: 110, y: 110, width: 15, height: 16))
        JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(x: 114, y: 114, width: 7, height: 8))
        jumper(ctx, x: 80, y: 66)
        // Motion arcs either side of the jumper: "up and over".
        ctx.setLineWidth(5); ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: 80, y: 96), radius: 46, startAngle: .pi * 1.15, endAngle: .pi * 1.32, clockwise: false); ctx.strokePath()
        ctx.addArc(center: CGPoint(x: 80, y: 96), radius: 46, startAngle: .pi * 1.68, endAngle: .pi * 1.85, clockwise: false); ctx.strokePath()
    }

    /// A croc tail swinging low (motion arrow underneath) and a jumper above it: "jump the tail".
    static let tailSign = drawnHi(CGSize(width: 160, height: 160), scale: 1.25) { ctx, size in
        badgeBase(ctx, size)
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: 134, y: 100))
        tail.addCurve(to: CGPoint(x: 30, y: 112), controlPoint1: CGPoint(x: 100, y: 102), controlPoint2: CGPoint(x: 60, y: 104))
        tail.addCurve(to: CGPoint(x: 134, y: 122), controlPoint1: CGPoint(x: 60, y: 116), controlPoint2: CGPoint(x: 100, y: 124))
        tail.close()
        JunglePalette.outline.setFill(); ctx.addPath(tail.cgPath); ctx.fillPath()
        for x in [70.0, 92.0, 114.0] as [CGFloat] {
            let sc = UIBezierPath(); sc.move(to: CGPoint(x: x - 7, y: 104)); sc.addLine(to: CGPoint(x: x, y: 93)); sc.addLine(to: CGPoint(x: x + 7, y: 103)); sc.close()
            ctx.addPath(sc.cgPath); ctx.fillPath()
        }
        // Sweep arrow under it, pointing the way it swings.
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(5); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 120, y: 136)); ctx.addQuadCurve(to: CGPoint(x: 44, y: 134), control: CGPoint(x: 82, y: 146)); ctx.strokePath()
        let head = UIBezierPath(); head.move(to: CGPoint(x: 36, y: 132)); head.addLine(to: CGPoint(x: 50, y: 125)); head.addLine(to: CGPoint(x: 49, y: 140)); head.close()
        JunglePalette.outline.setFill(); ctx.addPath(head.cgPath); ctx.fillPath()
        jumper(ctx, x: 80, y: 58)
    }

    // MARK: - Crocodile tail (articulated)

    /// One tail segment seen side-on, lying low: crest scutes on top, cream belly underneath, ink only along the
    /// top and bottom (segments overlap end to end, so there are no seams). Anchor: the segment's centre.
    static let tailSegment = designerPart("tail-segment") ?? drawnHi(CGSize(width: 120, height: 70), scale: 1.25) { ctx, size in
        let body = CGRect(x: 0, y: 22, width: size.width, height: 40)
        CreaturePalette.crocBase.setFill(); ctx.fill(body)
        CreaturePalette.crocBelly.setFill(); ctx.fill(CGRect(x: 0, y: 50, width: size.width, height: 12))
        CreaturePalette.crocShade.setFill(); ctx.fill(CGRect(x: 0, y: 44, width: size.width, height: 6))
        CreaturePalette.crocLight.setFill(); ctx.fill(CGRect(x: 0, y: 26, width: size.width, height: 5))
        // Two crest scutes per segment.
        for x in [30.0, 90.0] as [CGFloat] {
            let s = UIBezierPath(); s.move(to: CGPoint(x: x - 16, y: 24)); s.addQuadCurve(to: CGPoint(x: x + 16, y: 24), controlPoint: CGPoint(x: x, y: -4)); s.close()
            CreaturePalette.crocBase.setFill(); ctx.addPath(s.cgPath); ctx.fillPath()
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(4.5); ctx.addPath(s.cgPath); ctx.strokePath()
            CreaturePalette.crocLight.setFill(); ctx.fillEllipse(in: CGRect(x: x - 8, y: 10, width: 8, height: 7))
        }
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(5)
        ctx.move(to: CGPoint(x: 0, y: 24)); ctx.addLine(to: CGPoint(x: size.width, y: 24)); ctx.strokePath()
        ctx.move(to: CGPoint(x: 0, y: 62)); ctx.addLine(to: CGPoint(x: size.width, y: 62)); ctx.strokePath()
    }

    /// The tail tip: tapers to a rounded point. Anchor: left middle (joins the last segment).
    static let tailTip = designerPart("tail-tip") ?? drawnHi(CGSize(width: 140, height: 70), scale: 1.25) { ctx, _ in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 24)); p.addQuadCurve(to: CGPoint(x: 132, y: 44), controlPoint: CGPoint(x: 80, y: 26))
        p.addQuadCurve(to: CGPoint(x: 0, y: 62), controlPoint: CGPoint(x: 80, y: 62)); p.close()
        CreaturePalette.crocBase.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(p.cgPath); ctx.clip()
        CreaturePalette.crocBelly.setFill(); ctx.fill(CGRect(x: 0, y: 52, width: 140, height: 12))
        ctx.restoreGState()
        let s = UIBezierPath(); s.move(to: CGPoint(x: 14, y: 26)); s.addQuadCurve(to: CGPoint(x: 40, y: 28), controlPoint: CGPoint(x: 26, y: 6)); s.close()
        CreaturePalette.crocBase.setFill(); ctx.addPath(s.cgPath); ctx.fillPath()
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(4.5); ctx.setLineJoin(.round)
        ctx.addPath(s.cgPath); ctx.strokePath()
        ctx.addPath(p.cgPath); ctx.strokePath()
        // Re-cover the left edge (it overlaps the previous segment: no vertical seam line).
        CreaturePalette.crocBase.setFill(); ctx.fill(CGRect(x: 0, y: 27, width: 4, height: 33))
    }

    static var jumpSweepTextures: [SKTexture] { logFrames + [logRoots, logBranch, floatingLeaf, logSign, tailSign, tailSegment, tailTip] }
}
