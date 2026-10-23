import SpriteKit
import UIKit

/// Laser Breakout heist set pieces, in the same vault language as Art+Laser: navy/violet machined metal, electric
/// cyan tech light, coral security threats, gold for the loot; ink outline, flat cel shading, light from upper left.
@MainActor
extension Art {
    private static func hInk(_ ctx: CGContext, _ path: UIBezierPath, fill: UIColor, line: CGFloat) {
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        fill.setFill(); ctx.addPath(path.cgPath); ctx.fillPath()
        guard line > 0 else { return }
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(line); ctx.addPath(path.cgPath); ctx.strokePath()
    }
    private static let steel = UIColor(red: 0.42, green: 0.45, blue: 0.62, alpha: 1)
    private static let steelLight = UIColor(red: 0.62, green: 0.66, blue: 0.82, alpha: 1)
    private static let steelDark = UIColor(red: 0.22, green: 0.24, blue: 0.40, alpha: 1)

    // MARK: - The vault door (opening set piece). 100 pt per world unit; the disc is 2.4 units across.

    /// Round vault door: heavy rim, twelve locking bolts, machined face with rings.
    static let vaultDoorBody = drawnHi(CGSize(width: 260, height: 260), scale: 1.5) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        // Bolts (behind the rim): they slide in at runtime via the separate bolt ring, here as stubs.
        let rim = UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16))
        hInk(ctx, rim, fill: steel, line: 6)
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48)), fill: steelDark, line: 4)
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: 36, y: 36, width: size.width - 72, height: size.height - 72)), fill: steel, line: 4)
        // Upper-left highlight arc.
        ctx.setStrokeColor(steelLight.cgColor); ctx.setLineWidth(8)
        ctx.addArc(center: c, radius: size.width / 2 - 16, startAngle: .pi * 1.05, endAngle: .pi * 1.45, clockwise: false); ctx.strokePath()
        // Rivets.
        UIColor.white.withAlphaComponent(0.55).setFill()
        for k in 0..<24 {
            let a = CGFloat(k) / 24 * 2 * .pi
            ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * (size.width / 2 - 30) - 3, y: c.y + sin(a) * (size.width / 2 - 30) - 3, width: 6, height: 6))
        }
        // Gold diamond emblem at the hub.
        let d = UIBezierPath()
        d.move(to: CGPoint(x: c.x, y: c.y - 22)); d.addLine(to: CGPoint(x: c.x + 18, y: c.y)); d.addLine(to: CGPoint(x: c.x, y: c.y + 22)); d.addLine(to: CGPoint(x: c.x - 18, y: c.y)); d.close()
        hInk(ctx, d, fill: VaultPalette.gold, line: 4)
    }

    /// The spoked handle wheel on the door's face (spins as the bolts retract).
    static let vaultWheel = drawnHi(CGSize(width: 160, height: 160), scale: 1.5) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for k in 0..<4 {
            let a = CGFloat(k) / 4 * .pi
            let spoke = UIBezierPath()
            spoke.move(to: CGPoint(x: c.x + cos(a) * 70, y: c.y + sin(a) * 70)); spoke.addLine(to: CGPoint(x: c.x - cos(a) * 70, y: c.y - sin(a) * 70))
            ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(16); ctx.addPath(spoke.cgPath); ctx.strokePath()
            ctx.setStrokeColor(VaultPalette.gold.cgColor); ctx.setLineWidth(9); ctx.addPath(spoke.cgPath); ctx.strokePath()
        }
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * 2 * .pi
            hInk(ctx, UIBezierPath(ovalIn: CGRect(x: c.x + cos(a) * 70 - 9, y: c.y + sin(a) * 70 - 9, width: 18, height: 18)), fill: VaultPalette.goldLight, line: 3)
        }
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52)), fill: steelDark, line: 4)
    }

    /// One locking bolt (slides out of the rim into the frame, and back when unlocking).
    static let vaultBolt = drawnHi(CGSize(width: 40, height: 18), scale: 1.5) { ctx, size in
        hInk(ctx, UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4), cornerRadius: 6), fill: steelLight, line: 3)
    }

    // MARK: - Corridor structure

    /// A structural bulkhead around the corridor cross-section (4.0 × 2.65 units at 100 pt/unit): heavy ribs, corner
    /// braces, cyan service lights. Passing every few metres, they give the corridor rhythm, scale and strong flow.
    static let bulkhead = drawnHi(CGSize(width: 400, height: 265), scale: 1.0) { ctx, size in
        let outer = CGRect(origin: .zero, size: size)
        let t: CGFloat = 22
        let ring = UIBezierPath(rect: outer)
        let inner = UIBezierPath()
        let r = outer.insetBy(dx: t, dy: t)
        inner.move(to: CGPoint(x: r.minX + 30, y: r.minY)); inner.addLine(to: CGPoint(x: r.maxX - 30, y: r.minY))
        inner.addLine(to: CGPoint(x: r.maxX, y: r.minY + 30)); inner.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        inner.addLine(to: CGPoint(x: r.minX, y: r.maxY)); inner.addLine(to: CGPoint(x: r.minX, y: r.minY + 30)); inner.close()
        ring.append(inner.reversing())
        hInk(ctx, ring, fill: VaultPalette.metal, line: 4)
        ctx.saveGState(); ctx.addPath(ring.cgPath); ctx.clip()
        VaultPalette.metalLight.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 6))
        VaultPalette.navy.setFill(); ctx.fill(CGRect(x: 0, y: size.height - 10, width: size.width, height: 10))
        // Service lights along the ribs (white: tinted cyan/coral at runtime).
        UIColor.white.setFill()
        for y in stride(from: CGFloat(60), to: size.height - 30, by: 50) {
            ctx.fill(CGRect(x: 7, y: y, width: 8, height: 22)); ctx.fill(CGRect(x: size.width - 15, y: y, width: 8, height: 22))
        }
        for x in stride(from: CGFloat(80), to: size.width - 60, by: 80) { ctx.fill(CGRect(x: x, y: 8, width: 26, height: 7)) }
        ctx.restoreGState()
    }

    // MARK: - Final lockdown gate (dual security override)

    /// One half of the lockdown gate (2.0 × 2.65 units): armoured panel, hazard edge, a big lock dial socket.
    static let lockGateHalf = drawnHi(CGSize(width: 200, height: 265), scale: 1.0) { ctx, size in
        let panel = UIBezierPath(rect: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4))
        hInk(ctx, panel, fill: steelDark, line: 5)
        ctx.saveGState(); ctx.addPath(panel.cgPath); ctx.clip()
        steel.setFill()
        for y in stride(from: CGFloat(20), to: size.height, by: 48) { ctx.fill(CGRect(x: 14, y: y, width: size.width - 28, height: 30)) }
        // Hazard stripes along the meeting edge (right side of a left half).
        for i in stride(from: CGFloat(-40), through: size.height + 40, by: 24) {
            let s = UIBezierPath(); s.move(to: CGPoint(x: size.width - 18, y: i)); s.addLine(to: CGPoint(x: size.width, y: i - 12))
            s.addLine(to: CGPoint(x: size.width, y: i)); s.addLine(to: CGPoint(x: size.width - 18, y: i + 12)); s.close()
            VaultPalette.gold.setFill(); ctx.addPath(s.cgPath); ctx.fillPath()
        }
        ctx.restoreGState()
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: size.width / 2 - 52, y: 70, width: 104, height: 104)), fill: VaultPalette.navy, line: 5)
    }

    /// The lock dial in each half's socket (spins and clunks as its player cranks).
    static let lockDial = drawnHi(CGSize(width: 100, height: 100), scale: 1.5) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 88, height: 88)), fill: steel, line: 5)
        for k in 0..<3 {
            let a = CGFloat(k) / 3 * 2 * .pi
            let tooth = UIBezierPath(roundedRect: CGRect(x: c.x - 7, y: 8, width: 14, height: 38), cornerRadius: 5)
            tooth.apply(CGAffineTransform(translationX: -c.x, y: -c.y).rotated(by: a).translatedBy(x: 0, y: 0).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
            hInk(ctx, tooth, fill: steelLight, line: 3)
        }
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32)), fill: UIColor.white, line: 4)   // lock light (tinted)
    }

    /// The emergency pull handle that hangs above each player (yellow/black T-grip on a cable).
    static let pullHandle = drawnHi(CGSize(width: 120, height: 220), scale: 1.25) { ctx, size in
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(8)
        ctx.move(to: CGPoint(x: size.width / 2, y: 0)); ctx.addLine(to: CGPoint(x: size.width / 2, y: 160)); ctx.strokePath()
        ctx.setStrokeColor(steelLight.cgColor); ctx.setLineWidth(4)
        ctx.move(to: CGPoint(x: size.width / 2, y: 0)); ctx.addLine(to: CGPoint(x: size.width / 2, y: 160)); ctx.strokePath()
        let grip = UIBezierPath(roundedRect: CGRect(x: 8, y: 158, width: size.width - 16, height: 40), cornerRadius: 16)
        hInk(ctx, grip, fill: VaultPalette.gold, line: 6)
        ctx.saveGState(); ctx.addPath(grip.cgPath); ctx.clip()
        VaultPalette.ink.setFill()
        for x in stride(from: CGFloat(4), to: size.width, by: 26) {
            let s = UIBezierPath(); s.move(to: CGPoint(x: x, y: 158)); s.addLine(to: CGPoint(x: x + 12, y: 158)); s.addLine(to: CGPoint(x: x - 2, y: 200)); s.addLine(to: CGPoint(x: x - 14, y: 200)); s.close()
            ctx.addPath(s.cgPath); ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // MARK: - The security drone (the facility's face)

    static let droneBody = drawnHi(CGSize(width: 220, height: 150), scale: 1.25) { ctx, size in
        // Rotor arms.
        for side in [-1.0, 1.0] as [CGFloat] {
            let arm = UIBezierPath(roundedRect: CGRect(x: side < 0 ? 4 : size.width - 64, y: 34, width: 60, height: 12), cornerRadius: 6)
            hInk(ctx, arm, fill: steelDark, line: 4)
        }
        let shell = UIBezierPath(roundedRect: CGRect(x: 40, y: 22, width: size.width - 80, height: 116), cornerRadius: 50)
        hInk(ctx, shell, fill: VaultPalette.metal, line: 6)
        ctx.saveGState(); ctx.addPath(shell.cgPath); ctx.clip()
        VaultPalette.metalLight.setFill(); ctx.fillEllipse(in: CGRect(x: 52, y: 26, width: 70, height: 26))
        VaultPalette.navy.setFill(); ctx.fill(CGRect(x: 40, y: 118, width: size.width - 80, height: 20))
        ctx.restoreGState()
        // Visor socket for the eye.
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: size.width / 2 - 40, y: 46, width: 80, height: 80)), fill: VaultPalette.ink, line: 0)
    }

    static let droneEye = drawnHi(CGSize(width: 80, height: 80), scale: 1.5) { ctx, size in
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12))
    }

    static let dronePupil = drawnHi(CGSize(width: 40, height: 40), scale: 1.5) { ctx, size in
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(origin: .zero, size: size))       // iris (tinted by mood)
        VaultPalette.ink.setFill(); ctx.fillEllipse(in: CGRect(x: 10, y: 10, width: 20, height: 20))
        UIColor.white.setFill(); ctx.fillEllipse(in: CGRect(x: 12, y: 11, width: 7, height: 6))
    }

    static let droneRotor = drawnHi(CGSize(width: 90, height: 22), scale: 1.25) { ctx, size in
        UIColor(white: 0.9, alpha: 0.55).setFill(); ctx.fillEllipse(in: CGRect(x: 2, y: 4, width: size.width - 4, height: size.height - 8))
        VaultPalette.ink.withAlphaComponent(0.6).setFill(); ctx.fillEllipse(in: CGRect(x: size.width / 2 - 6, y: 6, width: 12, height: 10))
    }

    /// The eyelid: a dark arc that closes over the eye top for "suspicious" and "annoyed".
    static let droneLid = drawnHi(CGSize(width: 80, height: 80), scale: 1.5) { ctx, size in
        VaultPalette.metal.setFill()
        ctx.addRect(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)); ctx.fillPath()
        ctx.setStrokeColor(VaultPalette.ink.cgColor); ctx.setLineWidth(5)
        ctx.move(to: CGPoint(x: 4, y: size.height / 2)); ctx.addLine(to: CGPoint(x: size.width - 4, y: size.height / 2)); ctx.strokePath()
    }

    // MARK: - Wall emitter turret (replaces the plain box): base plate + barrel with a lens.

    static let emitterTurret = drawnHi(CGSize(width: 70, height: 44), scale: 1.5) { ctx, size in
        hInk(ctx, UIBezierPath(roundedRect: CGRect(x: 2, y: 4, width: 22, height: 36), cornerRadius: 5), fill: VaultPalette.metal, line: 3)
        hInk(ctx, UIBezierPath(roundedRect: CGRect(x: 18, y: 12, width: 40, height: 20), cornerRadius: 6), fill: VaultPalette.metalLight, line: 3)
        hInk(ctx, UIBezierPath(ovalIn: CGRect(x: 50, y: 10, width: 18, height: 24)), fill: UIColor.white, line: 3)   // lens (tinted)
    }

    // MARK: - The way out

    /// Night city skyline seen through the exit doors.
    static let citySkyline = drawnHi(CGSize(width: 800, height: 300), scale: 1.0) { ctx, size in
        let colors = [UIColor(red: 0.10, green: 0.12, blue: 0.32, alpha: 1).cgColor, UIColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 1).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1).setFill(); ctx.fillEllipse(in: CGRect(x: 600, y: 40, width: 60, height: 60))
        var rng = SeededGenerator(seed: 3)
        var x: CGFloat = 0
        while x < size.width {
            let w = CGFloat(40 + rng.next() * 60), h = CGFloat(90 + rng.next() * 170)
            let b = CGRect(x: x, y: size.height - h, width: w, height: h)
            UIColor(red: 0.07, green: 0.08, blue: 0.22, alpha: 1).setFill(); ctx.fill(b)
            for wy in stride(from: b.minY + 10, to: size.height - 10, by: 16) {
                for wx in stride(from: b.minX + 6, to: b.maxX - 8, by: 12) where rng.next() < 0.45 {
                    UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 0.9).setFill(); ctx.fill(CGRect(x: wx, y: wy, width: 5, height: 7))
                }
            }
            x += w + CGFloat(rng.next() * 8)
        }
    }

    static var heistTextures: [SKTexture] {
        [vaultDoorBody, vaultWheel, vaultBolt, bulkhead, lockGateHalf, lockDial, pullHandle, droneBody, droneEye, dronePupil, droneRotor, droneLid, emitterTurret, citySkyline]
    }
}
