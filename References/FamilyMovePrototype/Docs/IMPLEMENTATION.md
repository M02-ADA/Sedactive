# Implementation report

## Architecture and source inventory

The original tracking prototype was retained and moved into `FamilyMove/`. The app uses feature views/view models, focused services and repositories, and pure game systems. No networking or dependency-injection framework is involved.

| Directory | Responsibility |
| --- | --- |
| `App/` | SwiftData container, startup failure state, profile-driven app routing, main-actor tracking coordination |
| `Models/` | `FamilyMember`, `GameSession`, `ParticipantSessionStat`, `AppSettings`, `GameType` |
| `Persistence/` | Profile/settings repository, completed-session repository, model-to-record mapping, pure statistics service |
| `DesignSystem/` | Named asset colors, typography, spacing, button style, member avatars |
| `Features/Onboarding/` | Profile form validation, Add Member sheet, minimum-two onboarding |
| `Features/Home/` | Local-time greeting, weekly household activity, game cards/artwork, detail sheets |
| `Features/PlayerSelection/` | Ordered two-member selection and adding another member |
| `Features/GameSession/` | Explicit session state machine, readiness, calibration, countdown, gameplay composition, results |
| `Features/Progress/` | Personal metrics, history, derived achievements, measurement and goal editors |
| `Camera/` | Permission, iPad front camera/MacBook webcam capture, interruptions, mirrored preview and orientation |
| `BodyTracking/` | Vision adaptation, coordinate conversion, spatial assignment, smoothing, calibration, debug rendering |
| `Games/Shared/` | Timestamp clock, constants, participant counters, feedback, provisional energy estimator |
| `Games/WhackAMole/` | Mole model, weighted body-relative spawning, wrist collisions, timeout/respawn engine and rendering |
| `Games/BirdsAndAlligators/` | Obstacle stream, per-player movement detector, engine and rendering |
| `Resources/` | Privacy Info.plist and named asset colors |
| `Tests/TrackingCoreTests/` | Tracker/mapping, game systems, complete-round, persistence and calendar tests |
| `Tests/UITests/` | Onboarding/relaunch, detail/selection, and progress-edit UI flows |
| `Scripts/` | Project membership synchronization, milestone builds, portable core checks |

The exact file inventory is in [FILES.md](FILES.md). The Xcode project includes every app Swift source explicitly. The Swift Package compiles the same production core, persistence, and coordinator sources on macOS for tests. Tests do not replace Apple frameworks with mocks for persistence.

## Body tracking

`AVCaptureVideoDataOutput` uses a moderate capture resolution, requests 30 fps where supported, and discards late frames. Camera configuration and Vision run on one serial background queue. `VNDetectHumanBodyPoseRequest` produces internal observations with wrists, elbows, shoulders, hips, knees, ankles, and root. Points below confidence 0.30 are discarded. Up to two strongest usable bodies are retained. Vision starts at most 15 requests/second and never queues concurrent requests; its gate stays closed until the main thread consumes the result.

Capture pixels are rotated upright and left unmirrored. Vision receives `.up`. Both preview and output use the same semantic landscape orientation. The preview is mirrored; the shared coordinate mapper mirrors X, flips Y, scales to aspect fill, and applies crop offsets using actual pixel-buffer dimensions. Every gameplay system and debug marker consumes the same mapped screen values. Aspect-ratio changes clear old identity anchors and calibrations.

Initial mirrored left/right positions define P1/P2. Subsequent frames compare both complete assignments against prior centers and minimize total motion. This is spatial continuity, not person recognition. A center is retained for one second after loss to help reassignment; unavailable wrists/leg joints are immediately cleared. A watchdog clears stale actionable joints after 0.30 seconds without fresh results. EMA alpha is 0.30.

## Positioning and calibration

The selected names and standing sides are displayed before play. Whack the Mole requires visible shoulders and hips; Birds & Alligators additionally requires knees and ankles inside the preview. Both need continuous readiness for one second. Calibration averages at least five distinct pose samples over another second, rejecting excessive hip/shoulder movement or torso-scale variation, storing shoulders, hip/body baselines, torso length, shoulder width, and available leg landmarks. A 3–2–1–GO countdown precedes timer start.

The session has one state enum: positioning, calibrating, countdown, playing, paused, gameOver. A manual pause stays paused until Continue is chosen. Exiting a started round asks for confirmation while paused. Landscape flips invalidate poses/calibration and require setup again. Game time uses monotonic timestamps through `RoundClock`; pause and setup time are excluded. If both bodies disappear for two seconds, the round pauses. Camera/app interruptions require positioning, recalibration, and countdown before resuming. Completed rounds and their scores survive app state changes; an abandoned incomplete round is not persisted.

## Whack the Mole

Each player has one active mole. Spawn weights are side 40%, overhead 30%, low 30%, with at most two consecutive repeats per player. Positions use calibrated shoulders/hips and torso/shoulder dimensions, then clamp to the player's half and visible bounds clear of the HUD and bottom labels. The three visible holes stay fixed until recalibration. Targets encourage outer-side, overhead, or low reaches.

Only the owning player's available wrists may collide. Distance must be within visual radius × 1.3. A successful target is removed immediately, so it can score only once. Hits add 10, expiration after two seconds adds one miss without a penalty, and the next target waits 250–500 ms. Movement-zone counts, reactions, contributions, hits and misses are retained independently per player.

## Squats and jumps

`MovementDetector` is independent of SwiftUI, Vision, and the obstacle spawner. Each player's state progresses through standing, moving, qualified, and returning. It first observes standing to arm; stale/lost input cancels the in-flight movement. The detector uses fresh pose samples, not repeated render ticks.

Squats qualify when hips descend 18% of calibrated torso height, with knee-angle evidence below 125° when available. Jumps qualify when hips rise 13% of torso height, with ankle rise of at least 5% of torso height when those landmarks are available. Both complete only on return within 7% of the standing baseline, with a minimum 0.10-second movement duration, maximum two-second movement duration, and 0.5-second cooldown. A detector reset preserves its recent-completion cooldown.

Each player has a separate obstacle stream. Birds expect completed squats; alligators expect completed jumps. Wrong movements do not score. A movement must begin and complete while that obstacle is active. Obstacles expire after two seconds, wait 250–500 ms, and cannot repeat more than twice consecutively.

## Persistence

SwiftData stores profiles/settings and completed rounds with two participant records. Relationships link participant → member and participant → session. Session deletion cascades to its participant records; member removal would nullify participant membership. Profile edits save explicitly with rollback on failure. The app chooses initial onboarding from the actual profile count.

Every round has a UUID generated before play. The repository checks it before inserting, so automatic game-over save, Done, Retry Save, and Play Again share the same idempotent path. Failed saves remain visible on results and can be retried. Each replay receives a new UUID. Historical estimated calories are stored values and do not change after weight editing. Camera imagery is never stored.

## Statistics

A pure `StatisticsService` consumes value records mapped from persisted sessions. Home counts each completed session's duration once, regardless of participant count. Progress filters sessions by selected member ID. Calendar-week boundaries come from `Calendar.dateInterval(of: .weekOfYear)`, and streaks count distinct calendar days ending today or yesterday. DST changes do not rely on fixed 24-hour arithmetic. Household/personal high scores, weekly calories, capped goal percentage, and achievements derive from this history. Goal range is 1–30 with a default of 10.

Energy estimates use `MET × 3.5 × kg / 200 × minutes`, stored independently per participant. The centralized prototype intensity defaults are 3 MET for Mole and 4 for Birds. These values are provisional assumptions, not validated measurements or medical guidance.

## Assumptions and remaining device work

- Native sheets, project-owned SVG illustrations, and SF Symbols follow the supplied layouts. Countdown/success/completion audio cues and a stored mute preference are included. Preview video and temporary photo sharing remain optional and omitted.
- Height is optional and informational. Calibration determines gameplay dimensions.
- Movement counting occurs after returning to standing, so a complete movement must fit the obstacle's two-second window. Window length and movement thresholds are centralized for device tuning.
- The existing `videoOrientation` APIs remain available but deprecated on iPadOS 17+. Their use keeps output and preview consistent across iPad sensor mounts; a future RotationCoordinator migration needs hardware alignment validation.
- Spatial matching can change identity after crossing, a long disappearance, or extra bystanders. Lighting, clothing, occlusion, distance, and camera view affect confidence.
- No physical iPad camera tests, latency measurements, hit-accuracy study, or adult/child reach study have been performed. Software tests establish deterministic behavior, not those hardware outcomes.
- The full application is implemented, but physical-iPad acceptance remains required before calling the movement experience validated. See `VALIDATION.md`.

## Simulator fixtures

`App/UITestPoseSource.swift` provides Debug-only, launch-argument-guarded synthetic screen-space joints for automated game-flow tests. It is disabled in Release and bypasses Vision entirely; its scores and reaction timings are synthetic test data. Full camera and physical-movement acceptance remain unverified. See `PERFECTING.md`.

## Interactive Simulator play

`SessionInputMode` defaults to the real camera on every target. The separate FamilyMove Simulator scheme explicitly supplies `--simulator-controls`; that override is accepted only in Debug on Simulator. Explicit Debug-only automated test fixtures take precedence for UI tests. `SimulatorInput` stores short click/reach and duck/jump pulses; `SimulatedBodyPose` turns them into tracked joints. Existing collision and movement engines validate actions and update stats. There is no direct score increment from a UI button. Manual rounds stay at the normal duration; test-only short rounds require a separate flag plus the isolated UI-test mode. Simulated modes have a visible no-camera label. See `SIMULATOR.md`.

## Camera arcade presentation

The front-camera preview remains the full gameplay background. `HandFeedback` receives mapped `TrackedPlayer.confidentHands`; `CollisionDetector` consumes the same points. The cyan/pink wrist rings are visible without debug mode. Short trails retain genuine observation timestamps only, clear missing/low-confidence hands, and expire stale input after the existing maximum pose age. The effect never performs a second coordinate conversion or changes scoring.

`MoleArenaLayout` creates three fixed sites per calibrated player. The spawner and renderer use that same layout, so every active mole occupies a visible hole. The arena adapts to each shoulder width and torso length and remains within the corresponding half and HUD bounds. Sites are anchored for the round instead of following the body while it reaches. Repositioning recalibrates the arena. Native SwiftUI cave edges, hole rims, pop animations, hit bursts, and compact corner score/timer displays provide the arcade presentation without downloaded branding. The round remains 60 seconds with a shared score; the reference screenshot's hearts do not introduce a new life system.

## MacBook support

The existing FamilyMove app target also builds for Mac Catalyst (macOS 14+), with local ad-hoc signing, an app sandbox, and the camera entitlement. Mac builds use a separate bundle identifier and local data container. `CameraManager` discovers built-in wide-angle and external cameras with unspecified position on Mac; iPad retains front-camera selection. Both feed the same pixel-buffer Vision detector, mapper, tracker, and gameplay engines. Mac capture and preview keep native webcam rotation at zero and mirror only the preview/mapped points. iPad's semantic landscape orientation remains unchanged.

The Mac window sets a minimum arena size; normal viewport changes still invalidate calibration. Camera denial opens macOS Camera privacy settings. Onboarding offers a camera check using the existing tracking diagnostics without creating sample profiles. `Scripts/build-mac.sh` builds Debug or Release, and `Scripts/run-mac.sh` builds/opens the local app. `MACBOOK.md` contains the user steps. A live MacBook camera check detected one player and wrists; two-person physical gameplay still needs manual validation.
