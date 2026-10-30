# LH-00 checkpoint 1 — body-input contract proposal

**Owner:** Edo. **Reviewers:** Jevon and Kevin. **Revised:** 29 October 2026.

**Status: technical proposal finalized for an LH-00 CP1 branch implementation; implementation is not yet authorized. No Swift contracts are implemented by this document.** The accepted identity/calibration/body-data baseline and the Tech Lead's final delivery, display, timing and settings decisions are fixed. **Edo default** identifies a concrete local implementation choice, **Device tuning** identifies an unvalidated parameter, and **Integration review** identifies wiring/behavior Jevon or Kevin must review before merging. These are distinct from reopening product decisions.

Current approved decisions take precedence over older wording in TEAM_ALIGNMENT, the Architecture Reference and the gameplay draft. Section 15 records mismatches; this revision changes none of those files.

## 1. Scope, ownership and completed foundation

Checkpoint 1 defines framework-independent body values, input lifecycle behavior and deterministic replay evidence. It does not implement live capture, calibration processing, collision, rendering, profile UI/storage or energy calculations.

```text
Camera / Vision / segmentation    Edo: acquire observations
              ↓ PoseFrame
Motion / tracking / calibration   Edo: interpret observations
              ↓ BodySnapshot
Game / evidence selection         Jevon: select evidence and judge crossings
              ↓ shared game geometry and results
RealityKit presentation           Kevin: map and display the shared game world
```

`BodyInputService` runs the live input lifecycle and data flow: start/stop capture, connect processing and publish completed output. `MotionEngine` interprets poses and maintains motion/tracking state; it does not own an AVCaptureSession or know how to turn the camera on.

Jevon owns GameClock, bounded evidence history, evidence selection, LaserCollisionJudge, encounters, health and score. Edo supplies evidence, never verdict implementations. Kevin owns RealityKit rendering and GameWorldMapping. Domain contracts import no AVFoundation, Vision, RealityKit, Core Image or SwiftUI types. UUID may use Foundation without introducing camera or UI dependencies.

**LH-23 is completed**, as confirmed by the Tech Lead. The baseline is root-level `SedactiveTests/`, `Motion/CalibrationSession.swift`, `Rendering/LaserHeist/GameWorldMapping.swift` and `Rendering/LaserHeist/PlayerCutoutEntity.swift`. Static inspection during this revision found these paths and separate filesystem-synchronized app/test target groups. This is not a new build or Simulator verification, and LH-23 is not reopened here.

Image resources, ownership, orientation, cutout association and permitted display lag remain **LH-00 checkpoint 2**, agreed with Kevin. Do not create another body/cutout contract while that review is pending.

## 2. Accepted baseline and finalized technical decisions

| Classification | Decision |
|---|---|
| **Finalized — profiles/selection** | Player is persistent UUID-based id, name, weightKg; no PlayerRole or stored PlayZone. SelectedPlayers firstID/secondID derive displayed-left/displayed-right. No names/weight per frame. |
| **Finalized — high laser** | Valid crown and both direct Vision wrists; `max(crownY, leftWristY, rightWristY) + clearanceMargin < laserLowerY`. Wrist-only is the intentional MVP simplification. |
| **Finalized — low laser** | Valid both soles and valid airborne; `jumpPhase == airborne AND min(leftSoleY, rightSoleY) - clearanceMargin > laserUpperY`. |
| **Finalized — evidence/calibration** | Missing/stale/uncertain required evidence means UNAVAILABLE. Independent standing baselines, nose-specific head offset, separate ankle offsets, no wrist calibration or baseline changes during movement. Preserve distinct heights. |
| **Finalized — delivery** | Gameplay consumes `AsyncStream<BodySnapshot>` with `.bufferingNewest(8)` initially: eight complete two-player packets, bounded and lossy. One explicitly owned active consumer per generation continuously drains into Jevon's bounded history. |
| **Finalized — latest cache** | Separate read-only latestSnapshot is the compatible published snapshot with the highest capture-sequence frameID. A late older completion cannot replace it. It is diagnostic state, not Jevon's evidence history. |
| **Finalized — coordinates/display** | Upright unmirrored image/game evidence; normalized bottom-left camera origin, X right/Y up; player-plane floor Y = 0. Every player-facing live preview/cutout is mirrored once, preserving selected-first/displayed-left. |
| **Finalized — layout direction** | Shared PlayerPlaneLayout holds leftCenterX, rightCenterX and gameUnitsPerImageHeight. Calibration holds camera references, not copies of that shared scale or lane assignments. Numeric parameters need tuning. |
| **Finalized — time/lifecycle** | Capture, delivery and GameClock time are separate. One camera lifecycle across Setup → Calibration → Play where possible. Recalibration replaces context without reopening capture; gameplay pause does not automatically stop it. |
| **Finalized — LH-00 settings** | Preserve verified project-wide Swift/concurrency/deployment settings. Use immutable Sendable body values with deliberate non-MainActor Domain isolation and background processing. This is LH-00's convention, not whole-team B2 approval. |
| **Edo defaults / integration review / device tuning** | Concrete subscription/status/reset choices are in section 9, isolation in section 13, tests in section 18. Review categories and numeric tuning are explicitly separated. |

Wrist-only does not guarantee fingertip/elbow clearance. No leftHandTopY, rightHandTopY or hand-length fields are introduced. Jevon implements verdicts; this document finalizes only the input/evidence requirements and technical handoff.

## 3. Expected implementation locations — producer defines each type once

Paths here are relative to `Sedactive/`. These are future implementation locations, not files to implement in this revision.

| File | CP1 contents | Purpose |
|---|---|---|
| `Domain/Players/Player.swift` | PlayerID, Player, SelectedPlayers | Persistent profile and separate ordered session selection. |
| `Domain/Players/PlayerCalibration.swift` | PlayerCalibration, ImageToPlayerPlaneMapping | Standing measurements, offsets and conversion parameters. |
| `Domain/BodyInput/BodyGeometry.swift` | EvidenceValidity, EstimatedScalar, BodyGeometry; PlayerPlaneLayout | Live measurements, shared units and one shared session scale/layout. |
| `Domain/BodyInput/BodySnapshot.swift` | TrackingStatus, JumpPhase, JumpState, PlayerBodySample, BodySnapshot | One observation with explicit data for both selected UUIDs. |
| `Domain/BodyInput/BodyInputProviding.swift` | Provider interface, BodyInputConfiguration, context, delivery/status/failure/event/diagnostic values | Common live/replay lifecycle and bounded delivery behavior. |
| `Motion/PoseFrame.swift` | Raw pose candidate, joint and mask-measurement values | Internal Motion input, including both wrists and confidence. |
| `Debug/ReplayBodyInput.swift` | Replay provider and fixture decoding/control | Deterministic synthetic input without a camera. |

Supporting types can stay beside the main type; one file per type is unnecessary. Consumers import Edo's definitions instead of making local copies. Tests remain in root-level `SedactiveTests/`.

## 4. Player and ordered session selection

### Player — who the family member is

| Field | Representation | Simple explanation |
|---|---|---|
| `id` | PlayerID, a UUID-based value | Assigned when the family member is created. Stable across sessions, order changes and tracking loss. Never derived from a Vision candidate index. |
| `name` | String | Profile display name; not a unique identity key. |
| `weightKg` | Edo default: finite positive Double, kilograms | Reserved for future application-level energy estimation. Does not affect Motion, collision, health or score in LH-00. |

The three fields and UUID identity are accepted. Edo will verify concrete immutable value syntax during implementation; no profile UI, persistence or calorie algorithm is introduced here.

### SelectedPlayers — who is playing, in what order

**Accepted minimal fields:** `firstID: PlayerID`, `secondID: PlayerID`. Both must resolve to selected profiles and be distinct. This represents exactly two players without an arbitrary-length array.

- First selected ID determines logical left and must appear left during calibration and gameplay.
- Second selected ID determines logical right and must appear right.
- Selection stays fixed within an input-session generation. Reselection/reordering starts a new generation without changing profile UUIDs.
- Display names are resolved from selected profiles outside the camera-frame payload. Neither names nor weight belong in BodySnapshot or BodyInputConfiguration.
- Position is derived from selection order. Neither Player nor PlayerCalibration stores a zone, role or duplicate selection index.

Session A can select Kevin then Edo, while session B selects Edo then Kevin. Kevin keeps the same UUID, although his session position changes from left to right.

### Binding a selected UUID to an observed person

Vision does not know which family profile a body represents. Setup must bind selected UUIDs to the intended people using an agreed positioning/confirmation flow. This is setup association, not face recognition.

After binding, PlayerTracker preserves identity through candidate reordering and movement. Array position is never persistent identity. Overlap, tracking loss or ambiguous association produces uncertain/lost input for affected selected UUIDs; it must not silently swap identities or guess from the latest candidate order. The mirrored-preview binding and reacquisition/reconfirmation integration needs Jevon's setup-flow and Kevin's placement review.

**Final display policy:** every player-facing live camera presentation is mirrored horizontally exactly once, including calibration preview and gameplay cutouts. Initial UUID binding uses expected positions in that mirrored preview, never raw candidate order. Internal coordinates and anatomical left/right landmark labels remain unmirrored. Kevin reviews the effective preview/cutout/overlay transforms: mirror each player's imagery and local displayed movement while keeping the selected lane fixed. Never globally flip the world and exchange lanes.

## 5. Observation identity and three separate times

| Metadata | Final meaning |
|---|---|
| PlayerID | Persistent family UUID; outlives input generations. |
| sessionGeneration | Jevon supplies a new UUID on input restart/reselection. Setup → Calibration → Play normally shares one generation/camera session. Subscription reattachment alone does not create a new generation. |
| frameID | Unsigned capture-sequence number unique within a generation. Gaps allowed. Processing completion/publishing order may differ. Never renumber delayed frames to look new. |
| capturedAt | Original source capture time, expressed in a documented monotonic source-time domain. Not wall-clock Date, Vision completion, delivery time or GameClock time. |
| cameraGeometryRevision | Measurement-affecting camera orientation/crop/dimensions/configuration revision. A display mirror is not a change to canonical measurement geometry. |
| calibrationRevision | Per-player standing-baseline version; different players may have different versions. |

Observation identity is `(sessionGeneration, frameID)`; per-player identity additionally includes PlayerID. Repeated/duplicate deliveries represent the same immutable observation. No reprocessing, recalibration or late completion may silently change its metadata/payload or present it as a fresh capture. Only newly captured compatible observations may use newly accepted calibration revisions.

**Edo time-basis default for future live adaptation:** monotonic seconds in the Core Media host-clock domain. The adapter must establish the capture timestamp's source clock/timebase and explicitly convert/synchronize into this documented domain when needed. Do not blindly treat sample presentation time, host time, ContinuousClock instants, Date or arbitrary numerical seconds as interchangeable. If the clock relationship cannot be established, report a clock-normalization failure rather than fabricate a timestamp. Domain stores numbers/value metadata, never CMTime or camera objects. The conversion implementation remains outside CP1.

Replay injects deterministic synthetic capture times and clock advancement. Its basis is synthetic source seconds, not a claimed live host-clock epoch. `deliveredAt` controls transport/replay availability and remains outside the snapshot's capture metadata. Optional diagnostic completion/delivery time never substitutes for capturedAt.

Jevon owns capture-to-GameClock anchoring/conversion, pause/resume/time scaling and crossing eligibility. Edo never advances GameClock or shifts capturedAt to compensate for a pause. Before merging, agree how Jevon reads/anchors the documented source-clock basis; the policy and conversion implementation remain his responsibility.

Recalibration does not rewrite delivered evidence. Context compatibility checks use generation, camera revision and each affected player's calibration revision. Layout is fixed within a generation; changing it requires a new generation/validated calibration context.

## 6. Shared coordinates and PlayerCalibration

### Canonical player plane

**Confirmed principle:** body points and laser bands use compatible player-plane game units. Y points up from the calibrated floor. Kevin maps that same geometry into RealityKit for bodies, lasers and debug views. Collision never reads RealityKit transforms/physics.

**Final camera convention:** upright, unmirrored full-image normalized coordinates with bottom-left origin, X right/Y up and X/Y in 0…1. The future capture adapter explicitly controls orientation/mirroring and normalizes observations, rather than assuming source buffers arrive unmirrored. Localized mask observations are converted to this convention before Motion. Preserve anatomical left/right wrists and ankles; screen reflection never relabels them.

Image-space height is a fraction of the source image; player-plane height uses shared game units. Independently calibrating two players does not mean setting both standing heights to 1. Their different heights must remain distinguishable. RealityKit does not remove the need to map camera measurements into compatible coordinates.

### PlayerCalibration — one player's standing reference

| Field | Simple explanation |
|---|---|
| `playerID` | Persistent profile UUID whose body was measured. |
| `sessionGeneration` | Input session/context where calibration was accepted. A stable profile ID does not make calibration valid forever. |
| `revision` | Version of this player's accepted baseline. |
| `cameraGeometryRevision` | Camera geometry used; must match usable output. |
| `sourceFrameID` | Last accepted contributing source frame of the stable standing aggregate; not a claim that one frame alone established calibration. |
| `capturedAt` | Capture time of that source frame, on the source clock. |
| `standingCrownImageY` | Estimated standing crown Y in normalized image coordinates. |
| `standingLeftSoleImageY` | Independently estimated standing bottom of the left foot. |
| `standingRightSoleImageY` | Independently estimated standing bottom of the right foot. |
| `standingHipImageY` | Edo field definition: midpoint Y of valid left/right hip landmarks. |
| `standingBodyImageHeight` | Positive standing crown-to-sole image span: crown minus the lower standing sole. |
| `standingTorsoImageLength` | Positive shoulder-midpoint to hip-midpoint distance in aspect-corrected image-height units. Edo's field definition; the live estimator is validated under LH-22. |
| `headOffsetFromNoseShare` | Upward nose-to-crown image offset divided by standing body-image height. Explicitly nose-referenced. |
| `leftFootOffsetShare` | Downward left-ankle-to-left-sole image offset divided by standing body-image height. |
| `rightFootOffsetShare` | Separate downward right-ankle-to-right-sole offset divided by standing body-image height. |
| `mapping` | Image-to-player-plane parameters, including the calibrated floor reference below. |

No stored zone, permanent left/right role, standing wrist height or hand-length calibration. Floor lives once as `mapping.floorImageY`. Baselines are measured independently per selected player, stay fixed during ducking/jumping and change only through explicit recalibration/revision.

### Mapping and session placement

**Accepted ImageToPlayerPlaneMapping fields (concrete Swift syntax verified during implementation):**

| Field | Simple explanation |
|---|---|
| `imageAspectRatio` | Upright width / height; expresses X displacement in the same scale as Y. |
| `floorImageY` | Calibrated floor reference in the source image. |
| `originImageX` | This player's standing image center; camera reference for horizontal displacement, not a gameplay slot. |

**Shared PlayerPlaneLayout:** `leftCenterX`, `rightCenterX` in game units and positive `gameUnitsPerImageHeight` (sharedScale). These three values live once in session/layout configuration. Do not store independent scale copies in each PlayerCalibration. Calibration keeps imageAspectRatio, floorImageY and originImageX plus its standing references/offsets. Selection order derives the lane center. Kevin reviews integration with his GameWorldMapping; numeric lane spacing and scale remain tunable.

Baseline local conversion (not 3D reconstruction or physical-height measurement):

```text
sharedScale = layout.gameUnitsPerImageHeight
gameY = (imageY - floorImageY) * sharedScale
gameX = selectedCenterX
      + (imageX - originImageX) * imageAspectRatio * sharedScale

selectedCenterX = layout.leftCenterX  for SelectedPlayers.firstID
                 layout.rightCenterX for SelectedPlayers.secondID
```

Calibration stores the camera reference, selection determines the slot and layout supplies compatible coordinates. Kevin's mapping uses the resulting geometry for lasers and bodies. Perspective/size effects must preserve the visible relationship used by collision; decorative transforms cannot independently move judged geometry.

This is a calibrated local mapping for an agreed camera-distance range, not accurate depth/physical-height reconstruction. Camera placement, tolerated distance/scale drift and geometry changes need device tuning. They must reduce confidence/invalidate affected data rather than silently alter standing baselines. Do not choose separate scales to make both players the same standing game height. Reordering in another session requires newly validated calibration/context; UUID equality alone does not authorize reuse of an old mapping.

**Display contract:** calibration imagery, gameplay cutouts and their landmarks/overlays must share exactly the same effective image-to-display transform, including crop/orientation, lane-local placement and one horizontal reflection. The accepted camera-to-plane output stays unmirrored. Kevin owns the display projection/transform integration; the future calibration-preview owner must use the same convention. Mirror-like movement must be checked with real players, not inferred from candidate order or a global world flip. CP1 specifies this behavior without implementing previews, rendering or CP2 image transport.

### Crown estimation baseline — device validation required

1. Require a stable standing pose, whole body visible, hands down. Raised hands must not become the head reference.
2. Use relevant head landmarks (nose, eyes, ears, neck) and a reliably associated mask to localize crown. The highest point of an entire mask is not automatically crown.
3. Calculate headOffsetFromNoseShare from crown and nose relative to standing body-image height.
4. Baseline gameplay estimate: `crownImageY = liveNoseY + headOffsetFromNoseShare * standingBodyImageHeight`, while calibrated image scale remains valid.
5. Convert the image estimate through the agreed mapping.

An unavailable nose cannot be replaced by an ear, eye or neck using the same nose offset. Alternatives require their own explicitly defined, calibrated and validated rule; otherwise crown is unavailable. Head pose and segmentation reliability can reduce validity.

### Sole estimation baseline — device validation required

1. Detect both ankles during stable standing calibration.
2. Estimate each foot bottom independently from localized segmentation near the corresponding ankle, only with reliable association.
3. Store separate left/right ankle-to-sole offsets relative to standing body-image height.
4. Gameplay: `leftSoleImageY = liveLeftAnkleY - leftFootOffsetShare * standingBodyImageHeight`; use the right ankle and right offset independently for the right foot.
5. Convert each sole through the agreed mapping.

The lowest point of a whole-person mask does not establish both soles. Missing ankles do not borrow the other foot's value. Significant camera-geometry changes, identity uncertainty or distance/scale drift must invalidate measurements or reduce confidence until usable again. Drift thresholds and validated scale compensation are future work; never silently update a standing baseline during a jump/duck.

Wrists need no standing calibration: convert each live Vision wrist Y with the same image-to-plane mapping.

## 7. BodyGeometry and validity

### EstimatedScalar and EvidenceValidity

**Accepted EstimatedScalar shape; Edo representation default:** optional finite numeric `value`, plus `validity`. Valid requires a finite value. Invalid means `value = nil` with a reason; do not substitute zero, previous data or the other limb. Although the common type is called EstimatedScalar, wrists are mapped direct landmarks; crown/soles are inferred boundaries.

**Edo validity vocabulary default:** `valid`, `lowConfidence`, `missingLandmarks`, `outOfFrame`, `stale`, `identityUncertain`, `notCalibrated`. Thresholds/additional reasons need review. Only valid is usable required evidence. Raw joint confidence remains in PoseFrame; consumers do not reinterpret raw confidence to override invalid output.

Edo may flag established source/measurement staleness. Jevon independently decides whether selected evidence is temporally eligible for a crossing; producer-valid does not guarantee it meets his window. An immutable snapshot is not rewritten as wall time passes.

### BodyGeometry fields

All six fields are EstimatedScalar in player-plane game units.

| Field | Meaning | Used for |
|---|---|---|
| `crownY` | Estimated top of head | High laser |
| `leftWristY` | Direct left wrist, converted to player plane | High laser |
| `rightWristY` | Direct right wrist, converted to player plane | High laser |
| `leftSoleY` | Estimated bottom of left foot | Low laser |
| `rightSoleY` | Estimated bottom of right foot | Low laser |
| `centerX` | Horizontal center; Edo's initial definition is mapped hip midpoint X | Kevin's placement/debug review; not a prerequisite of these Y-only rules |

All fields describe the same captured observation and accepted calibration context. Partial validity is allowed: missing wrists prevent high judgment but do not alone invalidate valid low evidence. If identity/mapping is uncertain, dependent measurements cannot remain usable under that uncertain assignment.

### Finalized evidence requirements — Jevon implements verdicts

| Laser | Required valid evidence in selected sample | CLEAR condition |
|---|---|---|
| High | Crown, both wrists; reliable identity and compatible frame/revisions/time | `max(crownY, leftWristY, rightWristY) + clearanceMargin < laserLowerY` |
| Low | Both soles and JumpState; reliable identity and compatible frame/revisions/time | `jumpPhase == airborne AND min(leftSoleY, rightSoleY) - clearanceMargin > laserUpperY` |

High does not require soles, jump or a classified squat. Low does not require crown/wrists. Check required availability first: any required missing/invalid/stale evidence means UNAVAILABLE, even if another point looks unsafe. With fully valid eligible evidence, failure of the CLEAR condition means HIT. Equality at the margin is not CLEAR. Jevon owns sample selection, margins, finalization, verdict code and collision tests; none are implemented here.

## 8. TrackingStatus, JumpState and BodySnapshot

**Edo TrackingStatus vocabulary:** `reliable`, `uncertain`, `lost`. Reliable means confident UUID association, not guaranteed visibility of every joint. Uncertain/lost assignment cannot supply valid required evidence for that UUID.

**Edo JumpPhase vocabulary:** `grounded`, `takingOff`, `airborne`, `landing`, `unknown`.

| JumpState field | Meaning |
|---|---|
| `phase` | Classification at captured observation time. Only airborne meets the low-laser phase requirement. |
| `validity` | Whether classification is usable. Valid grounded fails low clearance; unknown/invalid means unavailable required phase evidence. |

JumpState remains separate from BodyGeometry. The detector can use past observations, but its output describes this capture time and cannot borrow future evidence. The phase vocabulary is an Edo branch default for Jevon's integration review; detector phase boundaries need later device validation. The valid-airborne requirement is final. No jump-cycle IDs/events in CP1 unless an agreed consumer need requires them.

### PlayerBodySample

| Field | Meaning |
|---|---|
| `playerID` | Selected persistent UUID; matches dictionary key. |
| `calibrationRevision` | Edo default: optional before calibration; nil means mapped geometry cannot yet be valid. |
| `trackingStatus` | Confidence in identity assignment. |
| `geometry` | Crown, both wrists, both soles and center X, each with validity. |
| `jumpState` | Phase/validity for this same observation. |

### BodySnapshot

| Field | Meaning |
|---|---|
| `sessionGeneration` | Source input session; excludes old-session work. |
| `frameID` | Frame identity shared by this packet's observations. |
| `capturedAt` | Capture time, never delivery time. |
| `cameraGeometryRevision` | Geometry used by frame and usable calibration. |
| `players` | Dictionary keyed by both expected selected UUIDs, including explicit uncertain/lost entries. Detection order is irrelevant. |

Shared metadata lives once on the envelope; calibration revision is per player. No names, weights, roles or duplicate selection/zone assignments in each frame. Profile lookup and ordered selection are separate context.

No crown from frame A combined with a wrist/sole from frame B, no unrelated jump state and no hidden old-pose fallback when a joint disappears. A frame with no people can publish lost samples for both UUIDs. Camera interruption must also be observable without inventing another frame.

## 9. Final conceptual BodyInputProviding contract

The following fixes observable behavior. It is documentation, not implemented Swift declarations. Section 13 defines LH-00 isolation; the implementation must verify exact accessor/closure signatures with the installed compiler.

### Configuration and context

| BodyInputConfiguration field | Meaning |
|---|---|
| sessionGeneration | Jevon-supplied input-generation UUID, echoed unchanged on data/status. |
| selectedPlayers | Accepted ordered persistent UUID pair; not profiles or Vision candidate IDs. |
| calibrations | Validated per-player baselines; empty allowed in setup. Reject outside-selection IDs, mismatched generation or incompatible camera metadata. |
| playerPlaneLayout | One leftCenterX, rightCenterX and gameUnitsPerImageHeight shared by both players. Fixed within the generation. |
| snapshotBufferCapacity | Configurable positive integer N; prototype default **8 completed BodySnapshots**, not eight per player. Fixed for a delivery lifecycle; change configuration through explicit restart, not a hidden buffer mutation. |
| noProgressPolicy | Configurable future-live monitoring policy: disabled by default for unvalidated production behavior, or diagnostic-only with an injected investigation threshold/arming rules. Approximately 1 second is an investigation starting point, not an approved timeout. |

**Edo default:** expose a read-only `currentContext` view of the provider's authoritative active generation, camera geometry and selected players' accepted calibration revisions, plus whether the context is active. It is derived from owned configuration/calibration state, not a second independently mutable copy. The view permits buffered evidence to be checked after reset. Initial camera geometry/revisions may be unavailable during startup; no dependent mapped value is then usable. Exact support-type syntax lives beside the provider contract.

### Operations and access

| Member | Final conceptual behavior / owner |
|---|---|
| start(configuration) — async, can fail | Edo establishes generation state and its prepared bounded stream before starting output. Success means source running, not calibrated/visible. Jevon owns calling it for session flow. |
| stop() — async | Explicit source shutdown: invalidate context, clear cache, finish delivery, cancel processing/capture, then publish stopped. Idempotent. Only the lifecycle owner calls it; subscription cancellation is not stop. |
| setCalibrations(values, generation) — async, can fail | Validate and atomically commit accepted baselines without reopening capture. Return/acknowledge the accepted context. Reject invalid requests without partially replacing state. Clear cache and invalidate incompatible buffered/history evidence; only new compatible captures may use new revisions. |
| snapshotStream — explicit single-consumer acquisition | Acquire `AsyncStream<BodySnapshot>` for the active generation using `.bufferingNewest(N)`. The initial N is 8. A second acquisition while claimed fails with an ownership/operation error, not a second camera or independent competing iterator. Exact Swift spelling may be a throwing acquisition method; it is not a getter that silently constructs streams. |
| latestSnapshot — read-only | Compatible published packet with the highest capture-sequence frameID. Nil before output and after incompatible context replacement/stop/fatal failure. No polling dependency for gameplay. |
| status — read-only | Current source lifecycle state, independent from snapshot transport. |
| statusUpdates — explicit observation registration | Independent current-state replay plus ordered status/context/progress/delivery notifications. Edo default is lightweight MainActor callback observation, not a lossy snapshot stream. Details below. |
| currentContext — read-only supporting view | Authoritative compatibility metadata used by the owner to reject old generation/camera/calibration data. |
| releaseSnapshotSubscription(generation) — supporting cleanup | Explicitly finish/release the current gameplay subscription on early loop exit; retain source capture if setup/calibration still uses it. Task cancellation also invokes token-checked cleanup. This is not stop(). |

`currentContext` and explicit subscription release are small support operations needed for correct reset/early-exit semantics. They do not add game history, clock conversion or a generic event framework to Edo's provider.

### Gameplay stream, ownership and coverage

- Edo owns snapshot production, validation, the continuation and delivery diagnostics. Jevon explicitly owns **one active gameplay consumer per generation** and his own bounded evidence history.
- Jevon registers lifecycle observation before start. start creates the stream before output can publish; he then explicitly acquires it and starts a continuously draining task before enabling gameplay. The task remains active through Setup/Calibration/Play and ordinary gameplay pauses when input remains needed; it never waits for a laser crossing to start reading. If start fails, status still reports the failure without a stream or camera frame.
- One packet contains both selected players from the same captured frame, including unavailable/lost samples. BufferingNewest(8) limits pending packets to eight total. It drops the oldest **buffered publication**, not necessarily the lowest capture-sequence ID. It does not sort completion order.
- No rendering/debug consumer iterates this gameplay stream. Diagnostics use latestSnapshot; Kevin's image handoff is CP2. Copying AsyncStream or constructing another iterator is not a multicast subscription.
- Late completed compatible observations may still enter the stream in completion/publication order with their original frameID/capturedAt/revisions. Jevon determines their crossing eligibility and deduplicates immutable observation keys. Do not reorder or rewrite metadata to hide processing delay.
- N = 8 is a configurable prototype default, not a permanent constant or a guarantee of eight valid frames near every crossing. Throughput, invalid measurements, scheduling, overflow and Jevon's independent history/window determine actual coverage.

### Latest cache is a different access mechanism

For the current compatible generation/camera/calibration context, publish a completed packet to the cache only when its frameID is greater than the cached packet's frameID (or cache is empty). Equal-ID identical evidence does not advance it; old-generation/incompatible completion is rejected. A compatible packet with invalid joints/lost tracking may still be the newest evidence: do not retain an older apparently safe pose instead.

Example publication sequence 101, 103, 102: stream can deliver 101, 103, 102; latestSnapshot ends at 103. A delayed 102 must not replace 103. The cache is not defined by delivery time or highest-confidence pose. During a compatible consumer detachment the provider may continue updating the cache for setup/diagnostics.

### Overflow and termination diagnostics

Inspect every continuation yield result. Enqueued means accepted/buffered or delivered to a waiting reader; dropped increments a saturating bounded-memory droppedSnapshotCount; terminated increments a saturating terminatedYieldCount. Count subscription termination separately, with a small reason category. A dropped result can describe the displaced older buffered element while the new packet was accepted: never treat it as proof the incoming packet was rejected.

Use bounded counters and small categories, not an ever-growing event log, image payloads, names, raw participant recordings or pose archives. Reset/summarize counters at an explicit generation boundary. Do not emit a status transition for every diagnostic count increment.

Overflow alone causes no HIT, CLEAR or automatic pause. No eligible valid crossing evidence remains UNAVAILABLE under Jevon's policy. Tracking loss, confirmed source interruption and processing stall are separate facts. A cancelled/closed consumer is a delivery state, not a camera failure.

### Subscription termination and explicit reattachment — Edo default

There is one active claim at a time. An acquisition returns the prepared stream and records its owner; repeated acquisition while active fails. It never silently creates another subscription. If the consumer cancels or exits, its owner releases the claim. An early break must explicitly release it rather than rely on deinitialization. onTermination performs only delivery cleanup, routed safely to the state owner; it must not stop camera capture needed elsewhere.

After release, an **explicit** acquisition may create a fresh bounded stream in the same still-active generation. This is a deliberate handoff, not automatic resubscription. The previous task must have exited before the replacement starts. An internal subscription token distinguishes old/new continuations and cleanup callbacks; it is transport ownership only and never changes PlayerID, generation, frameID or capture metadata. Old-token work cannot yield into or terminate a replacement stream. Previous queued packets are not replayed into the replacement; gaps are possible and do not imply a verdict.

Normal gameplay pause should keep the consumer alive. New-generation restart is reserved for source/session restart, reselection or incompatible layout change, not ordinary subscription reattachment. Camera lifetime belongs to start/stop and actual fatal source failure, not the subscription's cancellation handler.

### Recalibration/reset and buffered evidence — Edo default

The live stream stays attached across accepted recalibration; source capture remains open. The serialized context commit records a capture cutover, clears latestSnapshot and rejects old-context in-flight completions. Do not relabel a frame captured before the cutover with the new revision. The next new compatible capture can populate the cache and stream.

AsyncStream has no clear-buffer operation. **Invalidation is explicit compatibility rejection, not a claim that finish() purges pending values.** Already queued packets may still be yielded to the existing reader. Before inserting evidence into history or selecting a crossing, Jevon checks current active generation/camera and each affected player's accepted calibration revision. His history invalidates incompatible evidence on context change; packet/sample metadata is never rewritten. Unaffected player evidence may remain usable under its own matching revision. The lifecycle/context observer reports the committed context even with no new snapshot. Consumer acceptance and context commits must be serialized/checked so suspension cannot append an obsolete sample after reset.

On stop/fatal failure/new generation, context becomes inactive/incompatible and cache clears before delivery finishes. finish may leave old queued packets drainable; the old consumer must reject them. Startup/continuation/termination callbacks carry generation and subscription tokens, so old work cannot publish into the replacement generation. Repeated start with identical active configuration neither resets stream/history nor creates a second subscription. Different active configuration fails explicitly. Explicit stop then start uses a new generation.

### Independent lifecycle observation — Edo default

BodyInputStatus reports **starting**, **running**, **interrupted(reason)**, **failed(failureCategory)** and **stopped**. Permission/camera/processing/clock-normalization failures use small framework-independent categories. Operation misuse, such as a second stream claim, returns an operation error without falsifying source status.

StatusUpdates is an explicit observation surface: one lifecycle-owner callback registration for CP1, replaceable only after releasing the previous registration. On registration, synchronously replay the provider's authoritative current event on its owning MainActor before returning; subsequent changes are delivered serially in increasing statusRevision order. An event carries generation (nil only before the first generation), source-basis occurredAt, statusRevision, status, current context and delivery/progress facts. It needs no camera frame to exist. The owner can then share lightweight UI state through its own normal state model without adding gameplay stream subscribers.

Callbacks do not await or perform heavy processing. They immediately record/handle the immutable event; requested asynchronous recovery runs separately. Do not reenter provider control mutation from inside callback dispatch. No `.bufferingNewest(1)` or coalesced callback task is used for critical transitions: starting → running → failed must reach the registered observer in order. There is no unbounded status queue. A detached observer receives the current authoritative state when explicitly registering again, not a promise to replay all historical transitions. Sequence numbers/generation prevent stale queued owner work from overwriting newer state.

A fatal failure publishes failed(category), invalidates evidence, finishes delivery and releases source resources. **Failed remains current until explicit stop/restart**; do not automatically replace it with stopped and hide the cause. Explicit normal stop ends in stopped; an explicit stop after a failure may then report stopped. Gameplay consumer cancellation only changes delivery facts, leaving source running if still needed. These behaviors remain distinguishable even when no BodySnapshot arrives.

### Configurable no-progress policy for future live input

Track completed source-processing progress, not whether the gameplay reader happens to consume or whether a required landmark is valid. A completed lost-tracking packet is still processing progress. Overflow does not imply a processing stall, and duplicate transport delivery does not establish new source progress.

A diagnostic-only policy may report suspectedStall after an injected interval without completed output; approximately **1 second is only an investigation seed**. It is not an approved production timeout, pause rule or automatic failed/interrupted transition. Represent suspectedStall separately from a confirmed AVFoundation interruption (for example, progress facts accompanying running status). New compatible output clears the suspicion. Never invent an AVFoundation interruption reason from elapsed time.

Arm only while completed processing is expected, after initial output/transition readiness. Disarm/reset during startup, explicit stop/interruption, known calibration/context transitions or intentional suspension of processing; rearm after the first new compatible completion. Startup failure/never-producing input needs its own explicit source-start diagnostics, not a false one-second stall. Arming/grace rules and production tolerance require device validation. CP1 tests inject a manual clock and policy events; it implements no live camera watchdog.

Jevon owns all gameplay pause/recovery, clock conversion, bounded history, crossing selection and verdict finalization. No part of this interface selects LH-09 windows or judges a laser.

API behavior cross-check: [Swift AsyncStream specification (SE-0314)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md). Buffer/drop/finish behavior is the standard library's; ownership, context invalidation and callback status reporting above are Sedactive's explicit contract.

## 10. Motion/PoseFrame — raw values before interpretation

| Field/type | Meaning |
|---|---|
| Frame metadata | Generation, frame ID, capture timestamp, camera-geometry revision. Raw input exists before calibration. |
| `imageWidth`, `imageHeight` | Upright dimensions; derive aspect ratio. |
| `candidates` | Detected people not yet bound to selected UUIDs. |
| Candidate `candidateID` | Frame-local identifier/index; never persistent PlayerID. |
| Candidate `joints` | Named normalized X/Y points with per-point confidence. Explicitly includes **left wrist and right wrist**, plus nose, eyes, ears, neck, shoulders, hips and ankles when observed. Missing joints stay missing. |
| Candidate `maskTopImageY`, `maskBottomImageY` | Optional associated full-image mask extents; not automatically crown/both soles. |
| Candidate `leftFootBottomImageY`, `rightFootBottomImageY` | Optional independently localized foot bottoms near corresponding ankles. |
| Candidate `maskAssociation` | Edo default: matched / ambiguous / unavailable association to this pose candidate. Ambiguous mask observations cannot refine estimates as valid. |

All are plain values. Vision objects/images/buffers stay in Infrastructure. PlayerTracker separately binds selected UUIDs. Reliable head-region localization may require additional numeric observations during LH-22 design rather than trusting global mask bounds. BodyMeasurementExtractor maps live wrist points directly and estimates crown/soles from calibration. A later cutout packet can reference the same frame without entering PoseFrame/BodySnapshot.

## 11. Replay fixtures and deterministic behavior

Synthetic data only. Edo format default: versioned JSON mapping to accepted values. No JSON files/decoder are implemented here.

| Fixture field | Meaning |
|---|---|
| `schemaVersion` | Fixture shape version. |
| `profiles` | Context-only Player values with fixed synthetic UUIDs, names and weights for profile/selection lookup. No real participant records; never embedded in snapshots. |
| `sessionGeneration` | Fixed synthetic session UUID. |
| `selectedPlayers` | Two profile UUIDs in order. |
| `playerPlaneLayout` | One shared left/right center pair and gameUnitsPerImageHeight; no scale duplicated in calibrations. |
| `deliveryConfiguration` | Snapshot capacity N (default 8) and injected no-progress policy; no real wall-clock timeout. |
| `calibrations` | Complete synthetic standing references, separate offsets, mapping, source metadata and revisions; M1 does not wait for live LH-22. |
| `records` | Scheduled deliveries; array order breaks delivery-time ties. |
| Record `deliveredAt` | Synthetic availability time, separate from capturedAt, on source-clock basis. |
| Record `payload` | Snapshot or status event. No images, laser entities, verdicts, health or score mutations. |

Replay-only development/test control `advance(to:)` stays outside the live interface. Start resets the cursor; advancement delivers due records deterministically. No sleeps, camera, random IDs on decoding or wall-clock dependencies. Replay uses the same `.bufferingNewest(N)` stream, max-frameID latest cache, context checks and independent lifecycle observation as live input. Pausing the test reader intentionally fills/overflows the buffer; advancing source time does not secretly drain it. Tests needing separate arrivals explicitly coordinate consumer reads at each scheduled record, rather than relying on task scheduling or sleeps. Duplicate/stale/reordered/revision-mismatched inputs are intentional, not silently repaired. Jevon supplies encounters, game time and expected verdicts in his tests. Harness control steps can start/stop, replace calibration, attach/cancel a consumer and inject progress/status without changing snapshot payload metadata. Status delivery does not depend on another frame arriving.

**Replay boundary behavior:** new publication follows the same generation/context validation as live delivery. Negative fixture records can exercise rejection; do not repair their metadata or allow old-context records into a new generation as valid output. Already queued records may become incompatible after reset and must be rejected by the consumer. Jevon can additionally inject invalid evidence directly into his history/checker tests. This preserves deliberate stale/mismatched scenarios without exempting replay from the production contract. End-of-records alone does not stop/invalidate the source: EOF waits for an explicit fixture/harness stop/failure step, so the final packet is not silently erased by automatic shutdown.

### Fixed identities across different selection orders

| Synthetic profile | Persistent UUID |
|---|---|
| Kevin | `00000000-0000-4000-8000-000000000001` |
| Edo | `00000000-0000-4000-8000-000000000002` |

G1/G2 are readable aliases for distinct fixed fixture session UUIDs, not PlayerIDs.

| Session | Selection order | Expected displayed position |
|---|---|---|
| G1 | Kevin UUID, Edo UUID | Kevin left, Edo right |
| G2 | Edo UUID, Kevin UUID | Edo left, Kevin right |

Each session uses compatible newly accepted synthetic calibration metadata. Do not reuse G1's generation unchanged in G2 baselines. Reordering Vision candidates within G1 must not change selection or recreate G2's user selection.

In both sessions, player-facing preview/cutouts are mirrored once **within the assigned displayed lane**. Synthetic asymmetric left/right wrist points and a local horizontal displacement let Kevin check that imagery and debug landmarks use the same effective transform without relabeling anatomical joints. Mirroring must not turn G1 into Edo-left/Kevin-right.

Example only: layout centers −0.65/+0.65 and shared scale 2, image aspect 1.5. For the first selected player's imageX − originImageX = +0.02, canonical displacement is +0.06. A lane-local reflected display uses center −0.06 while retaining the left lane center. This illustrates local horizontal reflection before the agreed projection, not an implementation of Kevin's RealityKit transform. Numeric spacing is not approved tuning.

### Worked example — abbreviated, not a complete fixture

Synthetic common scale: floorImageY = 0.10, gameUnitsPerImageHeight = 2. Kevin's standing crown image Y 0.90 gives game Y 1.60; Edo's 0.625 gives 1.05. The scale comes once from PlayerPlaneLayout, not from separate baseline scale copies. Heights remain different. These are illustrative numbers, not device defaults. Profile weight plays no part.

G1 packet: frame 101, capturedAt 9.98, deliveredAt 10.03, compatible camera revision and per-player calibration revision 1. All measurements below are valid, identities reliable.

| Profile lookup label | Crown Y | Left wrist Y | Right wrist Y | Left sole Y | Right sole Y | JumpState |
|---|---:|---:|---:|---:|---:|---|
| Kevin UUID | 0.90 | 0.82 | 0.86 | 0.00 | 0.00 | grounded, valid |
| Edo UUID | 1.28 | 1.10 | 1.15 | 0.22 | 0.24 | airborne, valid |

If Jevon selects eligible evidence from this packet:

- High lower edge 1.10, margin 0.02: Kevin's maximum is 0.90; `0.90 + 0.02 < 1.10` permits CLEAR.
- Change only Kevin's right wrist to valid 1.12: `1.12 + 0.02 < 1.10` is false; fully valid evidence gives HIT despite the clear crown.
- Make that wrist nil/missingLandmarks: high is UNAVAILABLE, not CLEAR or automatic HIT. Soles/jump are not required for high.
- Low upper edge 0.16, margin 0.02: Edo's lower sole 0.22 satisfies `0.22 - 0.02 > 0.16`, and valid airborne permits CLEAR.
- Change Edo's right sole to valid 0.17: `0.17 - 0.02 > 0.16` is false, so valid evidence gives HIT. Missing sole instead means UNAVAILABLE. Crown/wrists neither rescue nor block low judgment.

These illustrate semantics; replay carries input values, not verdicts. Jevon owns executable collision assertions and eligibility/finalization. Equality at a strict margin fails clearance, but any required invalid evidence takes the UNAVAILABLE path first.

### Required body-data scenarios during authorized implementation

| Scenario | Edo's supplied evidence | Consumer/owner check |
|---|---|---|
| Standing, different heights | Independent complete baselines, grounded states, different heights | Edo verifies size-preserving conversion. |
| High clear | Crown and both wrists below beam with margin | Jevon verifies three-point requirement. |
| High raised wrist | Crown clear, one wrist above/inside clearance boundary | Jevon verifies crown alone cannot give CLEAR. |
| High missing/invalid wrist | Missing/low-confidence/otherwise invalid wrist | Jevon verifies UNAVAILABLE; Edo verifies no fallback. |
| Low clear | Both soles clear, valid airborne | Jevon verifies all low prerequisites. |
| Low sole too low | Both valid, one fails clearance | Jevon verifies HIT from fully valid evidence. |
| Low missing sole | One sole unavailable | Jevon verifies UNAVAILABLE, no copied second sole. |
| Low invalid/not-airborne phase | Invalid/unknown phase; separate valid grounded case | Jevon distinguishes unavailable from valid failure to jump. |
| Unrelated missing joints | Missing wrist in valid low sample; missing sole in valid high sample | Jevon verifies rule-specific availability. |
| Reversed session selection | Same UUIDs, G1/G2 reverse order, compatible new baselines | Jevon preserves identity; Kevin verifies displayed selection order. |
| Candidate reorder/overlap | Raw candidate reorder; overlap yields uncertain association | Edo verifies stable UUID or explicit uncertainty, never silent swap. |
| Tracking loss | Explicit lost sample for affected selected UUID | Consumers cannot infer clearance/reassign another body. |
| Stale/delayed | Old capture/later delivery; separate explicit stale evidence | Jevon tests temporal eligibility separately from producer validity. |
| Duplicate/reordered frames | Same key/payload twice; older capture arriving later | Jevon deduplicates/applies evidence policy. |
| Revision/generation mismatch | Old work after restart/recalibration or camera change | Consumers reject incompatible data. |
| Camera interruption | Status without subsequent body frame | Jevon pauses/blocks from lifecycle status alone. |

Edo's future `SedactiveTests/BodyInputTests/ReplayBodyInputTests.swift` verifies schema, deterministic stream scheduling, lifecycle/status, overflow, calibration injection and identity metadata. Detailed delivery/lifecycle/validity cases are in section 18. Motion tests cover tracker/extractor/jump implementations when in scope. Candidate-reordering tests require synthetic PoseFrame input; snapshot replay alone cannot prove the tracker. **Jevon owns collision verdict/timing tests.** Kevin owns mapping/alignment tests. Cross-owner integration checks precede merging; none are implemented in this revision.

## 12. How the main concepts relate

```text
Player                Who is this family member?
 id, name, weightKg    Stable profile across sessions.
        ↑ IDs only
SelectedPlayers       Which two, in what order, this session?
 firstID, secondID     Derives logical left/right placement.
        ↓ per selected ID
PlayerCalibration     What standing reference describes this body?
 offsets, camera refs  Accepted session/camera context; shared scale is in layout.
        ↓ Motion processes each observation
BodyGeometry          Where are the checked body points now?
 crown/wrists/soles     Live values with validity, including center X.
        ↓ with JumpState and observation metadata
BodySnapshot          Evidence Jevon can select and Kevin can align.
```

A profile is not a camera track. Session position is not a permanent profile property. Calibration is not a live wrist measurement. Geometry is not a verdict. This keeps one source of truth for each responsibility.

## 13. Decision register and LH-00 concurrency convention

### Four classifications — do not treat every item as pending

| CP1 area | Finalized by Tech Lead | Edo-selected branch default | Device tuning | Integration review before merge |
|---|---|---|---|---|
| CP1-01 identity/selection | Persistent UUID, accepted Player fields, ordered two-ID selection; no role/zone | Immutable UUID-backed value wrapper; reject duplicate selected IDs | Overlap/reacquisition behavior under real motion | Jevon's setup identity binding/recovery; Kevin's displayed positions |
| CP1-02 mirror policy | Upright unmirrored processing; mirrored player-facing preview/cutouts once; anatomical sides preserved | Explicit source normalization; one effective image-to-display transform for imagery/overlays | Orientation/crop/display alignment on iPad | Kevin + preview owner: lane-local mirror, no global lane swap |
| CP1-03 scale/layout | Common Y-up plane, floor 0; shared three-field PlayerPlaneLayout; preserve height differences | Camera references in calibration; scale stored once in layout; mapped hip midpoint as initial centerX | Scale, lane centers/spacing, distance range/drift | Kevin validates GameWorldMapping/projection; Jevon validates beam compatibility |
| CP1-04 source time | Capture/delivery/game time separate; identifiers unchanged | Live adapter target is host-monotonic seconds; synthetic injected replay basis; never assume raw clock interchangeability | Timestamp latency/normalization accuracy | Jevon agrees source-clock anchor/read integration and owns GameClock conversion |
| CP1-05 geometry/validity | Accepted crown/wrists/soles model; missing required data is UNAVAILABLE | Finite optional scalar plus validity reason; invalid value nil; reject incompatible metadata | Landmark confidence, out-of-frame/scale tolerances | Jevon checks high three-point/low phase+two-point eligibility; Kevin checks debug interpretation |
| CP1-06 jump | Low requires valid airborne; JumpState separate | grounded/takingOff/airborne/landing/unknown vocabulary; no cycle events initially | Phase thresholds/hysteresis when detector is implemented | Jevon verifies interpretation; Kevin reviews cues |
| CP1-07 calibration | Accepted standing/head/independent-foot fields, no wrist calibration/baseline drift | Mapping owns camera floor/center/aspect only; sourceFrameID is last aggregate contributor | Head/sole estimation and stability criteria | Jevon reviews calibration flow/revision invalidation; Kevin reviews size/placement |
| CP1-08 lifecycle | Camera may remain across Setup/Calibration/Play; explicit start/stop/calibration replacement | Atomic context commit, old-buffer compatibility rejection, explicit subscription release/reattachment | Live startup/recovery tolerances | Jevon keeps one continuous history-draining owner, handles context invalidation and pause |
| CP1-09 delivery/cache/status | AsyncStream bufferingNewest(8), bounded completed packets; max-capture-ID cache; status independent | N configurable; one active explicit claim, token-guarded reattachment; ordered callback status observation; saturating counters | Capacity N, scheduling/throughput, diagnostic stall threshold/arming | Jevon confirms drain task/reattachment/history behavior and status ownership; Kevin uses cache/CP2 rather than gameplay stream |
| CP1-10 raw PoseFrame | Both wrists and confidence; anatomical joint identity | Numeric mask observations only; candidate IDs never profile IDs | Mask matching/localization reliability | Kevin reviews later cutout association in CP2; no CP2 transport here |
| CP1-11 replay/tests | Deterministic injected capture/delivery times and stable identity | Versioned synthetic fixtures, manual advance and controlled consumer readiness | No physical accuracy claimed by fixtures | Owners agree cross-component cases; Jevon owns verdict tests |
| CP1-12 concurrency | Preserve existing project settings for LH-00; immutable Sendable values; no heavy MainActor processing/unsafe suppressions | MainActor control/cache/status facade; deliberate nonisolated Domain values and background ownership | Performance measured later | Consumer-facing signatures reviewed by Jevon/Kevin; no claim of whole-team B2 approval |

### Actual app/test settings inspected

Read the current project configuration and resolved Debug/Release build settings on this branch using installed Xcode **26.6 (17F113)** / Apple Swift **6.3.3**. Compiler version is distinct from project language mode.

| Setting | Sedactive Debug / Release | SedactiveTests Debug / Release |
|---|---|---|
| SWIFT_VERSION | 5.0 / 5.0 | 5.0 / 5.0 |
| SWIFT_DEFAULT_ACTOR_ISOLATION | MainActor / MainActor | MainActor / MainActor |
| SWIFT_APPROACHABLE_CONCURRENCY | YES / YES | YES / YES |
| IPHONEOS_DEPLOYMENT_TARGET | 26.5 / 26.5 | 26.5 / 26.5 |
| SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY | YES / YES | YES / YES |
| SWIFT_STRICT_CONCURRENCY | Not explicitly set/resolved | Not explicitly set/resolved |
| ENABLE_TESTABILITY | YES / NO | YES / NO |

Not explicitly set does not mean concurrency checking is disabled. No setting is changed by this revision. The shell's active developer directory points to Command Line Tools; commands used an explicit DEVELOPER_DIR instead of changing xcode-select globally. Initial target-only settings queries could not write the default DerivedData cache; the successful queries use a writable temporary DerivedData path and include both targets through the testing build action.

Settings-only verification (run once with Debug, once with Release; this does not execute a build/test):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Sedactive.xcodeproj -scheme Sedactive \
  -configuration Debug -derivedDataPath /private/tmp/lh00-settings-inspection \
  -showBuildSettings -json build-for-testing
```

### Intended isolation — local LH-00 convention

- Domain structs/enums and supporting configuration/context/status packets are immutable Swift values with checked Sendable conformance where they cross execution boundaries. They must be usable outside MainActor despite the project's default. Use explicit nonisolated nominal declarations where supported by this toolchain; verify generated isolation/conformances in the real app/test builds during implementation. Do not assume Sendable alone solves every inferred-isolation issue.
- The provider control surface, currentContext, latestSnapshot, status and callback registration are MainActor-facing. Only lightweight validation/commit/publication/observation runs there. Ownership of these values is single-source, not duplicated inside independent actors.
- Future Camera/Vision/segmentation/Motion heavy processing runs on explicitly owned background execution. An async method alone is not proof of leaving MainActor. Use the smallest supported explicit off-main mechanism after compiler verification; do not create an actor per file or introduce a framework merely for this contract.
- Completed immutable values cross to the facade. Context checks/cache comparison/yield are serialized. onTermination may arrive from another executor and must schedule token-checked cleanup without blocking or unsafe access. Consumers own their iterator/task; no concurrent next() calls or copied competing iterators.
- No unchecked Sendable, unsafe nonisolation, blind detached tasks or project-wide migration to silence diagnostics. If safe nominal isolation needs adjustment, handle it locally and verify it, rather than changing language/deployment settings.
- Concrete signatures/annotations and cross-boundary conformance must compile cleanly during authorized implementation. No claim is made that this document proves compilation or that the whole team's broader B2 migration/convention decision is approved.

This permits isolated CP1 implementation under existing settings. Jevon/Kevin review the public surface before merge; a future broader B2 decision does not block drafting/testing these local values and replay under the authorized convention.

## 14. Remaining tunable parameters and device risks

| Parameter | Initial/default status | What must be measured/decided |
|---|---|---|
| Snapshot capacity N | Configurable prototype **8 whole BodySnapshots** | Throughput, consumer scheduling, overflow/coverage; not eight guaranteed valid crossing frames. Changing configuration is explicit. |
| No-progress threshold | Approximately **1 second**, diagnostic investigation seed only | Device-specific completed-output gaps; production timeout is not approved. Policy initially disabled for unvalidated production behavior. |
| Stall arming/grace | Arm after expected processing/first compatible output; suppress startup/known transitions | Startup/calibration grace, deliberate processing suspension and recovery; no fixed production values selected. |
| Shared game scale | One positive gameUnitsPerImageHeight in PlayerPlaneLayout | Shared visual sizes, intended camera distance and valid movement range; not real-world meters. |
| Lane placement | leftCenterX/rightCenterX, no production numbers selected | Lane spacing, local motion range and projection alignment without swapping displayed identities. |
| Geometry/scale tolerances | No approved numeric thresholds | Camera movement/orientation/crop changes, body-distance drift, recalibration requirement. |
| Measurement confidence | No approved numeric thresholds | Crown/head association, wrists/ankles, independent feet, head pose, partial occlusion. |
| Motion phases | Five-phase vocabulary as branch default | Airborne boundaries/hysteresis and robustness; JumpDetector implementation is outside CP1. |
| Jevon-owned crossing policy | No timing windows/margins selected here | Capture-to-game anchoring, evidence window/history capacity, delay, clearance margins and recovery; review/test under LH-09/LH-10. |
| Display alignment/latency | Mirrored once; selected lanes fixed | Crop/orientation/overlay agreement and device lag. Cutout image transport and permitted lag remain CP2. |

Physical iPad validation is still required for hands-down crown calibration, independent foot localization/offsets, wrist-only fingertip/elbow limitations, airborne accuracy, identity through overlap, distance drift and mirrored preview/gameplay alignment. Replay cannot prove these. Lost tracking can coexist with source progress; overflow, processing stall and confirmed AVFoundation interruption must remain distinct.

These are tuning/validation risks, not open alternatives to accepted identity or high/low evidence requirements, and they do not require a live pipeline before CP1 values/replay can be implemented.

## 15. Mismatch register — other documents remain untouched

Current Tech Lead decisions override older text. These are documentation/integration follow-ups, not authorization to edit those files or redo LH-23.

| Source | Mismatch | Required follow-up before merge/integration |
|---|---|---|
| TEAM_ALIGNMENT §A/§F | Old CalibrationSession path, pending rename/move labels, pre-test-target guidance | Record completed LH-23/current paths; no repeat foundation implementation. |
| TEAM_ALIGNMENT §B | Snapshot minimum lacks wrists, persistent ordered selection and buffered delivery | Edo proposes updated wording; Jevon/Kevin review the finalized contract's integration. |
| TEAM_ALIGNMENT §C | Mirror policy TBD and described only through Kevin's mapping | Reflect mirrored preview AND gameplay, unmirrored processing, anatomical sides, one effective transform and no lane swap. Preview integration needs its owner. |
| TEAM_ALIGNMENT §C/B2 | Whole-project concurrency policy TBD | Record only LH-00 preserve-settings/local-isolation convention; no broader B2 approval or settings migration. |
| Architecture Reference — Player/geometry/high rule | Role/zone and crown-only clearance | Update to profiles/ordered selection and crown + both wrists; preserve low both soles + airborne. |
| Architecture Reference — mirror/mapping | Mirror convention pending, shared-scale ownership absent | Record final mirror policy and shared layout scale; Kevin validates game-to-world integration. |
| Architecture Reference — input/time | Final bounded stream, max-frameID cache, independent status, reset and clock domains unspecified | Reconcile CP1 surface, distinct from Jevon's history/GameClock. |
| Architecture Reference — LH-23 | Completion/review language predates confirmation | Reconcile historical status separately; LH-23 stays complete. |
| Gameplay draft — LH-00/shared summaries | Roles/zones, crown/sole-only geometry and latest-snapshot-only interface | Accepted identity/wrists, shared scale, bufferingNewest(N), separate cache/status and deterministic transport tests. |
| Gameplay draft — LH-01/LH-09/LH-10 | Crown-only high evidence | **Jevon reconciles all three with finalized crown + both wrists before implementation approval.** Low prerequisites unchanged. |
| Gameplay draft — LH-22 | Zone/standing-center coupling and broad mask-edge descriptions | Remove zone/scale copies; camera references separate from layout; localized head and independent feet. |
| Gameplay draft — role-dependent policies | Evidence/metrics/demand may need roles absent from Player | Jevon surfaces policies for explicit resolution; no inference from name, height, weight or order and no invented replacement mechanic. |
| Gameplay draft — B2 dependency | Could imply waiting for a whole-project migration/convention | Current instruction allows local CP1 under unchanged settings; public API reviewed/tested before merge. |
| Gameplay draft — LH-23/file map | Historical incomplete state/old paths | Update bookkeeping separately; preserve completed structure/RealityKit names. |

Parent/child playtest language may describe the audience without creating gameplay roles. CP2 image format, ownership, synchronization and permitted lag remain separate Kevin agreements.

## 16. Changelog for this final technical revision

1. **CP1-09 delivery:** bounded AsyncStream bufferingNewest(8), configurable N, one explicit active consumer continuously draining, yield-result diagnostics and explicit reattachment. latestSnapshot selects highest compatible published capture-sequence ID. Independent ordered status observation, buffered context rejection and cancellation/failure semantics are defined.
2. **CP1-02/03 coordinates:** unmirrored upright processing and mirrored player-facing preview/cutouts/overlays once without lane swaps. Shared scale moved into three-field PlayerPlaneLayout, removed from individual calibration. Added asymmetric display/selection examples.
3. **CP1-04/08 time/lifecycle:** capture/delivery/game time separated; host-monotonic adaptation direction and synthetic replay basis documented. Defined generation/subscription ownership, capture cutover, recalibration invalidation and source-vs-consumer lifetime.
4. **LH-00/B2:** inspected both targets in Debug/Release and toolchain, preserved settings, specified immutable Sendable/non-MainActor Domain values with lightweight MainActor control/publication. Broader B2 is not approved; exact signatures must compile during implementation.

Accepted Player/selection/calibration/geometry and high/low mechanics remain unchanged. Previous role/zone removal, direct wrists, nose/independent-foot approach and completed LH-23 baseline are preserved.

## 17. Implementation readiness and integration gate

**Current blocker to Swift edits:** this task authorizes documentation only. Wait for separate LH-00 CP1 implementation authorization. None of the finalized product/transport/mirror/settings decisions needs reopening to begin Edo's isolated feature-branch values/replay work.

**Not pre-implementation blockers:** device-tuned scale/spacing/confidence/timeouts, live camera/calibration, CP2 transport and broader B2 migration. Use explicit synthetic configurations. Compiler verification of exact signatures is implementation work, not already established by this proposal.

**Real implementation contingencies:** resolve/report unsupported isolation/accessor syntax or newly surfaced build errors locally; never silently change settings or use unsafe suppressions. No new Swift was compiled here. The shell developer-path issue was handled through DEVELOPER_DIR; it is not a missing-Xcode blocker.

**Before merging or wiring other owners' code:**

- [ ] Jevon reviews continuous-drain ownership, explicit cancellation/reattachment, buffered/history context invalidation, independent status callbacks and source-clock anchoring.
- [ ] Jevon reconciles high-laser specifications and surfaces role-dependent conflicts; he owns conversion, windows/history capacity and verdict tests.
- [ ] Kevin reviews displayed-left binding, mirrored preview/gameplay/debug transforms, anatomical labels, centerX/shared layout and beam alignment. Preview owner integrates the same convention; UI ownership is not reassigned.
- [ ] Edo implements/compiles accepted values/provider/replay and targeted tests only after separate authorization, preserving settings/ownership.
- [ ] Owners review cross-component replay integration and propose supporting document changes through the one-owner workflow. No duplicate types, competing stream consumers or guessed clock conversions.
- [ ] Public signatures/conformances pass actual app/test builds before merge; local LH-00 validation does not approve broader B2.

CP1 needs implementation and deterministic tests/integration. LH-00 overall also needs CP2. **Stop this step at Markdown/report: no Swift, project settings, other-owner edits, LH-23 redo, commit, push, merge, rebase, reset or deployment.**

## 18. Expected CP1 implementation files and deterministic tests

Next-step plan only. Paths below are repository-relative; these belong to Edo's contract/input/test areas.

| Expected file | Future CP1 scope |
|---|---|
| Sedactive/Domain/Players/Player.swift | Immutable PlayerID, Player and SelectedPlayers validation. |
| Sedactive/Domain/Players/PlayerCalibration.swift | Standing references/offsets/camera mapping; no lane/shared-scale copies. |
| Sedactive/Domain/BodyInput/BodyGeometry.swift | EstimatedScalar, validity, six measurements and shared PlayerPlaneLayout. |
| Sedactive/Domain/BodyInput/BodySnapshot.swift | Tracking/jump/sample/snapshot values with original identity/time/revisions. |
| Sedactive/Domain/BodyInput/BodyInputProviding.swift | Provider/configuration, context/status/diagnostic/observation support types and isolation/ownership. No live adapter/game logic. |
| Sedactive/Motion/PoseFrame.swift | Raw schema with anatomical wrists/ankles/confidence; no Vision requests. |
| Sedactive/Debug/ReplayBodyInput.swift | Concrete bounded replay producer, cache/context/status/lifecycle/manual scheduling; no camera. Keep helpers local until reuse is needed. |
| SedactiveTests/BodyInputTests/BodyInputContractTests.swift | Value/schema/identity/layout/validity invariants. |
| SedactiveTests/BodyInputTests/BodyInputDeliveryTests.swift | Buffer, yield counts, cache ordering and explicit consumer ownership. |
| SedactiveTests/BodyInputTests/BodyInputLifecycleTests.swift | Start/stop/calibration/cancellation/status/reset and injected progress policy. |
| SedactiveTests/BodyInputTests/ReplayBodyInputTests.swift | Fixture decoding/scheduling/determinism/evidence scenarios. |
| SedactiveTests/BodyInputTests/Fixtures/*.json | Fixed synthetic identities, one layout scale, complete baselines, controlled captures/deliveries/status. Verify test-resource membership when added. |

No planned CP1 live implementation in BodyInputService, CameraPipeline, PoseEstimator, PersonSegmenter, CalibrationSession, MotionEngine or JumpDetector. No Jevon game/session or Kevin Rendering/Play changes. App wiring is unnecessary to prove contract/replay tests. Preserve separate test target/smoke test; no LH-23 redo or project edits merely for placeholder test discovery.

Use established Swift Testing from the existing smoke test. Below are **tests to implement**, not tests reported as passed. Manual time and explicit consumer-readiness/read barriers replace sleeps and task-scheduling guesses.

| Group | Deterministic case | Expected behavior |
|---|---|---|
| Buffer | Claim, hold reader; publish ten compatible packets, N = 8 | Pending publications 3…10, exactly two drops; both selected UUIDs per packet, no verdict/pause. |
| Capacity | Repeat N = 2; reject nonpositive N | Configurable bounded policy, no per-player capacity; config changes explicit. |
| Delayed completion | Publish 101, 103, 102 with original capture/delivery times | Stream publication order preserved; cache 103; no rewritten metadata. |
| Capture vs publication overflow | Fill queue then offer late lower-ID packet | Oldest queued publication displaced; max-capture cache never regresses. |
| Duplicate | Same generation/frame/payload twice | Same immutable observation; equal ID does not advance cache. Conflicting payload under same key rejected, not repaired. Jevon deduplicates history. |
| Continuous drain | Coordinate one waiting reader and scheduled offers | One owner drains before crossing; no second consumer steals work. No physical coverage guarantee. |
| Ownership | Acquire twice; release/cancel then explicitly reacquire | Second active claim errors. Replacement has new transport token only; no hidden stream/camera shutdown/new generation. |
| Cancellation | Cancel pending next; early break with explicit release | Claim cleanup; setup source/cache/status can continue. Old cleanup cannot terminate replacement. |
| Terminated yield | Controlled offer races closure | Bounded terminated-yield/termination counters; no invented camera interruption. |
| Start | Repeat identical start, then incompatible config | Same stream/generation retained; reject incompatible request atomically. |
| Stop/restart | Queued/in-flight data, stop, start G2 | Cache clears; old context inactive; drainable old values cannot enter G2 evidence. |
| Recalibration | Queue rev1, commit rev2, old completion, then new capture | Cache reset; old completion rejected, queued incompatible samples filtered; only new capture uses rev2; no camera restart. Rejected baseline leaves current context intact. |
| Geometry/layout | Camera revision change/incompatible layout | Relevant mapping invalid; no stale revision marked valid. Layout change requires new generation. |
| Status without frames | Observe stopped; starting → running → interrupted → running → failed, no snapshots | All ordered revisions/reasons delivered; failed stays current until explicit stop/restart. |
| Status reattach | Unregister, rapid transitions, register | Immediate authoritative current-state replay; no stale overwrite/unbounded historical queue. |
| Stall | Inject manual diagnostic threshold while processing expected | Suspected stall only, not system interruption/pause/verdict; completion clears suspicion. |
| Stall suppression | Advance during startup/calibration; complete lost packets; overflow buffer | No false transition stall; lost-body completion is progress; overflow separate; duplicate transport does not fake source progress. |
| Identity/display | Same UUIDs, reversed selection, raw detection reorder | Identity stable; selection determines lanes; asymmetric fixture points support Kevin's mirror/overlay checks. |
| Calibration/layout | Two heights, one scale, separate foot offsets, fixed baseline | Sizes distinct; scale not duplicated; no wrist calibration or movement baseline updates. |
| Validity | High crown+both wrists; low both soles+valid airborne | Missing/stale/uncertain required fields explicit; unrelated missing joints do not block usable required evidence. No producer verdict implementation. |
| Replay | Same fixture/config/manual advance/read schedule twice, with overflow/reset | Identical packets/cache/counters/status; no regenerated IDs, sleeps, camera or GameClock dependency. |

Raw tracking/airborne/extraction accuracy tests belong to later implementations; CP1 validates their value contracts only. Jevon owns collision/timing assertions, Kevin owns projection/alignment tests. Boundaries remain intact.
