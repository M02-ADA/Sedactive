# Source file inventory

Current app sources, test suites, and build/asset scripts:

- `FamilyMove/App/AppCoordinator.swift`
- `FamilyMove/App/AppRootView.swift`
- `FamilyMove/App/FamilyMoveApp.swift`
- `FamilyMove/App/RootView.swift`
- `FamilyMove/App/TrackingController.swift`
- `FamilyMove/App/UITestPoseSource.swift`
- `FamilyMove/BodyTracking/BodyObservation.swift`
- `FamilyMove/BodyTracking/BodyPoseDetector.swift`
- `FamilyMove/BodyTracking/CalibrationSnapshot.swift`
- `FamilyMove/BodyTracking/CoordinateMapper.swift`
- `FamilyMove/BodyTracking/DebugOverlayView.swift`
- `FamilyMove/BodyTracking/PlayerTracker.swift`
- `FamilyMove/BodyTracking/PositionSmoother.swift`
- `FamilyMove/BodyTracking/TrackedPlayer.swift`
- `FamilyMove/Camera/CameraManager.swift`
- `FamilyMove/Camera/CameraPreview.swift`
- `FamilyMove/DesignSystem/AppTheme.swift`
- `FamilyMove/DesignSystem/SessionSoundPlayer.swift`
- `FamilyMove/Features/GameSession/GameHUDView.swift`
- `FamilyMove/Features/GameSession/GameOverView.swift`
- `FamilyMove/Features/GameSession/GameSessionCoordinator.swift`
- `FamilyMove/Features/GameSession/GameSessionView.swift`
- `FamilyMove/Features/GameSession/TrackingTestView.swift`
- `FamilyMove/Features/Home/HomeView.swift`
- `FamilyMove/Features/Onboarding/AddMemberView.swift`
- `FamilyMove/Features/Onboarding/OnboardingView.swift`
- `FamilyMove/Features/PlayerSelection/PlayerSelectionView.swift`
- `FamilyMove/Features/Progress/FamilyProgressView.swift`
- `FamilyMove/Games/BirdsAndAlligators/BirdsAlligatorsEngine.swift`
- `FamilyMove/Games/BirdsAndAlligators/BirdsAlligatorsView.swift`
- `FamilyMove/Games/BirdsAndAlligators/MovementDetector.swift`
- `FamilyMove/Games/BirdsAndAlligators/Obstacle.swift`
- `FamilyMove/Games/Shared/GameConstants.swift`
- `FamilyMove/Games/Shared/GameSessionState.swift`
- `FamilyMove/Games/Shared/RoundClock.swift`
- `FamilyMove/Games/Shared/SessionEnergyEstimator.swift`
- `FamilyMove/Games/WhackAMole/CollisionDetector.swift`
- `FamilyMove/Games/WhackAMole/Mole.swift`
- `FamilyMove/Games/WhackAMole/MoleSpawner.swift`
- `FamilyMove/Games/WhackAMole/WhackAMoleEngine.swift`
- `FamilyMove/Games/WhackAMole/WhackAMoleView.swift`
- `FamilyMove/Models/AppSettings.swift`
- `FamilyMove/Models/FamilyMember.swift`
- `FamilyMove/Models/GameSession.swift`
- `FamilyMove/Models/GameType.swift`
- `FamilyMove/Models/ParticipantSessionStat.swift`
- `FamilyMove/Persistence/ProfileRepository.swift`
- `FamilyMove/Persistence/SessionRecordMapping.swift`
- `FamilyMove/Persistence/SessionRepository.swift`
- `FamilyMove/Persistence/StatisticsService.swift`
- `FamilyMove/Resources/Info.plist`
- `Package.swift`
- `Scripts/build.sh`
- `Scripts/generate-assets.py`
- `Scripts/sync-project.py`
- `Scripts/test-core.sh`
- `Tests/CommandLineRunner.swift`
- `Tests/TrackingCoreTests/GameSystemsTests.swift`
- `Tests/TrackingCoreTests/SessionCoordinatorTests.swift`
- `Tests/TrackingCoreTests/StatisticsTests.swift`
- `Tests/TrackingCoreTests/TrackingCoreTests.swift`
- `Tests/UITests/FamilyMoveUITests.swift`

Named colors, SVG illustrations, and WAV data assets live in `FamilyMove/Resources/Assets.xcassets/`. The project and shared scheme are in `FamilyMove.xcodeproj/`.

Manual Simulator support adds `App/SessionInputMode.swift`, `BodyTracking/SimulatedBodyPose.swift`, `Games/Shared/SimulatorInput.swift`, `Features/GameSession/SimulatorControlsView.swift`, and `Tests/TrackingCoreTests/SimulatorInputTests.swift`. `Scripts/sync-project.py` now reads the project as a plist and preserves Xcode-reformatted settings while synchronizing app sources.

Camera arcade presentation adds `BodyTracking/HandFeedback.swift`, `BodyTracking/HandFeedbackView.swift`, `Games/WhackAMole/MoleArenaLayout.swift`, `Tests/TrackingCoreTests/CameraGameplayTests.swift`, and `Docs/CAMERA-GAMEPLAY.md`. The app target now includes 57 Swift files.

MacBook support adds `FamilyMove/Resources/Mac.entitlements`, `Scripts/build-mac.sh`, `Scripts/run-mac.sh`, and `Docs/MACBOOK.md`, and enables Mac Catalyst in the existing app target. The native camera, preview, startup window, onboarding camera check, and platform-specific camera settings share the existing source files.
