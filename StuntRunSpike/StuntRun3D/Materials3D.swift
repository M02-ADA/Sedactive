import RealityKit
import SpriteKit
import UIKit

/// Procedural textures and materials for the 3D experiment. Reuses the 2.5D art (via `SKTexture.cgImage()`)
/// so both renderers share one visual identity; nothing here is a modeled asset.
@MainActor
enum Mat3D {
    static func texture(_ sk: SKTexture) -> TextureResource? {
        guard let cg = srgb8(sk.cgImage()) else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    /// UIKit renders wide-colour, extended-range images on modern devices; RealityKit then mis-reads them and the
    /// darks wash out to lavender-grey. Redraw into plain 8-bit sRGB first.
    static func srgb8(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    static func texture(size: CGSize, draw: (CGContext, CGSize) -> Void) -> TextureResource? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        guard let source = image.cgImage, let cg = srgb8(source) else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    static func lit(_ color: UIColor, roughness: Float = 0.55, metallic: Float = 0.1,
                    emissive: UIColor? = nil, intensity: Float = 1, texture: TextureResource? = nil,
                    emissiveTexture: TextureResource? = nil) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let texture {
            m.baseColor = .init(tint: color, texture: .init(texture))
        } else {
            m.baseColor = .init(tint: color)
        }
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        // Low specular: the default environment reflection otherwise greys out every stylised colour.
        m.specular = .init(floatLiteral: 0.15)
        if let emissive {
            if let emissiveTexture {
                m.emissiveColor = .init(color: emissive, texture: .init(emissiveTexture))
            } else {
                m.emissiveColor = .init(color: emissive)
            }
            m.emissiveIntensity = intensity
        }
        return m
    }

    /// Self-lit neon: used for rails, rings, orbs and lane cues (RealityKit on iOS has no bloom, so glow is
    /// carried by emissive colour plus additive halo planes).
    static func neon(_ color: UIColor, alpha: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial(color: color)
        if alpha < 1 { m.blending = .transparent(opacity: .init(floatLiteral: alpha)) }
        return m
    }

    static func sprite(_ texture: TextureResource?, tint: UIColor = .white, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let texture {
            m.color = .init(tint: tint, texture: .init(texture))
        } else {
            m.color = .init(tint: tint)
        }
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }

    // MARK: Procedural tiles

    /// One 3-unit roof tile: panel seam, centre dash, hazard chevrons, yellow rails and two runway lights.
    static let roofTile = texture(size: CGSize(width: 512, height: 480)) { ctx, size in
        let w = size.width, h = size.height
        UIColor(red: 0.19, green: 0.13, blue: 0.42, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor(red: 0.05, green: 0.04, blue: 0.13, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 8))
        Palette.teal.setFill()
        ctx.fill(CGRect(x: w / 2 - 7, y: 40, width: 14, height: h * 0.5))
        for side in [0.0, 1.0] {
            let x0 = side == 0 ? w * 0.06 : w * 0.80
            for i in 0..<4 {
                (i % 2 == 0 ? Palette.coral : Palette.navy).setFill()
                let y = CGFloat(i) * h / 4
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x0, y: y)); path.addLine(to: CGPoint(x: x0 + w * 0.14, y: y + h / 8))
                path.addLine(to: CGPoint(x: x0, y: y + h / 4)); path.close()
                ctx.addPath(path.cgPath); ctx.fillPath()
            }
            Palette.yellow.setFill()
            ctx.fill(CGRect(x: side == 0 ? w * 0.02 : w * 0.95, y: 0, width: 14, height: h))
            Palette.yellow.withAlphaComponent(0.95).setFill()
            ctx.fillEllipse(in: CGRect(x: side == 0 ? w * 0.27 : w * 0.68, y: h / 2 - 14, width: 28, height: 28))
        }
    }

    static let groundTile = texture(size: CGSize(width: 512, height: 512)) { ctx, size in
        UIColor(red: 0.05, green: 0.04, blue: 0.17, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor(red: 0.66, green: 0.32, blue: 1.0, alpha: 0.9).setFill()
        for i in 0..<4 {
            ctx.fill(CGRect(x: CGFloat(i) * 128, y: 0, width: 5, height: size.height))
            ctx.fill(CGRect(x: 0, y: CGFloat(i) * 128, width: size.width, height: 5))
        }
    }

    /// Equirectangular dusk gradient with stars; only varies vertically, so sphere UV orientation does not matter.
    static let sky = texture(size: CGSize(width: 1024, height: 1024)) { ctx, size in
        let colors = [UIColor(red: 0.02, green: 0.03, blue: 0.12, alpha: 1).cgColor,
                      UIColor(red: 0.04, green: 0.05, blue: 0.18, alpha: 1).cgColor,
                      UIColor(red: 0.32, green: 0.14, blue: 0.58, alpha: 1).cgColor,
                      UIColor(red: 1.0, green: 0.47, blue: 0.42, alpha: 1).cgColor,
                      UIColor(red: 0.06, green: 0.04, blue: 0.16, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 0.42, 0.5, 0.56])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
        var rng = SeededRandom(seed: 5)
        UIColor.white.setFill()
        for _ in 0..<260 {
            let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height * 0.4)
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 2.5, height: 2.5))
        }
    }

    static let sun = texture(size: CGSize(width: 512, height: 512)) { ctx, size in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
        ctx.saveGState()
        ctx.addEllipse(in: rect); ctx.clip()
        let colors = [Palette.yellow.cgColor, UIColor(red: 1.0, green: 0.36, blue: 0.48, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        ctx.setBlendMode(.clear)
        for i in 0..<6 {
            let y = rect.midY + CGFloat(i) * 38 + 10
            ctx.fill(CGRect(x: 0, y: y, width: size.width, height: CGFloat(4 + i * 3)))
        }
        ctx.restoreGState()
    }
}
