import SpriteKit
import UIKit

/// Laser Breakout palette: deep navy / dark violet architecture, electric cyan accents, coral security lasers,
/// warm gold for the loot. Same ink outline and flat cel shading as the rest of Sedactive.
enum VaultPalette {
    static let navy = UIColor(red: 0.055, green: 0.063, blue: 0.20, alpha: 1)
    static let violet = UIColor(red: 0.17, green: 0.11, blue: 0.34, alpha: 1)
    static let metal = UIColor(red: 0.20, green: 0.22, blue: 0.40, alpha: 1)
    static let metalLight = UIColor(red: 0.34, green: 0.37, blue: 0.60, alpha: 1)
    static let cyan = UIColor(red: 0.17, green: 0.90, blue: 1.0, alpha: 1)
    static let laser = UIColor(red: 1.0, green: 0.30, blue: 0.37, alpha: 1)
    static let laserCore = UIColor(red: 1.0, green: 0.86, blue: 0.88, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1)
    static let goldLight = UIColor(red: 1.0, green: 0.93, blue: 0.65, alpha: 1)
    static let ink = UIColor(red: 0.03, green: 0.035, blue: 0.10, alpha: 1)
}

@MainActor
extension Art {
    private static func vInk(_ ctx: CGContext, _ path: UIBezierPath, fill: UIColor, line: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        fill.setFill(); ctx.addPath(path.cgPath); ctx.fillPath()
        guard line > 0 else { return }
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(line); ctx.addPath(path.cgPath); ctx.strokePath()
    }

    // MARK: - Security gate (drawn at 100 pt per world unit: the corridor's cross-section, 4.0 × 2.65)

    /// A security arch: heavy frame around the corridor cross-section, hazard stripes at the foot, a light edge that is
    /// tinted at runtime (cyan idle, coral armed). Transparent in the middle.
    static let gateFrame = drawnHi(CGSize(width: 400, height: 265), scale: 1.0) { ctx, size in
        let outer = CGRect(origin: .zero, size: size)
        let t: CGFloat = 16
        let ring = UIBezierPath(rect: outer)
        ring.append(UIBezierPath(roundedRect: outer.insetBy(dx: t, dy: t), cornerRadius: 10).reversing())
        vInk(ctx, ring, fill: VaultPalette.metal, line: 4)
        ctx.saveGState(); ctx.addPath(ring.cgPath); ctx.clip()
        VaultPalette.metalLight.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 5))
        // Hazard stripes on the floor sill.
        for i in stride(from: CGFloat(-20), through: size.width, by: 26) {
            let s = UIBezierPath(); s.move(to: CGPoint(x: i, y: size.height)); s.addLine(to: CGPoint(x: i + 13, y: size.height))
            s.addLine(to: CGPoint(x: i + 29, y: size.height - t)); s.addLine(to: CGPoint(x: i + 16, y: size.height - t)); s.close()
            VaultPalette.gold.withAlphaComponent(0.8).setFill(); ctx.addPath(s.cgPath); ctx.fillPath()
        }
        ctx.restoreGState()
        // Inner light edge (white: tinted at runtime).
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(3)
        ctx.addPath(UIBezierPath(roundedRect: outer.insetBy(dx: t + 2, dy: t + 2), cornerRadius: 9).cgPath); ctx.strokePath()
    }

    /// Laser emitter housing (mounted on the gate frame or the centre pylon); the lens glows when armed.
    static let emitter = drawnHi(CGSize(width: 40, height: 30), scale: 1.5) { ctx, size in
        let box = UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 36, height: 26), cornerRadius: 6)
        vInk(ctx, box, fill: VaultPalette.metalLight, line: 3)
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: 13, y: 8, width: 14, height: 14))
    }

    /// The centre pylon of a split-lane grid: floor-to-ceiling post between the players' lanes.
    static let gatePylon = drawnHi(CGSize(width: 24, height: 265), scale: 1.0) { ctx, size in
        let post = UIBezierPath(roundedRect: CGRect(x: 3, y: 0, width: 18, height: size.height), cornerRadius: 4)
        vInk(ctx, post, fill: VaultPalette.metal, line: 3)
        UIColor.white.setFill(); ctx.fill(CGRect(x: 10, y: 6, width: 4, height: size.height - 12))
    }

    /// One laser beam: a hot white core in a coral glow (stretched horizontally between emitters).
    static let laserBeam = drawnHi(CGSize(width: 64, height: 32), scale: 1.0) { ctx, size in
        let colors = [VaultPalette.laser.withAlphaComponent(0).cgColor, VaultPalette.laser.withAlphaComponent(0.55).cgColor,
                      VaultPalette.laserCore.cgColor, VaultPalette.laser.withAlphaComponent(0.55).cgColor, VaultPalette.laser.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 0.5, 0.7, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width, height: 3))
    }

    // MARK: - Corridor fixtures

    /// Ceiling-corner security camera with a red tally light (it pans to watch the cart).
    static let securityCamera = drawnHi(CGSize(width: 120, height: 80), scale: 1.25) { ctx, _ in
        let arm = UIBezierPath(rect: CGRect(x: 52, y: 0, width: 14, height: 30)); vInk(ctx, arm, fill: VaultPalette.metal, line: 3)
        let body = UIBezierPath(roundedRect: CGRect(x: 14, y: 26, width: 90, height: 36), cornerRadius: 10); vInk(ctx, body, fill: VaultPalette.metalLight, line: 4)
        let lens = UIBezierPath(ovalIn: CGRect(x: 4, y: 30, width: 30, height: 28)); vInk(ctx, lens, fill: VaultPalette.navy, line: 4)
        VaultPalette.cyan.setFill(); ctx.fillEllipse(in: CGRect(x: 12, y: 37, width: 12, height: 12))
        VaultPalette.laser.setFill(); ctx.fillEllipse(in: CGRect(x: 86, y: 32, width: 10, height: 10))
    }

    /// Wall-mounted alarm beacon: dome on a base (the rotating light is a separate tinted sprite).
    static let beacon = drawnHi(CGSize(width: 60, height: 50), scale: 1.25) { ctx, _ in
        let base = UIBezierPath(roundedRect: CGRect(x: 6, y: 36, width: 48, height: 12), cornerRadius: 3); vInk(ctx, base, fill: VaultPalette.metal, line: 3)
        let dome = UIBezierPath(); dome.move(to: CGPoint(x: 12, y: 38)); dome.addQuadCurve(to: CGPoint(x: 48, y: 38), controlPoint: CGPoint(x: 30, y: -6)); dome.close()
        vInk(ctx, dome, fill: UIColor.white, line: 3)
    }

    /// A rotating beam of light from the beacon (tinted, additive), drawn as a soft fan.
    static let beaconFan = drawnHi(CGSize(width: 256, height: 64), scale: 1.0) { ctx, size in
        let colors = [UIColor.white.withAlphaComponent(0.8).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        let fan = UIBezierPath(); fan.move(to: CGPoint(x: 0, y: size.height / 2)); fan.addLine(to: CGPoint(x: size.width, y: 0)); fan.addLine(to: CGPoint(x: size.width, y: size.height)); fan.close()
        ctx.addPath(fan.cgPath); ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: 0), options: [])
    }

    /// One half of a blast door (left half; mirrored for the right): heavy plate, hazard edge, rivets, a window slot.
    static let blastDoor = drawnHi(CGSize(width: 200, height: 265), scale: 1.0) { ctx, size in
        let plate = UIBezierPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)); vInk(ctx, plate, fill: VaultPalette.metal, line: 4)
        VaultPalette.metalLight.setFill(); ctx.fill(CGRect(x: 10, y: 10, width: size.width - 20, height: 8))
        let edge = CGRect(x: size.width - 26, y: 2, width: 24, height: size.height - 4)
        ctx.saveGState(); ctx.clip(to: edge)
        VaultPalette.ink.setFill(); ctx.fill(edge)
        for y in stride(from: CGFloat(-30), through: size.height, by: 30) {
            let s = UIBezierPath(); s.move(to: CGPoint(x: edge.minX, y: y)); s.addLine(to: CGPoint(x: edge.maxX, y: y + 16))
            s.addLine(to: CGPoint(x: edge.maxX, y: y + 30)); s.addLine(to: CGPoint(x: edge.minX, y: y + 14)); s.close()
            VaultPalette.gold.setFill(); ctx.addPath(s.cgPath); ctx.fillPath()
        }
        ctx.restoreGState()
        VaultPalette.ink.withAlphaComponent(0.6).setFill()
        for y in [40.0, 130.0, 220.0] as [CGFloat] { for x in [24.0, 150.0] as [CGFloat] { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 8, height: 8)) } }
        let slot = UIBezierPath(roundedRect: CGRect(x: 60, y: 60, width: 80, height: 18), cornerRadius: 9); vInk(ctx, slot, fill: VaultPalette.cyan.withAlphaComponent(0.6), line: 3)
    }

    /// The emergency exit at the end of the corridor (two leaves; the light behind is the shader's exit glow).
    static let exitSign = drawnHi(CGSize(width: 180, height: 60), scale: 1.25) { ctx, size in
        let plate = UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4), cornerRadius: 10)
        vInk(ctx, plate, fill: UIColor(red: 0.20, green: 0.85, blue: 0.45, alpha: 1), line: 4)
        let text = NSAttributedString(string: "EXIT", attributes: [.font: UIFont.systemFont(ofSize: 38, weight: .black), .foregroundColor: UIColor.white])
        let ts = text.size()
        text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2))
    }

    // MARK: - The getaway cart and the loot

    /// The cart's deck seen from above (warped into perspective at runtime): dark plate, gold trim, cyan floor lights.
    static let cartDeck = drawnHi(CGSize(width: 460, height: 380), scale: 1.0) { ctx, size in
        let deck = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 4), cornerRadius: 22)
        vInk(ctx, deck, fill: VaultPalette.metal.mixed(with: VaultPalette.metalLight, amount: 0.25), line: 8)
        ctx.saveGState(); ctx.addPath(deck.cgPath); ctx.clip()
        VaultPalette.metal.setFill()
        for y in stride(from: CGFloat(30), to: size.height, by: 54) { ctx.fill(CGRect(x: 20, y: y, width: size.width - 40, height: 3)) }
        ctx.restoreGState()
        ctx.setStrokeColor(VaultPalette.gold.cgColor); ctx.setLineWidth(7)
        ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 14), cornerRadius: 16).cgPath); ctx.strokePath()
        VaultPalette.cyan.setFill()
        for x in [44.0, size.width - 52] as [CGFloat] {
            for y in stride(from: CGFloat(40), to: size.height - 30, by: 60) { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 8, height: 8)) }
        }
    }

    /// The cart's front rail seen from inside: a low metal bulkhead with a cyan running light and a gold cap.
    static let cartNose = drawnHi(CGSize(width: 460, height: 70), scale: 1.0) { ctx, size in
        let lip = UIBezierPath(roundedRect: CGRect(x: 6, y: 4, width: size.width - 12, height: size.height - 8), cornerRadius: 14)
        vInk(ctx, lip, fill: VaultPalette.metal, line: 6)
        VaultPalette.gold.setFill()
        ctx.fill(CGRect(x: 14, y: 10, width: size.width - 28, height: 9))
        VaultPalette.cyan.setFill()
        ctx.fill(CGRect(x: 40, y: size.height - 30, width: size.width - 80, height: 6))
    }

    /// The stolen diamond: a faceted gem with warm gold highlights (the hero object).
    static let diamond = drawnHi(CGSize(width: 140, height: 120), scale: 1.5) { ctx, _ in
        let crown = UIBezierPath()
        crown.move(to: CGPoint(x: 20, y: 40)); crown.addLine(to: CGPoint(x: 44, y: 12)); crown.addLine(to: CGPoint(x: 96, y: 12))
        crown.addLine(to: CGPoint(x: 120, y: 40)); crown.addLine(to: CGPoint(x: 70, y: 112)); crown.close()
        vInk(ctx, crown, fill: UIColor(red: 0.62, green: 0.94, blue: 1.0, alpha: 1), line: 5)
        ctx.saveGState(); ctx.addPath(crown.cgPath); ctx.clip()
        UIColor.white.withAlphaComponent(0.85).setFill()
        let f1 = UIBezierPath(); f1.move(to: CGPoint(x: 44, y: 12)); f1.addLine(to: CGPoint(x: 70, y: 40)); f1.addLine(to: CGPoint(x: 20, y: 40)); f1.close(); ctx.addPath(f1.cgPath); ctx.fillPath()
        VaultPalette.gold.withAlphaComponent(0.55).setFill()
        let f2 = UIBezierPath(); f2.move(to: CGPoint(x: 70, y: 40)); f2.addLine(to: CGPoint(x: 120, y: 40)); f2.addLine(to: CGPoint(x: 70, y: 112)); f2.close(); ctx.addPath(f2.cgPath); ctx.fillPath()
        ctx.setStrokeColor(VaultPalette.ink.withAlphaComponent(0.5).cgColor); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 20, y: 40)); ctx.addLine(to: CGPoint(x: 120, y: 40)); ctx.strokePath()
        ctx.move(to: CGPoint(x: 70, y: 40)); ctx.addLine(to: CGPoint(x: 70, y: 112)); ctx.strokePath()
        ctx.restoreGState()
    }

    /// A small four-point glint (gold sparkle on the diamond, the celebration).
    static let glintStar = drawnHi(CGSize(width: 48, height: 48), scale: 1.0) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let p = UIBezierPath()
        p.move(to: CGPoint(x: c.x, y: 0)); p.addQuadCurve(to: CGPoint(x: size.width, y: c.y), controlPoint: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: size.height), controlPoint: c); p.addQuadCurve(to: CGPoint(x: 0, y: c.y), controlPoint: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: 0), controlPoint: c); p.close()
        UIColor.white.setFill(); ctx.addPath(p.cgPath); ctx.fillPath()
    }

    // MARK: - Warning badges (Sedactive badge family: disc, ink outline, pictogram)

    private static func laserBadge(_ ctx: CGContext, _ size: CGSize, high: Bool) {
        let r = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 0, color: Palette.deepNavy.withAlphaComponent(0.55).cgColor)
        VaultPalette.laser.setFill(); ctx.fillEllipse(in: r)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(9); ctx.strokeEllipse(in: r.insetBy(dx: 2, dy: 2))
        // The beam.
        let beamY: CGFloat = high ? 56 : 120
        UIColor.white.setFill(); ctx.fill(CGRect(x: 24, y: beamY - 4, width: 112, height: 8))
        // The figure: ducking under it, or tucked in the air over it.
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(7)
        VaultPalette.ink.setFill()
        if high {
            ctx.fillEllipse(in: CGRect(x: 71, y: 74, width: 18, height: 18))
            ctx.move(to: CGPoint(x: 80, y: 92)); ctx.addLine(to: CGPoint(x: 80, y: 108)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 64, y: 130)); ctx.addLine(to: CGPoint(x: 70, y: 112)); ctx.addLine(to: CGPoint(x: 80, y: 108)); ctx.addLine(to: CGPoint(x: 90, y: 112)); ctx.addLine(to: CGPoint(x: 96, y: 130)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 66, y: 100)); ctx.addLine(to: CGPoint(x: 80, y: 96)); ctx.addLine(to: CGPoint(x: 94, y: 100)); ctx.strokePath()
        } else {
            ctx.fillEllipse(in: CGRect(x: 71, y: 30, width: 18, height: 18))
            ctx.move(to: CGPoint(x: 80, y: 50)); ctx.addLine(to: CGPoint(x: 80, y: 70)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 64, y: 40)); ctx.addLine(to: CGPoint(x: 80, y: 54)); ctx.addLine(to: CGPoint(x: 96, y: 40)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 66, y: 76)); ctx.addLine(to: CGPoint(x: 80, y: 70)); ctx.addLine(to: CGPoint(x: 94, y: 76)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 66, y: 76)); ctx.addLine(to: CGPoint(x: 72, y: 88)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 94, y: 76)); ctx.addLine(to: CGPoint(x: 88, y: 88)); ctx.strokePath()
        }
    }
    static let duckBadge = drawnHi(CGSize(width: 160, height: 160), scale: 1.25) { ctx, size in laserBadge(ctx, size, high: true) }
    static let jumpBadge = drawnHi(CGSize(width: 160, height: 160), scale: 1.25) { ctx, size in laserBadge(ctx, size, high: false) }

    static var laserTextures: [SKTexture] {
        [gateFrame, emitter, gatePylon, laserBeam, securityCamera, beacon, beaconFan, blastDoor, exitSign, cartDeck, cartNose, diamond,
         glintStar, duckBadge, jumpBadge]
    }
}
