import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onOrientationChanged: (CaptureOrientation) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.onOrientationChanged = onOrientationChanged
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onOrientationChanged = onOrientationChanged
        view.updateConnection()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onOrientationChanged: ((CaptureOrientation) -> Void)?
        private var lastOrientation: CaptureOrientation?

        override func layoutSubviews() {
            super.layoutSubviews()
            updateConnection()
        }

        func updateConnection() {
            previewLayer.videoGravity = .resizeAspectFill
            #if targetEnvironment(macCatalyst)
            let orientation = CaptureOrientation.landscapeRight
            #else
            let orientation: CaptureOrientation = window?.windowScene?.interfaceOrientation == .landscapeLeft
                ? .landscapeLeft : .landscapeRight
            #endif
            if let connection = previewLayer.connection {
                #if targetEnvironment(macCatalyst)
                if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                #else
                if connection.isVideoOrientationSupported { connection.videoOrientation = orientation.avOrientation }
                #endif
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            if lastOrientation != orientation {
                lastOrientation = orientation
                DispatchQueue.main.async { [weak self] in self?.onOrientationChanged?(orientation) }
            }
        }
    }
}

