import Foundation
import Combine

@MainActor
final class GameSessionCoordinator: ObservableObject {
    let game: GameType
    @Published private(set) var state = GameSessionState.positioning
    @Published private(set) var countdownText = "3"
    @Published private(set) var readyIDs: Set<Int> = []
    @Published private(set) var calibrations: [Int: CalibrationSnapshot] = [:]
    @Published private(set) var score = 0
    @Published private(set) var remainingTime = GameConstants.defaultGameDuration
    @Published private(set) var feedback: [FeedbackEvent] = []
    @Published private(set) var pauseMessage = "Move back into the camera view."
    @Published private(set) var pauseReason = SessionPauseReason.tracking
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var setupMessage: String?
    @Published private(set) var players: [TrackedPlayer] = []
    private var viewport = CGSize.zero
    private var readySince: [Int: TimeInterval] = [:]
    private var phaseStarted: TimeInterval = 0
    private var samples: [Int: [CalibrationSnapshot]] = [:]
    private var lastSampleTime: TimeInterval = 0
    @Published private(set) var moles: [Mole] = []
    private var moleEngine = WhackAMoleEngine()
    private var birdsEngine = BirdsAlligatorsEngine()
    @Published private(set) var obstacles: [Obstacle] = []
    private var clock = RoundClock()
    private var bothLostSince: TimeInterval?
    private(set) var roundID = UUID()
    private(set) var startedAt: Date?
    var roundStats: [Int: PlayerRoundStats] { game == .whackAMole ? moleEngine.stats : birdsEngine.stats }
    var duration: TimeInterval { clock.duration }
    private var timer: AnyCancellable?

    init(game: GameType, duration: TimeInterval? = nil, automaticallyTicks: Bool = true) {
        self.game = game
        clock = RoundClock(duration: duration ?? game.defaultDuration)
        remainingTime = duration ?? game.defaultDuration
        guard automaticallyTicks else { return }
        timer = Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick(now: ProcessInfo.processInfo.systemUptime) }
    }
    func update(players: [TrackedPlayer], viewport: CGSize) {
        self.players = players; self.viewport = viewport
    }
    func newRound() {
        roundID = UUID(); startedAt = nil; score = 0
        clock = RoundClock(duration: clock.duration); remainingTime = clock.duration
        moleEngine = WhackAMoleEngine(); birdsEngine = BirdsAlligatorsEngine()
        resetPositioning()
    }
    func resetPositioning(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if state == .playing { clock.pause(at: now) }
        moleEngine.discardActive(); birdsEngine.discardActive(); moles = []; obstacles = []; feedback = []; bothLostSince = nil
        state = .positioning; readyIDs = []; readySince = [:]
        samples = [:]; calibrations = [:]; lastSampleTime = 0
        calibrationProgress = 0; setupMessage = nil
        pauseReason = .tracking
    }
    func invalidateTrackingGeometry(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard state != .gameOver else { return }
        let holdManualPause = state == .paused && pauseReason == .manual
        let message = pauseMessage
        players = []
        resetPositioning(at: now)
        if holdManualPause { state = .paused; pauseReason = .manual; pauseMessage = message }
    }
    func pause(message: String = "Camera temporarily unavailable.", reason: SessionPauseReason = .camera,
               at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard state != .gameOver, state != .positioning, state != .paused else { return }
        if state == .playing { clock.pause(at: now) }
        moleEngine.discardActive(); birdsEngine.discardActive(); moles = []; obstacles = []; feedback = []
        state = .paused; pauseMessage = message; pauseReason = reason
    }
    private func valid(_ player: TrackedPlayer, now: TimeInterval) -> Bool {
        guard player.isDetected, now - player.lastSeen <= GameConstants.maximumPoseAge,
              CalibrationSnapshot(player: player) != nil else { return false }
        let points = game == .birdsAndAlligators
            ? [player.leftShoulder, player.rightShoulder, player.leftHip, player.rightHip,
               player.leftKnee, player.rightKnee, player.leftAnkle, player.rightAnkle]
            : [player.leftShoulder, player.rightShoulder, player.leftHip, player.rightHip]
        return points.allSatisfy { joint in
            guard let joint else { return false }
            return CGRect(origin: .zero, size: viewport).contains(joint.position)
        }
    }
    func tick(now: TimeInterval) {
        let validPlayers = players.filter { valid($0, now: now) }
        switch state {
        case .positioning:
            for id in 1...2 {
                if validPlayers.contains(where: { $0.id == id }) {
                    if readySince[id] == nil { readySince[id] = now }
                    if now - readySince[id]! >= GameConstants.readyHoldDuration { readyIDs.insert(id) }
                } else { readySince[id] = nil; readyIDs.remove(id) }
            }
            if readyIDs.count == 2 { phaseStarted = now; samples = [:]; state = .calibrating }
        case .calibrating:
            guard validPlayers.count == 2 else { resetPositioning(at: now); return }
            calibrationProgress = min(1, (now - phaseStarted) / GameConstants.calibrationDuration)
            let frameTime = validPlayers.map(\.lastSeen).min() ?? 0
            if frameTime > lastSampleTime {
                for player in validPlayers {
                    if let sample = CalibrationSnapshot(player: player) { samples[player.id, default: []].append(sample) }
                }
                lastSampleTime = frameTime
            }
            if now - phaseStarted >= GameConstants.calibrationDuration {
                guard (samples[1]?.count ?? 0) >= 5, (samples[2]?.count ?? 0) >= 5 else { resetPositioning(at: now); return }
                let stable = samples.compactMapValues { CalibrationSnapshot.average($0) }
                guard stable.count == 2 else {
                    resetPositioning(at: now)
                    setupMessage = "Stand still for a moment while we get ready."
                    return
                }
                calibrations = stable
                phaseStarted = now; countdownText = "3"; state = .countdown
            }
        case .countdown:
            guard validPlayers.count == 2 else { resetPositioning(at: now); return }
            let elapsed = now - phaseStarted
            countdownText = elapsed < 3 ? "\(3 - Int(elapsed))" : "GO!"
            if elapsed >= 3.35 {
                if startedAt == nil { startedAt = Date(); NSLog("[SESSION START] %@ P1 P2", game.rawValue) }
                clock.resume(at: now); state = .playing
            }
        case .playing:
            remainingTime = clock.remaining(at: now)
            let activeTime = clock.elapsed(at: now)
            if remainingTime <= 0 {
                clock.pause(at: now); moleEngine.discardActive(); birdsEngine.discardActive(); moles = []; obstacles = []; feedback = []
                state = .gameOver; NSLog("[SESSION END] score %d", score); return
            }
            let freshPlayers = players.filter { $0.isDetected && now - $0.lastSeen <= GameConstants.maximumPoseAge }
            if freshPlayers.isEmpty {
                if bothLostSince == nil { bothLostSince = now }
                if now - bothLostSince! >= GameConstants.bothPlayersLostPauseDelay {
                    pause(message: "Move back into the camera view.", reason: .tracking, at: now); return
                }
            } else { bothLostSince = nil }
            feedback.removeAll { activeTime - $0.createdAt > 0.7 }
            if game == .whackAMole {
                feedback += moleEngine.update(players: freshPlayers, calibration: calibrations, screen: viewport, now: activeTime)
                moles = Array(moleEngine.moles.values)
            } else {
                feedback += birdsEngine.update(players: freshPlayers, calibration: calibrations, now: activeTime)
                obstacles = Array(birdsEngine.obstacles.values)
            }
            score = roundStats.values.map(\.scoreContribution).reduce(0, +)
        case .paused:
            if pauseReason == .tracking, validPlayers.count == 2 { resetPositioning(at: now) }
        case .gameOver: break
        }
    }
}
