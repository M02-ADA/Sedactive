import SpriteKit
import SwiftUI

@main
struct StuntRunApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var model = GameModel()
    @State private var pipeline = CameraPipeline()
    @State private var scene: WorldScene = Self.makeScene(.fromLaunchArgument)
    @State private var inputSource: CameraPipeline.Source = .none

    static func makeScene(_ mode: GameMode) -> WorldScene {
        let scene = WorldScene(size: CGSize(width: 1376, height: 1032))
        scene.scaleMode = .resizeFill
        scene.gameMode = mode
        return scene
    }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60,
                   options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes],
                   debugOptions: model.showMetrics ? [.showsFPS, .showsNodeCount, .showsDrawCount] : [])
            // SpriteView keeps presenting its first scene when handed a new one, so a game switch rebuilds the view.
            .id(ObjectIdentifier(scene))
            .ignoresSafeArea()
            .overlay(alignment: .bottomTrailing) {
                ControlPanel(model: model, scene: scene)
                    .padding(20)
            }
            .overlay(alignment: .bottomLeading) {
                if model.showMetrics {
                    MetricsPanel(metrics: model.metrics, status: model.inputStatus)
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .task {
                scene.model = model
                scene.pipeline = pipeline
                let source = await pipeline.start()
                inputSource = source
                scene.inputSource = source
                switch source {
                case .camera:
                    model.inputStatus = .camera
                    // Bots fill empty zones only when asked (`-autoplay YES`, used for unattended perf runs).
                    model.autoplay = UserDefaults.standard.bool(forKey: "autoplay")
                case .synthetic:
                    model.inputStatus = .simulatorTestCard
                case .none:
                    model.inputStatus = .unavailable("Camera unavailable — simulated players only")
                }
            }
            .onChange(of: model.gameMode) { _, mode in
                // Switching games recreates the scene; the camera pipeline and settings carry over.
                let next = Self.makeScene(mode)
                next.model = model
                next.pipeline = pipeline
                next.inputSource = inputSource
                if inputSource == .camera { model.autoplay = false }
                // Silence the outgoing scene explicitly; tearing down the view doesn't guarantee willMove(from:).
                scene.audio.stopAmbience()
                scene.isPaused = true
                scene = next
            }
            .onChange(of: systemReduceMotion, initial: true) { _, reduce in
                model.systemReduceMotion = reduce
            }
            .onChange(of: scenePhase, initial: true) { oldPhase, phase in
                // Players never touch the screen mid-game, so auto-lock would freeze the ride after a few minutes.
                UIApplication.shared.isIdleTimerDisabled = phase == .active
                // Never keep the camera running in the background.
                if phase == .background { pipeline.stop() }
                if phase == .active, oldPhase == .background, scene.inputSource != .none {
                    Task { _ = await pipeline.start() }
                }
            }
    }
}

/// Developer controls for the spike. Simulated squats feed the same detector as the camera; they test
/// game logic only and are never evidence of tracking accuracy.
struct ControlPanel: View {
    @Bindable var model: GameModel
    let scene: WorldScene

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if model.controlsExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Game", selection: $model.gameMode) {
                        ForEach(GameMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)

                    Picker("View", selection: $model.mode) {
                        ForEach(ViewMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)

                    Text("Simulated input").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        actionButton("P1 squat", key: "1", tint: Color(Palette.coral)) { scene.simulateSquat(.left) }
                        actionButton("P2 squat", key: "2", tint: Color(Palette.teal)) { scene.simulateSquat(.right) }
                        actionButton("Both", key: "3", tint: Color(Palette.violet)) {
                            scene.simulateSquat(.left)
                            scene.simulateSquat(.right)
                        }
                    }
                    HStack(spacing: 8) {
                        actionButton("P1 shallow", key: "q", tint: Color(Palette.coral).opacity(0.6)) { scene.simulateSquat(.left, shallow: true) }
                        actionButton("P2 shallow", key: "w", tint: Color(Palette.teal).opacity(0.6)) { scene.simulateSquat(.right, shallow: true) }
                    }
                    if model.gameMode == .jungleDrift {
                        HStack(spacing: 8) {
                            actionButton("P1 ◀ lean", key: "a", tint: Color(Palette.coral).opacity(0.75)) { scene.simulateLean(.left, direction: -1) }
                            actionButton("P1 lean ▶", key: "d", tint: Color(Palette.coral).opacity(0.75)) { scene.simulateLean(.left, direction: 1) }
                        }
                        HStack(spacing: 8) {
                            actionButton("P2 ◀ lean", key: "j", tint: Color(Palette.teal).opacity(0.75)) { scene.simulateLean(.right, direction: -1) }
                            actionButton("P2 lean ▶", key: "l", tint: Color(Palette.teal).opacity(0.75)) { scene.simulateLean(.right, direction: 1) }
                        }
                    }
                    if model.gameMode == .jungleDrift || model.gameMode == .laserBreakout {
                        HStack(spacing: 8) {
                            actionButton("P1 jump", key: "e", tint: Color(Palette.coral)) { scene.simulateJump(.left) }
                            actionButton("P2 jump", key: "i", tint: Color(Palette.teal)) { scene.simulateJump(.right) }
                            actionButton("Both", key: "4", tint: Color(Palette.violet)) {
                                scene.simulateJump(.left)
                                scene.simulateJump(.right)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        actionButton("Lose P1", key: "z", tint: .gray) { toggleLost(.left) }
                        actionButton("Lose P2", key: "x", tint: .gray) { toggleLost(.right) }
                    }

                    Text("Session").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        actionButton(model.isHaltedForControls ? "Resume" : "Pause", key: " ", tint: Color(Palette.yellow).opacity(0.85)) {
                            scene.togglePause()
                        }
                        actionButton("Replay", key: "r", tint: Color(Palette.electric)) { scene.replay(source: "button") }
                        actionButton(model.scriptRunning ? "Script…" : "Run script", key: "s", tint: Color(Palette.mint).opacity(0.8)) {
                            scene.startScript()
                        }
                        if model.gameMode == .jungleDrift {
                            // Log / tail sweep test script (same as `-scenario sweeps`).
                            actionButton("Jump script", key: "g", tint: Color(Palette.mint).opacity(0.6)) {
                                scene.startJungleScript(sweeps: true)
                            }
                        }
                        if model.gameMode == .laserBreakout {
                            actionButton("Debug", key: "v", tint: Color(Palette.electric).opacity(0.6)) { scene.toggleLaserDebug() }
                        }
                        if model.gameMode == .moonbound {
                            actionButton("Debug", key: "v", tint: Color(Palette.electric).opacity(0.6)) { scene.toggleMoonDebug() }
                        }
                    }
                    Text(model.playStateLabel).font(.caption.monospaced()).foregroundStyle(.secondary)

                    Toggle("Autoplay empty zones", isOn: $model.autoplay)
                    Toggle("Hero TEAM DUCK", isOn: $model.heroFX)
                    Toggle("Reduce Motion", isOn: $model.reduceMotionOverride)
                    Toggle("Swap Parent / Child sides", isOn: $model.swapRoles)
                    Toggle("Sound", isOn: $model.soundOn)
                    Toggle("Metrics", isOn: $model.showMetrics)
                }
                .font(.subheadline.weight(.semibold))
                .toggleStyle(.switch)
                .padding(16)
                .frame(width: 340)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
            }
            Button {
                withAnimation(.snappy(duration: 0.25)) { model.controlsExpanded.toggle() }
            } label: {
                Image(systemName: model.controlsExpanded ? "chevron.down.circle.fill" : "slider.horizontal.3")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: .circle)
            .accessibilityLabel(model.controlsExpanded ? "Hide controls" : "Show controls")
            .keyboardShortcut("h", modifiers: [])
        }
        .environment(\.colorScheme, .dark)
    }

    private func toggleLost(_ zone: Zone) {
        let lost = !(scene.slots[zone]?.simLost ?? false)
        scene.setSimulatedTrackingLost(zone, lost: lost)
    }

    private func actionButton(_ title: String, key: KeyEquivalent, tint: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .font(.footnote.weight(.bold))
    }
}

struct MetricsPanel: View {
    let metrics: MetricsSnapshot
    let status: InputStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(status.label).fontWeight(.bold)
            Text(String(format: "Render %.0f fps · frame %.1f ms (max %.1f) · hitches %.0f/min", metrics.renderFPS, metrics.frameTimeAvgMs, metrics.frameTimeMaxMs, metrics.hitchesPerMin))
            Text(String(format: "Vision %.0f fps · pose %.1f ms · mask %.1f ms · composite %.1f ms", metrics.visionFPS, metrics.poseMs, metrics.segmentationMs, metrics.compositeMs))
            Text(String(format: "Capture→texture %.0f ms · dropped camera frames %d", metrics.captureToTextureMs, metrics.droppedCameraFrames))
            Text("Capture→feedback " + (metrics.feedbackLatencyAvgMs.map { String(format: "avg %.0f ms", $0) } ?? "— (needs live squat)")
                 + (metrics.feedbackLatencyLastMs.map { String(format: " · last %.0f ms", $0) } ?? ""))
            Text(String(format: "Memory %.0f MB · thermal %@ · people %d · src %@ · mask %@", metrics.memoryMB, metrics.thermal, metrics.people, metrics.sourceSize, metrics.maskSize)
                 + (metrics.degraded ? " · DEGRADED" : ""))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 12))
    }
}
