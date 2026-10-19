import AVFoundation
import Combine

enum CaptureOrientation: Equatable {
    case landscapeLeft, landscapeRight

    #if !targetEnvironment(macCatalyst)
    var avOrientation: AVCaptureVideoOrientation {
        self == .landscapeLeft ? .landscapeLeft : .landscapeRight
    }
    #endif
}

enum CameraStatus: Equatable {
    case idle, requestingPermission, running, interrupted, denied
    case failed(String)
}

/// Session configuration, start/stop, sample delivery and Vision all share one
/// serial background queue. Published state is delivered only on the main queue.
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published private(set) var status: CameraStatus = .idle
    @Published private(set) var captureFPS: Double = 0
    private let queue = DispatchQueue(label: "camera.capture-and-vision", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var wantsRunning = false
    private var orientation = CaptureOrientation.landscapeRight
    private var frameCount = 0
    private var rateStarted = ProcessInfo.processInfo.systemUptime
    private let onFrameCaptured: (CVPixelBuffer, CaptureOrientation, TimeInterval) -> Void

    init(onFrameCaptured: @escaping (CVPixelBuffer, CaptureOrientation, TimeInterval) -> Void) {
        self.onFrameCaptured = onFrameCaptured
        super.init()
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(interrupted),
                                  name: AVCaptureSession.wasInterruptedNotification, object: session)
        notifications.addObserver(self, selector: #selector(interruptionEnded),
                                  name: AVCaptureSession.interruptionEndedNotification, object: session)
        notifications.addObserver(self, selector: #selector(runtimeError(_:)),
                                  name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func startSession() {
        #if targetEnvironment(simulator)
        publish(.failed("Camera gameplay is available on My Mac (Mac Catalyst) or a physical iPad."))
        #else
        queue.async { [self] in
            wantsRunning = true
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: configureAndStart()
            case .notDetermined:
                publish(.requestingPermission)
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    self.queue.async {
                        guard self.wantsRunning else { return }
                        if granted { self.configureAndStart() } else { self.publish(.denied) }
                    }
                }
            case .denied, .restricted: publish(.denied)
            @unknown default: publish(.failed("Camera authorization is unavailable."))
            }
        }
        #endif
    }

    func stopSession() {
        queue.async { [self] in
            wantsRunning = false
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { [weak self] in self?.captureFPS = 0 }
            publish(.idle)
        }
    }

    func setOrientation(_ orientation: CaptureOrientation) {
        queue.async { [self] in
            self.orientation = orientation
            configureOutputConnection()
        }
    }

    private func configureAndStart() {
        guard wantsRunning else { return }
        do {
            if !configured { try configureSession() }
            if !session.isRunning {
                frameCount = 0; rateStarted = ProcessInfo.processInfo.systemUptime
                session.startRunning()
            }
            if session.isRunning {
                publish(session.isInterrupted ? .interrupted : .running)
            } else {
                publish(.failed("The camera could not start. Try again."))
            }
        } catch { publish(.failed(error.localizedDescription)) }
    }

    private func configureSession() throws {
        #if targetEnvironment(macCatalyst)
        let cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                       mediaType: .video, position: .unspecified).devices
        let selected = cameras.first ?? AVCaptureDevice.default(for: .video)
        #else
        let selected = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        #endif
        guard let device = selected else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        guard session.canAddInput(input) else { throw CameraError.configuration }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraError.configuration
        }
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        configureOutputConnection()
        // Reduce capture load as well as throttling Vision. Some formats only allow
        // a fixed rate; leave those at their supported default.
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                device.unlockForConfiguration()
            } catch {
                NSLog("Camera frame-rate configuration unavailable: %@", error.localizedDescription)
            }
        }
        configured = true
    }

    private func configureOutputConnection() {
        guard let connection = output.connection(with: .video) else { return }
        // These orientation APIs remain available on iPadOS 17+. Using the same
        // semantic orientation on both connections accounts for different iPad
        // sensor mounts without hard-coded videoRotationAngle assumptions.
        #if targetEnvironment(macCatalyst)
        if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        #else
        if connection.isVideoOrientationSupported { connection.videoOrientation = orientation.avOrientation }
        #endif
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard wantsRunning else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        measureFrameRate()
        onFrameCaptured(buffer, orientation, ProcessInfo.processInfo.systemUptime)
    }

    private func measureFrameRate() {
        let now = ProcessInfo.processInfo.systemUptime
        frameCount += 1
        if now - rateStarted >= 1 {
            let rate = Double(frameCount) / (now - rateStarted)
            frameCount = 0; rateStarted = now
            DispatchQueue.main.async { [weak self] in self?.captureFPS = rate }
        }
    }

    @objc private func interrupted() { publish(.interrupted) }

    @objc private func interruptionEnded() {
        queue.async { [self] in configureAndStart() }
    }

    @objc private func runtimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        queue.async { [self] in
            if error?.code == .mediaServicesWereReset, wantsRunning {
                configureAndStart()
            } else {
                publish(.failed(error?.localizedDescription ?? "The camera stopped unexpectedly. Try again."))
            }
        }
    }

    private func publish(_ status: CameraStatus) {
        DispatchQueue.main.async { [weak self] in self?.status = status }
    }

    private enum CameraError: LocalizedError {
        case unavailable, configuration
        var errorDescription: String? {
            switch self {
            case .unavailable: return "No camera is available. Connect or enable a camera and try again."
            case .configuration: return "The camera could not be configured."
            }
        }
    }
}
