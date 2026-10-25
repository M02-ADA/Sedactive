# Laser Heist architecture foundation — working draft

Prepared for discussion on 25 October 2026. This proposes responsibilities and data contracts; it does not scaffold or change the app implementation.

**Follow-up:** [LaserHeist-Prototype-Comparison.md](LaserHeist-Prototype-Comparison.md) compares the actual `reference/kevin-prototype` source with Edward's current folders and supersedes the alternative layout below. The continuous-clearance policy in section 7 remains a proposal; the prototype banks a qualifying sample within a tolerance window. Fresh movement requirements also remain open. Do not treat either policy as an agreed implementation requirement.

## 1. Confirmed decisions and working assumptions

Confirmed by Edward:

- Two players participate simultaneously: a parent and a child.
- Both players share team health.
- Gameplay uses pose-based spatial collision: the player's estimated crown and soles determine clearance against lasers.
- The intended stack is AVFoundation, Vision, Core Image, SpriteKit, and SwiftUI.
- App screens are organized by feature.

Working assumptions to validate with the team:

- First slice: horizontal high/low lasers, with each player in an assigned play zone. Crossing and unrestricted movement are outside this slice; loss of assignment confidence pauses play rather than silently swapping identities.
- When either player loses tracking, the whole round pauses.
- A single encounter can remove at most one team health point, even if both players are hit. This is a proposed damage policy, not implied by shared health. If the team chooses damage per player instead, only the game rule changes.
- Maximum health, encounter duration, clearance margins, score rules, and round length are tuning values, not yet confirmed product decisions.
- Parent/child roles are assigned explicitly during setup. Apparent height and left/right position are not permanent identity.

The earlier research is useful prototype evidence, not a production specification. It contains older scoring, movement-detector, and scope proposals. Edward's confirmed decisions above take precedence. The chat retrieval exposes the prior user messages and two research attachments; prior assistant answers were returned as reference placeholders, so they are not treated as recovered advice.

Current repository: `SedactiveApp.swift` and `ContentView.swift` form a starter app. The project declares deployment target 26.5, Swift language mode 5.0, default MainActor isolation, and approachable concurrency. Those settings have not been changed; confirm the minimum supported iPad before implementation. No migration recommendation is made here.

## 2. Architecture fit and dependency boundaries

**Fit: feature-first organization with lightweight Clean Architecture boundaries.** This keeps camera/Vision replaceable and the game rules testable without a camera or SpriteKit. A small unidirectional state machine supports the session lifecycle. There is no need for a generic store framework, TCA dependency, repository for every service, or separate use-case file for every action.

- `Features`: SwiftUI screens and session orchestration.
- `Domain`: ordinary Swift values and deterministic game rules.
- `Motion`: framework-independent identity assignment and estimated body geometry.
- `Infrastructure`: camera, Vision, image processing, and audio implementations.
- `Rendering`: SpriteKit nodes, projection, and presentation resources.
- `App`: creates concrete dependencies and wires the boundaries.

Dependency direction:

```text
Features -------> Domain <------- Motion
Infrastructure -> Domain
Rendering ------> Domain
App wires Features, Infrastructure, and Rendering together.
```

Rendering may access image resources through a narrow presentation adapter. Domain never imports SwiftUI, SpriteKit, Vision, AVFoundation, or Core Image. Start with folders in one target; folders communicate ownership but do not enforce module boundaries. Separate targets/packages are a later option if dependency violations become a real problem.

`GameSessionCoordinator` means session orchestration here: it controls setup, capture lifecycle, pause/resume, and game handoff. It is not a navigation-only Coordinator pattern, and it does not contain laser collision math.

## 3. Proposed file map

This is a responsibility map, not a request to create every file immediately. Keep small related value types together until there is a reason to split them. Establish the contracts in section 4 and the first slice in section 11 before building the complete map.

```text
Sedactive/
├── App/
│   ├── SedactiveApp.swift
│   ├── AppDependencies.swift
│   └── RootView.swift
├── Features/
│   ├── Home/HomeView.swift
│   ├── Session/
│   │   ├── SessionView.swift
│   │   ├── GameSessionCoordinator.swift
│   │   └── SessionState.swift
│   ├── Setup/
│   │   ├── PlayerSetupView.swift
│   │   ├── CalibrationView.swift
│   │   └── CalibrationSession.swift
│   ├── Play/PlayView.swift
│   └── Results/ResultsView.swift
├── Domain/
│   ├── Players/
│   │   ├── Player.swift
│   │   └── PlayerCalibration.swift
│   ├── Tracking/
│   │   ├── BodyGeometry.swift
│   │   ├── BodySnapshot.swift
│   │   └── BodyInputProviding.swift
│   └── LaserHeist/
│       ├── LaserRules.swift
│       ├── LaserEncounter.swift
│       ├── LaserGameState.swift
│       ├── LaserGame.swift
│       ├── LaserWaveDirector.swift
│       ├── LaserCollisionJudge.swift
│       ├── GameEvent.swift
│       └── RoundSummary.swift
├── Motion/
│   ├── PoseFrame.swift
│   ├── PlayerTracker.swift
│   └── BodyGeometryEstimator.swift
├── Infrastructure/
│   ├── BodyInputService.swift
│   ├── Camera/CameraPipeline.swift
│   ├── Camera/FrameStore.swift
│   ├── Vision/PoseEstimator.swift
│   ├── Vision/PersonSegmenter.swift
│   ├── Compositing/PlayerCutoutCompositor.swift
│   └── Audio/AudioService.swift
├── Rendering/LaserHeist/
│   ├── LaserScene.swift
│   ├── LaserRenderer.swift
│   ├── PlayerCutoutNode.swift
│   ├── PlayerProjection.swift
│   └── GameRenderState.swift
└── Support/ReplayBodyInput.swift

SedactiveTests/
├── MotionTests.swift
├── CalibrationTests.swift
├── LaserCollisionTests.swift
├── LaserGameTests.swift
└── SessionTests.swift
```

Yes, this architecture has Models. `Player`, `PlayerCalibration`, `BodySnapshot`, `LaserEncounter`, `LaserGameState`, and `RoundSummary` are models. They live beside their responsibility; they do not need a global `Models/` folder. Most are value types, not observable objects or database entities.

## 4. Shared contracts: agree on these before splitting work

These are proposed fields, expressed in Swift-like notation rather than compilable source. Private construction/validation should enforce the invariants; external code should not freely mutate them.

| File/type | Essential data | Meaning and invariant |
|---|---|---|
| `Player.swift` / `Player` | `id: PlayerID`, `role: PlayerRole`, `zone: PlayZone` | ID remains stable throughout the session. Role is `.parent` or `.child`. Zone is an assignment, not the identity. No health property here. |
| `PlayerCalibration.swift` / `PlayerCalibration` | `playerID`, `standingCrownY`, `standingSolesY`, `standingHeight`, `headOffset`, `leftFootOffset`, `rightFootOffset`, `standingCenterX`, `validZone`, `geometryRevision`, `calibratedAt` | Baseline for one person. Height is derived from crown minus soles, not separately editable. Calibrate independently for parent and child. Offsets are estimates in the same coordinate system as pose. |
| `BodyGeometry.swift` | `NormalizedPoint(x: Double, y: Double)`, `NormalizedRect`, `BodyEnvelope(xRange, solesY, crownY)`, `GeometryRevision` | Values use the canonical upright, unmirrored full-camera image, lower-left origin, normalized 0–1. Missing or out-of-frame points are invalid, not clamped into a plausible body. |
| `BodySnapshot.swift` / `BodySnapshot` | `generationID`, `frameID`, `capturedAt: CaptureTime`, `geometryRevision`, `players: [PlayerID: PlayerBodySample]` | One atomic capture-time observation of both expected players. Every expected player has a usable or explicitly unavailable sample. Not an array whose order implies identity. |
| `BodySnapshot.swift` / `PlayerBodySample` | `playerID`, `geometry: BodyGeometryAvailability`, `tracking: TrackingStatus` | `geometry` is `.valid(BodyEnvelope)` or `.unavailable(reason)`. Tracking distinguishes reliable, uncertain, and lost. The estimator consumes landmark-level confidence; the game receives a validated result and reason, not one misleading averaged confidence. |
| `BodyInputProviding.swift` | `start() async throws`, `stop() async`, `latestSnapshot`, `status` | Main-actor-facing service interface. Status reports running, interrupted, failed, and stopped even if no frame arrives. Startup failure propagates; cancellation stops capture. Snapshot polling is synchronous and nonblocking on the game side. |
| `LaserRules.swift` / `LaserRules` | `maxTeamHealth`, `damagePolicy`, `roundDuration`, `clearanceMargin`, `maxPoseAge`, `maxSampleGap`, `verdictDeliveryBudget`, `scorePolicy` | Immutable configuration per round. Values are tuned later. Tracking confidence thresholds belong to the input configuration, not game rules. |
| `LaserEncounter.swift` / `LaserEncounter` | `id: EncounterID`, `targets: [LaserTarget]`, `warningAt`, `contactStartsAt`, `contactEndsAt`, `trajectory` | One obstacle/encounter. Targets identify affected player/zone and a horizontal laser band in canonical image coordinates at the player plane. Timing and geometry drive both judgement and drawing. |
| `LaserEncounter.swift` / `LaserTarget` | `playerID`, `zone`, `band: ClosedRange<Double>` | Band includes beam thickness. Targets may differ between parent and child based on their own calibration. The renderer must show the actual target bands. |
| `LaserGameState.swift` / `LaserGameState` | `elapsed: GameTime`, `team: TeamState`, `players: [PlayerID: PlayerRoundStats]`, `activeEncounters`, `encounterProgress`, `outcome` | Authoritative gameplay state, privately mutated by `LaserGame`. Progress contains judgement evidence and a damage-applied flag per encounter; it is pruned or archived when resolved. |
| `LaserGameState.swift` / `TeamState` | `health`, `score` | Exactly one health value for the team. Only `LaserGame` mutates it. Maximum health comes from immutable rules. |
| `LaserGameState.swift` / `PlayerRoundStats` | `hits`, `clears`, `judgedEncounters` | Personal feedback/statistics can exist despite shared health. Accuracy is computed, with zero judgements handled explicitly. |
| `GameEvent.swift` | Event ID, encounter ID, player IDs, game time; cases such as `.playerHit`, `.playerCleared`, `.teamDamaged`, `.roundEnded` | Domain facts, emitted once. Audio and VFX consume them without changing health. A player hit and team damage are distinct events. |
| `RoundSummary.swift` | `roundID`, `outcome`, `activeDuration`, `finalTeamHealth`, `teamScore`, `playerStats` | Immutable final result. Results receives this value, not the live camera, scene, or mutable game. Saving it is a separate future concern. |

`CaptureTime` and `GameTime` are deliberately different concepts. Capture time is a monotonic observation timestamp. Game time is active round elapsed time with pauses removed. `Date` is suitable for a human-readable result timestamp, not collision timing.

For the first implementation, identifiers can be lightweight wrappers around UUIDs. Use separate `PlayerID`, `EncounterID`, and generation identifiers so one cannot accidentally be passed in place of another. Fixtures use fixed IDs and scripted encounters for reproducible tests.

## 5. Ownership and variables in the remaining files

### App and features

| File | Owns / receives | Main operations and limits |
|---|---|---|
| `SedactiveApp.swift` | One stable dependency container and root view | Bootstrap only. |
| `AppDependencies.swift` | Live input service, audio implementation, factories for a session/scene | Constructor injection; also provide replay dependencies. No global singleton. |
| `RootView.swift` | Small route state such as home or session | App-level navigation. Round results remain inside the session flow. |
| `HomeView.swift` | `onStart` callback; optional local presentation state | Does not open the camera itself. |
| `SessionView.swift` | Stable reference to its session coordinator | Switches displayed feature from session phase. The coordinator survives setup → play → results. |
| `SessionState.swift` | `SessionPhase`, `PauseReason`, `SessionFailure`, `PlayHUDState` | Values, not another independent mutable state owner. HUD contains health, score, remaining time, and feedback derived from the game. |
| `GameSessionCoordinator.swift` | `phase`, stable `players`, `calibrations`, input/audio dependencies; private game, clock, latest accepted frame ID, short timestamped input history, cancellation handles, generation token | `start`, `tick`, `pause`, `resume`, `retry`, `end`. Runs lifecycle effects and routes events. Validates generation/freshness and maps capture time to game time. Never implements body estimation or collision formulas. |
| `PlayerSetupView.swift` | Assignments/readiness plus intent callbacks | UI for parent/child role and play-zone assignment. Emits intent; does not infer identities from array indices. |
| `CalibrationView.swift` | Calibration progress, per-player feedback, completion callback | Shows whether both people are visible and standing. |
| `CalibrationSession.swift` | Bounded recent standing samples per player, stability progress, configuration, validation errors | Produces validated `PlayerCalibration` values. A gameplay duck must not silently update the standing baseline. |
| `PlayView.swift` | Stable `LaserScene`, read-only HUD, pause/exit callbacks | Embeds SpriteKit and displays UI. It does not own the authoritative health or timer. |
| `ResultsView.swift` | `summary: RoundSummary`, retry/home callbacks | Read-only presentation; no dependency on a running session. |

Proposed phase vocabulary:

```text
idle → requestingCamera → settingUp → calibrating → countdown → playing
playing → paused(reason) → countdown → playing
playing → finished(summary)
startup/runtime failure → failed(recoverable reason)
exit → stop services → return home
```

Use enum cases with associated values where necessary. Do not store parallel flags such as `isPlaying`, `isPaused`, `hasFinished`, and `cameraFailed` that can contradict the phase. Maintain an explicit set of active pause blockers when causes overlap: recovering tracking must not resume while the app is inactive or the camera remains interrupted.

The coordinator can be a main-actor `@Observable` object. Keep the frame-rate game, buffers, scene references, and resource handles out of observation. Publish only UI changes needed by the HUD, with a suitably throttled timer display. A view that creates the coordinator retains it with private `@State`; other views receive it or receive just their required values.

### Motion, camera, and compositing

| File | Owned data / dependencies | Output and responsibility |
|---|---|---|
| `PoseFrame.swift` | Capture time, frame ID, geometry revision, candidates containing named joints with coordinates and confidence | Plain Swift values mapped from Vision; no `VNHumanBodyPoseObservation` escapes the Vision adapter. |
| `PlayerTracker.swift` | Previous center/shape estimates, last-seen times, explicit player/zone assignments, matching thresholds | Maps detection candidates to stable IDs with ambiguity/loss reasons. Never reassign parent/child solely because they exchange x positions. If reliable reassociation is impossible, request setup again. |
| `BodyGeometryEstimator.swift` | Calibration, measurement config; small per-player filter history if needed | Estimates crown/soles and horizontal extent, validates required landmarks and bounds, emits body geometry. If smoothing is used, its time constant is based on capture-time delta. |
| `BodyInputService.swift` | Camera/pose/segmentation/tracker/estimator/compositor/store dependencies; lifecycle status and generation | Implements `BodyInputProviding`. Coordinates one bounded pipeline and hides camera/Vision types from the game. Exposes render resources through a separate presentation adapter. |
| `CameraPipeline.swift` | Capture session/device/output, capture configuration, serial execution owner, interruption state | Produces frame IDs, capture timestamps, orientation metadata, and buffers. Start/configuration/image processing do not block the main actor. |
| `FrameStore.swift` | One latest complete published packet, synchronization mechanism, generation | Atomic handoff for metadata and associated image resource handles. A published buffer remains immutable/retained until its readers finish. No unbounded frame queue or frame history here. |
| `PoseEstimator.swift` | Reused Vision body-pose request, orientation policy, landmark mapping | Converts one camera frame to `PoseFrame`. More than two detections are candidates; the tracker chooses assigned players. |
| `PersonSegmenter.swift` | Reused segmentation request and quality configuration | Mask resources stamped with their source frame and geometry revision. Person segmentation alone does not assign parent/child identities. |
| `PlayerCutoutCompositor.swift` | Reused CI context, mask/crop resources, image transform metadata | Transparent body images with crop-to-full-image transforms and frame IDs. Mask/camera frames must match, or an explicitly bounded lag policy must apply. It does not decide HIT/SAFE. |
| `AudioService.swift` | Loaded sound resources, mute state, short event deduplication if needed | Plays game/lifecycle feedback. Audio callbacks do not drive game timing. |

The minimum input contract still needs enough head, ankle, and torso/extent information to estimate geometry and maintain identity. “Minimal landmarks” means using the relevant measurements, not assuming the detector returns crown/sole measurements directly or that only two points can solve all tracking tasks.

Do not add mandatory `SquatDetector.swift`, `JumpDetector.swift`, or `MovementState.swift` to this first slice. Geometric clearance answers whether the laser touched the player. Add action recognition separately when a concrete feature needs repetitions, tutorials, or form feedback. An `isJumping` Boolean is not proof the soles cleared a beam.

### Game and rendering

| File | Owned data / dependencies | Operations and limits |
|---|---|---|
| `LaserGame.swift` | Private `LaserGameState`, immutable rules, director state, judge state | Applies ordered inputs and active-time steps; returns events/renderable state. Sole authority for shared health, score, and ending the round. |
| `LaserWaveDirector.swift` | Scripted sequence, next index, next scheduled time; later a seeded RNG if needed | Emits encounters with explicit IDs and timing. It does not read the wall clock, spawn nodes, or change team health. Start with a fixed sequence. |
| `LaserCollisionJudge.swift` | Explicit per-encounter/per-player evidence in game-owned progress; clearance policy | Evaluates geometry over the contact interval and produces pending, hit, safe, or unjudgeable results. It does not damage the team. |
| `LaserScene.swift` | Nodes, latest render state/resource references, weak tick delegate | SpriteKit `update` supplies the one frame driver. It invokes a synchronous tick and applies the returned presentation. It does not create a second game or run camera processing. Avoid coordinator ↔ scene retain cycles. |
| `LaserRenderer.swift` | Node pool keyed by encounter ID, visual asset configuration | Draws beam positions/widths/stages from the encounter state and projection. Visual effects may decorate it but cannot move the authoritative collision geometry. |
| `PlayerCutoutNode.swift` | Player ID, texture handle, crop transform, visual appearance | Draws the cutout on the player plane. Cosmetic scaling/lift must not disconnect the rendered feet/head from judged geometry. |
| `PlayerProjection.swift` | Viewport size, aspect/crop transform, mirror flag, fixed player plane, perspective parameters, geometry revision | One mapping for body, beam, debug overlay, and cutout placement. Handles resize explicitly. An incompatible camera-geometry change pauses and invalidates calibration. |
| `GameRenderState.swift` | Read-only active time, encounters, body geometry, relevant events/feedback | Disposable presentation snapshot. It never becomes a competing source of health or score. Image resources are supplied separately, not embedded into pure domain values. |
| `ReplayBodyInput.swift` | Timestamped fixture sequence, cursor, controllable source time | Implements the same input contract without a camera. Can replay valid frames, missing feet, identity ambiguity, interruptions, and delayed delivery. It does not need video files for the first slice. |

## 6. Coordinate and collision contract

The first judge supports horizontal laser bands in assigned zones, not arbitrary silhouette collision. Crown and soles cannot establish whether a diagonal beam struck an extended arm. Expand the geometry contract only when that mechanic enters scope.

1. Normalize orientation before interpreting landmarks. Use upright, unmirrored full-image coordinates with lower-left origin: y increases upward.
2. Apply crop, display mirroring, and perspective only through the shared projection. Cropped cutouts retain their transform back into the full-image coordinate space.
3. Calibration establishes standing body size, floor baseline, head/foot offsets, and a valid play zone for each person.
4. A laser's band at the player plane is expressed in that same canonical space. Per-player body-relative difficulty can create different bands; both bands must be rendered as judged.
5. Crown is an estimate above head landmarks. Soles are estimates below both ankle landmarks. For jumping, use the lower of the two sole estimates so one raised foot cannot clear the whole body.
6. The body and beam overlap in x/assigned zone before evaluating their y ranges. Unexpected departure from the calibrated zone is a tracking/setup issue in this slice.

For a valid sample and an intersecting horizontal band, with a nonnegative clearance margin:

```text
duck clear: crownY < beamLowerY - clearanceMargin
jump clear: solesY > beamUpperY + clearanceMargin
otherwise: body envelope intersects the beam or lacks required clearance
```

These are proposed conservative game rules, not exact pixel-level collision. Crown/sole offsets and clearance margin need validation against the visible cutout. If that alignment cannot be made reliable, the team must choose a different geometry estimator before calling the visual result accurate.

Apple's 2D joint API lists eyes, ears, nose, neck, shoulders, hips, knees, and ankles; crown and soles are not direct joints: [supported joint names](https://developer.apple.com/documentation/vision/vnhumanbodyposeobservation/jointname).

## 7. One timeline, bounded input, explicit uncertainty

Rendering and judging use the same encounter trajectory and contact interval. Laser phase is derived from game time, not separately advanced by SpriteKit actions.

Proposed tick order:

```text
LaserScene.update(frameTime)
  → coordinator checks input-service status and current pause blockers
  → accepts a new snapshot only when generation/frame/geometry are valid
  → maps capture time to active game time and appends to a short history
  → processes fresh samples; checks age, validity, and expected players
  → if playable, advances the single game clock and LaserGame
  → handles emitted game events once, updates HUD as needed
  → returns GameRenderState; scene applies matching image resources
```

The clock can be a small private helper initially; split `GameClock.swift` when useful. It owns the last frame timestamp and active elapsed time. Reset the frame anchor on resume. Large frame gaps or app inactivity trigger pause/recovery, not a catch-up step that skips an entire encounter. There is no second Timer advancing laser state.

Capture timestamps and render timestamps are mapped to one known monotonic basis; their numeric values must not be assumed interchangeable. Keep the pause intervals/epoch needed to map delayed capture samples correctly. Reject stale samples and out-of-generation completion callbacks. Never relabel an old frame with its delivery time.

The raw pipeline keeps only bounded latest data. The game keeps a short, bounded history of numeric geometry covering the contact interval and delivery allowance. It processes each source frame once; repeated display frames are not independent observations.

Proposed interval policy:

- A fresh valid overlap sample during the active interval yields HIT.
- SAFE requires valid clearance observations covering the interval, with no gap greater than the configured maximum.
- Before enough evidence arrives, the verdict is pending.
- Finalization waits up to a bounded delivery allowance for camera latency. A gap, missing landmark, ambiguous identity, or stale input yields unjudgeable when coverage cannot be established.
- Unjudgeable causes pause/retry of the encounter without damage or a clear reward. A recommended simple MVP recovery is to cancel unresolved encounters, clear their evidence, and reissue them with new IDs after the recovery countdown. Completed outcomes are not replayed.
- The exact sample rate, allowed gap, and delivery allowance are measured/tuned on the target device. A frame-based system cannot guarantee detecting contact shorter than its observation gaps.

AVFoundation can drop late frames; the app must also bound work after the capture delegate. Returning quickly and launching unlimited asynchronous Vision tasks would still create a backlog. See [alwaysDiscardsLateVideoFrames](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/alwaysdiscardslatevideoframes).

## 8. Shared health, per-player judgement

For each encounter, keep independent results for each affected player. The game converts those facts into team consequences using the chosen policy.

Recommended first policy:

```text
parent HIT + child SAFE → one team health point lost
parent SAFE + child HIT → one team health point lost
parent HIT + child HIT → one team health point lost in total
both SAFE              → no damage; apply configured reward
input unjudgeable      → recover/retry; no automatic SAFE or HIT
```

An encounter-level `damageApplied` flag prevents repeat damage across frames and across a later hit by the other player. It lives with that encounter's game-owned progress, not in `LaserScene`. Distinct encounters can still damage the team separately; cross-encounter invulnerability would be an additional product rule.

Keep health within `0...maxTeamHealth`. At zero, the proposed behavior is round failure. Ending conditions, round duration, and exact scoring remain working proposals until the team agrees.

## 9. Isolation and lifecycle rules

- Main actor: observable session/HUD state and the SpriteKit scene adapter. Keep the small deterministic game step in the same serialized runtime initially.
- Background pipeline: capture configuration, Vision, and Core Image preparation on one explicit serial owner or appropriate actor/executor. `Task {}` inside a main-actor owner does not by itself move expensive synchronous work off it.
- Across that boundary: immutable numeric snapshots; narrowly managed image-resource handles. Do not declare raw pixel buffers, Vision requests, or SpriteKit textures Sendable merely to suppress diagnostics.
- A thread-safe mailbox needs a documented buffer-retention/immutability invariant. A protected pointer swap alone does not make a reused buffer safe.
- Keep actor isolation explicit for framework-facing facades. Verify value-type isolation under the project's default MainActor setting before implementing cross-boundary Sendable contracts.
- One session owns capture. Setup and Play consume the same service; screen changes do not create a second camera session.
- On exit, cancel session work, stop capture, release resources, and invalidate the generation token. On interruption, stop advancing gameplay and expose a recoverable reason. Capture status must reach the session even without a new frame.
- Restart is idempotent; stale async startup/calibration completions cannot revive an abandoned round. Recalibrate when camera geometry changes or player assignment cannot be recovered.

## 10. Three-person ownership proposal

| Owner | Primary responsibility | First concrete deliverable |
|---|---|---|
| Edward / tech lead | Shared contracts, pure game, session integration, review of timing/projection boundaries | Fixed two-player encounter sequence driven by replay input, with shared health and deterministic outcomes |
| Tech member 1 | Camera, Vision, tracking, geometry, calibration internals | Live `BodyInputProviding` implementation with explicit missing/uncertain states and stable assigned IDs |
| Tech member 2 | SpriteKit world, cutout presentation, shared projection, game HUD and feedback | Scene that consumes replayed bodies/encounters and overlays the actual judged crown/sole/beam geometry |

Assign each file one primary owner. Review shared contract changes with all affected owners before merging. The input developer can develop against fixtures, and the rendering developer can render the same fixtures; neither needs to wait for the complete live pipeline. The tech lead owns the integration of calibration UI with the input service rather than leaving that handoff unassigned.

## 11. Build the foundation as one thin vertical slice

1. Agree on the contract: coordinate origin, mirroring owner, IDs/roles/zones, capture vs active time, missing-input policy, and shared-damage policy.
2. Define the core values in a few files, plus a fake input source. Avoid dozens of empty classes.
3. Use two scripted players and one high/low laser sequence. Demonstrate parent-only HIT, child-only HIT, both HIT, both SAFE, and tracking loss.
4. Render exactly that sequence with a debug overlay. Confirm beam, estimated crown, soles, and cutout agree after mirroring/resizing.
5. Connect live camera/Vision behind the same interface. Validate two-player identity, calibration, latency, and pause/recovery on the actual iPad.
6. Add cutout quality, audio, results polish, and more mechanics only after this slice is reliable.

Meaningful initial tests:

| Test file | Behavior to verify |
|---|---|
| `MotionTests.swift` | Candidate order changes do not swap IDs; ambiguous assignment is surfaced; one foot raised does not create two-foot clearance; missing required landmarks invalidate geometry |
| `CalibrationTests.swift` | Separate parent/child baselines; unstable samples cannot finish calibration; geometry revision invalidates incompatible calibration |
| `LaserCollisionTests.swift` | Crown/sole boundaries, beam thickness, margin, time-window coverage, delayed frames, and missing evidence |
| `LaserGameTests.swift` | Both players hit one encounter → one proposed shared deduction; repeated updates do not repeat damage; separate encounters resolve independently; zero health ends the round |
| `SessionTests.swift` | Pause freezes active time; recovery countdown retries unresolved encounters; overlapping pause reasons block resume; stale generations are ignored; exit stops input |

Use supplied timestamps and fixtures rather than sleeping in tests. Projection/cutout alignment and identity under real motion also need device observation; pure tests alone do not validate the camera experience. These tests are proposed, not implemented or run by this document.

## 12. Decisions to discuss next

1. Confirm damage per encounter versus per player hit. Shared health alone does not decide this.
2. Confirm the first mechanics: horizontal high/low lasers in assigned zones, or a wider scope requiring more body geometry.
3. Agree on tracking-loss recovery: retry unresolved encounters after countdown, or another explicit policy.
4. Choose minimum iPad/OS and supported orientation. The current 26.5 deployment setting is only a repository fact.
5. Set a first-pass round ending and scoring rule before those fields become implementation commitments.

Feature-specific PR review checklist:

- Does the change preserve the agreed dependency direction and one owner for each mutable state?
- Are player ID, role, and play zone distinct, with team health stored only once?
- Are geometry, orientation/mirroring, and time units explicit at the boundary?
- Do the beam renderer and judge consume the same encounter geometry/timing?
- Can missing or stale input avoid becoming a false SAFE, with bounded work and idempotent recovery?
- Are camera effects cancellable, startup/runtime errors visible, and old generations ignored?
- Do replay tests cover the changed game behavior, and is any device-only claim backed by device evidence?
