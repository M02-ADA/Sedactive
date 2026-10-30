# Laser Heist: prototype comparison and first foundation

Working discussion, 25 October 2026.

Source inspected: local Git branch `reference/kevin-prototype`, commit `7218dc0e4dbc0688dd4fe54518b7d01fa4118187`. The branch was read through Git and extracted to a temporary review folder; the working branch was not switched. This comparison follows the current `Sedactive/Features`, `Motion`, `Game/LaserHeist/{Domain,Presentation}`, `Infrastructure`, and `Debug` structure. It supersedes the alternative folder layout in the earlier architecture draft.

Confirmed product decisions: two simultaneous parent/child players, shared team health, camera-driven body input, and crown/sole clearance as an important judgement input. Whether ordinary lasers require a fresh movement remains explicitly OPEN at Edward's request. Damage grouping, timing tolerance, round duration, and which advanced encounters ship first are also open.

## 1. What the actual prototype does

The Laser Breakout mode is a choreographed cooperative escape on a cart. The players occupy a fixed interaction plane in a pseudo-3D corridor. Gates approach that plane, turrets sweep through the lanes, each player receives their own cue, and the game combines individual contributions into a team result.

| Observed behavior | Source, relative to `StuntRunSpike/StuntRunSpike/` | Consequence for the foundation |
|---|---|---|
| High beam, floor sweep, and split duck/jump requirements | `LaserLogic.swift:53` | Model the requirement per player; one encounter is not necessarily one shared action. |
| One timing definition derives cue, crossing, and gate depth | `LaserLogic.swift:73` | Keep authoritative time/trajectory data together and have the renderer consume it. |
| Per-lane crossings/windows, including staggered turret crossings and a child allowance | `LaserLogic.swift:138`, `LaserLogic.swift:429`, `WorldScene+Laser.swift:623` | Do not assume both players are judged at exactly the same time. |
| Multiple gates can overlap during sequences | `WorldScene+Laser.swift:187`, `LaserLogic.swift:463` | Game state needs a collection of encounters, not only `currentLaser`. |
| Director script includes phases, breathers, sequences, checkpoint, override, and escape | `LaserLogic.swift:228` | Separate a mission beat from an individual laser encounter. Start with a short script. |
| A clear combines movement eligibility and measured body clearance | `LaserLogic.swift:174`, `WorldScene+Laser.swift:756` | Geometry and action recognition are separate inputs. Keeping both is a product decision, not an architectural requirement. |
| The clear is banked on a qualifying sample anywhere in a tolerance window | `JumpSweepLogic.swift:73` | This is not continuous contact simulation. Preserving it and requiring clearance throughout an interval produce different behavior. |
| A squat serial can be consumed once; held squats do not clear successive beams | `LaserLogic.swift:118` | A fresh-movement policy needs per-player movement identity/history. Leave that policy open. |
| Crown/feet are obtained from rendered body placement and converted to world height | `WorldScene+Checkpoint.swift:81` | Extract a shared placement/measurement contract so the domain does not query SpriteKit nodes. |
| Hits give feedback and increase Security Alert; they do not remove Team Power | `WorldScene+Laser.swift:850`, `LaserLogic.swift:197` | Shared health is a new domain rule. Security Alert is not a health implementation. |
| Hide checkpoint measures a proportion of time concealed | `LaserLogic.swift:565` | A hold objective needs duration evidence, unlike the ordinary laser's banked success. |
| Final override requires completed squat reps independently from both players | `LaserLogic.swift:329` | Action events have a concrete purpose if this objective enters scope. |
| Pause withdraws an unresolved laser/sequence and queues a retry; tracking recovery waits for explicit resume | `WorldScene+Laser.swift:1382`, `CoopLogic.swift:80` | Recovery policy must be explicit; distinguish the logical encounter from a new retry attempt. |

Important details in the code:

- The comments describe freshness relative to warning, but the live gate path takes `duckMark` when the encounter is created at reveal (`WorldScene+Laser.swift:612–641`). Decide the intended boundary before reproducing it.
- The ordinary judge treats an absent `clear` dictionary entry as no clearance veto. Missing measurements can therefore fall back to detector eligibility (`LaserLogic.swift:174–182`). A production input contract should represent unavailable evidence explicitly.
- `PersonPose` is already mirrored in the prototype (`Pose.swift:16`). The previous draft proposed unmirrored canonical coordinates. Either convention can work, but carrying prototype math into the other convention without conversion would invert assignments.
- Left/right zone assignment is positional, with limited memory for a lone detection (`Pose.swift:97–149`). It is not persistent parent/child identity tracking.

These are observations from static code review and the logic harness, not a new device-validation result. The branch's laser evidence README identifies its animated gameplay captures as simulated input; this does not negate Edward's separately reported hands-on prototype test.

## 2. Keep the current folders

**Fit:** lightweight Clean Architecture boundaries, with MVVM limited to screen presentation. The existing folders already express this well:

```text
Infrastructure → Motion values/processing → game input
                                         ↓
Features/Play orchestration → Game/LaserHeist/Domain
                                         ↓
                          Presentation + HUD + audio
```

The arrows describe runtime flow. The compile-time dependency rule is that `Game/LaserHeist/Domain` may consume plain motion values, but never imports Vision, AVFoundation, Core Image, SwiftUI, or SpriteKit. `AppDependencies` constructs concrete implementations. Constructor injection and a small input-source protocol make replay input interchangeable with live input.

Do not move everything into a new top-level `Domain` just to match the earlier proposal. `Game/LaserHeist/Domain` and its neighboring `Presentation` folder are sensible. Avoid dependency-heavy use-case/repository layers for this local frame-driven game.

The prototype's useful seams are its pure rule types, one bounded camera pipeline, one latest-frame handoff, shared trajectory math, and scripted inputs. Preserve those ideas while separating scene state from gameplay state.

## 3. The core ownership decisions

| Owner | Authoritative state | Must not own |
|---|---|---|
| `GameSessionCoordinator` | Session phase, service lifecycle, pause blockers, generation, integration handles | Collision equations, a second health value, detector thresholds |
| `GameClock` | Active elapsed game time and frame anchor | Mission script or node animations |
| `MotionEngine` | Per-player tracking/measurement state; optional movement-detector history | Encounter outcomes, health, score |
| `LaserGame` | `LaserGameState`, director/judge progression, shared health, scoring, end condition | Nodes, camera requests, sound playback |
| `PlayViewModel` | Presentation-only state such as a dismissed hint or HUD formatting | Another independently advancing timer/game/health |
| `LaserScene` / `LaserVisuals` | Nodes, textures, visual interpolation and event feedback | Authoritative encounter resolution or health |

The scene can supply the one frame callback. The coordinator performs the synchronous ordered tick, then the scene applies a render snapshot. Avoid a strong retain cycle in that callback. No second Timer advances gameplay.

Keep these three kinds of phase distinct:

- **Session phase:** setup, calibration, countdown, playing, paused, finished, failed.
- **Mission phase:** alarm, pursuit, lockdown, if the first content script uses them.
- **Encounter phase:** warning, approach, cue/contact, recovery, resolved; mostly derived from encounter time.

They answer different questions. A session can be paused during pursuit while an encounter is approaching.

## 4. Data to establish in your actual files

These are design contracts, not implemented declarations. Use related types in the existing files before splitting more files. Prefer immutable input/output values and private mutation at the owning engine.

### Motion

| File | Proposed foundation |
|---|---|
| `Motion/Models/PlayerID.swift` | Stable `PlayerID`; separate `PlayerRole` and `PlayerAssignment(playerID, role, zone)`. Role and lane must not be inferred from array order. |
| `Motion/Models/PersonPose.swift` | `Joint`, `JointPoint(x, y, confidence)`, `PersonPose(joints, imageAspect)`. Pose coordinates explicitly state upright orientation, origin, and mirror convention. A frame envelope adds frame ID, generation, capture time, and coordinate revision. |
| `Motion/Models/BodyClearance.swift` | Validated geometric measurements such as `crownHeight`, `leftSoleHeight`, `rightSoleHeight`, horizontal extent, and unavailable reasons. Heights are explicitly in shared player-plane units. Both soles are required for reliable two-foot clearance. This model does not contain a universal `isSafe`. |
| `Motion/PlayerCalibration.swift` | Per-player standing baseline, standing span, head/foot offsets, image-to-player-plane scale/offset, valid play zone, coordinate revision. A person's crouch must not become the new standing height. |
| `Motion/PlayerTracker.swift` | Last reliable positions/timestamps and explicit assignments; outputs assigned poses plus reliable/uncertain/lost status. A positional tracker cannot promise identity through arbitrary crossing/occlusion. |
| `Motion/BodyMeasurementExtractor.swift` | Takes pose, calibration, and agreed placement transform; returns valid measurements or a reason it cannot measure. It must not read SKNode positions. |
| `Motion/MotionEngine.swift` | Owns tracker/estimator state and calibrations, handles a new source frame once, outputs one snapshot. If action policies are chosen, keep detector state per player here. |
| `Motion/JumpDetector.swift` | Optional action recognition: phase, takeoff/landing timestamps, rep/event identity. Do not make its Boolean the only way a body can clear a laser. |
| Suggested `Motion/Models/MotionSnapshot.swift` | `generationID`, `frameID`, `capturedAt`, `coordinateRevision`, and samples keyed by player ID. Each sample includes tracking/geometry availability and optional motion facts. It is the central team handoff. |

For `BodyClearance`, player-plane units preserve the prototype's useful corridor geometry. The exact units and calibration mapping should be agreed before implementation. They are virtual game units, not measured real-world meters.

Keep `PersonPose` image coordinates and `BodyClearance` player-plane heights visibly distinct in naming/types. The earlier draft's all-image-coordinate approach is an alternative, not a mix-and-match addition to this one.

### Laser domain

| File | Proposed foundation |
|---|---|
| `LaserModels.swift` | `EncounterID`, `LaserPattern`, `LaserTiming`, per-player `LaserTarget`, `Judgement`, `GameEvent`, immutable `LaserGameConfig`, and `RoundSummary` initially. A mission beat can later contain a single laser, sequence, breather, checkpoint, or finale. |
| `LaserGameState.swift` | `teamHealth`, `teamScore`, per-player stats, mission progress, collection of active encounter states, and round outcome. Each encounter holds its targets, start time, judgement/effect-deduplication state, and retry-attempt identity when needed. |
| `LaserWaveDirector.swift` | Script/beat list, next index, next spawn time, active sequence progress. Start with a fixed short script. Do not let it create SpriteKit nodes. |
| `LaserCollisionJudge.swift` | Geometry evaluation with explicit judgement policy and temporal evidence per encounter/player. Missing geometry returns unavailable/pending rather than silently clearing. It returns facts; it does not mutate team health. |
| `LaserGame.swift` | Applies ordered snapshots/time steps, evaluates encounters, changes shared health/score once, emits events and final summary. It is the sole gameplay mutation owner. |

The minimum encounter contract should answer:

```text
Who is affected?       player IDs / assigned lanes
What is approaching?   pattern and physical beam geometry
Where does it touch?   shared player-plane geometry and trajectory
When does it matter?   start, cue, per-target crossing/window
What has happened?    per-target judgement and applied effects
```

Do not collapse those into `laserY`, `speed`, and `isHit`. That would lose the prototype's split/staggered timing and make replay/recovery fragile.

### Features and presentation

| File | Proposed foundation |
|---|---|
| `App/AppDependencies.swift` | Input-source, motion-engine, game, audio, and scene factories. Provide live/replay construction without global singletons. |
| `Features/Setup/PlayerSetupState.swift` | Assignments, camera readiness, per-player visibility/calibration progress, validation errors. UI readiness is not gameplay health. |
| `Features/Setup/PlayerSetuViewModel.swift` | Presentation intents and setup feedback. The current filename has a missing `p` in `Setup`; rename when editing it. Do not duplicate calibration baselines here. |
| `Features/Setup/PlayerSetupView.swift`, `CalibrationView.swift` | Render setup state and emit intents. Calibration accumulation can begin as a helper owned by the motion/setup boundary. |
| `Features/Play/SessionPhase.swift` | Explicit lifecycle enum and pause/failure reasons. Overlapping causes need pause blockers: tracking recovery alone cannot resume an inactive/interrupted app. |
| `Features/Play/GameClock.swift` | Last frame anchor and active elapsed time; freeze while paused, reset frame anchor on resume. Capture time and game time require an explicit mapping. |
| `Features/Play/GameSessionCoordinator.swift` | Input-source dependency, motion/game/clock instances, phase, generation, latest processed frame, cancellation handles, bounded observation history if the judgement policy needs it. |
| `Features/Play/PlayViewModel.swift` | Read-only HUD projection and genuinely local UI state. It can remain minimal until it has a responsibility beyond forwarding coordinator values. |
| `Features/Play/PlayView.swift` | Stable scene, HUD input, user-intent callbacks. |
| `Features/Results/ResultsViewModel.swift`, `ResultsView.swift` | Immutable `RoundSummary`, formatting if needed, replay/home intents. No live game/camera ownership. A simple result screen can receive the summary directly. |
| `Features/Home/HomeView.swift`, `ContentView.swift`, `App/SedactiveApp.swift` | Home/start intent, root routing, and one stable dependency/session lifetime. |
| `Game/LaserHeist/Presentation/LaserScene.swift` | Frame callback, node collections keyed by encounter/player ID, application of render state. |
| `Game/LaserHeist/Presentation/LaserVisuals.swift` | Beam/gate appearance and animation from the authoritative encounter state/time. Keep visual decoration outside collision geometry. |
| `Game/LaserHeist/Presentation/LaserCutoutNode.swift` | Player ID, frame resource, crop/placement transform, tint/light state. A texture is not an authoritative player measurement. |
| Suggested `Game/LaserHeist/Presentation/PlayerProjection.swift` | Viewport/perspective math. Consumes the same fixed player plane and placement data as judgement. Cosmetic camera movement must preserve their alignment. |
| Suggested `Game/LaserHeist/Presentation/GameRenderState.swift` | Read-only render values for encounters, players, and feedback. Image resource handles remain in the presentation adapter, outside pure domain values. |
| `Debug/PoseDebugOverlay.swift` | Displays frame age, player IDs, tracking validity, crown/soles, beam bands, and contact timing from the same values the game uses. |

### Infrastructure

| File | Proposed foundation |
|---|---|
| `CameraPipeline.swift` | Capture session/configuration, serial processing owner, generation/frame IDs, capture timestamps, interruption/failure status. Keep expensive capture configuration and image processing off the UI executor. |
| `FrameStore.swift` | Bounded latest data/resource packet with a documented retention/immutability invariant. Metadata and image resources must carry matching source IDs; separate calls to read metadata and copy the latest pixels do not guarantee the same frame. |
| `PoseEstimator.swift` | Reused Vision request and mapping to plain joint values. No gameplay or parent/child assignment here. |
| `PlayerCutoutCompositor.swift` | Reused CI resources, segmentation strategy, source-aligned mask/crop transforms, output-resource identity. Segmentation can begin as an internal helper; a separate file is optional. |
| `AudioService.swift` | Loaded sounds/mute state; reacts to uniquely identified events without changing game state. |

One session owns the input pipeline across Setup and Play. On exit: invalidate generation, cancel work, stop capture, release resources. On runtime interruption/error: expose service status even if no more frames arrive, pause gameplay, and recover explicitly. Async completion from an old session must be ignored. Cross-executor values should be immutable numeric snapshots; image buffers need narrow, verified ownership rather than blanket `@unchecked Sendable` adoption from the prototype.

## 5. What to preserve, extract, or decide

| Preserve | Extract/rework | Product decision still open |
|---|---|---|
| One bounded camera pipeline and latest-frame handoff | Split camera, Vision mapping, and compositing responsibilities without adding unbounded task queues | Initial device/orientation support |
| Pure rule values and deterministic fixtures | Split `LaserGate` into domain encounter state and presentation nodes | Fresh movement versus geometry alone |
| Shared timing/trajectory math | Move crown/sole calculation out of scene extensions using explicit placement | A tolerance-window clear versus continuous clearance |
| Per-player contribution and one resolved encounter result | Add shared team health as a new rule | Damage per player, per gate, or capped per sequence |
| Scripted encounters and generous per-player timing support | Separate role from zone and preserve calibrated baselines | Which checkpoint/override/advanced sequences enter the first release |

The prototype's `LaserRuntime` mixes script state, alert state, gate objects, flash/FOV values, HUD nodes, and scripts. Do not move that entire object into `LaserGameState`. Put gameplay values in the game, node/flash presentation in rendering, and service/lifecycle state in the coordinator.

The live-body code also follows the feet when grounding a standing player, then freezes the vertical offset during a detected jump (`WorldScene+Heist.swift:591–626`). That explains why jump detection currently affects how a jump looks. A new calibrated placement must preserve foot lift: re-grounding the cutout from the current ankles every frame would visually erase jumping. Extract the mapping, not only the detector call.

## 6. First delivery for the three-person team

1. **Agree on contracts:** identity/role/zone, coordinate conventions and player-plane mapping, frame/capture time, unavailable evidence, and encounter target/timing fields. Mark the unsettled gameplay policy rather than hard-coding it.
2. **Tech lead:** define those values, a short scripted encounter, and `LaserGame` with shared health and event deduplication. Use supplied timestamps and fixed IDs.
3. **Member 1:** implement pose → assigned player → calibration/measurement → `MotionSnapshot`, initially with fixtures and then live capture.
4. **Member 2:** render the same scripted encounter/body measurements with the shared projection and a debug overlay; then add cutout resources.
5. **Integrate one high beam, one low beam, and one split gate.** Observe individual results, team consequences, pause, tracking loss, and retry. Only then generalize sequences and special objectives.

Under the game's input protocol, provide a fixture/replay implementation so neither teammate waits for the live camera. A scene or game test should not need to instantiate AVFoundation.

Small meaningful checks: both soles must clear a low beam; missing measurements stay unavailable; repeated frames do not repeat damage; distinct targets keep their own crossing times; pause freezes gameplay; old-generation callbacks are ignored; retry does not accidentally re-award an already completed objective. With shared health, decide whether a whole-sequence retry retains earlier damage/rewards before allowing it to duplicate outcomes.

The current project has one app target and placeholder files under `Sedactive/Tests`, with no unit-test target. Connect those files to a real test target before expecting them to run. No source restructuring or foundation implementation was performed in this review.

## 7. Verification and review checklist

The existing prototype's pure logic harness compiled in Swift 6 mode and ran successfully from the extracted snapshot: **All logic tests passed**. The driver contains numbered groups through 65, covering multiple modes, including Laser Breakout choreography, freshness, turret crossings, body interaction, and Body-Fit geometry. It does not validate live tracking, cutout alignment on an iPad, or the new shared-health rule.

Review each foundation PR for:

- One authoritative owner for health, time, calibration, and identity.
- No camera, SpriteKit, or SwiftUI dependency inside game rules.
- Explicit coordinates, placement revision, frame identity, and time basis.
- Renderer and judge consuming the same target geometry and encounter timeline.
- Missing/stale input represented rather than silently cleared.
- Bounded work, cancellation, visible lifecycle failures, and ignored stale completions.
- Meaningful fixture coverage and device evidence for any camera/performance claim.
