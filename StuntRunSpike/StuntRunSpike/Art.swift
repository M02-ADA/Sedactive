import SpriteKit
import UIKit

/// Premium Playful Arcade palette.
enum Palette {
    static let navy = UIColor(red: 0.055, green: 0.063, blue: 0.20, alpha: 1)
    static let deepNavy = UIColor(red: 0.03, green: 0.035, blue: 0.12, alpha: 1)
    static let violet = UIColor(red: 0.42, green: 0.23, blue: 1.0, alpha: 1)
    static let electric = UIColor(red: 0.18, green: 0.48, blue: 1.0, alpha: 1)
    static let coral = UIColor(red: 1.0, green: 0.42, blue: 0.37, alpha: 1)
    static let yellow = UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
    static let teal = UIColor(red: 0.10, green: 0.83, blue: 0.77, alpha: 1)
    static let mint = UIColor(red: 0.35, green: 0.95, blue: 0.55, alpha: 1)
    static let white = UIColor.white

    static func color(for zone: Zone, swapped: Bool) -> UIColor {
        (zone == .left) != swapped ? coral : teal
    }
}

/// Procedurally drawn placeholder art, generated once at launch and shared, so sprites batch by texture.
/// Stand-ins for production illustration; the Sketch source was not reachable from this session.
@MainActor
enum Art {
    static let white = texture(CGSize(width: 4, height: 4)) { ctx, size in
        UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
    }

    static let glow = texture(CGSize(width: 128, height: 128)) { ctx, size in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.45).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1])!
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
    }

    static let streak = texture(CGSize(width: 12, height: 128)) { ctx, size in
        let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1])!
        ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6).cgPath)
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }

    static let pylon = texture(CGSize(width: 64, height: 320)) { ctx, size in
        let pole = CGRect(x: 26, y: 40, width: 12, height: size.height - 40)
        fillGradient(ctx, rect: pole, colors: [Palette.violet, Palette.navy], vertical: true, radius: 6)
        UIColor.white.withAlphaComponent(0.35).setFill()
        ctx.fill(CGRect(x: 28, y: 44, width: 3, height: size.height - 60))
        fillGradient(ctx, rect: CGRect(x: 8, y: 34, width: 48, height: 10), colors: [Palette.electric, Palette.violet], vertical: false, radius: 5)
        let orb = CGRect(x: 14, y: 2, width: 36, height: 36)
        ctx.setShadow(offset: .zero, blur: 10, color: Palette.yellow.cgColor)
        Palette.yellow.setFill()
        ctx.fillEllipse(in: orb)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        UIColor.white.setFill()
        ctx.fillEllipse(in: orb.insetBy(dx: 9, dy: 9))
    }

    static let buildings: [SKTexture] = (0..<4).map { variant in
        texture(CGSize(width: 220, height: 560)) { ctx, size in
            var rng = SeededRandom(seed: UInt64(variant * 977 + 13))
            let bodyColors: [[UIColor]] = [
                [UIColor(red: 0.20, green: 0.15, blue: 0.48, alpha: 1), UIColor(red: 0.09, green: 0.08, blue: 0.27, alpha: 1)],
                [UIColor(red: 0.13, green: 0.20, blue: 0.52, alpha: 1), UIColor(red: 0.06, green: 0.08, blue: 0.25, alpha: 1)],
                [UIColor(red: 0.30, green: 0.14, blue: 0.45, alpha: 1), UIColor(red: 0.10, green: 0.06, blue: 0.24, alpha: 1)],
                [UIColor(red: 0.16, green: 0.12, blue: 0.40, alpha: 1), UIColor(red: 0.05, green: 0.06, blue: 0.20, alpha: 1)],
            ]
            let top: CGFloat = 40
            let body = CGRect(x: 10, y: top, width: size.width - 20, height: size.height - top)
            fillGradient(ctx, rect: body, colors: bodyColors[variant], vertical: true, radius: 10)
            // Lit windows.
            let windowColors = [Palette.yellow, Palette.coral, Palette.teal, UIColor(white: 1, alpha: 1)]
            let cols = 5, rows = 16
            let cell = CGSize(width: (body.width - 30) / CGFloat(cols), height: (body.height - 40) / CGFloat(rows))
            for r in 0..<rows {
                for c in 0..<cols where rng.next() < 0.42 {
                    let color = windowColors[Int(rng.next() * Double(windowColors.count))]
                    color.withAlphaComponent(0.55 + 0.45 * rng.next()).setFill()
                    let rect = CGRect(x: body.minX + 15 + CGFloat(c) * cell.width + 4, y: body.minY + 24 + CGFloat(r) * cell.height + 4,
                                      width: cell.width - 8, height: cell.height - 9)
                    ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 2).cgPath)
                    ctx.fillPath()
                }
            }
            // Neon roof line and antenna.
            let neon = [Palette.coral, Palette.teal, Palette.yellow, Palette.violet][variant]
            ctx.setShadow(offset: .zero, blur: 8, color: neon.cgColor)
            neon.setFill()
            ctx.fill(CGRect(x: body.minX, y: top, width: body.width, height: 6))
            ctx.fill(CGRect(x: size.width / 2 - 2, y: 6, width: 4, height: top - 6))
            ctx.fillEllipse(in: CGRect(x: size.width / 2 - 6, y: 0, width: 12, height: 12))
        }
    }

    static let arch = texture(CGSize(width: 700, height: 540)) { ctx, size in
        let path = UIBezierPath()
        let inset: CGFloat = 40
        path.move(to: CGPoint(x: inset, y: size.height))
        path.addLine(to: CGPoint(x: inset, y: size.height * 0.42))
        path.addArc(withCenter: CGPoint(x: size.width / 2, y: size.height * 0.42), radius: size.width / 2 - inset,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: size.width - inset, y: size.height))
        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 24, color: Palette.teal.cgColor)
        ctx.setLineWidth(30)
        ctx.setStrokeColor(Palette.violet.cgColor)
        ctx.addPath(path.cgPath); ctx.strokePath()
        ctx.setLineWidth(12)
        ctx.setStrokeColor(Palette.teal.cgColor)
        ctx.addPath(path.cgPath); ctx.strokePath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setLineWidth(4)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.addPath(path.cgPath); ctx.strokePath()
    }

    static let skyline = texture(CGSize(width: 2400, height: 360)) { ctx, size in
        var rng = SeededRandom(seed: 42)
        var x: CGFloat = 0
        while x < size.width {
            let w = CGFloat(40 + rng.next() * 110)
            let h = CGFloat(80 + rng.next() * 250)
            let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
            UIColor(red: 0.17, green: 0.12, blue: 0.40, alpha: 1).setFill()
            ctx.fill(rect)
            for _ in 0..<Int(h / 18) where rng.next() < 0.5 {
                let wx = rect.minX + 6 + CGFloat(rng.next()) * (w - 14)
                let wy = rect.minY + 8 + CGFloat(rng.next()) * (h - 16)
                (rng.next() < 0.5 ? Palette.yellow : Palette.coral).withAlphaComponent(0.7).setFill()
                ctx.fill(CGRect(x: wx, y: wy, width: 5, height: 6))
            }
            x += w + CGFloat(rng.next() * 12)
        }
    }

    static let mountains = texture(CGSize(width: 2400, height: 300)) { ctx, size in
        var rng = SeededRandom(seed: 7)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        path.addLine(to: CGPoint(x: 0, y: size.height * 0.5))
        while x < size.width {
            x += CGFloat(80 + rng.next() * 160)
            path.addLine(to: CGPoint(x: x, y: CGFloat(20 + rng.next() * 190)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.close()
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.clip()
        fillGradient(ctx, rect: CGRect(origin: .zero, size: size),
                     colors: [UIColor(red: 0.45, green: 0.24, blue: 0.70, alpha: 1), UIColor(red: 0.14, green: 0.09, blue: 0.36, alpha: 1)],
                     vertical: true, radius: 0)
        ctx.restoreGState()
        ctx.setStrokeColor(Palette.coral.withAlphaComponent(0.65).cgColor)
        ctx.setLineWidth(3)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    static let cloud = texture(CGSize(width: 420, height: 160)) { ctx, _ in
        UIColor.white.withAlphaComponent(0.9).setFill()
        for blob in [CGRect(x: 30, y: 70, width: 160, height: 80), CGRect(x: 110, y: 30, width: 170, height: 120),
                     CGRect(x: 230, y: 55, width: 150, height: 95), CGRect(x: 60, y: 95, width: 320, height: 55)] {
            ctx.fillEllipse(in: blob)
        }
    }

    // MARK: Obstacle parts

    static let beam = texture(CGSize(width: 1000, height: 100)) { ctx, size in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 6)
        ctx.saveGState()
        ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 22).cgPath)
        ctx.clip()
        Palette.navy.setFill(); ctx.fill(rect)
        Palette.yellow.setFill()
        var x: CGFloat = -60
        while x < size.width + 60 {
            let stripe = UIBezierPath()
            stripe.move(to: CGPoint(x: x, y: rect.maxY))
            stripe.addLine(to: CGPoint(x: x + 40, y: rect.maxY))
            stripe.addLine(to: CGPoint(x: x + 100, y: rect.minY))
            stripe.addLine(to: CGPoint(x: x + 60, y: rect.minY))
            stripe.close()
            ctx.addPath(stripe.cgPath); ctx.fillPath()
            x += 80
        }
        UIColor.white.withAlphaComponent(0.35).setFill()
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 10))
        ctx.restoreGState()
        ctx.setStrokeColor(Palette.deepNavy.cgColor)
        ctx.setLineWidth(8)
        ctx.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 20).cgPath)
        ctx.strokePath()
    }

    static let post = texture(CGSize(width: 70, height: 420)) { ctx, size in
        let rect = CGRect(x: 10, y: 0, width: 50, height: size.height)
        fillGradient(ctx, rect: rect, colors: [Palette.violet, Palette.navy], vertical: false, radius: 12)
        Palette.coral.setFill()
        ctx.fill(CGRect(x: 10, y: size.height - 30, width: 50, height: 30))
        UIColor.white.withAlphaComponent(0.4).setFill()
        ctx.fill(CGRect(x: 16, y: 8, width: 6, height: size.height - 40))
    }

    /// White so it can be tinted per player; the chevrons say "go down".
    static let lanePanel = texture(CGSize(width: 360, height: 260)) { ctx, size in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
        let shape = UIBezierPath(roundedRect: rect, cornerRadius: 28)
        UIColor.white.withAlphaComponent(0.42).setFill()
        ctx.addPath(shape.cgPath); ctx.fillPath()
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(10)
        ctx.addPath(shape.cgPath); ctx.strokePath()
        drawChevrons(ctx, in: rect.insetBy(dx: 60, dy: 40), count: 2, lineWidth: 22)
    }

    static let chevron = texture(CGSize(width: 180, height: 150)) { ctx, size in
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 0, color: Palette.deepNavy.withAlphaComponent(0.6).cgColor)
        drawChevrons(ctx, in: CGRect(origin: .zero, size: size).insetBy(dx: 22, dy: 18), count: 2, lineWidth: 24)
    }

    static let check = texture(CGSize(width: 140, height: 140)) { ctx, size in
        Palette.mint.setFill()
        ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6))
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
        ctx.setLineWidth(16); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: 40, y: 72)); ctx.addLine(to: CGPoint(x: 62, y: 94)); ctx.addLine(to: CGPoint(x: 102, y: 48))
        ctx.strokePath()
    }

    static let shard = texture(CGSize(width: 48, height: 48)) { ctx, _ in
        UIColor.white.setFill()
        ctx.move(to: CGPoint(x: 4, y: 44)); ctx.addLine(to: CGPoint(x: 24, y: 4)); ctx.addLine(to: CGPoint(x: 44, y: 36)); ctx.closePath()
        ctx.fillPath()
    }

    static let star = texture(CGSize(width: 64, height: 64)) { ctx, size in
        let path = UIBezierPath()
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 30 : 13
            let a = CGFloat(i) * .pi / 5 - .pi / 2
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.close()
        UIColor.white.setFill()
        ctx.addPath(path.cgPath); ctx.fillPath()
    }

    static let pad = texture(CGSize(width: 440, height: 150)) { ctx, size in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 16)
        ctx.setShadow(offset: .zero, blur: 14, color: UIColor.white.cgColor)
        UIColor.white.withAlphaComponent(0.22).setFill()
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(9)
        ctx.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: rect.insetBy(dx: 40, dy: 22))
    }

    static let pill = texture(CGSize(width: 64, height: 32)) { ctx, size in
        UIColor.white.setFill()
        ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).cgPath)
        ctx.fillPath()
    }

    static func card(color: UIColor) -> SKTexture {
        texture(CGSize(width: 520, height: 210)) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 14)
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: 36)
            ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 0, color: Palette.deepNavy.withAlphaComponent(0.7).cgColor)
            color.setFill()
            ctx.addPath(shape.cgPath); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.withAlphaComponent(0.18).setFill()
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: rect.minX + 10, y: rect.minY + 8, width: rect.width - 20, height: rect.height * 0.42), cornerRadius: 28).cgPath)
            ctx.fillPath()
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(7)
            ctx.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 3.5, dy: 3.5), cornerRadius: 33).cgPath)
            ctx.strokePath()
        }
    }

    /// Cartoon stand-in shown before the camera cutout is available (and in the Simulator).
    static func placeholder(color: UIColor, child: Bool) -> SKTexture {
        let size = child ? CGSize(width: 220, height: 380) : CGSize(width: 240, height: 520)
        return texture(size) { ctx, size in
            let w = size.width, h = size.height
            let head = child ? 120.0 : 110.0
            let outline = Palette.deepNavy.cgColor
            ctx.setLineWidth(9)
            ctx.setStrokeColor(outline)
            ctx.setLineCap(.round)
            // Legs.
            color.withAlphaComponent(1).setStroke()
            let legTop = h * (child ? 0.62 : 0.58)
            for dx in [-0.16, 0.16] {
                ctx.setStrokeColor(outline); ctx.setLineWidth(child ? 44 : 50)
                ctx.move(to: CGPoint(x: w / 2 + w * dx, y: legTop)); ctx.addLine(to: CGPoint(x: w / 2 + w * dx * 1.2, y: h - 26)); ctx.strokePath()
                ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(child ? 32 : 38)
                ctx.move(to: CGPoint(x: w / 2 + w * dx, y: legTop)); ctx.addLine(to: CGPoint(x: w / 2 + w * dx * 1.2, y: h - 26)); ctx.strokePath()
            }
            // Arms.
            for dx in [-1.0, 1.0] {
                ctx.setStrokeColor(outline); ctx.setLineWidth(36)
                ctx.move(to: CGPoint(x: w / 2 + dx * w * 0.2, y: head + 30)); ctx.addLine(to: CGPoint(x: w / 2 + dx * w * 0.38, y: legTop - 10)); ctx.strokePath()
                ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(24)
                ctx.move(to: CGPoint(x: w / 2 + dx * w * 0.2, y: head + 30)); ctx.addLine(to: CGPoint(x: w / 2 + dx * w * 0.38, y: legTop - 10)); ctx.strokePath()
            }
            // Torso.
            let torso = UIBezierPath(roundedRect: CGRect(x: w * 0.24, y: head - 6, width: w * 0.52, height: legTop - head + 30), cornerRadius: w * 0.2)
            color.setFill(); ctx.addPath(torso.cgPath); ctx.fillPath()
            ctx.setStrokeColor(outline); ctx.setLineWidth(9); ctx.addPath(torso.cgPath); ctx.strokePath()
            UIColor.white.withAlphaComponent(0.25).setFill()
            ctx.fillEllipse(in: CGRect(x: w * 0.34, y: head + 14, width: w * 0.32, height: (legTop - head) * 0.5))
            // Head.
            let headRect = CGRect(x: w / 2 - head / 2, y: 6, width: head, height: head)
            color.setFill(); ctx.fillEllipse(in: headRect)
            ctx.strokeEllipse(in: headRect)
            UIColor.white.setFill()
            for dx in [-0.18, 0.18] { ctx.fillEllipse(in: CGRect(x: w / 2 + head * dx - 11, y: head * 0.42, width: 22, height: 26)) }
            Palette.deepNavy.setFill()
            for dx in [-0.18, 0.18] { ctx.fillEllipse(in: CGRect(x: w / 2 + head * dx - 5, y: head * 0.47, width: 11, height: 14)) }
            ctx.setStrokeColor(outline); ctx.setLineWidth(6)
            ctx.addArc(center: CGPoint(x: w / 2, y: head * 0.66), radius: head * 0.14, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: false)
            ctx.strokePath()
        }
    }

    // MARK: Helpers

    private static func drawChevrons(_ ctx: CGContext, in rect: CGRect, count: Int, lineWidth: CGFloat) {
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let step = rect.height / CGFloat(count + 1)
        for i in 0..<count {
            let y = rect.minY + step * CGFloat(i) + lineWidth / 2
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.midX, y: y + step * 0.95))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.strokePath()
        }
    }

    private static func fillGradient(_ ctx: CGContext, rect: CGRect, colors: [UIColor], vertical: Bool, radius: CGFloat) {
        ctx.saveGState()
        if radius > 0 { ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath); ctx.clip() } else { ctx.clip(to: rect) }
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
        let end = vertical ? CGPoint(x: rect.minX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.minY)
        ctx.drawLinearGradient(gradient, start: rect.origin, end: end, options: [])
        ctx.restoreGState()
    }

    private static func texture(_ size: CGSize, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}

/// Deterministic generator so procedural art looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}
