import SwiftUI

struct TrackingTestView: View {
    @ObservedObject var controller: TrackingController
    @ObservedObject var camera: CameraManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            header
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.94, green: 0.95, blue: 0.97)
                    CameraPreview(session: camera.session, onOrientationChanged: controller.setOrientation)
                        .opacity(camera.status == .running || camera.status == .interrupted ? 1 : 0)
                    if camera.status == .running {
                        Color.black.opacity(0.08).allowsHitTesting(false)
                        playerGuides
                        if controller.debugMode { DebugOverlayView(players: controller.players) }
                    } else {
                        cameraMessage
                    }
                    if camera.status == .running {
                        VStack {
                            HStack {
                                #if targetEnvironment(macCatalyst)
                                Label("MACBOOK CAMERA · MIRRORED", systemImage: "camera.fill")
                                #else
                                Label("FRONT CAMERA · MIRRORED", systemImage: "camera.fill")
                                #endif
                                Spacer()
                                if controller.debugMode {
                                    Text(String(format: "%.0f detections/s · %.0f ms Vision", controller.detectionFPS, controller.processingMilliseconds))
                                        .monospacedDigit()
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(12).background(.ultraThinMaterial)
                            Spacer()
                            Text(guidance).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule()).padding(.bottom, 16)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.black.opacity(0.08)))
                .onAppear { controller.resize(to: geometry.size) }
                .onChange(of: geometry.size) { _, size in controller.resize(to: size) }
            }
            HStack(spacing: 14) {
                ForEach(controller.players) { player in playerCard(player) }
            }
            if let error = controller.visionError {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityLabel(error)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .background(Color(red: 0.98, green: 0.98, blue: 0.99))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Stand Here").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Stand side by side. Keep your shoulders and hands in view.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $controller.debugMode) {
                Label("Debug markers", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.button).tint(PlayerStyle.blue)
            .accessibilityHint("Shows tracked wrists, body centers, and confidence values")
        }
    }

    private var playerGuides: some View {
        HStack(spacing: 44) {
            ForEach(controller.players) { player in
                VStack(spacing: 8) {
                    Text("Player \(player.id)").font(.title3.bold())
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [9, 8]))
                        .overlay {
                            if !player.isDetected {
                                Image(systemName: "figure.stand").font(.system(size: 100, weight: .light)).opacity(0.7)
                            }
                        }
                }
                .foregroundStyle(PlayerStyle.color(for: player.id))
            }
        }
        .padding(.horizontal, 60).padding(.top, 53).padding(.bottom, 70)
        .allowsHitTesting(false)
    }

    private func playerCard(_ player: TrackedPlayer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: player.isDetected ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.system(size: 30)).foregroundStyle(PlayerStyle.color(for: player.id))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Player \(player.id)").font(.headline)
                    Text(player.isDetected ? "DETECTED" : (player.bodyCenter == nil ? "NOT DETECTED" : "REACQUIRING"))
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
                Text("Left wrist \(confidence(player.leftWrist))   ·   Right wrist \(confidence(player.rightWrist))")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(PlayerStyle.color(for: player.id).opacity(0.2)))
        .accessibilityElement(children: .combine)
    }

    private func confidence(_ joint: JointPoint?) -> String {
        joint.map { String(format: "%.2f", $0.confidence) } ?? "—"
    }

    private var guidance: String {
        switch controller.players.filter(\.isDetected).count {
        case 2: return "Both players detected. Raise each hand to check the wrist markers."
        case 1: return controller.players[0].isDetected ? "Waiting for Player 2…" : "Waiting for Player 1…"
        default: return "Stand in front of the camera."
        }
    }

    private var cameraMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: camera.status == .denied ? "camera.fill.badge.xmark" : "camera.viewfinder")
                .font(.system(size: 48, weight: .light)).foregroundStyle(PlayerStyle.blue)
            switch camera.status {
            case .denied:
                Text("Camera access is required to play.").font(.title3.bold())
                Text("Allow camera access in Settings, then return to this app.").foregroundStyle(.secondary)
                Button("Open Settings") {
                    #if targetEnvironment(macCatalyst)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { openURL(url) }
                    #else
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    #endif
                }.buttonStyle(.borderedProminent)
            case .failed(let message):
                Text(message).multilineTextAlignment(.center).frame(maxWidth: 480)
                Button("Try Again") { controller.start() }.buttonStyle(.borderedProminent)
            case .interrupted:
                Text("Camera interrupted").font(.title3.bold())
                Text("Return to the app and make sure the camera is available.").foregroundStyle(.secondary)
            default:
                ProgressView()
                Text(camera.status == .requestingPermission ? "Allow camera access to begin." : "Starting camera…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}
