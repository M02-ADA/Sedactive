import SpriteKit
import UIKit

/// Moonbound palette: a white-and-orange rocket, the players' own coral/teal on their engines, sky blues that turn
/// to violet-black, warm flame golds. Same ink outline and flat cel shading as the rest of Sedactive.
enum MoonPalette {
    static let hull = UIColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 1)
    static let hullShade = UIColor(red: 0.72, green: 0.76, blue: 0.90, alpha: 1)
    static let orange = UIColor(red: 1.0, green: 0.52, blue: 0.22, alpha: 1)
    static let metal = UIColor(red: 0.36, green: 0.40, blue: 0.56, alpha: 1)
    static let flameCore = UIColor(red: 1.0, green: 0.98, blue: 0.86, alpha: 1)
    static let flame = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
    static let flameEdge = UIColor(red: 1.0, green: 0.42, blue: 0.20, alpha: 1)
    static let cloud = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    static let cloudShade = UIColor(red: 0.80, green: 0.83, blue: 0.97, alpha: 1)
    static let moon = UIColor(red: 0.86, green: 0.86, blue: 0.92, alpha: 1)
    static let moonShade = UIColor(red: 0.62, green: 0.62, blue: 0.74, alpha: 1)
    static let ink = UIColor(red: 0.03, green: 0.035, blue: 0.12, alpha: 1)
}

@MainActor
extension Art {
    private static func mInk(_ ctx: CGContext, _ path: UIBezierPath, fill: UIColor, line: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        fill.setFill(); ctx.addPath(path.cgPath); ctx.fillPath()
        guard line > 0 else { return }
        ctx.setStrokeColor(MoonPalette.ink.cgColor); ctx.setLineWidth(line); ctx.addPath(path.cgPath); ctx.strokePath()
    }

    // MARK: - Race rockets (one per player). 300 pt = 0.9 world units wide; the deck top is at the texture's top.

    /// A chunky race pod: the player stands on the round deck at the top (seen from slightly above, an ellipse),
    /// a cel-shaded hull below it with portholes, chevrons and fins, and three nozzles at the bottom.
    static let racePod = drawnHi(CGSize(width: 300, height: 300), scale: 1.0) { ctx, size in
        let w = size.width
        let deckH: CGFloat = 70
        // Fins (behind the hull).
        for side in [-1.0, 1.0] as [CGFloat] {
            let fin = UIBezierPath()
            let x0 = w / 2 + side * 92
            fin.move(to: CGPoint(x: x0, y: 150)); fin.addQuadCurve(to: CGPoint(x: x0 + side * 52, y: 268), controlPoint: CGPoint(x: x0 + side * 58, y: 196))
            fin.addLine(to: CGPoint(x: x0 + side * 34, y: 274)); fin.addLine(to: CGPoint(x: x0, y: 246)); fin.close()
            mInk(ctx, fin, fill: MoonPalette.orange, line: 6)
        }
        // Hull: a barrel that tapers into the nozzle skirt.
        let hull = UIBezierPath()
        hull.move(to: CGPoint(x: w / 2 - 112, y: deckH / 2))
        hull.addLine(to: CGPoint(x: w / 2 + 112, y: deckH / 2))
        hull.addCurve(to: CGPoint(x: w / 2 + 78, y: 252), controlPoint1: CGPoint(x: w / 2 + 124, y: 140), controlPoint2: CGPoint(x: w / 2 + 104, y: 222))
        hull.addLine(to: CGPoint(x: w / 2 - 78, y: 252))
        hull.addCurve(to: CGPoint(x: w / 2 - 112, y: deckH / 2), controlPoint1: CGPoint(x: w / 2 - 104, y: 222), controlPoint2: CGPoint(x: w / 2 - 124, y: 140))
        hull.close()
        mInk(ctx, hull, fill: MoonPalette.hull, line: 7)
        ctx.saveGState(); ctx.addPath(hull.cgPath); ctx.clip()
        // Cylinder shading: a soft core light left of centre, a cool shadow band on the right.
        MoonPalette.hullShade.setFill(); ctx.fill(CGRect(x: w / 2 + 52, y: 0, width: 80, height: size.height))
        UIColor(red: 0.60, green: 0.64, blue: 0.82, alpha: 1).setFill(); ctx.fill(CGRect(x: w / 2 + 92, y: 0, width: 40, height: size.height))
        UIColor.white.setFill(); ctx.fill(CGRect(x: w / 2 - 70, y: 0, width: 16, height: size.height))
        // Chevrons.
        for k in 0..<3 {
            let y = 196 + CGFloat(k) * 16
            let c = UIBezierPath(); c.move(to: CGPoint(x: w / 2 - 60, y: y)); c.addLine(to: CGPoint(x: w / 2, y: y + 12)); c.addLine(to: CGPoint(x: w / 2 + 60, y: y))
            ctx.setStrokeColor(MoonPalette.orange.cgColor); ctx.setLineWidth(7); ctx.addPath(c.cgPath); ctx.strokePath()
        }
        ctx.restoreGState()
        // Portholes.
        for x in [-46.0, 0, 46] as [CGFloat] {
            mInk(ctx, UIBezierPath(ovalIn: CGRect(x: w / 2 + x - 15, y: 120, width: 30, height: 30)), fill: UIColor(red: 0.35, green: 0.78, blue: 1, alpha: 1), line: 5)
            UIColor.white.withAlphaComponent(0.8).setFill(); ctx.fillEllipse(in: CGRect(x: w / 2 + x - 8, y: 125, width: 9, height: 7))
        }
        // Nozzle skirt: three bells.
        for (x, bw) in [(-58.0, 44.0), (0, 62), (58, 44)] as [(CGFloat, CGFloat)] {
            let bell = UIBezierPath()
            bell.move(to: CGPoint(x: w / 2 + x - bw * 0.32, y: 248)); bell.addLine(to: CGPoint(x: w / 2 + x + bw * 0.32, y: 248))
            bell.addLine(to: CGPoint(x: w / 2 + x + bw / 2, y: 292)); bell.addLine(to: CGPoint(x: w / 2 + x - bw / 2, y: 292)); bell.close()
            mInk(ctx, bell, fill: MoonPalette.metal, line: 5)
        }
        // Deck: the round platform the player stands on (top face as an ellipse).
        let deck = UIBezierPath(ovalIn: CGRect(x: w / 2 - 128, y: 2, width: 256, height: deckH))
        mInk(ctx, deck, fill: UIColor(red: 0.24, green: 0.27, blue: 0.44, alpha: 1), line: 7)
        UIColor(red: 0.32, green: 0.36, blue: 0.56, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: w / 2 - 100, y: 12, width: 200, height: deckH - 22))
    }

    /// The player-coloured band and deck light ring (white: tinted at runtime). Same frame as `racePod`.
    static let racePodBand = drawnHi(CGSize(width: 300, height: 300), scale: 1.0) { ctx, size in
        let w = size.width
        ctx.saveGState()
        let hull = UIBezierPath(rect: CGRect(x: w / 2 - 118, y: 72, width: 236, height: 30))
        UIColor.white.setFill(); ctx.addPath(hull.cgPath); ctx.fillPath()
        ctx.restoreGState()
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(6)
        ctx.strokeEllipse(in: CGRect(x: w / 2 - 112, y: 9, width: 224, height: 56))
    }

    /// The front half of the deck's rim, drawn IN FRONT of the player's feet: the cutout's ankles sink behind it,
    /// so the player reads as standing in the deck (and small foot-tracking jitter is hidden).
    static let raceDeckLip = drawnHi(CGSize(width: 300, height: 80), scale: 1.0) { ctx, size in
        let w = size.width
        let lip = UIBezierPath()
        lip.move(to: CGPoint(x: w / 2 - 128, y: 37))
        lip.addCurve(to: CGPoint(x: w / 2 + 128, y: 37), controlPoint1: CGPoint(x: w / 2 - 128, y: 84), controlPoint2: CGPoint(x: w / 2 + 128, y: 84))
        lip.addLine(to: CGPoint(x: w / 2 + 128, y: 52))
        lip.addCurve(to: CGPoint(x: w / 2 - 128, y: 52), controlPoint1: CGPoint(x: w / 2 + 120, y: 100), controlPoint2: CGPoint(x: w / 2 - 120, y: 100))
        lip.close()
        mInk(ctx, lip, fill: MoonPalette.hull, line: 6)
        ctx.setStrokeColor(MoonPalette.orange.cgColor); ctx.setLineWidth(6)
        let stripe = UIBezierPath(); stripe.move(to: CGPoint(x: w / 2 - 110, y: 52))
        stripe.addCurve(to: CGPoint(x: w / 2 + 110, y: 52), controlPoint1: CGPoint(x: w / 2 - 100, y: 82), controlPoint2: CGPoint(x: w / 2 + 100, y: 82))
        ctx.addPath(stripe.cgPath); ctx.strokePath()
    }

    /// Launch clamp: a heavy arm from the tower that holds a rocket until lift-off.
    static let clampArm = drawnHi(CGSize(width: 260, height: 50), scale: 1.0) { ctx, size in
        let arm = UIBezierPath(roundedRect: CGRect(x: 4, y: 12, width: size.width - 40, height: 26), cornerRadius: 8)
        mInk(ctx, arm, fill: UIColor(red: 0.85, green: 0.32, blue: 0.22, alpha: 1), line: 5)
        let claw = UIBezierPath(roundedRect: CGRect(x: size.width - 46, y: 4, width: 40, height: 42), cornerRadius: 10)
        mInk(ctx, claw, fill: MoonPalette.metal, line: 5)
        UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).setFill()
        for x in stride(from: CGFloat(20), to: size.width - 60, by: 34) { ctx.fill(CGRect(x: x, y: 20, width: 14, height: 10)) }
    }

    /// The leader's crown (hops between lanes on an overtake).
    static let crown = drawnHi(CGSize(width: 120, height: 90), scale: 1.25) { ctx, _ in
        let c = UIBezierPath()
        c.move(to: CGPoint(x: 10, y: 80)); c.addLine(to: CGPoint(x: 6, y: 22)); c.addLine(to: CGPoint(x: 36, y: 48)); c.addLine(to: CGPoint(x: 60, y: 8))
        c.addLine(to: CGPoint(x: 84, y: 48)); c.addLine(to: CGPoint(x: 114, y: 22)); c.addLine(to: CGPoint(x: 110, y: 80)); c.close()
        mInk(ctx, c, fill: UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1), line: 6)
        UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).setFill(); ctx.fill(CGRect(x: 16, y: 62, width: 88, height: 8))
        for x in [6.0, 60, 114] as [CGFloat] { mInk(ctx, UIBezierPath(ovalIn: CGRect(x: x - 8, y: x == 60 ? 2 : 14, width: 16, height: 16)), fill: UIColor(red: 1, green: 0.4, blue: 0.45, alpha: 1), line: 4) }
    }

    /// The Moon gate: a glowing checkered ring (the finish line), tinted at runtime.
    static let moonGate = drawnHi(CGSize(width: 600, height: 180), scale: 1.0) { ctx, size in
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        ctx.setLineWidth(26)
        for k in 0..<24 {
            let a0 = CGFloat(k) / 24 * 2 * .pi, a1 = CGFloat(k + 1) / 24 * 2 * .pi
            let path = UIBezierPath()
            for step in 0...6 {
                let a = a0 + (a1 - a0) * CGFloat(step) / 6
                let pt = CGPoint(x: outer.midX + cos(a) * (outer.width / 2 - 14), y: outer.midY + sin(a) * (outer.height / 2 - 14))
                if step == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.setStrokeColor((k % 2 == 0 ? UIColor.white : UIColor(white: 0.12, alpha: 1)).cgColor)
            ctx.addPath(path.cgPath); ctx.strokePath()
        }
        ctx.setStrokeColor(MoonPalette.ink.cgColor); ctx.setLineWidth(4)
        ctx.strokeEllipse(in: outer.insetBy(dx: 1, dy: 1)); ctx.strokeEllipse(in: outer.insetBy(dx: 27, dy: 27))
    }

    /// Sun with soft rays (revealed above the cloud deck).
    static let sunFlare = drawnHi(CGSize(width: 320, height: 320), scale: 1.0) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for k in 0..<12 {
            let a = CGFloat(k) / 12 * 2 * .pi
            let ray = UIBezierPath()
            ray.move(to: c)
            ray.addLine(to: CGPoint(x: c.x + cos(a - 0.08) * 160, y: c.y + sin(a - 0.08) * 160))
            ray.addLine(to: CGPoint(x: c.x + cos(a + 0.08) * 160, y: c.y + sin(a + 0.08) * 160)); ray.close()
            UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.18).setFill(); ctx.addPath(ray.cgPath); ctx.fillPath()
        }
        let colors = [UIColor(red: 1, green: 1, blue: 0.92, alpha: 1).cgColor, UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 0.6).cgColor, UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 120, options: [])
    }

    /// Engine flame: white-hot core, gold body, orange edge; anchored at its top (the nozzle). Drawn additive.
    static let flame = drawnHi(CGSize(width: 128, height: 420), scale: 1.0) { ctx, size in
        func plume(_ width: CGFloat, _ length: CGFloat, _ color: UIColor) {
            let p = UIBezierPath()
            let cx = size.width / 2
            p.move(to: CGPoint(x: cx - width / 2, y: 0))
            p.addCurve(to: CGPoint(x: cx, y: length), controlPoint1: CGPoint(x: cx - width * 0.62, y: length * 0.35), controlPoint2: CGPoint(x: cx - width * 0.12, y: length * 0.8))
            p.addCurve(to: CGPoint(x: cx + width / 2, y: 0), controlPoint1: CGPoint(x: cx + width * 0.12, y: length * 0.8), controlPoint2: CGPoint(x: cx + width * 0.62, y: length * 0.35))
            p.close()
            color.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
        }
        plume(120, size.height, MoonPalette.flameEdge.withAlphaComponent(0.55))
        plume(88, size.height * 0.78, MoonPalette.flame.withAlphaComponent(0.85))
        plume(50, size.height * 0.5, MoonPalette.flameCore)
    }

    /// A soft smoke/exhaust puff (cel-shaded, with a lilac underside).
    static let smokePuff = drawnHi(CGSize(width: 160, height: 140), scale: 1.0) { ctx, size in
        let blobs: [CGRect] = [CGRect(x: 10, y: 40, width: 80, height: 80), CGRect(x: 50, y: 14, width: 90, height: 90), CGRect(x: 70, y: 50, width: 80, height: 76)]
        MoonPalette.cloudShade.setFill()
        for b in blobs { ctx.fillEllipse(in: b.offsetBy(dx: 0, dy: 8)) }
        MoonPalette.cloud.setFill()
        for b in blobs { ctx.fillEllipse(in: b.insetBy(dx: 4, dy: 4).offsetBy(dx: -2, dy: -4)) }
    }

    /// Cartoon cumulus: domed top, flat shaded base, ink outline.
    static let cloudPuff = drawnHi(CGSize(width: 420, height: 200), scale: 1.0) { ctx, size in
        let shape = UIBezierPath()
        shape.move(to: CGPoint(x: 30, y: 170))
        shape.addCurve(to: CGPoint(x: 90, y: 100), controlPoint1: CGPoint(x: 0, y: 160), controlPoint2: CGPoint(x: 20, y: 96))
        shape.addCurve(to: CGPoint(x: 200, y: 40), controlPoint1: CGPoint(x: 100, y: 40), controlPoint2: CGPoint(x: 160, y: 10))
        shape.addCurve(to: CGPoint(x: 320, y: 80), controlPoint1: CGPoint(x: 250, y: 6), controlPoint2: CGPoint(x: 310, y: 30))
        shape.addCurve(to: CGPoint(x: 390, y: 170), controlPoint1: CGPoint(x: 380, y: 80), controlPoint2: CGPoint(x: 420, y: 150))
        shape.close()
        mInk(ctx, shape, fill: MoonPalette.cloud, line: 5)
        ctx.saveGState(); ctx.addPath(shape.cgPath); ctx.clip()
        MoonPalette.cloudShade.setFill()
        ctx.fillEllipse(in: CGRect(x: 40, y: 128, width: 340, height: 90))
        ctx.restoreGState()
    }

    /// Wispy high cloud (flat streak).
    static let skyWisp = drawnHi(CGSize(width: 420, height: 90), scale: 1.0) { ctx, size in
        MoonPalette.cloud.withAlphaComponent(0.85).setFill()
        ctx.fillEllipse(in: CGRect(x: 10, y: 30, width: 260, height: 40))
        ctx.fillEllipse(in: CGRect(x: 150, y: 20, width: 260, height: 44))
        MoonPalette.cloudShade.withAlphaComponent(0.8).setFill()
        ctx.fillEllipse(in: CGRect(x: 60, y: 54, width: 300, height: 18))
    }

    // MARK: - Launch site

    /// The launch gantry: an orange lattice tower with a service arm (1.2 × 14 units at 40 pt per unit).
    static let gantry = drawnHi(CGSize(width: 120, height: 560), scale: 1.0) { ctx, size in
        let w: CGFloat = 70
        let tower = UIBezierPath(rect: CGRect(x: 10, y: 20, width: w, height: size.height - 20))
        mInk(ctx, tower, fill: UIColor(red: 0.85, green: 0.32, blue: 0.20, alpha: 0.18), line: 0)
        ctx.setStrokeColor(UIColor(red: 0.90, green: 0.34, blue: 0.22, alpha: 1).cgColor); ctx.setLineWidth(6)
        ctx.stroke(CGRect(x: 10, y: 20, width: w, height: size.height - 20))
        ctx.setLineWidth(4)
        for y in stride(from: CGFloat(20), to: size.height, by: 40) {
            ctx.move(to: CGPoint(x: 10, y: y)); ctx.addLine(to: CGPoint(x: 10 + w, y: y + 40))
            ctx.move(to: CGPoint(x: 10 + w, y: y)); ctx.addLine(to: CGPoint(x: 10, y: y + 40))
            ctx.move(to: CGPoint(x: 10, y: y)); ctx.addLine(to: CGPoint(x: 10 + w, y: y))
        }
        ctx.strokePath()
        // Service arm toward the rocket, and a beacon.
        mInk(ctx, UIBezierPath(rect: CGRect(x: 80, y: 120, width: 40, height: 14)), fill: MoonPalette.metal, line: 3)
        mInk(ctx, UIBezierPath(ovalIn: CGRect(x: 32, y: 2, width: 26, height: 22)), fill: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), line: 3)
    }

    /// A floodlight mast for the launch site.
    static let floodMast = drawnHi(CGSize(width: 70, height: 360), scale: 1.0) { ctx, size in
        mInk(ctx, UIBezierPath(rect: CGRect(x: 31, y: 40, width: 8, height: size.height - 40)), fill: MoonPalette.metal, line: 3)
        let head = UIBezierPath(roundedRect: CGRect(x: 6, y: 8, width: 58, height: 34), cornerRadius: 6)
        mInk(ctx, head, fill: MoonPalette.metal, line: 3)
        UIColor(red: 1, green: 0.97, blue: 0.8, alpha: 1).setFill()
        for x in [12.0, 28.0, 44.0] as [CGFloat] { ctx.fillEllipse(in: CGRect(x: x, y: 14, width: 14, height: 14)) }
    }

    /// Distant rolling hills and mountains (one strip; tinted by haze at runtime).
    static let hills = drawnHi(CGSize(width: 1024, height: 200), scale: 1.0) { ctx, size in
        let back = UIBezierPath()
        back.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        var i = 0
        while x <= size.width {
            let peak: CGFloat = [70, 20, 90, 40, 10, 60, 30, 80][i % 8]
            back.addQuadCurve(to: CGPoint(x: x + 128, y: peak + 20), controlPoint: CGPoint(x: x + 64, y: peak - 20))
            x += 128; i += 1
        }
        back.addLine(to: CGPoint(x: size.width, y: size.height)); back.close()
        UIColor(red: 0.56, green: 0.66, blue: 0.92, alpha: 1).setFill(); ctx.addPath(back.cgPath); ctx.fillPath()
        let front = UIBezierPath()
        front.move(to: CGPoint(x: 0, y: size.height))
        front.addLine(to: CGPoint(x: 0, y: 130))
        front.addCurve(to: CGPoint(x: size.width, y: 120), controlPoint1: CGPoint(x: 300, y: 70), controlPoint2: CGPoint(x: 700, y: 170))
        front.addLine(to: CGPoint(x: size.width, y: size.height)); front.close()
        UIColor(red: 0.40, green: 0.62, blue: 0.62, alpha: 1).setFill(); ctx.addPath(front.cgPath); ctx.fillPath()
    }

    // MARK: - Things in the sky and in orbit

    static let airliner = drawnHi(CGSize(width: 220, height: 80), scale: 1.0) { ctx, _ in
        let body = UIBezierPath(roundedRect: CGRect(x: 10, y: 34, width: 190, height: 22), cornerRadius: 11)
        mInk(ctx, body, fill: MoonPalette.hull, line: 4)
        let wing = UIBezierPath(); wing.move(to: CGPoint(x: 90, y: 46)); wing.addLine(to: CGPoint(x: 130, y: 46)); wing.addLine(to: CGPoint(x: 96, y: 76)); wing.addLine(to: CGPoint(x: 74, y: 76)); wing.close()
        mInk(ctx, wing, fill: MoonPalette.hullShade, line: 4)
        let tail = UIBezierPath(); tail.move(to: CGPoint(x: 14, y: 40)); tail.addLine(to: CGPoint(x: 4, y: 8)); tail.addLine(to: CGPoint(x: 30, y: 8)); tail.addLine(to: CGPoint(x: 44, y: 38)); tail.close()
        mInk(ctx, tail, fill: MoonPalette.orange, line: 4)
        UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1).setFill()
        for x in stride(from: CGFloat(60), to: 180, by: 14) { ctx.fillEllipse(in: CGRect(x: x, y: 40, width: 7, height: 7)) }
    }

    static let hotAirBalloon = drawnHi(CGSize(width: 140, height: 200), scale: 1.0) { ctx, _ in
        let env = UIBezierPath()
        env.move(to: CGPoint(x: 50, y: 140)); env.addCurve(to: CGPoint(x: 70, y: 6), controlPoint1: CGPoint(x: 0, y: 110), controlPoint2: CGPoint(x: 0, y: 6))
        env.addCurve(to: CGPoint(x: 90, y: 140), controlPoint1: CGPoint(x: 140, y: 6), controlPoint2: CGPoint(x: 140, y: 110)); env.close()
        mInk(ctx, env, fill: UIColor(red: 1, green: 0.42, blue: 0.48, alpha: 1), line: 5)
        ctx.saveGState(); ctx.addPath(env.cgPath); ctx.clip()
        UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).setFill()
        ctx.fill(CGRect(x: 52, y: 0, width: 36, height: 150))
        ctx.restoreGState()
        ctx.setStrokeColor(MoonPalette.ink.cgColor); ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: 54, y: 140)); ctx.addLine(to: CGPoint(x: 58, y: 168)); ctx.move(to: CGPoint(x: 86, y: 140)); ctx.addLine(to: CGPoint(x: 82, y: 168)); ctx.strokePath()
        mInk(ctx, UIBezierPath(roundedRect: CGRect(x: 54, y: 166, width: 32, height: 24), cornerRadius: 4), fill: UIColor(red: 0.6, green: 0.4, blue: 0.25, alpha: 1), line: 4)
    }

    static let weatherBalloon = drawnHi(CGSize(width: 90, height: 170), scale: 1.0) { ctx, _ in
        mInk(ctx, UIBezierPath(ovalIn: CGRect(x: 8, y: 6, width: 74, height: 86)), fill: UIColor(red: 0.96, green: 0.96, blue: 1, alpha: 1), line: 4)
        ctx.setStrokeColor(MoonPalette.ink.cgColor); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 45, y: 92)); ctx.addLine(to: CGPoint(x: 45, y: 140)); ctx.strokePath()
        mInk(ctx, UIBezierPath(rect: CGRect(x: 32, y: 140, width: 26, height: 22)), fill: MoonPalette.orange, line: 3)
    }

    static let satellite = drawnHi(CGSize(width: 260, height: 110), scale: 1.0) { ctx, _ in
        for x in [6.0, 164.0] as [CGFloat] {
            let panel = UIBezierPath(rect: CGRect(x: x, y: 30, width: 90, height: 50))
            mInk(ctx, panel, fill: UIColor(red: 0.20, green: 0.36, blue: 0.82, alpha: 1), line: 4)
            ctx.setStrokeColor(UIColor(red: 0.5, green: 0.7, blue: 1, alpha: 1).cgColor); ctx.setLineWidth(2)
            for k in 1..<4 { ctx.move(to: CGPoint(x: x + CGFloat(k) * 22.5, y: 30)); ctx.addLine(to: CGPoint(x: x + CGFloat(k) * 22.5, y: 80)) }
            ctx.strokePath()
        }
        mInk(ctx, UIBezierPath(rect: CGRect(x: 96, y: 52, width: 68, height: 6)), fill: MoonPalette.metal, line: 0)
        mInk(ctx, UIBezierPath(roundedRect: CGRect(x: 106, y: 26, width: 48, height: 58), cornerRadius: 8), fill: UIColor(red: 1, green: 0.82, blue: 0.35, alpha: 1), line: 4)
        mInk(ctx, UIBezierPath(ovalIn: CGRect(x: 116, y: 2, width: 28, height: 22)), fill: MoonPalette.hull, line: 3)
    }

    static let spaceStation = drawnHi(CGSize(width: 420, height: 180), scale: 1.0) { ctx, _ in
        mInk(ctx, UIBezierPath(rect: CGRect(x: 20, y: 84, width: 380, height: 12)), fill: MoonPalette.metal, line: 3)
        for x in [20.0, 110.0, 250.0, 340.0] as [CGFloat] {
            let panel = UIBezierPath(rect: CGRect(x: x, y: 10, width: 60, height: 160))
            mInk(ctx, panel, fill: UIColor(red: 0.85, green: 0.62, blue: 0.20, alpha: 1), line: 4)
        }
        mInk(ctx, UIBezierPath(roundedRect: CGRect(x: 175, y: 60, width: 70, height: 60), cornerRadius: 14), fill: MoonPalette.hull, line: 4)
        mInk(ctx, UIBezierPath(ovalIn: CGRect(x: 196, y: 76, width: 28, height: 28)), fill: UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1), line: 3)
    }

    /// A small tumbling rock (space debris to fly past).
    static let spaceRock = drawnHi(CGSize(width: 90, height: 80), scale: 1.0) { ctx, _ in
        let r = UIBezierPath()
        r.move(to: CGPoint(x: 10, y: 40)); r.addLine(to: CGPoint(x: 30, y: 8)); r.addLine(to: CGPoint(x: 66, y: 10)); r.addLine(to: CGPoint(x: 84, y: 42))
        r.addLine(to: CGPoint(x: 60, y: 74)); r.addLine(to: CGPoint(x: 22, y: 70)); r.close()
        mInk(ctx, r, fill: UIColor(red: 0.55, green: 0.48, blue: 0.62, alpha: 1), line: 4)
        UIColor(red: 0.42, green: 0.36, blue: 0.50, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: 34, y: 28, width: 18, height: 14)); ctx.fillEllipse(in: CGRect(x: 56, y: 46, width: 12, height: 10))
    }

    /// The Moon: a pale disc with craters and a soft terminator.
    static let moonDisc = drawnHi(CGSize(width: 512, height: 512), scale: 1.0) { ctx, size in
        let disc = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
        mInk(ctx, disc, fill: MoonPalette.moon, line: 10)
        ctx.saveGState(); ctx.addPath(disc.cgPath); ctx.clip()
        MoonPalette.moonShade.setFill()
        ctx.fillEllipse(in: CGRect(x: 170, y: 60, width: 440, height: 470))
        MoonPalette.moon.withAlphaComponent(0.55).setFill()
        ctx.fillEllipse(in: CGRect(x: 60, y: 120, width: 300, height: 260))
        let craters: [(CGFloat, CGFloat, CGFloat)] = [(150, 140, 60), (300, 120, 34), (230, 270, 80), (110, 330, 40), (360, 330, 52), (300, 420, 30), (180, 430, 26)]
        for (x, y, r) in craters {
            MoonPalette.moonShade.withAlphaComponent(0.85).setFill(); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            MoonPalette.moon.withAlphaComponent(0.6).setFill(); ctx.fillEllipse(in: CGRect(x: x - r * 0.7, y: y - r * 0.55, width: 1.4 * r, height: 1.3 * r))
        }
        ctx.restoreGState()
        ctx.setStrokeColor(MoonPalette.ink.cgColor); ctx.setLineWidth(10); ctx.addPath(disc.cgPath); ctx.strokePath()
    }

    /// The Earth seen from the Moon (for the landing sky).
    static let earthDisc = drawnHi(CGSize(width: 256, height: 256), scale: 1.0) { ctx, size in
        let disc = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6))
        mInk(ctx, disc, fill: UIColor(red: 0.18, green: 0.50, blue: 0.92, alpha: 1), line: 6)
        ctx.saveGState(); ctx.addPath(disc.cgPath); ctx.clip()
        UIColor(red: 0.36, green: 0.72, blue: 0.36, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: 40, y: 50, width: 90, height: 120)); ctx.fillEllipse(in: CGRect(x: 140, y: 120, width: 80, height: 70))
        UIColor.white.withAlphaComponent(0.85).setFill()
        ctx.fillEllipse(in: CGRect(x: 90, y: 30, width: 110, height: 26)); ctx.fillEllipse(in: CGRect(x: 30, y: 170, width: 120, height: 24))
        UIColor.black.withAlphaComponent(0.3).setFill(); ctx.fillEllipse(in: CGRect(x: 120, y: -20, width: 220, height: 300))
        ctx.restoreGState()
    }

    /// The team flag planted at touchdown: coral and teal halves with a star.
    static let teamFlag = drawnHi(CGSize(width: 200, height: 260), scale: 1.0) { ctx, _ in
        mInk(ctx, UIBezierPath(rect: CGRect(x: 14, y: 10, width: 10, height: 246)), fill: MoonPalette.metal, line: 3)
        let cloth = UIBezierPath()
        cloth.move(to: CGPoint(x: 24, y: 16)); cloth.addCurve(to: CGPoint(x: 190, y: 26), controlPoint1: CGPoint(x: 80, y: 0), controlPoint2: CGPoint(x: 130, y: 40))
        cloth.addLine(to: CGPoint(x: 190, y: 126)); cloth.addCurve(to: CGPoint(x: 24, y: 116), controlPoint1: CGPoint(x: 130, y: 140), controlPoint2: CGPoint(x: 80, y: 100)); cloth.close()
        mInk(ctx, cloth, fill: Palette.coral, line: 5)
        ctx.saveGState(); ctx.addPath(cloth.cgPath); ctx.clip()
        Palette.teal.setFill(); ctx.fill(CGRect(x: 107, y: 0, width: 100, height: 150))
        ctx.restoreGState()
        ctx.setStrokeColor(MoonPalette.ink.cgColor); ctx.setLineWidth(5); ctx.addPath(cloth.cgPath); ctx.strokePath()
        let star = UIBezierPath()
        for k in 0..<10 {
            let r: CGFloat = k % 2 == 0 ? 26 : 11
            let a = CGFloat(k) * .pi / 5 - .pi / 2
            let pt = CGPoint(x: 107 + r * cos(a), y: 70 + r * sin(a))
            if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
        }
        star.close()
        mInk(ctx, star, fill: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), line: 4)
    }

    /// Progress track icons.
    static let rocketIcon = drawnHi(CGSize(width: 60, height: 80), scale: 1.25) { ctx, _ in
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 30, y: 4)); body.addQuadCurve(to: CGPoint(x: 46, y: 56), controlPoint: CGPoint(x: 50, y: 24))
        body.addLine(to: CGPoint(x: 14, y: 56)); body.addQuadCurve(to: CGPoint(x: 30, y: 4), controlPoint: CGPoint(x: 10, y: 24)); body.close()
        mInk(ctx, body, fill: MoonPalette.hull, line: 4)
        for side in [-1.0, 1.0] as [CGFloat] {
            let fin = UIBezierPath(); fin.move(to: CGPoint(x: 30 + side * 14, y: 40)); fin.addLine(to: CGPoint(x: 30 + side * 24, y: 66)); fin.addLine(to: CGPoint(x: 30 + side * 12, y: 58)); fin.close()
            mInk(ctx, fin, fill: MoonPalette.orange, line: 3)
        }
        mInk(ctx, UIBezierPath(ovalIn: CGRect(x: 23, y: 20, width: 14, height: 14)), fill: UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1), line: 3)
        UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1).setFill(); ctx.fillEllipse(in: CGRect(x: 22, y: 60, width: 16, height: 18))
    }

    static var moonTextures: [SKTexture] {
        [racePod, racePodBand, raceDeckLip, clampArm, crown, moonGate, sunFlare, flame, smokePuff, cloudPuff, skyWisp, gantry, floodMast, hills, airliner,
         hotAirBalloon, weatherBalloon, satellite, spaceStation, spaceRock, moonDisc, earthDisc, teamFlag, rocketIcon]
    }
}
