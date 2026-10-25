# Laser Heist architecture reference

This is the consolidated folder reference, prepared on 25 October 2026. Use it in place of the alternative folder layouts in the earlier draft and prototype-comparison documents. It defines responsibilities; it does not mean every file has already been implemented.

The design has a simple purpose: screens display the experience, motion processing understands the players, game rules decide outcomes, and rendering draws the world. These parts exchange small data values so three developers can work independently.

## Complete structure

`[optional]` means add the implementation when a confirmed mechanic needs it. All other entries form the proposed foundation. They can be built gradually.

```text
Sedactive/                                      # Repository
├── Sedactive/                                  # App source
│   ├── App/
│   │   ├── SedactiveApp.swift                   # Starts the app
│   │   ├── AppDependencies.swift                # Creates and connects services and engines
│   │   └── RootView.swift                       # Chooses the app's current screen/flow
│   │
│   ├── Features/
│   │   ├── Home/
│   │   │   └── HomeView.swift                   # Home screen and Start action
│   │   ├── Setup/
│   │   │   ├── PlayerSetupView.swift            # Player assignment and readiness screen
│   │   │   ├── PlayerSetupState.swift           # Data that the setup screen displays
│   │   │   ├── CalibrationView.swift            # Calibration instructions and progress
│   │   │   └── CalibrationSession.swift         # Collects stable samples to calibrate players
│   │   ├── Session/
│   │   │   ├── GameSessionCoordinator.swift     # Connects input, game, and session lifecycle
│   │   │   ├── SessionState.swift               # Setup/countdown/play/pause/end state
│   │   │   └── GameClock.swift                  # Active game time; freezes while paused
│   │   ├── Play/
│   │   │   └── PlayView.swift                   # Hosts the game scene and SwiftUI HUD
│   │   └── Results/
│   │       └── ResultsView.swift                # Displays the completed round's summary
│   │
│   ├── Domain/
│   │   ├── Players/
│   │   │   ├── Player.swift                     # Player identity, role, and assigned zone
│   │   │   └── PlayerCalibration.swift          # Validated standing baseline for one player
│   │   ├── BodyInput/
│   │   │   ├── BodyGeometry.swift               # Crown/sole measurements and their validity
│   │   │   ├── BodySnapshot.swift               # Timestamped body data keyed by player ID
│   │   │   └── BodyInputProviding.swift         # Contract for live or replay body input
│   │   └── LaserHeist/
│   │       ├── LaserGame.swift                  # Applies rules, health changes, and scoring
│   │       ├── LaserGameState.swift             # Authoritative current gameplay data
│   │       ├── LaserEncounter.swift             # Laser targets, geometry, and encounter timing
│   │       ├── LaserWaveDirector.swift          # Chooses and schedules encounters/sequences
│   │       ├── LaserCollisionJudge.swift        # Evaluates player evidence against a laser
│   │       └── RoundSummary.swift               # Immutable result of a completed round
│   │
│   ├── Motion/
│   │   ├── PoseFrame.swift                      # Detected poses, joints/confidence, frame metadata
│   │   ├── MotionEngine.swift                   # Coordinates tracking and body measurement
│   │   ├── PlayerTracker.swift                  # Matches detections to stable player identities
│   │   ├── BodyMeasurementExtractor.swift       # Estimates geometry from pose and calibration
│   │   ├── JumpDetector.swift                   # [optional] Recognizes jump phases/events
│   │   └── SquatDetector.swift                  # [optional] Recognizes squat phases/repetitions
│   │
│   ├── Infrastructure/
│   │   ├── BodyInputService.swift               # Runs the live input pipeline
│   │   ├── Camera/
│   │   │   ├── CameraPipeline.swift             # Captures frames and reports camera status
│   │   │   └── FrameStore.swift                 # Safely hands off the latest bounded frame data
│   │   ├── Vision/
│   │   │   ├── PoseEstimator.swift              # Maps Vision results into plain pose values
│   │   │   └── PersonSegmenter.swift            # Produces a mask separating people/background
│   │   ├── Compositing/
│   │   │   └── PlayerCutoutCompositor.swift     # Produces transparent player images from masks
│   │   └── Audio/
│   │       └── AudioService.swift               # Plays sound feedback from game/session events
│   │
│   ├── Rendering/
│   │   └── LaserHeist/
│   │       ├── LaserScene.swift                 # Creates/updates SpriteKit world and laser nodes
│   │       ├── PlayerProjection.swift           # Converts shared game geometry to screen positions
│   │       └── PlayerCutoutNode.swift           # Displays each player's cutout and visual feedback
│   │
│   └── Debug/
│       ├── ReplayBodyInput.swift                # Supplies scripted snapshots without a camera
│       └── PoseDebugOverlay.swift              # Shows tracking, body bounds, and laser checks
│
├── SedactiveTests/                              # Separate unit-test target
│   ├── MotionTests/
│   │   ├── PlayerTrackerTests.swift             # Identity assignment and tracking loss
│   │   └── BodyMeasurementExtractorTests.swift  # Valid/invalid crown and sole measurements
│   ├── CollisionTests/
│   │   └── LaserCollisionJudgeTests.swift       # Clearance, timing, and unavailable evidence
│   ├── GameLogicTests/
│   │   ├── LaserGameTests.swift                 # Shared health, scoring, and duplicate prevention
│   │   └── LaserWaveDirectorTests.swift         # Encounter order and scheduling
│   └── SessionTests/
│       ├── GameClockTests.swift                 # Time progression and pause behavior
│       └── GameSessionCoordinatorTests.swift    # Start, pause/recover, exit, stale work
│
├── Docs/                                       # Architecture and team decisions
└── Sedactive.xcodeproj/
```

## Why these folders exist

| Folder | Simple question it answers |
|---|---|
| `App` | How do we start and connect everything? |
| `Features` | What does the user see and do on each screen? |
| `Domain` | What data and rules define the game? |
| `Motion` | What can we reliably understand about the players' bodies? |
| `Infrastructure` | How do camera, Vision, image processing, and sound actually work? |
| `Rendering` | How do we draw that game and those players? |
| `Debug` | How do we inspect or reproduce behavior during development? |
| `SedactiveTests` | How do we verify rules and processing without a live camera? |

The main architectural boundary is the domain: game rules do not depend on SwiftUI, SpriteKit, Vision, AVFoundation, or Core Image. UI, live services, and rendering connect to the domain's values/contracts. Constructor injection in `AppDependencies` selects concrete implementations.

## One frame through the system

`BodyInputService` implements `BodyInputProviding` for the live camera. It coordinates the following processing rather than putting all of it into one class:

```text
CameraPipeline → PoseEstimator → PoseFrame
                                    ↓
                               MotionEngine
                           ┌────────┴─────────┐
                      PlayerTracker    BodyMeasurementExtractor
                           └────────┬─────────┘
                                    ↓
                               BodySnapshot
                                    ↓
                         GameSessionCoordinator
                                    ↓
                                LaserGame
                         ┌──────────┴──────────┐
                  LaserWaveDirector    LaserCollisionJudge
                         └──────────┬──────────┘
                                    ↓
                         Game state and events
                                    ↓
                       Scene + HUD + sound feedback
```

There is also an image path: camera frame → person mask → transparent cutout → player node. This image path and the numeric body snapshot use matching source-frame identities and a shared placement mapping. The diagram is runtime data flow, not a requirement for the domain to import its outer adapters.

Optional detectors run inside the motion-processing flow when the chosen mechanic needs action facts. The game decides what those facts mean for an encounter.

## Important distinctions

### Data versus processing

`BodyGeometry` is data: for example, crown height and left/right sole heights with validity. `BodyMeasurementExtractor` is the code that calculates that data. Neither decides universal safety; the judge evaluates it against a specific laser.

`PoseFrame` contains plain raw pose values, including related `PersonPose`, joint, and confidence types if useful. There is no separate mandatory `PersonPose.swift` in this layout.

`BodySnapshot` contains identified, timestamped, game-facing measurements. It is the same central handoff previously called `MotionSnapshot`; use **BodySnapshot** consistently from here onward.

### Calibration work versus calibration result

`CalibrationSession` collects stable samples and validates them. Its output is `PlayerCalibration`, the baseline the rest of the system uses. `PlayerSetupState` exposes readiness, messages, and a progress projection for display; it does not independently calculate another calibration baseline.

The session coordinator owns the active setup/calibration flow. It passes completed calibration values to the input/motion processing. Calibration values have one source of truth.

### Live service versus motion engine

`BodyInputService` manages the live pipeline and its lifecycle. `MotionEngine` processes plain pose values, owns tracking/optional detector history, and produces body snapshots using supplied calibration values. Motion processing must not require a running camera or SpriteKit scene.

The service handles asynchronous startup, errors, interruptions, and stopping. The coordinator cancels/stops it on exit and ignores old-session completion callbacks. Keep capture/image work off the UI executor, use bounded latest-data delivery, and give every snapshot its capture timestamp. The service must report failure even if no further frame arrives.

### Session state versus game state

`SessionState` says where the app is in a round's lifecycle: setup, calibration, countdown, playing, paused, finished, or failed. `LaserGameState` says what is happening inside the game: team health/score, active encounters, individual results, and round progress.

`GameSessionCoordinator` owns the session state and the `LaserGame` instance. `LaserGame` privately mutates its game state. These are distinct responsibilities, not two copies of health or score.

`GameClock` is the single active-time source. The scene can provide frame callbacks, but it does not maintain another authoritative gameplay clock. Camera timestamps remain distinct from active game time and are mapped explicitly.

### Scheduling versus judgement versus presentation

`LaserWaveDirector` decides what obstacle comes next and when. `LaserEncounter` describes an obstacle, its targets, geometry, and timing; targets can differ between players. `LaserCollisionJudge` evaluates their evidence. `LaserGame` applies the result to shared health/score and emits events. `LaserScene` draws the result and reacts visually.

Use a collection of active encounters so overlapping gates can be supported. Keep node/texture references out of domain encounter state. Related pattern, timing, target, and judgement types can initially live in `LaserEncounter.swift`; related team/player statistics can live in `LaserGameState.swift`, and game-event definitions can initially live in `LaserGame.swift`.

`PlayerProjection` turns shared player-plane geometry into screen positions. Body measurement and cutout placement consume the same agreed mapping and calibration; measurement must not obtain its authoritative geometry by querying SpriteKit nodes.

## Naming and scope decisions

- Use **BodyMeasurementExtractor.swift**. Do not also create `BodyGeometryEstimator.swift`; these names previously referred to the same responsibility.
- Keep the calibration data model only in **Domain/Players/PlayerCalibration.swift**. The active sampling process is **Features/Setup/CalibrationSession.swift**.
- Use **BodySnapshot.swift** for the shared game-facing handoff; do not add a parallel `MotionSnapshot.swift` with the same data.
- `JumpDetector` and `SquatDetector` are optional. Geometry alone can establish clearance; detectors add takeoff/landing, fresh-action, or rep facts when mechanics require them. Fresh movement is still an open product decision.
- A separate `SessionPhase.swift` is not required initially. Its lifecycle enum can live in `SessionState.swift`.
- `PlayViewModel` and `ResultsViewModel` are not required for this foundation. Add one only when the screen gains presentation work that needs its own owner. Never duplicate authoritative health/time there.
- `ContentView.swift` is the existing starter screen; `RootView.swift` takes over its app-entry routing role when the foundation is wired. It is not a second root flow to maintain.
- The test directory must be connected to an actual unit-test target. Merely creating test folders inside the app source does not make tests runnable.

This reference fixes the folder layout and ownership boundaries. It does not settle fresh-action rules, timing tolerance, damage grouping, or the initial advanced encounter scope.

## Build and review order

Define players/calibrations, body snapshots, and one encounter first. Add replay input. Then implement a short replay-driven game, renderer, and debug overlay before integrating live capture. This lets the input developer and rendering developer work against the same examples.

Initial tests should cover missing landmarks, identity ambiguity, per-player target timing, repeated-frame deduplication, health changes, pause/recovery, and stale-session work. Add detector-specific tests when those optional mechanics are implemented. Real tracking and visible cutout/laser alignment also need target-device checks.

For each foundation change, review: one owner per mutable value; no platform dependencies inside rules; explicit coordinates/time/frame identity; matched drawing and judgement; visible input failure; bounded/cancellable work; and fixture coverage for the behavior changed.
