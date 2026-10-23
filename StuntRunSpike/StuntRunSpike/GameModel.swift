import Foundation
import Observation

enum ViewMode: String, CaseIterable, Identifiable {
    case camera = "A · Camera"
    case immersive = "B · Immersive"
    var id: String { rawValue }
}

enum InputStatus: Equatable {
    case starting
    case camera
    case simulatorTestCard
    case unavailable(String)

    var label: String {
        switch self {
        case .starting: "Starting camera…"
        case .camera: "Live camera"
        case .simulatorTestCard: "Simulator test card (no camera)"
        case .unavailable(let reason): reason
        }
    }
}

struct MetricsSnapshot: Equatable {
    var renderFPS = 0.0
    var frameTimeAvgMs = 0.0
    var frameTimeMaxMs = 0.0
    var hitchesPerMin = 0.0
    var visionFPS = 0.0
    var poseMs = 0.0
    var segmentationMs = 0.0
    var compositeMs = 0.0
    var captureToTextureMs = 0.0
    var feedbackLatencyLastMs: Double?
    var feedbackLatencyAvgMs: Double?
    var droppedCameraFrames = 0
    var memoryMB = 0.0
    var thermal = "nominal"
    var people = 0
    var maskSize = ""
    var sourceSize = ""
    var degraded = false
}

/// Shared state between SwiftUI controls and the SpriteKit scene. The scene reads it once per frame;
/// SwiftUI only observes the low-frequency fields (controls and metrics refreshed twice a second).
@Observable
final class GameModel {
    var mode: ViewMode = .immersive
    var systemReduceMotion = false
    var reduceMotionOverride = false
    var autoplay = true
    /// Developer overlays start hidden in Moonbound (polished presentation); the gear button / `h` opens them.
    var showMetrics = GameMode.fromLaunchArgument == .stuntRun || GameMode.fromLaunchArgument == .jungleDrift
    var swapRoles = false
    var soundOn = true
    var controlsExpanded = GameMode.fromLaunchArgument == .stuntRun || GameMode.fromLaunchArgument == .jungleDrift
    /// Which game the scene plays (`-gameMode jungle` at launch; the dev panel switches by recreating the scene).
    var gameMode: GameMode = .fromLaunchArgument
    /// TEAM DUCK presentation: hero (baked 3D debris + layered FX) or Revision 3's original (`-heroFX legacy`).
    var heroFX = true
    /// Mirrors the scene's play state for the controls (updated only on transitions).
    var playState: PlayState = .countdown(endsAt: 0)
    var scriptRunning = false
    var inputStatus: InputStatus = .starting
    var metrics = MetricsSnapshot()

    /// Opt-in test harness only (launch argument `-evidenceDir <path>`): periodic scene snapshots and a
    /// metrics log written locally for verification runs. Never enabled by default; nothing is uploaded.
    var evidenceDirectory: URL?
    /// Seconds between evidence snapshots (`-evidenceInterval`); each PNG encode costs a frame hitch.
    var evidenceInterval: TimeInterval = 3

    var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    var isHaltedForControls: Bool {
        switch playState {
        case .paused, .ready, .trackingLost: true
        case .running, .countdown: false
        }
    }

    var playStateLabel: String {
        switch playState {
        case .running: "State: running"
        case .countdown: "State: countdown"
        case .paused: "State: paused"
        case .ready: "State: ready — tap Resume"
        case .trackingLost(let zones): "State: tracking lost (\(zones.count))"
        }
    }

    /// Launch arguments for repeatable captures, e.g. `-cleanUI YES -mode camera -reduceMotion YES`.
    init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "cleanUI") {
            showMetrics = false
            controlsExpanded = false
        }
        if defaults.string(forKey: "mode") == "camera" { mode = .camera }
        if defaults.bool(forKey: "reduceMotion") { reduceMotionOverride = true }
        if defaults.string(forKey: "heroFX") == "legacy" { heroFX = false }
        if defaults.double(forKey: "evidenceInterval") > 0 { evidenceInterval = defaults.double(forKey: "evidenceInterval") }
        if let path = defaults.string(forKey: "evidenceDir") {
            // "documents" keeps device runs inside the app container, retrievable with `devicectl device copy from`.
            evidenceDirectory = path == "documents"
                ? URL.documentsDirectory.appendingPathComponent("evidence", isDirectory: true)
                : URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: evidenceDirectory!, withIntermediateDirectories: true)
        }
    }
}

nonisolated enum DeviceStats {
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
