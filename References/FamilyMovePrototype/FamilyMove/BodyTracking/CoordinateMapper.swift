import CoreGraphics
import Foundation

/// Matches AVCaptureVideoPreviewLayer.videoGravity = .resizeAspectFill.
/// Capture buffers have already been rotated upright by AVCaptureConnection.
struct CoordinateMapper {
    let imageSize: CGSize
    let screenSize: CGSize
    var mirrored = true

    func screenPoint(from visionPoint: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0,
              screenSize.width > 0, screenSize.height > 0 else { return .zero }
        let scale = max(screenSize.width / imageSize.width, screenSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = mirrored ? 1 - visionPoint.x : visionPoint.x
        return CGPoint(x: x * width + (screenSize.width - width) / 2,
                       y: (1 - visionPoint.y) * height + (screenSize.height - height) / 2)
    }

    func screenJoint(from joint: JointPoint?) -> JointPoint? {
        guard let joint, joint.confidence >= GameConstants.minimumJointConfidence else { return nil }
        return JointPoint(position: screenPoint(from: joint.position), confidence: joint.confidence)
    }
}
