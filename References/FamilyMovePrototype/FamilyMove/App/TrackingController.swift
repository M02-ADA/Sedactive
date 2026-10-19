import Combine
import Foundation

@MainActor
final class TrackingController: ObservableObject {
    let detector = BodyPoseDetector()
    private(set) var camera: CameraManager!
    @Published private(set) var players = [TrackedPlayer(id: 1), TrackedPlayer(id: 2)]
    @Published private(set) var processingMilliseconds: Double = 0
    @Published private(set) var detectionFPS: Double = 0
    @Published private(set) var visionError: String?
    @Published var debugMode = GameConstants.debugMode
    private var tracker = PlayerTracker()
    private var viewport = CGSize.zero
    private var orientation = CaptureOrientation.landscapeRight
    private var imageSize = CGSize.zero
    private var lastFrameTime: TimeInterval?
    private var expiryTimer: AnyCancellable?
    private var statusSubscription: AnyCancellable?
    private var acceptsFrames = false
    private var startedAt: TimeInterval = 0

    init() {
        let detector = detector
        camera = CameraManager { [weak self] buffer, orientation, timestamp in
            detector.process(buffer, orientation: orientation, timestamp: timestamp) { [weak self] frame in
                self?.receive(frame)
            }
        }
        expiryTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.expireTracking() }
        statusSubscription = camera.$status.sink { [weak self] status in
            guard let self else { return }
            if status != .running { self.clearTracking() }
        }
    }

    func start() {
        startedAt = ProcessInfo.processInfo.systemUptime
        acceptsFrames = true
        camera.startSession()
    }
    func stop() { acceptsFrames = false; camera.stopSession(); clearTracking() }

    func resize(to size: CGSize) {
        guard size != viewport else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        viewport = size
        clearTracking()
    }

    func setOrientation(_ newValue: CaptureOrientation) {
        guard orientation != newValue else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        orientation = newValue
        clearTracking()
        camera.setOrientation(newValue)
    }

    private func receive(_ frame: PoseFrame) {
        guard acceptsFrames, camera.status == .running, frame.timestamp >= startedAt,
              frame.orientation == orientation,
              viewport.width > 0, viewport.height > 0,
              ProcessInfo.processInfo.systemUptime - frame.timestamp <= GameConstants.maximumPoseAge else { return }
        if frame.imageSize != imageSize {
            clearTracking()
            imageSize = frame.imageSize
        }
        let mapper = CoordinateMapper(imageSize: frame.imageSize, screenSize: viewport)
        let updated = tracker.update(observations: frame.observations, mapper: mapper, timestamp: frame.timestamp)
        logTrackingChanges(updated)
        players = updated
        processingMilliseconds = frame.processingMilliseconds
        visionError = frame.errorMessage
        if let lastFrameTime { detectionFPS = 1 / max(frame.timestamp - lastFrameTime, 0.001) }
        lastFrameTime = frame.timestamp
    }

    private func expireTracking() {
        tracker.expire(at: ProcessInfo.processInfo.systemUptime)
        logTrackingChanges(tracker.players)
        players = tracker.players
        if let lastFrameTime, ProcessInfo.processInfo.systemUptime - lastFrameTime > GameConstants.maximumPoseAge {
            detectionFPS = 0
        }
    }

    private func clearTracking() {
        tracker.reset()
        players = tracker.players
        lastFrameTime = nil
        detectionFPS = 0
        processingMilliseconds = 0
        visionError = nil
    }

    private func logTrackingChanges(_ updated: [TrackedPlayer]) {
        for player in updated {
            if players.first(where: { $0.id == player.id })?.isDetected != player.isDetected {
                NSLog("[TRACKING] P%d %@", player.id, player.isDetected ? "recovered" : "lost")
            }
        }
    }
}
