import AVFoundation
import CoreImage
import QuartzCore
import UIKit
import Vision

nonisolated struct PipelineStats: Sendable {
    var poseMs = 0.0
    var segmentationMs = 0.0
    var compositeMs = 0.0
    var totalMs = 0.0
    var droppedFrames = 0
    var maskWidth = 0
    var maskHeight = 0
    var sourceWidth = 0
    var sourceHeight = 0
}

nonisolated struct VisionSnapshot: Sendable {
    var sequence: UInt64
    /// Host time (CACurrentMediaTime clock) at which the camera captured the frame.
    var captureTime: Double
    var completedTime: Double
    var people: [PersonPose]
    var hasCutout: Bool
    var stats: PipelineStats
}

/// Double-buffered RGBA pixels shared between the processing queue (writer) and the render loop (reader).
/// Only the newest frame is kept; the writer never waits on the renderer except for a pointer swap.
nonisolated final class FrameStore: @unchecked Sendable {
    let width: Int
    let height: Int
    var byteCount: Int { width * height * 4 }

    private let lock = NSLock()
    private var front: UnsafeMutableRawPointer
    /// Written only from the processing queue.
    private(set) var back: UnsafeMutableRawPointer
    private var snapshot: VisionSnapshot?

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        front = .allocate(byteCount: width * height * 4, alignment: 64)
        back = .allocate(byteCount: width * height * 4, alignment: 64)
        front.initializeMemory(as: UInt8.self, repeating: 0, count: width * height * 4)
        back.initializeMemory(as: UInt8.self, repeating: 0, count: width * height * 4)
    }

    deinit {
        front.deallocate()
        back.deallocate()
    }

    func publish(_ snap: VisionSnapshot) {
        lock.lock()
        swap(&front, &back)
        snapshot = snap
        lock.unlock()
    }

    func latest() -> VisionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func copyFront(to destination: UnsafeMutableRawPointer, length: Int) {
        lock.lock()
        memcpy(destination, front, min(length, byteCount))
        lock.unlock()
    }
}

/// Front camera → Vision (body pose + person segmentation) → Core Image cutout → FrameStore.
///
/// Bounded by construction: the sample-buffer delegate runs on one serial queue, the output discards
/// late frames, and all Vision work happens synchronously inside the callback. At most one frame is
/// in flight; stale frames are dropped by AVFoundation instead of queuing up.
nonisolated final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Source: Sendable { case none, camera, synthetic }

    static let outputWidth = 640
    static let outputHeight = 480

    let store = FrameStore(width: CameraPipeline.outputWidth, height: CameraPipeline.outputHeight)

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "stuntrun.camera-vision", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let sequenceHandler = VNSequenceRequestHandler()
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var syntheticTimer: DispatchSourceTimer?
    private var syntheticPool: CVPixelBufferPool?
    private var syntheticCard: CGImage?

    private let settingsLock = NSLock()
    private var _wantsCutout = true
    private var _rimColorsSwapped = false
    private var _quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced

    private var isConfigured = false

    // Processing-queue state.
    private var sequence: UInt64 = 0
    private var droppedFrames = 0
    private var rimImages: (normal: CIImage, swapped: CIImage)

    var wantsCutout: Bool {
        get { settingsLock.withLock { _wantsCutout } }
        set { settingsLock.withLock { _wantsCutout = newValue } }
    }

    var rimColorsSwapped: Bool {
        get { settingsLock.withLock { _rimColorsSwapped } }
        set { settingsLock.withLock { _rimColorsSwapped = newValue } }
    }

    /// Degrade to `.fast` under thermal pressure.
    var segmentationQuality: VNGeneratePersonSegmentationRequest.QualityLevel {
        get { settingsLock.withLock { _quality } }
        set { settingsLock.withLock { _quality = newValue } }
    }

    override init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "StuntRunCutout"])
        } else {
            ciContext = CIContext(options: [.cacheIntermediates: false])
        }
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        rimImages = Self.makeRimImages(width: CameraPipeline.outputWidth, height: CameraPipeline.outputHeight)
        super.init()
    }

    // MARK: - Start / stop

    func start() async -> Source {
        #if targetEnvironment(simulator)
        let card = await Self.makeTestCard(width: 640, height: 480)
        queue.async { if self.syntheticTimer == nil { self.startSynthetic(card: card) } }
        return .synthetic
        #else
        if isConfigured {
            queue.async { if !self.session.isRunning { self.session.startRunning() } }
            return .camera
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        switch status {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { return .none }
        let configured = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.configureSession()) }
        }
        guard configured else { return .none }
        isConfigured = true
        queue.async { self.session.startRunning() }
        return .camera
        #endif
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.syntheticTimer?.cancel()
            self.syntheticTimer = nil
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .external],
            mediaType: .video, position: .unspecified)
        let device = discovery.devices.first { $0.position == .front } ?? discovery.devices.first ?? AVCaptureDevice.default(for: .video)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        // Center Stage reframes the shot on its own, which would move players relative to their zones.
        if AVCaptureDevice.isCenterStageEnabled || AVCaptureDevice.centerStageControlMode != .app {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = device.minAvailableVideoZoomFactor
            let thirty = CMTime(value: 1, timescale: 30)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameDuration <= thirty && $0.maxFrameDuration >= thirty }) {
                device.activeVideoMinFrameDuration = thirty
                device.activeVideoMaxFrameDuration = thirty
            }
            device.unlockForConfiguration()
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { return false }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        // On a Mac (iPad app on Mac, or Catalyst) the webcam is always landscape and upright, but iOS emulates an
        // iPad orientation, so RotationCoordinator can report 90°/180° and the picture comes out rotated or upside down.
        if ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp {
            applyRotation(0)
            return true
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            guard let self else { return }
            self.queue.async { self.applyRotation(angle) }
        }
        return true
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection = videoOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    // MARK: - Capture callbacks (processing queue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let captureTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        process(pixelBuffer, captureTime: captureTime, runVision: true)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFrames += 1
    }

    private func process(_ pixelBuffer: CVPixelBuffer, captureTime: Double, runVision: Bool) {
        let start = CACurrentMediaTime()
        let wantsCutout = self.wantsCutout
        var stats = PipelineStats()
        stats.sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        stats.sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

        if runVision {
            try? sequenceHandler.perform([poseRequest], on: pixelBuffer, orientation: .up)
        }
        let afterPose = CACurrentMediaTime()

        var mask: CVPixelBuffer?
        if runVision, wantsCutout {
            segmentationRequest.qualityLevel = segmentationQuality
            try? sequenceHandler.perform([segmentationRequest], on: pixelBuffer, orientation: .up)
            mask = segmentationRequest.results?.first?.pixelBuffer
        }
        let afterSegmentation = CACurrentMediaTime()

        let fit = aspectFill(sourceWidth: Double(stats.sourceWidth), sourceHeight: Double(stats.sourceHeight))
        let people = runVision ? extractPeople(fit: fit) : []
        let hasCutout = composite(pixelBuffer, mask: mask, fit: fit)
        let end = CACurrentMediaTime()

        if let mask {
            stats.maskWidth = CVPixelBufferGetWidth(mask)
            stats.maskHeight = CVPixelBufferGetHeight(mask)
        }
        stats.poseMs = (afterPose - start) * 1000
        stats.segmentationMs = (afterSegmentation - afterPose) * 1000
        stats.compositeMs = (end - afterSegmentation) * 1000
        stats.totalMs = (end - start) * 1000
        stats.droppedFrames = droppedFrames

        sequence += 1
        store.publish(VisionSnapshot(sequence: sequence, captureTime: captureTime, completedTime: end,
                                     people: people, hasCutout: hasCutout, stats: stats))
    }

    /// Scale + offset that aspect-fills the source into the fixed output texture (centre crop).
    private struct Fit { var scale: Double; var tx: Double; var ty: Double; var sourceWidth: Double; var sourceHeight: Double }

    private func aspectFill(sourceWidth: Double, sourceHeight: Double) -> Fit {
        let w = Double(store.width), h = Double(store.height)
        let scale = max(w / sourceWidth, h / sourceHeight)
        return Fit(scale: scale, tx: (w - sourceWidth * scale) / 2, ty: (h - sourceHeight * scale) / 2,
                   sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    private func extractPeople(fit: Fit) -> [PersonPose] {
        guard let observations = poseRequest.results else { return [] }
        let w = Double(store.width), h = Double(store.height)
        return observations.compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            var joints: [Joint: JointPoint] = [:]
            for joint in Joint.allCases {
                guard let p = points[joint.visionName], p.confidence > 0.1 else { continue }
                let x = (p.location.x * fit.sourceWidth * fit.scale + fit.tx) / w
                let y = (p.location.y * fit.sourceHeight * fit.scale + fit.ty) / h
                joints[joint] = JointPoint(x: x, y: y, confidence: Double(p.confidence))
            }
            return joints.count >= 4 ? PersonPose(joints: joints, aspect: w / h) : nil
        }
    }

    /// Renders either the raw camera image or the masked cutout (with a player-coloured rim) into the back buffer.
    private func composite(_ pixelBuffer: CVPixelBuffer, mask: CVPixelBuffer?, fit: Fit) -> Bool {
        let target = CGRect(x: 0, y: 0, width: store.width, height: store.height)
        let placement = CGAffineTransform(scaleX: fit.scale, y: fit.scale).concatenating(CGAffineTransform(translationX: fit.tx, y: fit.ty))
        let camera = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: placement)
        var output = camera
        var hasCutout = false

        if let mask {
            var maskImage = CIImage(cvPixelBuffer: mask)
            let maskScale = CGAffineTransform(scaleX: fit.sourceWidth / maskImage.extent.width,
                                              y: fit.sourceHeight / maskImage.extent.height)
            maskImage = maskImage.transformed(by: maskScale.concatenating(placement))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 1.1)
                .cropped(to: target)
            let person = camera.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: maskImage,
            ])
            let rimMask = maskImage.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 3.0]).cropped(to: target)
            let rimColor = rimColorsSwapped ? rimImages.swapped : rimImages.normal
            let rim = rimColor.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: rimMask,
            ])
            output = person.composited(over: rim)
            hasCutout = true
        }

        // Core Image writes the top row first; SpriteKit mutable textures expect the bottom row first.
        let flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -target.height)
        ciContext.render(output.cropped(to: target).transformed(by: flip), toBitmap: store.back,
                         rowBytes: store.width * 4, bounds: target, format: .RGBA8, colorSpace: colorSpace)
        return hasCutout
    }

    private static func makeRimImages(width: Int, height: Int) -> (normal: CIImage, swapped: CIImage) {
        let coral = CIColor(red: 1.0, green: 0.45, blue: 0.40, alpha: 0.95)
        let teal = CIColor(red: 0.15, green: 0.88, blue: 0.80, alpha: 0.95)
        let half = CGFloat(width) / 2
        func split(_ left: CIColor, _ right: CIColor) -> CIImage {
            let l = CIImage(color: left).cropped(to: CGRect(x: 0, y: 0, width: half, height: CGFloat(height)))
            let r = CIImage(color: right).cropped(to: CGRect(x: half, y: 0, width: half, height: CGFloat(height)))
            return r.composited(over: l)
        }
        return (split(coral, teal), split(teal, coral))
    }

    // MARK: - Simulator test source

    /// The Simulator has no camera. A synthetic test card exercises the same bounded queue, compositing,
    /// texture upload, orientation and latency measurement; it cannot exercise segmentation quality.
    private func startSynthetic(card: CGImage?) {
        syntheticCard = card
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 480,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &syntheticPool)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2, repeating: 1.0 / 30)
        timer.setEventHandler { [weak self] in self?.emitSyntheticFrame() }
        syntheticTimer = timer
        timer.resume()
    }

    private func emitSyntheticFrame() {
        guard let pool = syntheticPool, let card = syntheticCard else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        let now = CACurrentMediaTime()
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 480, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(card, in: CGRect(x: 0, y: 0, width: 640, height: 480))
            // A moving bar makes dropped or stale frames visible.
            let x = (now.truncatingRemainder(dividingBy: 2) / 2) * 600
            context.setFillColor(CGColor(red: 1, green: 0.82, blue: 0.25, alpha: 1))
            context.fill(CGRect(x: x, y: 40, width: 40, height: 40))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        process(buffer, captureTime: now, runVision: true)
    }

    @MainActor private static func makeTestCard(width: Int, height: Int) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.05, green: 0.06, blue: 0.2, alpha: 1).cgColor,
                          UIColor(red: 0.42, green: 0.23, blue: 1, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: UIColor.white,
            ]
            ("TOP-LEFT ↖" as NSString).draw(at: CGPoint(x: 20, y: 16), withAttributes: attributes)
            ("SIMULATOR TEST CARD" as NSString).draw(at: CGPoint(x: 120, y: 210), withAttributes: attributes)
            ("no camera in Simulator" as NSString).draw(at: CGPoint(x: 150, y: 260), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: UIColor(white: 1, alpha: 0.8),
            ])
        }
        return image.cgImage
    }
}

nonisolated extension Joint {
    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: .nose
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .root: .root
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        }
    }
}
