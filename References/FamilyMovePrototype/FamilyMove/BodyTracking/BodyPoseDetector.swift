import AVFoundation
import Vision

struct PoseFrame {
    let observations: [BodyObservation]
    let imageSize: CGSize
    let orientation: CaptureOrientation
    let timestamp: TimeInterval
    let processingMilliseconds: Double
    let errorMessage: String?
}

final class BodyPoseDetector {
    private let request = VNDetectHumanBodyPoseRequest()
    private let gate = NSLock()
    private var isProcessing = false
    private var lastFrameTime: TimeInterval = -.infinity

    /// Called only on CameraManager's serial background queue. The gate remains
    /// closed until the MAIN thread consumes the result, bounding UI delivery too.
    func process(_ buffer: CVPixelBuffer, orientation: CaptureOrientation, timestamp: TimeInterval,
                 completion: @escaping @MainActor (PoseFrame) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrameTime >= 1 / GameConstants.visionFramesPerSecond else { return }
        gate.lock()
        guard !isProcessing else { gate.unlock(); return }
        isProcessing = true
        gate.unlock()
        lastFrameTime = now

        var observations: [BodyObservation] = []
        var errorMessage: String?
        do {
            // AVCaptureVideoDataOutput already rotates the pixels. Applying an
            // EXIF rotation or mirror here would transform them a second time.
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            observations = (request.results ?? []).compactMap(Self.extract)
                .filter { $0.bodyCenter != nil }
                .sorted { $0.quality > $1.quality }
                .prefix(GameConstants.maximumPlayers).map { $0 }
        } catch { errorMessage = "Pose detection failed: \(error.localizedDescription)" }
        let frame = PoseFrame(observations: observations,
                              imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
                              orientation: orientation, timestamp: timestamp,
                              processingMilliseconds: (ProcessInfo.processInfo.systemUptime - now) * 1_000,
                              errorMessage: errorMessage)
        DispatchQueue.main.async { [self] in
            defer { finishProcessing() }
            completion(frame)
        }
    }

    private func finishProcessing() {
        gate.lock()
        isProcessing = false
        gate.unlock()
    }

    private static func extract(_ observation: VNHumanBodyPoseObservation) -> BodyObservation? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> JointPoint? {
            guard let point = points[name], point.confidence >= GameConstants.minimumJointConfidence else { return nil }
            return JointPoint(position: point.location, confidence: point.confidence)
        }
        return BodyObservation(id: observation.uuid,
                               leftWrist: joint(.leftWrist), rightWrist: joint(.rightWrist),
                               leftElbow: joint(.leftElbow), rightElbow: joint(.rightElbow),
                               leftShoulder: joint(.leftShoulder), rightShoulder: joint(.rightShoulder),
                               leftHip: joint(.leftHip), rightHip: joint(.rightHip),
                               leftKnee: joint(.leftKnee), rightKnee: joint(.rightKnee),
                               leftAnkle: joint(.leftAnkle), rightAnkle: joint(.rightAnkle), root: joint(.root))
    }
}
