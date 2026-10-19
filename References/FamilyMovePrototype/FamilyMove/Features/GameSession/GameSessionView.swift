import SwiftUI
import SwiftData

struct GameSessionView: View {
    let game: GameType
    let members: [FamilyMember]
    let onDone: () -> Void
    @StateObject private var tracking = TrackingController()
    @StateObject private var session: GameSessionCoordinator
    @State private var viewport = CGSize.zero
    @State private var cameraStatus = CameraStatus.idle
    @State private var captureFPS: Double = 0
    @State private var orientation: CaptureOrientation?
    @State private var showExitConfirmation = false
    @State private var soundEnabled = true
    @State private var soundPlayer = SessionSoundPlayer()
    @State private var simulatorInput = SimulatorInput()
    private let inputMode = SessionInputMode.current
    @Environment(\.modelContext) private var context
    @State private var saveError: String?
    @State private var debugError: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(game: GameType, members: [FamilyMember], onDone: @escaping () -> Void) {
        self.game = game; self.members = members; self.onDone = onDone
        _session = StateObject(wrappedValue: GameSessionCoordinator(game: game, duration: SessionInputMode.roundDuration))
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppColors.secondary
                if inputMode.usesCamera {
                    CameraPreview(session: tracking.camera.session, onOrientationChanged: updateOrientation)
                }
                if inputMode == .simulator {
                    SimulatorArenaView(players: session.players)
                } else if !inputMode.usesCamera { Color.black.opacity(0.12).allowsHitTesting(false) }
                if tracking.debugMode { DebugOverlayView(players: session.players) }
                if session.state == .gameOver {
                    GameOverView(game: game, score: session.score, members: members, stats: session.roundStats,
                                 saveError: saveError, onRetry: { _ = saveResult() }, onPlayAgain: {
                        if saveResult() { session.newRound(); simulatorInput.reset(); if inputMode.usesCamera { tracking.start() } }
                    }, onDone: leave)
                } else if cameraStatus != .running { cameraMessage }
                else {
                    switch session.state {
                    case .positioning, .calibrating:
                        if inputMode == .simulator {
                            SimulatorSetupView(game: game, members: members, isPreparing: simulatorInput.hasStarted) {
                                simulatorInput.begin(); updateSimulatorPlayers()
                            }
                        } else { positioning }
                    case .countdown:
                        Text(session.countdownText).font(.system(size: 130, weight: .black, design: .rounded))
                            .foregroundStyle(inputMode == .simulator ? AppColors.accent : .white).shadow(radius: 8)
                    case .playing:
                        if game == .whackAMole {
                            WhackAMoleView(moles: session.moles, calibration: session.calibrations, screen: viewport,
                                feedback: session.feedback, debug: tracking.debugMode, activeTime: elapsedTime)
                        } else {
                            BirdsAlligatorsView(obstacles: session.obstacles, calibration: session.calibrations, screen: viewport)
                            ForEach(session.feedback) { event in
                                Text(event.text).font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange).shadow(color: .black.opacity(0.4), radius: 2)
                                    .position(event.position)
                            }
                        }
                        if inputMode == .simulator && game == .whackAMole {
                            SimulatorMoleTargets(moles: session.moles) { mole in
                                guard session.state == .playing else { return }
                                simulatorInput.hit(mole, elapsed: elapsedTime); updateSimulatorPlayers()
                            }
                        }
                        GameHUDView(remainingTime: session.remainingTime, score: session.score,
                                    members: members, players: session.players, immersive: game == .whackAMole)
                    case .paused:
                        VStack(spacing: 16) {
                            Text(session.pauseReason == .manual ? "Take a breather" : "We can’t see you.").font(AppTypography.title)
                            Text(session.pauseMessage)
                            Button(session.pauseReason == .manual ? "Continue" : "Reposition") { session.resetPositioning() }.buttonStyle(.borderedProminent)
                        }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    case .gameOver: EmptyView()
                    }
                    if game == .whackAMole && session.state != .paused {
                        HandFeedbackView(players: session.players).id(session.roundID)
                    }
                }
                VStack {
                    if session.state != .gameOver { sessionToolbar }
                    Spacer()
                    if let error = tracking.visionError ?? debugError {
                        Text(error).font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding()
                    }
                }
            }
            .clipped()
            .onAppear {
                resize(geometry.size)
                do {
                    let settings = try ProfileRepository(context: context).settings()
                    tracking.debugMode = settings.debugModeEnabled
                    soundEnabled = settings.soundEnabled
                    soundPlayer.enabled = settings.soundEnabled
                }
                catch { debugError = error.localizedDescription }
                if inputMode.usesCamera { tracking.start() } else { cameraStatus = .running }
            }
            .onChange(of: geometry.size) { _, size in resize(size) }
        }
        .onChange(of: tracking.debugMode) { _, enabled in
            do {
                let settings = try ProfileRepository(context: context).settings()
                settings.debugModeEnabled = enabled
                try context.save()
            } catch { context.rollback(); debugError = error.localizedDescription }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if inputMode == .simulator {
                SimulatorControlsView(game: game, isPlaying: session.state == .playing,
                    busyPlayers: Set((1...2).filter { simulatorInput.isMoving($0, elapsed: elapsedTime) })) { id, movement in
                    guard session.state == .playing else { return }
                    simulatorInput.move(movement, playerID: id, elapsed: elapsedTime)
                    updateSimulatorPlayers()
                }
            }
        }
        .task { await driveSimulatedPlayers() }
        .onChange(of: soundEnabled) { _, enabled in
            soundPlayer.enabled = enabled
            if !enabled { soundPlayer.stop() }
            do {
                let settings = try ProfileRepository(context: context).settings()
                settings.soundEnabled = enabled; try context.save()
            } catch { context.rollback(); debugError = error.localizedDescription }
        }
        .onChange(of: session.countdownText) { _, text in
            if session.state == .countdown { soundPlayer.play(text == "GO!" ? .success : .countdown) }
        }
        .onChange(of: session.score) { old, score in if score > old { soundPlayer.play(.success) } }
        .onDisappear { tracking.stop(); soundPlayer.stop() }
        .alert("End this round?", isPresented: $showExitConfirmation) {
            Button("Keep Playing", role: .cancel) { session.resetPositioning() }
            Button("End Round", role: .destructive) { onDone() }
        } message: { Text("This round’s progress won’t be saved.") }
        .onChange(of: session.state) { _, state in
            if state != .playing { simulatorInput.clearActions() }
            if state == .gameOver { _ = saveResult(); tracking.stop(); soundPlayer.play(.complete) }
            if state == .countdown { soundPlayer.play(.countdown) }
        }
        .onReceive(tracking.$players) { if inputMode.usesCamera { session.update(players: $0, viewport: viewport) } }
        .onReceive(tracking.camera.$captureFPS) { captureFPS = $0 }
        .onReceive(tracking.camera.$status) { status in
            guard inputMode.usesCamera else { return }
            cameraStatus = status
            if status != .running { session.pause() }
            else if session.state == .paused && session.pauseReason == .camera { session.resetPositioning() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && session.state != .gameOver {
                if !showExitConfirmation && session.pauseReason != .manual { session.resetPositioning() }
                if inputMode.usesCamera { tracking.start() } else { cameraStatus = .running }
            } else {
                session.pause(message: "Stand in position to resume.", reason: .background)
                tracking.stop(); soundPlayer.stop()
            }
        }
    }
    private var sessionToolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(action: requestLeave) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Leave game")
                if session.state != .playing { Text(game.displayName).font(.headline) }
                if session.state == .playing {
                    Button { session.pause(message: "Continue when you’re ready to move again.", reason: .manual); soundPlayer.stop() } label: {
                        Image(systemName: "pause.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel("Pause game")
                }
                Button { soundEnabled.toggle() } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 44, height: 44)
                }.accessibilityLabel(soundEnabled ? "Mute game sounds" : "Enable game sounds").accessibilityIdentifier("gameSound")
                Button { tracking.debugMode.toggle() } label: {
                    Image(systemName: "figure.stand").frame(width: 44, height: 44)
                        .foregroundStyle(tracking.debugMode ? .orange : .white)
                }.accessibilityLabel("Body tracking debug").accessibilityValue(tracking.debugMode ? "On" : "Off")
            }.buttonStyle(.plain).foregroundStyle(.white)
                .padding(.horizontal, 8).background(.black.opacity(0.72), in: Capsule())
            if !inputMode.usesCamera {
                Text(inputMode == .automatedTest ? "TEST POSES · NO CAMERA" : "SIMULATOR CONTROLS · NO CAMERA")
                    .font(.caption2.bold()).tracking(1).padding(6)
                    .background(.black.opacity(0.75), in: Capsule()).foregroundStyle(.white)
            } else if tracking.debugMode {
                Text(String(format: "Capture %.0f/s · Vision %.0f/s · %.0f ms", captureFPS, tracking.detectionFPS, tracking.processingMilliseconds))
                    .font(.caption.monospaced()).padding(6)
                    .background(.black.opacity(0.75), in: Capsule()).foregroundStyle(.white)
            }
        }.padding(.top, 22)
    }
    @MainActor
    private func driveSimulatedPlayers() async {
        guard !inputMode.usesCamera else { return }
        while !Task.isCancelled {
            if scenePhase == .active && session.state != .gameOver {
                if inputMode == .simulator { updateSimulatorPlayers() }
                else {
                    session.update(players: UITestPoseSource.players(screen: viewport, session: session,
                        now: ProcessInfo.processInfo.systemUptime), viewport: viewport)
                }
            }
            do { try await Task.sleep(for: .milliseconds(66)) } catch { break }
        }
    }
    private var elapsedTime: TimeInterval { session.duration - session.remainingTime }
    private func updateSimulatorPlayers() {
        session.update(players: simulatorInput.players(screen: viewport, timestamp: ProcessInfo.processInfo.systemUptime,
            elapsed: elapsedTime, moles: session.moles), viewport: viewport)
    }
    private func saveResult() -> Bool {
        guard let started = session.startedAt else { return false }
        do {
            try SessionRepository(context: context).saveCompleted(id: session.roundID, game: game,
                members: members, startedAt: started, duration: session.duration, score: session.score, stats: session.roundStats)
            saveError = nil; return true
        } catch { saveError = error.localizedDescription; return false }
    }
    private func leave() {
        if session.state != .gameOver || saveResult() { onDone() }
    }
    private func requestLeave() {
        guard session.startedAt != nil, session.state != .gameOver else { leave(); return }
        session.pause(message: "Your round is paused.", reason: .manual)
        soundPlayer.stop(); showExitConfirmation = true
    }
    private func resize(_ size: CGSize) {
        guard size != viewport else { return }
        viewport = size
        simulatorInput.clearActions()
        session.invalidateTrackingGeometry()
        tracking.resize(to: size)
    }
    private func updateOrientation(_ value: CaptureOrientation) {
        if let orientation, orientation != value { session.invalidateTrackingGeometry() }
        orientation = value
        tracking.setOrientation(value)
    }
    private var positioning: some View {
        VStack(spacing: 16) {
            Text(session.state == .calibrating ? "Hold still for a moment…" : "Step into the picture").font(AppTypography.title)
            Text(session.state == .calibrating ? "Getting to know your moves" : game == .birdsAndAlligators
                 ? "Step back so we can see your whole body." : "Keep your hips in view. Raise your hands to see them glow!")
                .font(.title3.weight(.semibold))
            if let hint = session.setupMessage { Text(hint).font(.headline).foregroundStyle(.white) }
            if session.state == .calibrating {
                SwiftUI.ProgressView(value: session.calibrationProgress).tint(.white).frame(maxWidth: 340)
                    .accessibilityLabel("Calibrating your standing position")
            }
            HStack(spacing: 50) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    let ready = session.readyIDs.contains(index + 1)
                    let color = ArcadeStyle.handColor(index + 1)
                    VStack(spacing: 10) {
                        Text("P\(index + 1) · \(member.name)").font(.title2.bold())
                            .padding(12).background(.black.opacity(0.65), in: Capsule())
                        Spacer(minLength: 12)
                        Image(systemName: ready ? "checkmark.circle.fill" : "figure.stand")
                            .font(.system(size: ready ? 60 : 105)).opacity(ready ? 1 : 0.3)
                        Spacer(minLength: 12)
                        Text(ready ? "Ready ✓" : "\(index == 0 ? "LEFT" : "RIGHT") · Stand in view")
                            .font(.headline).padding(10).background(.black.opacity(0.65), in: Capsule())
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(color.opacity(ready ? 0.9 : 0.5),
                        style: StrokeStyle(lineWidth: 3, dash: ready ? [] : [12, 12])))
                    .foregroundStyle(color)
                }
            }.frame(maxWidth: 850, maxHeight: .infinity)
            if game == .whackAMole {
                Text("Reach with either hand to hit a mole. No need to touch the screen.")
                    .font(.headline).padding(12).background(.black.opacity(0.7), in: Capsule())
            }
        }.padding(.top, 110).padding(.bottom, 28).padding(.horizontal, 40)
            .foregroundStyle(.white).shadow(color: .black.opacity(0.65), radius: 3)
    }
    private var cameraMessage: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder").font(.system(size: 50))
            switch cameraStatus {
            case .denied:
                Text("Camera access is required to play.").font(.title2.bold())
                Button("Open Settings") { openURL(cameraSettingsURL) }
                    .buttonStyle(.borderedProminent)
            case .failed(let message):
                #if targetEnvironment(simulator)
                Text("Play with your Mac camera").font(.title2.bold())
                Text("In Xcode, select My Mac (Mac Catalyst) as the run destination and press ⌘R. Camera gameplay also works on a physical iPad. The iPad Simulator offers a separate controls preview.")
                    .multilineTextAlignment(.center)
                #else
                Text(message).multilineTextAlignment(.center)
                Button("Try Again") { tracking.start() }.buttonStyle(.borderedProminent)
                #endif
            case .interrupted: Text("Camera temporarily unavailable.")
            default: ProgressView("Starting camera…")
            }
        }.padding(28).frame(maxWidth: 520).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
    private var cameraSettingsURL: URL {
        #if targetEnvironment(macCatalyst)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        #else
        URL(string: UIApplication.openSettingsURLString)!
        #endif
    }
}
