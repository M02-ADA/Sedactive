// Offline bake for the TEAM DUCK hero moment (macOS only, not part of the app).
//
// Renders the gate beam shattering into lit, rotating 3D chunks with RealityKit's RealityRenderer — tone mapping off,
// transparent background, 4× temporal supersampling for baked motion blur — from the *same camera* as the game
// (camera 1.0 above the roof, player plane 1.9, 58° vertical FOV, 3.8° pitch). Output: one sprite sheet PNG plus
// JSON metadata the SpriteKit scene uses to place the frames in screen space. Deterministic (seeded).
//
// Build & run:  ./Tools/BakeTeamDuck/bake.sh
import CoreGraphics
import Foundation
import ImageIO
import Metal
import RealityKit
import UniformTypeIdentifiers

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let screen = (w: 1376, h: 1032)                  // iPad Pro 13" landscape points; scene = 4:3
let renderScale = 1.0
let outputScale = 0.5                           // stored frames are half-resolution
let fps = 30.0, frameCount = 15, subframes = 4  // 0.5 s
let camH: Float = 1.0, beamY: Float = 1.62
/// Where the beam is when it breaks: 0.3 s before reaching the players (z 1.9) at cruise 10 m/s (EncounterTiming.impactLead).
let zp: Float = 1.9 + 10 * 0.3

struct Rng { var s: UInt64; mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 33) & 0xFFFFFF) / Float(0xFFFFFF) } }
var rng = Rng(s: 2026)
@MainActor func rand(_ a: Float, _ b: Float) -> Float { a + (b - a) * rng.next() }

@MainActor func stripeTexture() throws -> TextureResource {
    let w = 256, h = 64
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.055, green: 0.063, blue: 0.20, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.82, blue: 0.25, alpha: 1))
    var x = -64.0
    while x < Double(w) + 64 {
        ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x + 32, y: 0))
        ctx.addLine(to: CGPoint(x: x + 64, y: Double(h))); ctx.addLine(to: CGPoint(x: x + 32, y: Double(h))); ctx.closePath(); ctx.fillPath()
        x += 64
    }
    return try TextureResource(image: ctx.makeImage()!, options: .init(semantic: .color))
}

final class DoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

struct Chunk { let entity: ModelEntity; var p: SIMD3<Float>; var v: SIMD3<Float>; let axis: SIMD3<Float>; let spin: Float; var angle: Float = 0 }

@MainActor func run() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("no Metal") }
    let renderer = try RealityRenderer()
    renderer.cameraSettings.isToneMappingEnabled = false   // keep the arcade palette exact
    renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
    renderer.cameraSettings.antialiasing = .multisample4X

    let root = Entity()
    let camera = PerspectiveCamera()
    camera.camera.fieldOfViewInDegrees = 58
    camera.camera.fieldOfViewOrientation = .vertical
    camera.camera.near = 0.05
    camera.position = [0, camH, 0]
    camera.orientation = simd_quatf(angle: -3.8 * .pi / 180, axis: [1, 0, 0])
    root.addChild(camera)
    let key = DirectionalLight(); key.light.intensity = 9000; key.light.color = .init(red: 1, green: 0.9, blue: 0.85, alpha: 1)
    key.look(at: [0, beamY, -zp], from: [3, 6, 3], relativeTo: nil); root.addChild(key)
    let rim = DirectionalLight(); rim.light.intensity = 6000; rim.light.color = .init(red: 0.55, green: 0.45, blue: 1, alpha: 1)
    rim.look(at: [0, beamY, -zp], from: [-4, 2, -8], relativeTo: nil); root.addChild(rim)

    // Beam 5.1 × 0.45 × 0.35, split into 11 irregular columns × 2 rows. Left half glows coral, right half teal:
    // the debris literally carries both players' colours.
    let stripes = try stripeTexture()
    func material(_ tint: (Double, Double, Double)) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(stripes))
        m.roughness = 0.35; m.metallic = 0.2
        m.emissiveColor = .init(color: .init(red: tint.0, green: tint.1, blue: tint.2, alpha: 1)); m.emissiveIntensity = 0.3
        return m
    }
    let coral = material((1.0, 0.42, 0.37)), teal = material((0.10, 0.83, 0.77))
    var chunks: [Chunk] = []
    var edges: [Float] = [-2.55]
    for i in 1..<11 { edges.append(-2.55 + Float(i) * 0.4636 + rand(-0.12, 0.12)) }
    edges.append(2.55)
    for c in 0..<11 {
        for r in 0..<2 {
            let w = edges[c + 1] - edges[c] - 0.02
            let x = (edges[c] + edges[c + 1]) / 2
            let y = beamY + (r == 0 ? -0.112 : 0.112)
            let box = ModelEntity(mesh: .generateBox(width: w, height: 0.22, depth: 0.35, cornerRadius: 0.025), materials: [x < 0 ? coral : teal])
            root.addChild(box)
            // The gate is fixed to the track and the train carries the players through it, so the pieces keep
            // that relative motion: past the players toward the camera (+z, ~10 m/s), bursting up and outward so
            // they leave through the top and sides of the frame and never retreat into the distance.
            let outward = x / 2.55
            let v: SIMD3<Float> = [outward * rand(2.0, 4.0) + rand(-0.4, 0.4), rand(1.8, 4.2) + (r == 1 ? 0.8 : 0), rand(8, 12)]
            let axis = simd_normalize(SIMD3<Float>(rand(-1, 1), rand(-1, 1), rand(-1, 1)))
            chunks.append(Chunk(entity: box, p: [x, y, -zp], v: v, axis: axis, spin: rand(5, 11)))
        }
    }
    var sparkMat = UnlitMaterial(color: .init(red: 1, green: 0.95, blue: 0.7, alpha: 1)); sparkMat.blending = .opaque
    for _ in 0..<14 {
        let s = ModelEntity(mesh: .generateBox(size: 0.05), materials: [sparkMat])
        root.addChild(s)
        let x = rand(-2.3, 2.3)
        chunks.append(Chunk(entity: s, p: [x, beamY, -zp], v: [x * rand(1, 3), rand(1, 4), rand(8, 12)], axis: [0, 0, 1], spin: rand(10, 20)))
    }
    renderer.entities.append(root)
    renderer.activeCamera = camera

    let rw = Int(Double(screen.w) * renderScale), rh = Int(Double(screen.h) * renderScale)
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: rw, height: rh, mipmapped: false)
    desc.usage = [.renderTarget, .shaderRead]
    desc.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: desc) else { fatalError("texture") }
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))

    let dt = Float(1 / (fps * Double(subframes)))
    var frames: [[Float]] = []
    for _ in 0..<frameCount {
        var accum = [Float](repeating: 0, count: rw * rh * 4)
        for _ in 0..<subframes {
            for i in chunks.indices {
                chunks[i].v.y -= 6 * dt
                chunks[i].p += chunks[i].v * dt
                chunks[i].angle += chunks[i].spin * dt
                chunks[i].entity.position = chunks[i].p
                chunks[i].entity.orientation = simd_quatf(angle: chunks[i].angle, axis: chunks[i].axis)
            }
            let done = DoneFlag()
            try renderer.updateAndRender(deltaTime: Double(dt), cameraOutput: output, onComplete: { _ in done.set() })
            while !done.isSet { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
            var bytes = [UInt8](repeating: 0, count: rw * rh * 4)
            texture.getBytes(&bytes, bytesPerRow: rw * 4, from: MTLRegionMake2D(0, 0, rw, rh), mipmapLevel: 0)
            for k in 0..<bytes.count { accum[k] += Float(bytes[k]) }
        }
        frames.append(accum.map { $0 / Float(subframes) })
    }
    _ = queue

    // Union bounding box of visible pixels across frames, then crop + downscale + pack into one sheet.
    var minX = rw, minY = rh, maxX = 0, maxY = 0
    for f in frames {
        for y in stride(from: 0, to: rh, by: 2) {
            for x in stride(from: 0, to: rw, by: 2) where f[(y * rw + x) * 4 + 3] > 6 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    minX = max(0, minX - 4); minY = max(0, minY - 4); maxX = min(rw - 1, maxX + 4); maxY = min(rh - 1, maxY + 4)
    let cropW = maxX - minX + 1, cropH = maxY - minY + 1
    let fw = Int(Double(cropW) * outputScale), fh = Int(Double(cropH) * outputScale)
    let cols = 6, rows = (frameCount + cols - 1) / cols
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sheet = CGContext(data: nil, width: fw * cols, height: fh * rows, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    sheet.interpolationQuality = .high
    for (i, f) in frames.enumerated() {
        var bytes = [UInt8](repeating: 0, count: cropW * cropH * 4)
        for y in 0..<cropH {
            for x in 0..<cropW {
                let s = ((y + minY) * rw + (x + minX)) * 4, d = (y * cropW + x) * 4
                for k in 0..<4 { bytes[d + k] = UInt8(max(0, min(255, f[s + k].rounded()))) }
            }
        }
        let frameCtx = CGContext(data: &bytes, width: cropW, height: cropH, bitsPerComponent: 8, bytesPerRow: cropW * 4,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = frameCtx.makeImage()!
        let col = i % cols, row = i / cols
        // CGContext origin is bottom-left; put frame 0 in the top-left cell.
        sheet.draw(image, in: CGRect(x: col * fw, y: (rows - 1 - row) * fh, width: fw, height: fh))
    }
    let url = outputDir.appendingPathComponent("TeamDuckShatter.png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, sheet.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    // Metal texture rows are top-first, so minY is measured from the top of the screen.
    let meta: [String: Any] = [
        "frames": frameCount, "cols": cols, "rows": rows, "fps": fps,
        "frameWidth": fw, "frameHeight": fh,
        "screenWidth": rw, "screenHeight": rh,
        "originX": Double(minX) / Double(rw), "originTop": Double(minY) / Double(rh),
        "width": Double(cropW) / Double(rw), "height": Double(cropH) / Double(rh),
    ]
    try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        .write(to: outputDir.appendingPathComponent("TeamDuckShatter.json"))
    print("baked \(frameCount) frames \(fw)x\(fh) sheet \(fw * cols)x\(fh * rows), crop origin (\(minX),\(minY)) size \(cropW)x\(cropH)")
}

MainActor.assumeIsolated {
    do { try run() } catch { print("bake failed: \(error)"); exit(1) }
}
