import SpriteKit
import UIKit

/// Set-piece and atmosphere art for the environment pass. Same procedural pipeline and palette as `Art`.
@MainActor
extension Art {
    /// Hollow neon ring for tunnel sections (white core, tinted per ring).
    static let ring = drawn(CGSize(width: 512, height: 512)) { ctx, size in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 40, dy: 40)
        ctx.setShadow(offset: .zero, blur: 26, color: UIColor.white.cgColor)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(34)
        ctx.strokeEllipse(in: rect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: rect)
        // Segment ticks make the ring's rotation readable.
        ctx.setLineWidth(18)
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = rect.width / 2
            ctx.move(to: CGPoint(x: c.x + cos(a) * (r - 22), y: c.y + sin(a) * (r - 22)))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * (r + 22), y: c.y + sin(a) * (r + 22)))
            ctx.strokePath()
        }
    }

    /// Soft dark band used for shadows cast onto the roof.
    static let shadowBand = drawn(CGSize(width: 64, height: 64)) { ctx, size in
        let colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.cgColor, UIColor.black.cgColor,
                      UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 0.7, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }

    static let searchlight = drawn(CGSize(width: 160, height: 512)) { ctx, size in
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size.width / 2 - 6, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: size.width / 2 + 6, y: size.height))
        path.close()
        ctx.addPath(path.cgPath)
        ctx.clip()
        let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.9).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }

    static let ferrisWheel = drawn(CGSize(width: 900, height: 900)) { ctx, size in
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = 400
        ctx.setLineCap(.round)
        ctx.setStrokeColor(UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1).cgColor)
        ctx.setLineWidth(8)
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi
            ctx.move(to: c)
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            ctx.strokePath()
        }
        ctx.setShadow(offset: .zero, blur: 18, color: Palette.coral.cgColor)
        ctx.setStrokeColor(Palette.coral.cgColor)
        ctx.setLineWidth(20)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.setStrokeColor(Palette.yellow.cgColor)
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: 2 * r * 0.62, height: 2 * r * 0.62))
        let gondolaColors = [Palette.teal, Palette.yellow, Palette.coral, Palette.violet]
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            gondolaColors[i % 4].setFill()
            ctx.setShadow(offset: .zero, blur: 14, color: gondolaColors[i % 4].cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52))
            UIColor.white.setFill()
            ctx.fillEllipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
        }
        Palette.yellow.setFill()
        ctx.fillEllipse(in: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68))
    }

    static let ferrisSupport = drawn(CGSize(width: 600, height: 520)) { ctx, size in
        ctx.setLineCap(.round)
        ctx.setStrokeColor(UIColor(red: 0.20, green: 0.15, blue: 0.48, alpha: 1).cgColor)
        ctx.setLineWidth(30)
        let hub = CGPoint(x: size.width / 2, y: 20)
        for x in [60.0, 540.0] {
            ctx.move(to: hub); ctx.addLine(to: CGPoint(x: x, y: size.height - 10)); ctx.strokePath()
        }
        ctx.setLineWidth(14)
        ctx.move(to: CGPoint(x: 170, y: 330)); ctx.addLine(to: CGPoint(x: 430, y: 330)); ctx.strokePath()
        UIColor(red: 0.12, green: 0.09, blue: 0.32, alpha: 1).setFill()
        ctx.fill(CGRect(x: 30, y: size.height - 40, width: size.width - 60, height: 40))
    }

    static let signTower = drawn(CGSize(width: 200, height: 1000)) { ctx, size in
        let body = CGRect(x: 50, y: 0, width: 100, height: size.height)
        UIColor(red: 0.14, green: 0.11, blue: 0.38, alpha: 1).setFill()
        ctx.fill(body)
        ctx.setStrokeColor(UIColor(red: 0.40, green: 0.30, blue: 0.85, alpha: 1).cgColor)
        ctx.setLineWidth(6)
        var y: CGFloat = 0
        while y < size.height {
            ctx.move(to: CGPoint(x: 50, y: y)); ctx.addLine(to: CGPoint(x: 150, y: y + 60))
            ctx.move(to: CGPoint(x: 150, y: y)); ctx.addLine(to: CGPoint(x: 50, y: y + 60))
            ctx.strokePath()
            y += 60
        }
        for i in stride(from: 40, to: Int(size.height), by: 120) {
            Palette.coral.setFill()
            ctx.fillEllipse(in: CGRect(x: 88, y: CGFloat(i), width: 24, height: 24))
        }
    }

    static let stuntRunSign = drawn(CGSize(width: 1000, height: 460)) { ctx, size in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 16)
        let shape = UIBezierPath(roundedRect: rect, cornerRadius: 60)
        Palette.navy.setFill()
        ctx.addPath(shape.cgPath); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 24, color: Palette.teal.cgColor)
        ctx.setStrokeColor(Palette.teal.cgColor)
        ctx.setLineWidth(14)
        ctx.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 14, dy: 14), cornerRadius: 50).cgPath)
        ctx.strokePath()
        let font = UIFont(name: "AvenirNext-HeavyItalic", size: 150) ?? .systemFont(ofSize: 150, weight: .black)
        ctx.setShadow(offset: .zero, blur: 22, color: Palette.coral.cgColor)
        let text = NSAttributedString(string: "STUNT RUN", attributes: [
            .font: font, .foregroundColor: Palette.yellow, .strokeColor: Palette.coral, .strokeWidth: -3,
        ])
        let textSize = text.size()
        text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 - 10))
    }

    static let bridge = drawn(CGSize(width: 1600, height: 900)) { ctx, size in
        let deckTop: CGFloat = 330, deckBottom: CGFloat = 450
        let towerColor = UIColor(red: 0.18, green: 0.13, blue: 0.44, alpha: 1)
        // Towers.
        for x in [180.0, 1420.0] {
            towerColor.setFill()
            ctx.fill(CGRect(x: x - 40, y: 0, width: 80, height: size.height))
            Palette.coral.setFill()
            ctx.fill(CGRect(x: x - 40, y: 0, width: 80, height: 22))
            ctx.setShadow(offset: .zero, blur: 16, color: Palette.coral.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 14, y: 34, width: 28, height: 28))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        // Suspension cables.
        ctx.setStrokeColor(Palette.teal.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(8)
        ctx.move(to: CGPoint(x: 180, y: 40))
        ctx.addQuadCurve(to: CGPoint(x: 1420, y: 40), control: CGPoint(x: 800, y: deckTop + 120))
        ctx.strokePath()
        ctx.setLineWidth(3)
        for i in 1..<24 {
            let x = 180 + CGFloat(i) * (1240 / 24)
            let t = (x - 180) / 1240
            let cableY = (1 - t) * (1 - t) * 40 + 2 * (1 - t) * t * (deckTop + 120) + t * t * 40
            ctx.move(to: CGPoint(x: x, y: cableY)); ctx.addLine(to: CGPoint(x: x, y: deckTop)); ctx.strokePath()
        }
        // Truss deck.
        let deck = CGRect(x: 0, y: deckTop, width: size.width, height: deckBottom - deckTop)
        towerColor.setFill(); ctx.fill(deck)
        ctx.setStrokeColor(UIColor(red: 0.45, green: 0.32, blue: 0.95, alpha: 1).cgColor)
        ctx.setLineWidth(7)
        var x: CGFloat = 0
        while x < size.width {
            ctx.move(to: CGPoint(x: x, y: deckBottom)); ctx.addLine(to: CGPoint(x: x + 60, y: deckTop))
            ctx.addLine(to: CGPoint(x: x + 120, y: deckBottom)); ctx.strokePath()
            x += 120
        }
        Palette.yellow.setFill()
        ctx.fill(CGRect(x: 0, y: deckBottom - 10, width: size.width, height: 10))
        for i in stride(from: 30, to: Int(size.width), by: 80) {
            Palette.teal.setFill()
            ctx.fillEllipse(in: CGRect(x: CGFloat(i), y: deckTop + 8, width: 14, height: 14))
        }
    }

    /// Rear of the lead locomotive, seen from the carriages behind it: red tail lights and a glowing cab read as
    /// "the front of our train, pulling us toward the horizon".
    static let locomotiveRear = drawn(CGSize(width: 640, height: 300)) { ctx, size in
        let w = size.width, h = size.height
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 12, y: h))
        body.addLine(to: CGPoint(x: 12, y: h * 0.42))
        body.addCurve(to: CGPoint(x: w - 12, y: h * 0.42), controlPoint1: CGPoint(x: 40, y: -h * 0.12), controlPoint2: CGPoint(x: w - 40, y: -h * 0.12))
        body.addLine(to: CGPoint(x: w - 12, y: h))
        body.close()
        ctx.saveGState()
        ctx.addPath(body.cgPath); ctx.clip()
        let colors = [UIColor(red: 0.30, green: 0.20, blue: 0.62, alpha: 1).cgColor, UIColor(red: 0.10, green: 0.08, blue: 0.28, alpha: 1).cgColor] as CFArray
        ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!,
                               start: .zero, end: CGPoint(x: 0, y: h), options: [])
        Palette.coral.setFill()
        ctx.fill(CGRect(x: 0, y: h * 0.62, width: w, height: 16))
        Palette.yellow.setFill()
        ctx.fill(CGRect(x: 0, y: h * 0.62 + 16, width: w, height: 5))
        // Rear cab window glow.
        UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.9).setFill()
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: w * 0.3, y: h * 0.2, width: w * 0.4, height: h * 0.2), cornerRadius: 14).cgPath)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.setStrokeColor(Palette.deepNavy.cgColor)
        ctx.setLineWidth(8)
        ctx.addPath(body.cgPath); ctx.strokePath()
        // Tail lights.
        for x in [w * 0.12, w * 0.88] {
            ctx.setShadow(offset: .zero, blur: 22, color: UIColor.red.cgColor)
            UIColor(red: 1.0, green: 0.15, blue: 0.2, alpha: 1).setFill()
            ctx.fillEllipse(in: CGRect(x: x - 26, y: h * 0.74, width: 52, height: 40))
            UIColor(red: 1.0, green: 0.7, blue: 0.7, alpha: 1).setFill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.fillEllipse(in: CGRect(x: x - 10, y: h * 0.74 + 10, width: 20, height: 16))
        }
    }

    static func drawn(_ size: CGSize, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
