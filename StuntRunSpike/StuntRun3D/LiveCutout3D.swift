import Metal
import QuartzCore
import RealityKit

/// Compositing probe (`-liveTexture YES`): the existing CameraPipeline output (cutout on device, synthetic test card
/// in the Simulator) streamed into the 3D world every frame via LowLevelTexture + a Metal blit, on a plane at the
/// player depth. Because the bodies live *inside* the scene, 3D objects occlude them correctly — the property a
/// layered (3D background / 2D bodies / overlay) stack cannot give. Measures the per-frame upload cost.
@MainActor
final class LiveCutout3D {
    let pipeline = CameraPipeline()
    let plane: ModelEntity
    private let texture: LowLevelTexture
    private let queue: MTLCommandQueue
    private var staging: [MTLBuffer]
    private var nextStaging = 0
    private let scratch: UnsafeMutableRawPointer
    private var lastSequence: UInt64 = 0
    private(set) var uploadMs: [Double] = []
    private(set) var uploads = 0

    private let width = CameraPipeline.outputWidth
    private let height = CameraPipeline.outputHeight

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        var descriptor = LowLevelTexture.Descriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm_srgb
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = 1
        descriptor.mipmapLevelCount = 1
        descriptor.textureUsage = [.shaderRead, .shaderWrite]
        guard let texture = try? LowLevelTexture(descriptor: descriptor),
              let resource = try? TextureResource(from: texture) else { return nil }
        let bytes = width * height * 4
        guard let a = device.makeBuffer(length: bytes, options: .storageModeShared),
              let b = device.makeBuffer(length: bytes, options: .storageModeShared) else { return nil }
        self.texture = texture
        self.queue = queue
        staging = [a, b]
        scratch = .allocate(byteCount: bytes, alignment: 64)
        var material = UnlitMaterial()
        material.color = .init(texture: .init(resource))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        plane = ModelEntity(mesh: .generatePlane(width: 2.6, height: 1.95), materials: [material])
        plane.components.set(DynamicLightShadowComponent(castsShadow: false))
    }

    func start() {
        pipeline.wantsCutout = true
        Task { _ = await pipeline.start() }
    }

    /// Called from the RealityKit update loop; uploads only when the pipeline has a new frame.
    func update() {
        guard let snapshot = pipeline.store.latest(), snapshot.sequence != lastSequence else { return }
        lastSequence = snapshot.sequence
        let start = CACurrentMediaTime()
        let rowBytes = width * 4
        pipeline.store.copyFront(to: scratch, length: rowBytes * height)
        // FrameStore rows are bottom-first (SpriteKit convention); Metal textures are top-first.
        let buffer = staging[nextStaging]
        nextStaging = (nextStaging + 1) % staging.count
        let destination = buffer.contents()
        for row in 0..<height {
            memcpy(destination + row * rowBytes, scratch + (height - 1 - row) * rowBytes, rowBytes)
        }
        guard let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        let target = texture.replace(using: commandBuffer)
        blit.copy(from: buffer, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * height,
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: target,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
        uploads += 1
        uploadMs.append((CACurrentMediaTime() - start) * 1000)
        if uploadMs.count > 300 { uploadMs.removeFirst(uploadMs.count - 300) }
    }
}
