import SpriteKit
import UIKit

/// Creature palette (see JUNGLE_ART_DIRECTION.md): one base, one shadow tone, one highlight per material.
enum CreaturePalette {
    static let crocBase = UIColor(red: 0.36, green: 0.56, blue: 0.26, alpha: 1)
    static let crocShade = UIColor(red: 0.22, green: 0.38, blue: 0.18, alpha: 1)
    static let crocLight = UIColor(red: 0.58, green: 0.76, blue: 0.34, alpha: 1)
    static let crocBelly = UIColor(red: 0.90, green: 0.84, blue: 0.56, alpha: 1)
    static let mouth = UIColor(red: 0.93, green: 0.42, blue: 0.42, alpha: 1)
    static let throat = UIColor(red: 0.50, green: 0.13, blue: 0.20, alpha: 1)
    static let tooth = UIColor(red: 0.99, green: 0.97, blue: 0.88, alpha: 1)
    static let iris = UIColor(red: 1.0, green: 0.80, blue: 0.22, alpha: 1)
    static let foam = UIColor(red: 0.88, green: 0.99, blue: 0.96, alpha: 1)
    static let waterInner = UIColor(red: 0.55, green: 0.86, blue: 0.84, alpha: 1)

    /// Macaw palettes share roles: body, chest, head, underwing coverts, wing band, flight feathers, tail tip.
    struct Macaw {
        let body, chest, head, coverts, band, flight, tailTip: UIColor
    }
    static let scarlet = Macaw(body: Palette.coral, chest: Palette.coral.mixed(with: .white, amount: 0.12),
                               head: Palette.coral, coverts: Palette.coral.mixed(with: Palette.yellow, amount: 0.25),
                               band: Palette.yellow, flight: UIColor(red: 0.10, green: 0.62, blue: 0.80, alpha: 1),
                               tailTip: UIColor(red: 0.10, green: 0.62, blue: 0.80, alpha: 1))
    static let blueGold = Macaw(body: UIColor(red: 0.10, green: 0.62, blue: 0.80, alpha: 1), chest: Palette.yellow,
                                head: UIColor(red: 0.20, green: 0.78, blue: 0.62, alpha: 1), coverts: Palette.yellow,
                                band: Palette.yellow.mixed(with: Palette.coral, amount: 0.25),
                                flight: UIColor(red: 0.08, green: 0.42, blue: 0.70, alpha: 1),
                                tailTip: UIColor(red: 0.08, green: 0.42, blue: 0.70, alpha: 1))
}

@MainActor
extension Art {
    /// Creatures are drawn above 1× so they stay crisp at the size they reach beside the raft.
    static func drawnHi(_ size: CGSize, scale: CGFloat, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Evaluation hook for designer deliveries (`-crocParts <folder>`): loads `<folder>/<name>@2x.png` in place of the
    /// code-drawn part, so delivered PNGs can be checked in game with no code changes. The PNG's point size must match
    /// the canvas in DesignerKit/ASSET_SPEC.md (pivots are derived from it). Without the argument nothing changes.
    static func designerPart(_ name: String) -> SKTexture? {
        guard let folder = UserDefaults.standard.string(forKey: "crocParts"),
              let data = FileManager.default.contents(atPath: (folder as NSString).appendingPathComponent("\(name)@2x.png")),
              let image = UIImage(data: data, scale: 2) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Union outline: stroke every shape wide in ink first, then fill them all, so overlapping parts read as one
    /// drawing with a single outer line (the same edge weight on every part of a rig).
    private static func inked(_ ctx: CGContext, _ paths: [(UIBezierPath, UIColor)], outline: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.setStrokeColor(JunglePalette.outline.cgColor)
        ctx.setLineWidth(outline * 2)
        for (p, _) in paths { ctx.addPath(p.cgPath); ctx.strokePath() }
        for (p, c) in paths { c.setFill(); ctx.addPath(p.cgPath); ctx.fillPath() }
    }

    private static func clipped(_ ctx: CGContext, _ path: UIBezierPath, _ draw: () -> Void) {
        ctx.saveGState(); ctx.addPath(path.cgPath); ctx.clip(); draw(); ctx.restoreGState()
    }

    private static func tooth(_ ctx: CGContext, at x: CGFloat, baseY: CGFloat, height: CGFloat, width: CGFloat, down: Bool) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x - width / 2, y: baseY))
        p.addQuadCurve(to: CGPoint(x: x + width * 0.08, y: baseY + (down ? height : -height)), controlPoint: CGPoint(x: x - width * 0.3, y: baseY + (down ? height * 0.6 : -height * 0.6)))
        p.addQuadCurve(to: CGPoint(x: x + width / 2, y: baseY), controlPoint: CGPoint(x: x + width * 0.3, y: baseY + (down ? height * 0.4 : -height * 0.4)))
        p.close()
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(3); ctx.setLineJoin(.round)
        CreaturePalette.tooth.setFill(); ctx.addPath(p.cgPath); ctx.drawPath(using: .fillStroke)
    }

    // MARK: - Crocodile, side view (attack). Facing +x. Hinge points are listed with each part.

    static let crocOutline: CGFloat = 5

    /// Cranium + upper jaw. Hinge (jaw pivot) at (40, 130) in the canvas (UIKit coordinates).
    static let crocUpperHinge = CGPoint(x: 40, y: 130)
    static let crocUpper = designerPart("croc-upper") ?? drawnHi(CGSize(width: 380, height: 200), scale: 1.5) { ctx, _ in
        let head = UIBezierPath()
        head.move(to: CGPoint(x: 24, y: 132))
        head.addCurve(to: CGPoint(x: 34, y: 66), controlPoint1: CGPoint(x: 12, y: 112), controlPoint2: CGPoint(x: 16, y: 80))
        head.addCurve(to: CGPoint(x: 120, y: 46), controlPoint1: CGPoint(x: 56, y: 50), controlPoint2: CGPoint(x: 92, y: 40))
        head.addCurve(to: CGPoint(x: 196, y: 80), controlPoint1: CGPoint(x: 146, y: 54), controlPoint2: CGPoint(x: 166, y: 74))
        head.addCurve(to: CGPoint(x: 318, y: 88), controlPoint1: CGPoint(x: 240, y: 88), controlPoint2: CGPoint(x: 286, y: 90))
        head.addCurve(to: CGPoint(x: 346, y: 74), controlPoint1: CGPoint(x: 326, y: 78), controlPoint2: CGPoint(x: 336, y: 70))
        head.addCurve(to: CGPoint(x: 368, y: 108), controlPoint1: CGPoint(x: 362, y: 78), controlPoint2: CGPoint(x: 370, y: 94))
        head.addCurve(to: CGPoint(x: 340, y: 134), controlPoint1: CGPoint(x: 366, y: 126), controlPoint2: CGPoint(x: 354, y: 134))
        head.addLine(to: CGPoint(x: 24, y: 134))
        head.close()
        let bump = UIBezierPath(ovalIn: CGRect(x: 54, y: 10, width: 70, height: 66))
        inked(ctx, [(bump, CreaturePalette.crocBase), (head, CreaturePalette.crocBase)], outline: crocOutline)
        // Shadow tone on the lower half of the jaw, highlight along the top of the snout and the eye bump.
        clipped(ctx, head) {
            CreaturePalette.crocShade.setFill(); ctx.fill(CGRect(x: 0, y: 112, width: 380, height: 30))
            CreaturePalette.crocLight.setFill()
            ctx.fillEllipse(in: CGRect(x: 150, y: 80, width: 150, height: 10))
            // Side scales: a few rounded plates, low contrast.
            CreaturePalette.crocShade.withAlphaComponent(0.35).setFill()
            for (x, y, w) in [(60.0, 96.0, 26.0), (92, 100, 22), (124, 96, 20), (70, 72, 18), (154, 98, 18), (186, 100, 16)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: w * 0.62), cornerRadius: w * 0.3).cgPath); ctx.fillPath()
            }
        }
        clipped(ctx, bump) { CreaturePalette.crocLight.setFill(); ctx.fillEllipse(in: CGRect(x: 64, y: 16, width: 34, height: 18)) }
        // Nostril.
        JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(x: 344, y: 80, width: 12, height: 8))
        // Upper teeth (pointing down) with the overbite fang near the tip.
        for x in stride(from: CGFloat(132), through: 300, by: 24) { tooth(ctx, at: x, baseY: 132, height: 12, width: 13, down: true) }
        tooth(ctx, at: 326, baseY: 131, height: 24, width: 16, down: true)
    }

    /// Lower jaw. Hinge at (40, 8). Coral mouth floor and teeth show only when the jaw opens.
    static let crocLowerHinge = CGPoint(x: 40, y: 8)
    static let crocLower = designerPart("croc-lower") ?? drawnHi(CGSize(width: 380, height: 90), scale: 1.5) { ctx, _ in
        let jaw = UIBezierPath()
        jaw.move(to: CGPoint(x: 24, y: 6))
        jaw.addLine(to: CGPoint(x: 330, y: 12))
        jaw.addCurve(to: CGPoint(x: 352, y: 30), controlPoint1: CGPoint(x: 346, y: 12), controlPoint2: CGPoint(x: 352, y: 20))
        jaw.addCurve(to: CGPoint(x: 296, y: 58), controlPoint1: CGPoint(x: 352, y: 46), controlPoint2: CGPoint(x: 330, y: 56))
        jaw.addCurve(to: CGPoint(x: 70, y: 62), controlPoint1: CGPoint(x: 220, y: 64), controlPoint2: CGPoint(x: 120, y: 66))
        jaw.addCurve(to: CGPoint(x: 24, y: 6), controlPoint1: CGPoint(x: 36, y: 56), controlPoint2: CGPoint(x: 18, y: 26))
        jaw.close()
        inked(ctx, [(jaw, CreaturePalette.crocBase)], outline: crocOutline)
        clipped(ctx, jaw) {
            CreaturePalette.crocBelly.setFill(); ctx.fill(CGRect(x: 0, y: 36, width: 380, height: 40))
            CreaturePalette.crocBelly.mixed(with: CreaturePalette.crocShade, amount: 0.3).setFill()
            for x in stride(from: CGFloat(80), through: 300, by: 28) { ctx.fill(CGRect(x: x, y: 38, width: 3, height: 26)) }
            CreaturePalette.mouth.setFill(); ctx.fill(CGRect(x: 50, y: 6, width: 290, height: 9))
        }
        for x in stride(from: CGFloat(118), through: 318, by: 24) { tooth(ctx, at: x, baseY: 12, height: 11, width: 12, down: false) }
    }

    /// Throat: fills the gap between the jaws. Anchored at the hinge (20, 6) and scaled vertically with the jaw.
    static let crocThroatHinge = CGPoint(x: 20, y: 6)
    static let crocThroat = designerPart("croc-throat") ?? drawnHi(CGSize(width: 340, height: 200), scale: 1.0) { ctx, _ in
        let w = UIBezierPath()
        w.move(to: CGPoint(x: 20, y: 6))
        w.addLine(to: CGPoint(x: 316, y: 4))
        w.addQuadCurve(to: CGPoint(x: 262, y: 178), controlPoint: CGPoint(x: 312, y: 120))
        w.addLine(to: CGPoint(x: 20, y: 12))
        w.close()
        CreaturePalette.throat.setFill(); ctx.addPath(w.cgPath); ctx.fillPath()
        clipped(ctx, w) {
            CreaturePalette.mouth.setFill()
            ctx.fillEllipse(in: CGRect(x: 120, y: 90, width: 190, height: 120))   // tongue
            CreaturePalette.mouth.mixed(with: .white, amount: 0.25).setFill()
            ctx.fillEllipse(in: CGRect(x: 170, y: 104, width: 90, height: 22))
        }
    }

    /// Body: neck at the right (anchor (420, 92)), scute ridge along the back, belly below.
    static let crocBodyAnchor = CGPoint(x: 420, y: 92)
    static let crocBody = designerPart("croc-body") ?? drawnHi(CGSize(width: 440, height: 170), scale: 1.25) { ctx, _ in
        let b = UIBezierPath()
        b.move(to: CGPoint(x: 424, y: 44))
        b.addCurve(to: CGPoint(x: 70, y: 52), controlPoint1: CGPoint(x: 320, y: 30), controlPoint2: CGPoint(x: 160, y: 36))
        b.addCurve(to: CGPoint(x: 18, y: 96), controlPoint1: CGPoint(x: 40, y: 58), controlPoint2: CGPoint(x: 18, y: 74))
        b.addCurve(to: CGPoint(x: 80, y: 142), controlPoint1: CGPoint(x: 18, y: 122), controlPoint2: CGPoint(x: 44, y: 140))
        b.addCurve(to: CGPoint(x: 424, y: 140), controlPoint1: CGPoint(x: 200, y: 150), controlPoint2: CGPoint(x: 340, y: 150))
        b.close()
        var scutes: [(UIBezierPath, UIColor)] = []
        for (i, x) in stride(from: CGFloat(70), through: 400, by: 30).enumerated() {
            let r: CGFloat = 13 + CGFloat(i % 2) * 2
            let y = 44 - 10 * sin(.pi * (x - 70) / 330)
            scutes.append((UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r * 0.9, width: r * 2, height: r * 1.6)), CreaturePalette.crocBase))
        }
        inked(ctx, scutes + [(b, CreaturePalette.crocBase)], outline: crocOutline)
        clipped(ctx, b) {
            CreaturePalette.crocShade.setFill(); ctx.fill(CGRect(x: 0, y: 104, width: 440, height: 20))
            CreaturePalette.crocBelly.setFill(); ctx.fill(CGRect(x: 0, y: 122, width: 440, height: 40))
            CreaturePalette.crocShade.withAlphaComponent(0.35).setFill()
            for row in 0..<2 {
                for x in stride(from: CGFloat(90 + row * 15), through: 400, by: 30) {
                    ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: 66 + CGFloat(row) * 20, width: 22, height: 13), cornerRadius: 6).cgPath); ctx.fillPath()
                }
            }
        }
        CreaturePalette.crocLight.setFill()
        for (p, _) in scutes { clipped(ctx, p) { let r = p.bounds; ctx.fillEllipse(in: CGRect(x: r.minX + 3, y: r.minY + 2, width: r.width * 0.55, height: r.height * 0.45)) } }
    }

    /// Tail: base at the right (anchor (350, 56)), double crest, tapering to the tip.
    static let crocTailAnchor = CGPoint(x: 350, y: 56)
    static let crocTail = designerPart("croc-tail") ?? drawnHi(CGSize(width: 360, height: 110), scale: 1.0) { ctx, _ in
        let t = UIBezierPath()
        t.move(to: CGPoint(x: 352, y: 14))
        t.addCurve(to: CGPoint(x: 8, y: 64), controlPoint1: CGPoint(x: 220, y: 22), controlPoint2: CGPoint(x: 80, y: 44))
        t.addCurve(to: CGPoint(x: 352, y: 102), controlPoint1: CGPoint(x: 90, y: 84), controlPoint2: CGPoint(x: 220, y: 104))
        t.close()
        var crest: [(UIBezierPath, UIColor)] = []
        for x in stride(from: CGFloat(60), through: 330, by: 26) {
            let s = 5 + 7 * (x - 60) / 270
            let y = 64 - (64 - 14) * (x - 8) / 344 - 2
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x - s, y: y + 3)); p.addQuadCurve(to: CGPoint(x: x + s, y: y + 3), controlPoint: CGPoint(x: x, y: y - s * 2.2)); p.close()
            crest.append((p, CreaturePalette.crocBase))
        }
        inked(ctx, crest + [(t, CreaturePalette.crocBase)], outline: crocOutline - 1)
        clipped(ctx, t) {
            CreaturePalette.crocBelly.setFill()
            let belly = UIBezierPath(); belly.move(to: CGPoint(x: 352, y: 80)); belly.addQuadCurve(to: CGPoint(x: 20, y: 66), controlPoint: CGPoint(x: 160, y: 84)); belly.addLine(to: CGPoint(x: 352, y: 120)); belly.close()
            ctx.addPath(belly.cgPath); ctx.fillPath()
            CreaturePalette.crocShade.withAlphaComponent(0.35).setFill()
            for x in stride(from: CGFloat(80), through: 330, by: 30) { ctx.fill(CGRect(x: x, y: 40, width: 3, height: 40)) }
        }
    }

    /// Front leg reaching for the raft: shoulder anchor at (40, 18).
    static let crocLegAnchor = CGPoint(x: 40, y: 18)
    static let crocLeg = designerPart("croc-leg") ?? drawnHi(CGSize(width: 150, height: 160), scale: 1.25) { ctx, _ in
        let limb = UIBezierPath()
        limb.move(to: CGPoint(x: 40, y: 18)); limb.addLine(to: CGPoint(x: 62, y: 84)); limb.addLine(to: CGPoint(x: 92, y: 116))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(34 + crocOutline * 2); ctx.addPath(limb.cgPath); ctx.strokePath()
        let foot = UIBezierPath(ovalIn: CGRect(x: 72, y: 104, width: 60, height: 30))
        var claws: [(UIBezierPath, UIColor)] = []
        for i in 0..<4 {
            let x = 98 + CGFloat(i) * 10, y = 126 + CGFloat(i % 2) * 2
            let c = UIBezierPath(); c.move(to: CGPoint(x: x - 5, y: y)); c.addQuadCurve(to: CGPoint(x: x + 9, y: y + 18), controlPoint: CGPoint(x: x + 6, y: y + 4)); c.addLine(to: CGPoint(x: x + 5, y: y)); c.close()
            claws.append((c, CreaturePalette.tooth))
        }
        inked(ctx, [(foot, CreaturePalette.crocBase)] + claws, outline: crocOutline - 1)
        ctx.setStrokeColor(CreaturePalette.crocBase.cgColor); ctx.setLineWidth(34); ctx.addPath(limb.cgPath); ctx.strokePath()
        CreaturePalette.crocBase.setFill(); ctx.fillEllipse(in: CGRect(x: 72, y: 104, width: 60, height: 30))
        ctx.setStrokeColor(CreaturePalette.crocLight.cgColor); ctx.setLineWidth(8)
        ctx.move(to: CGPoint(x: 36, y: 22)); ctx.addLine(to: CGPoint(x: 52, y: 70)); ctx.strokePath()
    }

    // MARK: - Crocodile eye (shared by both views): sclera + iris, pupil, lid, brow.

    static let crocEye = designerPart("croc-eye") ?? drawnHi(CGSize(width: 80, height: 80), scale: 1.5) { ctx, _ in
        let r = CGRect(x: 10, y: 10, width: 60, height: 60)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(crocOutline * 1.2)
        UIColor.white.setFill(); ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r)
        CreaturePalette.iris.setFill(); ctx.fillEllipse(in: r.insetBy(dx: 9, dy: 9))
    }
    static let crocPupil = designerPart("croc-pupil") ?? drawnHi(CGSize(width: 16, height: 40), scale: 1.5) { ctx, size in
        JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 1))
    }
    /// A filled cap that slides over the eye from the top (anchor top-centre, scaled vertically).
    static let crocLid = designerPart("croc-lid") ?? drawnHi(CGSize(width: 80, height: 70), scale: 1.5) { ctx, size in
        let r = CGRect(x: 6, y: -6, width: 68, height: size.height + 2)
        CreaturePalette.crocBase.setFill(); ctx.fillEllipse(in: r)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(crocOutline * 1.2)
        ctx.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
        ctx.strokePath()
    }
    static let crocBrow = designerPart("croc-brow") ?? drawnHi(CGSize(width: 96, height: 40), scale: 1.5) { ctx, _ in
        let p = UIBezierPath(roundedRect: CGRect(x: 8, y: 10, width: 80, height: 20), cornerRadius: 10)
        inked(ctx, [(p, CreaturePalette.crocBase)], outline: crocOutline)
        CreaturePalette.crocLight.setFill(); ctx.fillEllipse(in: CGRect(x: 18, y: 12, width: 40, height: 7))
    }
    /// Specular dot: keeps the eye alive (always on top, never moves with the pupil).
    static let crocGlint = designerPart("croc-glint") ?? drawnHi(CGSize(width: 16, height: 16), scale: 1.5) { ctx, size in
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
    }

    // MARK: - Crocodile, head-on (approach): eyes and snout above the waterline. Waterline at y = 150.

    static let crocFrontWaterline: CGFloat = 150
    static let crocFrontEyes: [CGPoint] = [CGPoint(x: 96, y: 92), CGPoint(x: 204, y: 92)]
    static let crocFront = designerPart("croc-front") ?? drawnHi(CGSize(width: 300, height: 170), scale: 1.25) { ctx, _ in
        // Low, wide and flat: the back of the skull barely breaks the surface, almond eye bumps under heavy brows,
        // and the snout runs toward the camera to a separate nostril pad at the waterline.
        let skull = UIBezierPath(ovalIn: CGRect(x: 22, y: 112, width: 256, height: 70))
        let bumps = crocFrontEyes.map { UIBezierPath(ovalIn: CGRect(x: $0.x - 42, y: $0.y - 30, width: 84, height: 58)) }
        let snout = UIBezierPath()
        snout.move(to: CGPoint(x: 112, y: 116)); snout.addLine(to: CGPoint(x: 188, y: 116))
        snout.addQuadCurve(to: CGPoint(x: 178, y: 152), controlPoint: CGPoint(x: 196, y: 140))
        snout.addLine(to: CGPoint(x: 122, y: 152))
        snout.addQuadCurve(to: CGPoint(x: 112, y: 116), controlPoint: CGPoint(x: 104, y: 140)); snout.close()
        let pad = UIBezierPath(ovalIn: CGRect(x: 120, y: 132, width: 60, height: 30))
        var brows: [UIBezierPath] = []
        for (i, e) in crocFrontEyes.enumerated() {
            let dir: CGFloat = i == 0 ? -1 : 1
            let brow = UIBezierPath()
            brow.move(to: CGPoint(x: e.x - dir * 40, y: e.y - 14))
            brow.addQuadCurve(to: CGPoint(x: e.x + dir * 30, y: e.y - 32), controlPoint: CGPoint(x: e.x - dir * 8, y: e.y - 44))
            brow.addQuadCurve(to: CGPoint(x: e.x - dir * 40, y: e.y - 14), controlPoint: CGPoint(x: e.x, y: e.y - 26))
            brow.close()
            brows.append(brow)
        }
        let scutes = (0..<3).map { UIBezierPath(ovalIn: CGRect(x: 128 + CGFloat($0) * 16, y: 104 - CGFloat($0 % 2) * 2, width: 14, height: 12)) }
        let shapes: [UIBezierPath] = [skull] + scutes + [snout] + bumps + brows + [pad]
        inked(ctx, shapes.map { (path: UIBezierPath) -> (UIBezierPath, UIColor) in (path, CreaturePalette.crocBase) }, outline: crocOutline)
        clipped(ctx, skull) { CreaturePalette.crocShade.setFill(); ctx.fill(CGRect(x: 0, y: 136, width: 300, height: 40)) }
        clipped(ctx, snout) { CreaturePalette.crocShade.setFill(); ctx.fill(CGRect(x: 0, y: 140, width: 300, height: 20)) }
        CreaturePalette.crocLight.setFill()
        for b in brows { clipped(ctx, b) { let r = b.bounds; ctx.fillEllipse(in: CGRect(x: r.minX + 6, y: r.minY + 2, width: r.width * 0.6, height: r.height * 0.4)) } }
        clipped(ctx, pad) { ctx.fillEllipse(in: CGRect(x: 130, y: 134, width: 34, height: 9)) }
        clipped(ctx, snout) { ctx.fillEllipse(in: CGRect(x: 128, y: 118, width: 44, height: 8)) }
        JunglePalette.outline.setFill()
        for dx in [-10.0, 10.0] { ctx.fillEllipse(in: CGRect(x: 150 + dx - 5, y: 142, width: 10, height: 8)) }
    }

    /// Submerged silhouette (seen through the water from above), head toward the camera. Soft, no outline.
    static let crocShadow = drawnHi(CGSize(width: 220, height: 460), scale: 0.75) { ctx, size in
        let shape = UIBezierPath()
        shape.move(to: CGPoint(x: 110, y: 440))
        shape.addCurve(to: CGPoint(x: 150, y: 300), controlPoint1: CGPoint(x: 140, y: 430), controlPoint2: CGPoint(x: 150, y: 360))
        shape.addCurve(to: CGPoint(x: 140, y: 150), controlPoint1: CGPoint(x: 170, y: 250), controlPoint2: CGPoint(x: 160, y: 190))
        shape.addCurve(to: CGPoint(x: 110, y: 10), controlPoint1: CGPoint(x: 125, y: 100), controlPoint2: CGPoint(x: 115, y: 40))
        shape.addCurve(to: CGPoint(x: 80, y: 150), controlPoint1: CGPoint(x: 105, y: 40), controlPoint2: CGPoint(x: 95, y: 100))
        shape.addCurve(to: CGPoint(x: 70, y: 300), controlPoint1: CGPoint(x: 60, y: 190), controlPoint2: CGPoint(x: 50, y: 250))
        shape.addCurve(to: CGPoint(x: 110, y: 440), controlPoint1: CGPoint(x: 70, y: 360), controlPoint2: CGPoint(x: 80, y: 430))
        shape.close()
        // Soft-edged: the fill casts a same-coloured blurred shadow around itself.
        let dark = UIColor(red: 0.0, green: 0.10, blue: 0.10, alpha: 1)
        ctx.setShadow(offset: .zero, blur: 16, color: dark.cgColor)
        dark.setFill(); ctx.addPath(shape.cgPath); ctx.fillPath()
        for (x, y) in [(36.0, 240.0), (184, 240), (40, 330), (180, 330)] as [(CGFloat, CGFloat)] { ctx.fillEllipse(in: CGRect(x: x - 22, y: y - 12, width: 44, height: 24)) }
    }

    // MARK: - Water reactions (no outline: water is light, creatures are ink)

    /// A splash crown in six authored frames: rise, peak with breaking tips, collapse, spreading foam.
    static let splashCrown: [SKTexture] = (0..<6).map { (frame: Int) -> SKTexture in
        drawnHi(CGSize(width: 280, height: 260), scale: 1.0) { ctx, size in
            var rng = SeededRandom(seed: 404)
            let k = CGFloat(frame) / 5
            let base: CGFloat = size.height - 24
            let width = 100 + 150 * k
            // Fast rise, slower fall (water is heavy): heights per frame.
            let height = 170 * ([0.35, 0.8, 1.0, 0.8, 0.45, 0.12] as [CGFloat])[frame]
            let cx = size.width / 2
            let tips = 7
            let sheet = UIBezierPath()
            sheet.move(to: CGPoint(x: cx - width / 2, y: base))
            for i in 0..<tips {
                let u = CGFloat(i) / CGFloat(tips - 1)
                let x = cx - width / 2 + width * (0.08 + 0.84 * u)
                let h = height * (0.55 + 0.45 * sin(.pi * u)) * CGFloat(0.85 + rng.next() * 0.3)
                sheet.addQuadCurve(to: CGPoint(x: x, y: base - h), controlPoint: CGPoint(x: x - width * 0.07, y: base - h * 0.55))
            }
            sheet.addQuadCurve(to: CGPoint(x: cx + width / 2, y: base), controlPoint: CGPoint(x: cx + width * 0.5, y: base - height * 0.3))
            sheet.addQuadCurve(to: CGPoint(x: cx - width / 2, y: base), controlPoint: CGPoint(x: cx, y: base + 18))
            sheet.close()
            CreaturePalette.foam.withAlphaComponent(frame >= 4 ? 0.75 : 0.95).setFill(); ctx.addPath(sheet.cgPath); ctx.fillPath()
            // Inner face of the sheet: a darker, see-through band gives the crown volume.
            CreaturePalette.waterInner.withAlphaComponent(0.7).setFill()
            ctx.fillEllipse(in: CGRect(x: cx - width * 0.36, y: base - height * 0.35, width: width * 0.72, height: max(8, height * 0.3)))
            // Detached drops at the peak and while it collapses.
            if (2...4).contains(frame) {
                CreaturePalette.foam.setFill()
                for i in 0..<9 {
                    let u = CGFloat(i) / 8
                    let x = cx + (u - 0.5) * width * (1.1 + k * 0.4)
                    let y = max(14, base - height * (0.98 + CGFloat(rng.next()) * 0.2) - 6 + CGFloat(frame - 2) * 38)
                    let r = CGFloat(5 + rng.next() * 6) * (1 - k * 0.4)
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2.3))
                }
            }
            // Foam ring at the base.
            CreaturePalette.foam.withAlphaComponent(0.85).setFill()
            for i in 0..<14 {
                let a = CGFloat(i) / 14 * 2 * .pi
                let r = CGFloat(10 + rng.next() * 8)
                ctx.fillEllipse(in: CGRect(x: cx + cos(a) * width * 0.55 - r, y: base + sin(a) * 10 - r * 0.5, width: r * 2, height: r))
            }
        }
    }

    /// A thin, slightly broken ripple ring for the water surface (no glow: water is light, not neon).
    static let rippleRing = drawnHi(CGSize(width: 240, height: 240), scale: 1.0) { ctx, size in
        var rng = SeededRandom(seed: 626)
        ctx.setLineCap(.round)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for i in 0..<10 {
            let a0 = CGFloat(i) / 10 * 2 * .pi + CGFloat(rng.next()) * 0.2
            let a1 = a0 + 0.42 + CGFloat(rng.next()) * 0.12
            ctx.setStrokeColor(CreaturePalette.foam.withAlphaComponent(0.55 + CGFloat(rng.next()) * 0.4).cgColor)
            ctx.setLineWidth(5 + CGFloat(rng.next()) * 4)
            ctx.addArc(center: c, radius: size.width / 2 - 10, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.strokePath()
        }
    }

    /// Lumpy foam collar where a body breaks the surface.
    static let foamCollar = drawnHi(CGSize(width: 300, height: 70), scale: 1.0) { ctx, size in
        var rng = SeededRandom(seed: 515)
        CreaturePalette.foam.withAlphaComponent(0.85).setFill()
        for i in 0..<34 {
            let a = CGFloat(i) / 34 * 2 * .pi
            let r = CGFloat(7 + rng.next() * 9)
            let x = size.width / 2 + cos(a) * (size.width / 2 - 20)
            let y = size.height / 2 + sin(a) * (size.height / 2 - 14)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
        }
    }

    // MARK: - Macaw (seen from the front and slightly below, flying at the camera)

    static let macawCanvas = CGSize(width: 320, height: 270)

    private enum MacawShape { case flap(CGFloat), glide, tuck, flare, startled }

    /// One parametric macaw; every frame and pose is rendered from the same proportions.
    private static func drawMacaw(_ ctx: CGContext, _ pal: CreaturePalette.Macaw, _ shape: MacawShape) {
        let outline: CGFloat = 4.5
        let cx: CGFloat = 160, bodyY: CGFloat = 124
        var angle: CGFloat = 0, fold: CGFloat = 0, tailFan: CGFloat = 0.3, feet = false, startled = false
        switch shape {
        case .flap(let s):
            // Downstroke (s 0 → 0.5): fully spread. Upstroke: wings partly folded on the way up.
            let up: CGFloat = 1.05, down: CGFloat = -0.85
            if s < 0.5 {
                let k = s / 0.5; angle = up + (down - up) * (k * k * (3 - 2 * k))
            } else {
                let k = (s - 0.5) / 0.5; angle = down + (up - down) * (k * k * (3 - 2 * k)); fold = 0.55 * sin(.pi * k)
            }
        case .glide: angle = 0.14
        case .tuck: angle = -0.5; fold = 0.72; tailFan = 0.1
        case .flare: angle = 1.25; tailFan = 1; feet = true
        case .startled: angle = 0.75; fold = 0.2; tailFan = 0.8; feet = true; startled = true
        }

        // Tail first (behind the body): three long feathers, fanned by `tailFan`.
        var parts: [(UIBezierPath, UIColor)] = []
        for i in -1...1 {
            let a = CGFloat(i) * (0.12 + 0.22 * tailFan)
            let len: CGFloat = 104 - CGFloat(abs(i)) * 14
            let p = UIBezierPath()
            let base = CGPoint(x: cx, y: bodyY + 36)
            let tip = CGPoint(x: base.x + sin(a) * len, y: base.y + cos(a) * len)
            let side = CGPoint(x: cos(a) * 11, y: -sin(a) * 11)
            p.move(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
            p.addQuadCurve(to: tip, controlPoint: CGPoint(x: (base.x + tip.x) / 2 - side.x * 1.2, y: (base.y + tip.y) / 2 - side.y * 1.2))
            p.addQuadCurve(to: CGPoint(x: base.x + side.x, y: base.y + side.y), controlPoint: CGPoint(x: (base.x + tip.x) / 2 + side.x * 1.2, y: (base.y + tip.y) / 2 + side.y * 1.2))
            p.close()
            parts.append((p, pal.body))
        }

        // Wings: built in a local frame (shoulder at origin, along +x), mirrored for the left wing.
        func wing(_ dir: CGFloat) -> (outline: UIBezierPath, coverts: UIBezierPath, band: UIBezierPath) {
            let span = 128 * (1 - 0.45 * fold)
            let chord = 46 * (1 - 0.3 * fold)
            let shoulder = CGPoint(x: cx + dir * 22, y: bodyY - 14)
            let t = CGAffineTransform(translationX: shoulder.x, y: shoulder.y).rotated(by: -angle * dir).scaledBy(x: dir, y: 1)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }
            let w = UIBezierPath()
            w.move(to: pt(0, -10))
            w.addQuadCurve(to: pt(span * 0.48, -chord * 0.28), controlPoint: pt(span * 0.22, -chord * 0.36))   // leading edge to the wrist
            w.addQuadCurve(to: pt(span, chord * 0.05), controlPoint: pt(span * 0.8, -chord * 0.3))              // to the tip
            // Trailing edge: four primary "fingers", then scalloped secondaries back to the body.
            let fingers = 4
            for i in 0..<fingers {
                let u = CGFloat(i + 1) / CGFloat(fingers)
                let tipX = span * (1 - 0.13 * u), tipY = chord * (0.18 + 0.3 * u)
                w.addQuadCurve(to: pt(tipX - span * 0.06, tipY - chord * 0.12), controlPoint: pt(tipX + span * 0.02, tipY + chord * 0.08))
            }
            for i in 0..<3 {
                let x0 = span * (0.42 - 0.13 * CGFloat(i))
                w.addQuadCurve(to: pt(x0 - span * 0.12, chord * 0.62), controlPoint: pt(x0 - span * 0.04, chord * 0.92))
            }
            w.addQuadCurve(to: pt(0, chord * 0.35), controlPoint: pt(span * 0.02, chord * 0.7))
            w.close()
            let cov = UIBezierPath()
            cov.move(to: pt(0, -10)); cov.addQuadCurve(to: pt(span * 0.5, -chord * 0.26), controlPoint: pt(span * 0.22, -chord * 0.36))
            cov.addQuadCurve(to: pt(span * 0.42, chord * 0.12), controlPoint: pt(span * 0.52, 0))
            cov.addQuadCurve(to: pt(0, chord * 0.25), controlPoint: pt(span * 0.2, chord * 0.3)); cov.close()
            let band = UIBezierPath()
            band.move(to: pt(span * 0.38, -chord * 0.3)); band.addQuadCurve(to: pt(span * 0.72, -chord * 0.22), controlPoint: pt(span * 0.55, -chord * 0.38))
            band.addQuadCurve(to: pt(span * 0.6, chord * 0.4), controlPoint: pt(span * 0.72, chord * 0.1))
            band.addQuadCurve(to: pt(span * 0.08, chord * 0.42), controlPoint: pt(span * 0.3, chord * 0.62)); band.close()
            return (w, cov, band)
        }
        let wings = [wing(-1), wing(1)]
        let body = UIBezierPath(ovalIn: CGRect(x: cx - 34, y: bodyY - 44, width: 68, height: 92))
        let head = UIBezierPath(ovalIn: CGRect(x: cx - 33, y: bodyY - 96, width: 66, height: 64))
        var feetPaths: [(UIBezierPath, UIColor)] = []
        if feet {
            for dx in [-14.0, 14.0] as [CGFloat] { feetPaths.append((UIBezierPath(ovalIn: CGRect(x: cx + dx - 9, y: bodyY + 36, width: 18, height: 16)), UIColor(white: 0.35, alpha: 1))) }
        }
        inked(ctx, parts + wings.map { ($0.outline, pal.flight) } + feetPaths + [(body, pal.body), (head, pal.head)], outline: outline)
        // Tail tips, wing colour bands (coverts → band → flight feathers), chest, face.
        for (p, _) in parts { clipped(ctx, p) { pal.tailTip.setFill(); let b = p.bounds; ctx.fill(CGRect(x: b.minX, y: b.maxY - b.height * 0.35, width: b.width, height: b.height)) } }
        for w in wings {
            clipped(ctx, w.outline) {
                pal.band.setFill(); ctx.addPath(w.band.cgPath); ctx.fillPath()
                pal.coverts.setFill(); ctx.addPath(w.coverts.cgPath); ctx.fillPath()
            }
        }
        clipped(ctx, body) {
            pal.chest.setFill(); ctx.fillEllipse(in: CGRect(x: cx - 24, y: bodyY - 30, width: 48, height: 70))
            pal.body.mixed(with: JunglePalette.outline, amount: 0.25).setFill(); ctx.fill(CGRect(x: cx - 40, y: bodyY + 30, width: 80, height: 30))
        }
        clipped(ctx, head) {
            UIColor.white.withAlphaComponent(0.25).setFill(); ctx.fillEllipse(in: CGRect(x: cx - 26, y: bodyY - 94, width: 30, height: 18))
        }
        // Bare white face patch with the players' eye style (white sclera, dark pupil).
        UIColor.white.setFill()
        for dx in [-15.0, 15.0] as [CGFloat] { ctx.fillEllipse(in: CGRect(x: cx + dx - 13, y: bodyY - 82, width: 26, height: 30)) }
        let eyeR: CGFloat = startled ? 9 : 8
        for dx in [-15.0, 15.0] as [CGFloat] {
            ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(2.5)
            UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: cx + dx - eyeR, y: bodyY - 76, width: eyeR * 2, height: eyeR * 2.2)); ctx.strokeEllipse(in: CGRect(x: cx + dx - eyeR, y: bodyY - 76, width: eyeR * 2, height: eyeR * 2.2))
            JunglePalette.outline.setFill()
            let pr: CGFloat = startled ? 3 : 4.5
            ctx.fillEllipse(in: CGRect(x: cx + dx - pr + (dx < 0 ? 1.5 : -1.5), y: bodyY - 70, width: pr * 2, height: pr * 2.4))
        }
        // Beak: ivory hooked upper mandible, dark lower (open when startled).
        let gape: CGFloat = startled ? 10 : 0
        let lower = UIBezierPath(); lower.move(to: CGPoint(x: cx - 11, y: bodyY - 50 + gape)); lower.addQuadCurve(to: CGPoint(x: cx + 11, y: bodyY - 50 + gape), controlPoint: CGPoint(x: cx, y: bodyY - 30 + gape)); lower.close()
        let upper = UIBezierPath()
        upper.move(to: CGPoint(x: cx - 15, y: bodyY - 60))
        upper.addQuadCurve(to: CGPoint(x: cx + 15, y: bodyY - 60), controlPoint: CGPoint(x: cx, y: bodyY - 70))
        upper.addQuadCurve(to: CGPoint(x: cx + 2, y: bodyY - 34), controlPoint: CGPoint(x: cx + 14, y: bodyY - 44))
        upper.addQuadCurve(to: CGPoint(x: cx - 15, y: bodyY - 60), controlPoint: CGPoint(x: cx - 14, y: bodyY - 46))
        upper.close()
        inked(ctx, [(lower, JunglePalette.outline.mixed(with: .white, amount: 0.15)), (upper, CreaturePalette.tooth)], outline: 2.5)
        if startled {
            // Ruffled crown feathers.
            pal.head.setFill(); ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(3)
            for dx in [-14.0, 0, 14.0] as [CGFloat] {
                let p = UIBezierPath(); p.move(to: CGPoint(x: cx + dx - 7, y: bodyY - 92)); p.addLine(to: CGPoint(x: cx + dx * 1.5, y: bodyY - 112)); p.addLine(to: CGPoint(x: cx + dx + 7, y: bodyY - 92)); p.close()
                ctx.addPath(p.cgPath); ctx.drawPath(using: .fillStroke)
            }
        }
    }

    private static func macawSet(_ pal: CreaturePalette.Macaw) -> (flap: [SKTexture], glide: SKTexture, tuck: SKTexture, flare: SKTexture, startled: SKTexture) {
        func make(_ s: MacawShape) -> SKTexture { drawnHi(macawCanvas, scale: 1.25) { ctx, _ in drawMacaw(ctx, pal, s) } }
        let flap = (0..<BirdPose.flapFrames).map { make(.flap((CGFloat($0) + 0.5) / CGFloat(BirdPose.flapFrames))) }
        return (flap, make(.glide), make(.tuck), make(.flare), make(.startled))
    }
    static let macaws = [macawSet(CreaturePalette.scarlet), macawSet(CreaturePalette.blueGold)]
    /// The body centre of the canvas (the sprite anchor), so wing beats never shift the bird's position.
    static let macawAnchor = CGPoint(x: 160.0 / 320.0, y: 1 - 124.0 / 270.0)

    static func macawTexture(_ pose: BirdPose, palette: Int) -> SKTexture {
        let set = macaws[palette % macaws.count]
        switch pose {
        case .flap: return set.flap[pose.frameIndex ?? 0]
        case .glide: return set.glide
        case .tuck: return set.tuck
        case .flare: return set.flare
        case .startled: return set.startled
        }
    }

    static var creatureTextures: [SKTexture] {
        var all: [SKTexture] = [crocUpper, crocLower, crocThroat, crocBody, crocTail, crocLeg, crocEye, crocPupil, crocLid, crocBrow,
                                crocGlint, crocFront, crocShadow, foamCollar, rippleRing] + splashCrown
        for set in macaws { all += set.flap + [set.glide, set.tuck, set.flare, set.startled] }
        return all
    }
}
