// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FamilyMoveCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "TrackingCore", targets: ["TrackingCore"])],
    targets: [
        .target(name: "TrackingCore", path: "FamilyMove",
                exclude: ["App", "Camera", "DesignSystem", "Features/Onboarding", "Features/Home", "Features/PlayerSelection", "Features/Progress",
                          "Features/GameSession/SimulatorControlsView.swift", "Features/GameSession/GameHUDView.swift", "Features/GameSession/GameSessionView.swift", "Features/GameSession/GameOverView.swift", "Features/GameSession/TrackingTestView.swift", "Resources",
                          "BodyTracking/BodyPoseDetector.swift", "BodyTracking/DebugOverlayView.swift", "BodyTracking/HandFeedbackView.swift",
                          "Games/WhackAMole/WhackAMoleView.swift", "Games/BirdsAndAlligators/BirdsAlligatorsView.swift"],
                sources: ["Features/GameSession/GameSessionCoordinator.swift", "Models", "Persistence", "Games", "BodyTracking/BodyObservation.swift",
                          "BodyTracking/CoordinateMapper.swift", "BodyTracking/PlayerTracker.swift",
                          "BodyTracking/TrackedPlayer.swift", "BodyTracking/PositionSmoother.swift", "BodyTracking/CalibrationSnapshot.swift", "BodyTracking/SimulatedBodyPose.swift", "BodyTracking/HandFeedback.swift"]),
        .testTarget(name: "TrackingCoreTests", dependencies: ["TrackingCore"], path: "Tests/TrackingCoreTests")
    ]
)
