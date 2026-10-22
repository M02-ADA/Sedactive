import SpriteKit
import UIKit

/// Piranha palette (JUNGLE_ART_DIRECTION.md roles): a cool slate back that sits on the river, and the one warm note —
/// a coral-red belly — so the fish pops off the water and reads as "danger, but a cheeky one".
extension CreaturePalette {
    static let piranhaBack = UIColor(red: 0.40, green: 0.53, blue: 0.62, alpha: 1)
    static let piranhaShade = UIColor(red: 0.26, green: 0.37, blue: 0.47, alpha: 1)
    static let piranhaLight = UIColor(red: 0.70, green: 0.82, blue: 0.88, alpha: 1)
    static let piranhaBelly = UIColor(red: 0.96, green: 0.38, blue: 0.30, alpha: 1)
    static let piranhaFin = UIColor(red: 0.30, green: 0.42, blue: 0.52, alpha: 1)
}

/// Code-drawn piranha set: side view facing +x, layered so the tail and jaw move procedurally (like the croc rig).
/// Same ink outline weight on every part, flat cel shading, white sclera + dark pupil.
@MainActor
extension Art {
    static let piranhaOutline: CGFloat = 4.5

    private static func piranhaInked(_ ctx: CGContext, _ paths: [(UIBezierPath, UIColor)], outline: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.setStrokeColor(JunglePalette.outline.cgColor)
        ctx.setLineWidth(outline * 2)
        for (p, _) in paths { ctx.addPath(p.cgPath); ctx.strokePath() }
        for (p, c) in paths { c.setFill(); ctx.addPath(p.cgPath); ctx.fillPath() }
    }

    private static func piranhaClipped(_ ctx: CGContext, _ path: UIBezierPath, _ draw: () -> Void) {
        ctx.saveGState(); ctx.addPath(path.cgPath); ctx.clip(); draw(); ctx.restoreGState()
    }

    /// Body: tall, rounded disc with a blunt head at the right, dorsal and anal fins, the eye and the upper teeth.
    /// Tail joint at (34, 80); jaw hinge at (150, 98) (UIKit canvas coordinates).
    static let piranhaTailJoint = CGPoint(x: 34, y: 80)
    static let piranhaJawHinge = CGPoint(x: 150, y: 98)
    static let piranhaBody = drawnHi(CGSize(width: 230, height: 160), scale: 1.5) { ctx, _ in
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 30, y: 80))
        body.addCurve(to: CGPoint(x: 128, y: 22), controlPoint1: CGPoint(x: 44, y: 44), controlPoint2: CGPoint(x: 84, y: 20))
        body.addCurve(to: CGPoint(x: 208, y: 74), controlPoint1: CGPoint(x: 170, y: 24), controlPoint2: CGPoint(x: 204, y: 46))
        body.addCurve(to: CGPoint(x: 196, y: 100), controlPoint1: CGPoint(x: 210, y: 86), controlPoint2: CGPoint(x: 204, y: 96))
        body.addLine(to: CGPoint(x: 150, y: 100))
        body.addCurve(to: CGPoint(x: 30, y: 80), controlPoint1: CGPoint(x: 120, y: 142), controlPoint2: CGPoint(x: 52, y: 128))
        body.close()
        let dorsal = UIBezierPath()
        dorsal.move(to: CGPoint(x: 70, y: 36)); dorsal.addQuadCurve(to: CGPoint(x: 92, y: 4), controlPoint: CGPoint(x: 70, y: 12))
        dorsal.addQuadCurve(to: CGPoint(x: 116, y: 26), controlPoint: CGPoint(x: 108, y: 8)); dorsal.close()
        let anal = UIBezierPath()
        anal.move(to: CGPoint(x: 62, y: 112)); anal.addQuadCurve(to: CGPoint(x: 70, y: 146), controlPoint: CGPoint(x: 56, y: 134))
        anal.addQuadCurve(to: CGPoint(x: 100, y: 122), controlPoint: CGPoint(x: 90, y: 140)); anal.close()
        piranhaInked(ctx, [(dorsal, CreaturePalette.piranhaFin), (anal, CreaturePalette.piranhaFin), (body, CreaturePalette.piranhaBack)],
                     outline: piranhaOutline)
        piranhaClipped(ctx, body) {
            // Coral belly (the danger accent), shadow tone low on the flank, highlight along the back.
            CreaturePalette.piranhaBelly.setFill()
            let belly = UIBezierPath()
            belly.move(to: CGPoint(x: 20, y: 96)); belly.addQuadCurve(to: CGPoint(x: 160, y: 92), controlPoint: CGPoint(x: 90, y: 78))
            belly.addLine(to: CGPoint(x: 160, y: 160)); belly.addLine(to: CGPoint(x: 20, y: 160)); belly.close()
            ctx.addPath(belly.cgPath); ctx.fillPath()
            CreaturePalette.piranhaShade.setFill(); ctx.fill(CGRect(x: 0, y: 114, width: 230, height: 40))
            CreaturePalette.piranhaLight.setFill(); ctx.fillEllipse(in: CGRect(x: 74, y: 28, width: 96, height: 16))
            // A few soft speckles: low contrast, so detail stays at the face.
            CreaturePalette.piranhaLight.withAlphaComponent(0.45).setFill()
            for (x, y) in [(70.0, 58.0), (92, 66), (60, 74), (114, 56), (84, 48)] as [(CGFloat, CGFloat)] {
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 9, height: 9))
            }
        }
        // Gill line.
        ctx.setStrokeColor(CreaturePalette.piranhaShade.cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 140, y: 40)); ctx.addQuadCurve(to: CGPoint(x: 138, y: 96), control: CGPoint(x: 126, y: 68)); ctx.strokePath()
        // Pectoral fin.
        let pec = UIBezierPath()
        pec.move(to: CGPoint(x: 128, y: 82)); pec.addQuadCurve(to: CGPoint(x: 100, y: 100), controlPoint: CGPoint(x: 108, y: 80))
        pec.addQuadCurve(to: CGPoint(x: 128, y: 82), controlPoint: CGPoint(x: 120, y: 98)); pec.close()
        piranhaInked(ctx, [(pec, CreaturePalette.piranhaFin)], outline: piranhaOutline - 1.5)
        // Eye: big white sclera and a dark pupil looking forward-down (at the players' feet), heavy brow.
        let eye = CGRect(x: 158, y: 40, width: 34, height: 34)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(piranhaOutline)
        UIColor.white.setFill(); ctx.fillEllipse(in: eye); ctx.strokeEllipse(in: eye)
        JunglePalette.outline.setFill(); ctx.fillEllipse(in: CGRect(x: 174, y: 52, width: 14, height: 16))
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: 176, y: 54, width: 5, height: 5))
        let brow = UIBezierPath()
        brow.move(to: CGPoint(x: 152, y: 36)); brow.addQuadCurve(to: CGPoint(x: 198, y: 46), controlPoint: CGPoint(x: 178, y: 26))
        brow.addLine(to: CGPoint(x: 196, y: 52)); brow.addQuadCurve(to: CGPoint(x: 154, y: 44), controlPoint: CGPoint(x: 176, y: 36)); brow.close()
        piranhaInked(ctx, [(brow, CreaturePalette.piranhaShade)], outline: 2)
        // Upper teeth: three small triangles along the mouth line (the underbite carries the big ones).
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(2.5); ctx.setLineJoin(.round)
        for x in [166.0, 178, 190] as [CGFloat] {
            let t = UIBezierPath(); t.move(to: CGPoint(x: x - 5, y: 99)); t.addLine(to: CGPoint(x: x, y: 108)); t.addLine(to: CGPoint(x: x + 5, y: 99)); t.close()
            CreaturePalette.tooth.setFill(); ctx.addPath(t.cgPath); ctx.drawPath(using: .fillStroke)
        }
    }

    /// Lower jaw: the underbite, jutting past the upper lip, with four big teeth pointing up. Hinge at (8, 10).
    static let piranhaJawPivot = CGPoint(x: 8, y: 10)
    static let piranhaJaw = drawnHi(CGSize(width: 80, height: 46), scale: 1.5) { ctx, _ in
        let jaw = UIBezierPath()
        jaw.move(to: CGPoint(x: 6, y: 8)); jaw.addLine(to: CGPoint(x: 66, y: 10))
        jaw.addCurve(to: CGPoint(x: 60, y: 32), controlPoint1: CGPoint(x: 76, y: 12), controlPoint2: CGPoint(x: 74, y: 28))
        jaw.addCurve(to: CGPoint(x: 6, y: 8), controlPoint1: CGPoint(x: 40, y: 40), controlPoint2: CGPoint(x: 10, y: 30))
        jaw.close()
        piranhaInked(ctx, [(jaw, CreaturePalette.piranhaBelly)], outline: piranhaOutline)
        piranhaClipped(ctx, jaw) {
            CreaturePalette.piranhaBelly.mixed(with: JunglePalette.outline, amount: 0.25).setFill()
            ctx.fill(CGRect(x: 0, y: 26, width: 80, height: 20))
        }
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(2.5); ctx.setLineJoin(.round)
        for x in [22.0, 36, 50, 62] as [CGFloat] {
            let t = UIBezierPath(); t.move(to: CGPoint(x: x - 6, y: 11)); t.addLine(to: CGPoint(x: x, y: -1)); t.addLine(to: CGPoint(x: x + 6, y: 11)); t.close()
            CreaturePalette.tooth.setFill(); ctx.addPath(t.cgPath); ctx.drawPath(using: .fillStroke)
        }
    }

    /// Tail fan, base at the right (pivot (70, 46)): two lobes with a notch, beaten procedurally.
    static let piranhaTailPivot = CGPoint(x: 70, y: 46)
    static let piranhaTail = drawnHi(CGSize(width: 76, height: 92), scale: 1.25) { ctx, _ in
        let t = UIBezierPath()
        t.move(to: CGPoint(x: 72, y: 38))
        t.addCurve(to: CGPoint(x: 10, y: 6), controlPoint1: CGPoint(x: 50, y: 30), controlPoint2: CGPoint(x: 24, y: 4))
        t.addQuadCurve(to: CGPoint(x: 30, y: 46), controlPoint: CGPoint(x: 6, y: 30))
        t.addQuadCurve(to: CGPoint(x: 10, y: 86), controlPoint: CGPoint(x: 6, y: 62))
        t.addCurve(to: CGPoint(x: 72, y: 54), controlPoint1: CGPoint(x: 24, y: 88), controlPoint2: CGPoint(x: 50, y: 62))
        t.close()
        piranhaInked(ctx, [(t, CreaturePalette.piranhaFin)], outline: piranhaOutline - 1)
        piranhaClipped(ctx, t) {
            CreaturePalette.piranhaLight.withAlphaComponent(0.5).setFill()
            ctx.fillEllipse(in: CGRect(x: 18, y: 12, width: 30, height: 12))
            CreaturePalette.piranhaShade.setFill(); ctx.fill(CGRect(x: 0, y: 64, width: 76, height: 30))
        }
    }

    /// A dorsal fin cutting the surface (the warning): inked, so it reads as a creature, never as water.
    static let piranhaFinTex = drawnHi(CGSize(width: 70, height: 56), scale: 1.25) { ctx, _ in
        let f = UIBezierPath()
        f.move(to: CGPoint(x: 6, y: 52)); f.addQuadCurve(to: CGPoint(x: 40, y: 6), controlPoint: CGPoint(x: 18, y: 16))
        f.addQuadCurve(to: CGPoint(x: 64, y: 52), controlPoint: CGPoint(x: 52, y: 30)); f.close()
        piranhaInked(ctx, [(f, CreaturePalette.piranhaBack)], outline: piranhaOutline - 1)
        piranhaClipped(ctx, f) {
            CreaturePalette.piranhaLight.setFill(); ctx.fillEllipse(in: CGRect(x: 26, y: 12, width: 14, height: 22))
            CreaturePalette.piranhaShade.setFill(); ctx.fill(CGRect(x: 0, y: 42, width: 70, height: 14))
        }
    }

    /// Warning badge over the water on the attack side: a yellow roundel with a leaping piranha and an up arrow.
    static let piranhaSign = drawnHi(CGSize(width: 160, height: 160), scale: 1.25) { ctx, size in
        let r = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 0, color: Palette.deepNavy.withAlphaComponent(0.55).cgColor)
        Palette.yellow.setFill(); ctx.fillEllipse(in: r)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(9); ctx.strokeEllipse(in: r.insetBy(dx: 2, dy: 2))
        // Waves at the bottom.
        ctx.setLineWidth(7); ctx.setLineCap(.round)
        for i in 0..<2 {
            let y = 112 + CGFloat(i) * 14
            ctx.move(to: CGPoint(x: 38, y: y))
            for k in 0..<4 { ctx.addQuadCurve(to: CGPoint(x: 38 + CGFloat(k + 1) * 21, y: y), control: CGPoint(x: 38 + CGFloat(k) * 21 + 10.5, y: y - 8)) }
            ctx.strokePath()
        }
        // Leaping fish silhouette (ink) on an arc, with a white eye and teeth.
        ctx.saveGState()
        ctx.translateBy(x: 78, y: 70); ctx.rotate(by: -0.45)
        let fish = UIBezierPath()
        fish.move(to: CGPoint(x: -38, y: 0)); fish.addCurve(to: CGPoint(x: 30, y: -2), controlPoint1: CGPoint(x: -20, y: -30), controlPoint2: CGPoint(x: 18, y: -26))
        fish.addLine(to: CGPoint(x: 34, y: 8)); fish.addCurve(to: CGPoint(x: -38, y: 0), controlPoint1: CGPoint(x: 10, y: 28), controlPoint2: CGPoint(x: -22, y: 22))
        fish.move(to: CGPoint(x: -36, y: 0)); fish.addLine(to: CGPoint(x: -54, y: -16)); fish.addLine(to: CGPoint(x: -50, y: 0)); fish.addLine(to: CGPoint(x: -54, y: 16)); fish.close()
        JunglePalette.outline.setFill(); ctx.addPath(fish.cgPath); ctx.fillPath()
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: 12, y: -14, width: 10, height: 10))
        for x in [18.0, 26] as [CGFloat] {
            let t = UIBezierPath(); t.move(to: CGPoint(x: x - 3, y: 4)); t.addLine(to: CGPoint(x: x, y: -3)); t.addLine(to: CGPoint(x: x + 3, y: 4)); t.close()
            ctx.addPath(t.cgPath); ctx.fillPath()
        }
        ctx.restoreGState()
        // Up arrow ("jump") above the fish.
        let a = UIBezierPath()
        a.move(to: CGPoint(x: 116, y: 44)); a.addLine(to: CGPoint(x: 128, y: 26)); a.addLine(to: CGPoint(x: 140, y: 44)); a.close()
        JunglePalette.outline.setFill(); ctx.addPath(a.cgPath); ctx.fillPath()
        ctx.setStrokeColor(JunglePalette.outline.cgColor); ctx.setLineWidth(7); ctx.move(to: CGPoint(x: 128, y: 40)); ctx.addLine(to: CGPoint(x: 128, y: 62)); ctx.strokePath()
    }

    /// One dash of the leap-path guide drawn across the deck (tinted at runtime).
    static let piranhaDash = drawnHi(CGSize(width: 44, height: 18), scale: 1.0) { ctx, size in
        UIColor.white.setFill()
        ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), cornerRadius: 7).cgPath); ctx.fillPath()
    }

    static var piranhaTextures: [SKTexture] { [piranhaBody, piranhaJaw, piranhaTail, piranhaFinTex, piranhaSign, piranhaDash] }
}
