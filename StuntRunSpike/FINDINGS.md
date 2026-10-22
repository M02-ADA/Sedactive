# Stunt Run Spike — Findings (20 Oct 2026)

**Question:** Can we build a Shape Up–inspired, visually spectacular cooperative motion game with native Apple technologies, without compromising real-time performance or the two-month MVP?

**Short answer:** Yes for the rendering and compositing approach, and it should be **2.5D SpriteKit + live Vision cutouts (direction B)**. **On an iPad Pro 13" (M4, iPadOS 26.7.1) with its front camera and one or two real people, it held 60 fps render (every 5-second window's longest frame was 16.7 ms), about 30 fps Vision (pose ~11 ms, segmentation ~13 ms, compositing ~4 ms), about 68 ms from camera timestamp to texture, ~370 MB of memory, and nominal thermal state.** In a third session at **2.5–3 m with two people squatting on cue**, full bodies stood on the pads inside the moving world, and **capture-to-feedback for real squats was ~69 ms**. Total time on device was about 8.5 minutes across three sessions. Still open: a **10-minute thermal run** (every session ended at ~3.5 minutes when the app was backgrounded or closed; thermal state stayed nominal throughout) and **rep accuracy against a manual count**.

---

## 1. What was built

`StuntRunSpike/` is an isolated Xcode project (iPadOS 18+, landscape). It has no dependencies, no git repository, and no network access.

| File | Role |
|---|---|
| `WorldScene.swift` | Pinhole pseudo-3D projection, streaming props, speed lines, shaders, frame loop, metrics |
| `WorldScene+Gameplay.swift` | Zone drivers (live / simulated / absent), duck gates, warning window, resolution |
| `WorldScene+Feedback.swift` | HUD, anticipation/response/impact/team reactions, rolling metrics |
| `Shaders.swift` | Full-screen floor shader (train roof plus a lower neon ground plane) and sky shader (gradient, striped sun, stars) |
| `CameraPipeline.swift` | Front camera → Vision pose + person segmentation → Core Image cutout with player-colour rim → double-buffered pixels |
| `Pose.swift`, `SquatDetector.swift` | Pure, Vision-free squat state machine and zone assignment, unit-tested on macOS |
| `AudioFX.swift` | Eight sounds synthesised at launch on one SFX bus, with pitch variants |
| `Art.swift` | Procedural placeholder art in the Premium Playful Arcade palette |
| `StuntRunApp.swift` | SwiftUI shell: `SpriteView`, dev controls, metrics overlay |
| `LogicTests/` | `./LogicTests/run.sh` runs 12 deterministic squat and zone tests; all pass |

**Scene:** "Neon Express". Two players ride the roof of a train at dusk through a synthwave city. Pylons, buildings and neon arches stream from the horizon, and the ground grid below the train scrolls with real parallax. Overhead **duck gates** approach with per-player lane panels: coral for Parent (left), teal for Child (right). Successful squats pop the panels. If both players succeed, the gate shatters (**TEAM DUCK!**), the train surges, and Team Power fills. A full meter triggers **TURBO**, which also transitions the palette from dusk to night.

**Toggle:** `A · Camera` shows the raw camera with gates, pads and HUD on top. `B · Immersive` shows the cutouts inside the world.

**Launch arguments** for repeatable captures: `-cleanUI YES`, `-mode camera`, `-reduceMotion YES`. The test harness `-evidenceDir <path>` saves a scene snapshot every 3 s plus a metrics log. It's off by default and writes locally only.

## 2. Reference study

I watched the video (`m21pUSP1IBI`) in a browser and sampled frames from 0:30 to 7:55. It shows Shape Up's menus, an arena squat mode, a vertical "squat to the moon" mode and the **train-roof run** (about 6:30–7:35). Techniques worth borrowing:

- **Full-body cutouts standing on glowing P1/P2 floor discs.** The disc grounds a flat cutout in a 3D world. I copied this as the pads.
- **Rear-camera track with converging yellow rails.** The vanishing-point geometry carries most of the speed sensation.
- **Obstacle cues are big translucent red zones with white arrows inside green frames,** approaching from the horizon. Down arrows mean duck, side arrows mean dodge. I adapted this as the lane panels with chevrons.
- **Per-player combo counters at the screen edges, GOOD/OK/PERFECT pop-ups at the player, and a big timer and distance at the top.**
- **Environments change during a run** (canyon → city → bridge).
- **Split-screen per player** in the train mode. I chose one shared lane instead, because co-op is the goal.

I'm not claiming anything I didn't see. I didn't measure the game's latency or study its rendering internals.

## 3. Skills used, and what each changed

| Skill | Decision it drove |
|---|---|
| `spritekit` | `ignoresSiblingOrder` with explicit z bands; billboards as `SKSpriteNode` with shared textures, not `SKShapeNode`; pooled props, sparks and shards that are recycled instead of reallocated; scene stored in `@State` and SwiftUI talking to it through an `@Observable` model |
| `vision-framework` | `.balanced` segmentation (not `.accurate`) for live video; multi-person `VNDetectHumanBodyPoseRequest`; normalised bottom-left coordinates mapped straight into SpriteKit. I **didn't** copy its per-frame `Task` pattern (see §6) |
| `game-feel` | Front-loaded response: the lane turns green and squashes **on the frame the descent is detected**, not when the squat completes; at least two feedback channels per action (visual plus sound); measured latency instead of estimating it; hysteresis so jitter can't produce extra reps (tested) |
| `motion-design` | One "playful" signature curve (ease-out-back) for reactions; anticipation (gate rises and panels drop with overshoot before they're needed); exits faster than entrances; primary, secondary and ambient layers (gate, sparks, clouds and stars) |
| `swiftui-expert-skill` | `@State` model and scene ownership; the scene reads the model each frame, and SwiftUI only re-renders the 2 Hz metrics and controls; `onChange(of: accessibilityReduceMotion, initial: true)` |
| `apple-design` | Reduce Motion means gentler, not none: slower cruise, no speed lines, no shake or flash, capped boost, cross-fade banners, frozen sky animation |
| `audio-design` | One SFX bus at −4 dB for headroom, gains in dB, pitch-variant pools to avoid "machine-gun" repeats |
| `create-game-assets` | Read it; used only its palette and consistency discipline. All art is procedural placeholder (the Sketch MCP server was offline, so I couldn't reach source assets) |
| `write-swift` | Swift 6 with MainActor default isolation; capture pipeline explicitly `nonisolated`; the texture copier closure is built outside the main actor because SpriteKit may call it from its render thread |

## 4. Verification

### Where things ran

| Target | What it proved |
|---|---|
| **iPad Pro 13" (M5) Simulator, iPadOS 26** | World, gameplay loop, HUD, sound, Reduce Motion, Mode A rendering and texture orientation (synthetic test card). No camera, so no segmentation |
| **M5 MacBook Pro, Mac Catalyst build, built-in camera, two real people** | Live Vision pose and segmentation, Core Image cutout, texture upload, multi-person zone assignment, live squat events and latency |
| **iPad Pro 13" (M4) iPad16,5, iPadOS 26.7.1, Release build, front camera** | The full pipeline on target hardware: 60 fps render, Vision timing, cutouts with one and two people, landscape rotation (4:3 640×480 source with no crop), memory, thermal, full-body framing at play distance. Three sessions (~1.5, ~3.3, ~3.5 minutes); run 3 at 2.5–3 m with two people squatting |
| **macOS logic tests** | 12/12 pass (geometry, rep sequence, shallow-dip rejection, threshold jitter, simulated reps, loss/recovery, hip-drop fallback, zone assignment, seated start, too-fast cycle, centre-line jitter, brief dropout) |

### Measurements (real, from the in-app meter)

| Metric | Simulator (test card) | M5 Mac, live camera, 1–4 people | **iPad Pro M4, live camera, 0–2 people** |
|---|---|---|---|
| Render | 60 fps, 16.7 ms frames | 60 fps (31 samples at 5 s intervals: avg 59.7, min 54.6), 52/56 windows with max frame = 16.7 ms | **60 fps; every 5 s window's longest frame was 16.7 ms (55 windows)** |
| Draw calls / nodes | ~79 / 235 (immersive), 18 (Mode A) | — | — |
| Vision rate | n/a | 29.4 fps avg (camera runs at 30) | **29.7 fps avg** |
| Body pose | n/a | 5.6 ms avg (5.2–6.6) | **11.1 ms avg (6.3–22.6)** |
| Person segmentation (`.balanced`, 512×384 mask) | fails in Simulator | 14.6 ms avg (11.6–20.0) | **13.0 ms avg (7.8–15.4)** |
| Core Image cutout + rim | 25–35 ms (software Metal, not meaningful) | 2.7 ms avg | **3.7 ms avg** |
| Camera timestamp → texture uploaded | — | 82 ms avg (69–99) with harness; 70 ms on the clean run | **68 ms avg (56–84)** |
| **Camera timestamp → squat feedback committed** | — | ≈71–85 ms running average over live descents, plus ~1 frame to reach the screen. Testers were close and often seated, so some of these descents were probably false positives | **~69 ms (63–70) from real squats at 2.5–3 m** (run 3), plus ~1 frame to reach the screen |
| Dropped camera frames | 0 | 52 at camera warm-up, then +4 over ~3 minutes | 2–3 at startup, then none |
| Memory (phys footprint) | 37–43 MB | ~425 MB steady on the clean run; up to 707 MB with the snapshot harness running | **~370 MB avg (318–438)** |
| Thermal | nominal | nominal for the whole run | **nominal** over ~5 minutes in total (10-minute run not completed) |

Notes on reading these numbers:

- On the iPad, Vision costs about 28 ms per frame in total (pose + segmentation + compositing), close to the 33 ms frame budget at 30 fps. It keeps up today, but adding a second Vision request (e.g. instance masks) would need pose or segmentation to run on alternate frames.
- **Hitches are caused by the evidence harness, not the game.** With 3-second full-resolution PNG snapshots the iPad showed ~22–40 hitches/min; with 20-second snapshots, 0–8/min. Production builds don't include the harness.
- The Mac numbers are Apple-silicon-class evidence; the M5 runs pose about 2× faster than the iPad M4.
- The latency figures start at the camera's own sensor timestamp. That means about 50 ms of the total is spent inside the camera pipeline before my code ever sees the frame.
- A few frame-time spikes during the live run coincide with the snapshot harness encoding a full-resolution PNG on the main thread. The clean run had none.

### Evidence (in `Evidence/`)

- `01`–`05`: the immersive loop with clean UI (warning, squat under gate, TEAM DUCK, TURBO, night transition).
- `06`: Mode A with the test card and metrics.
- `07`: dev panel.
- `08`: Reduce Motion.
- `gameplay-simulator-28s.mp4`: 28 s clip of the gameplay.
- `mac-camera-run/`: **real two-person cutouts in the world**, plus both metrics logs.
- `ipad-run/`: **iPad Pro M4 live cutouts**. `16`–`18` are full bodies at play distance (gate overhead, deep squat, two people); `19` shows head cropping; `13`–`15` are the earlier close and seated sessions. Also includes every device metrics log, plus `run3-play-distance-metrics-and-squats.log` with each live squat event.
- The camera-run images show the people who tested. Delete them if they shouldn't be kept.

## 5. The ten questions

1. **Convincing motion?** Yes. Exact pinhole perspective, a roof and ground plane that scroll at the same speed but different depths (real parallax), near-field pylons at a steady rhythm, arches sweeping past the camera and speed lines. It reads as fast forward travel in both stills and video.
2. **Is 2.5D deep enough?** For this fantasy, yes. Camera-facing billboards are exact under this projection, and the shader floor gives true depth. The limit is that the camera can't orbit or bank. Shape Up's cameras are mostly locked too.
3. **Does compositing improve immersion?** Clearly. Compare `07` (cartoon stand-ins) with `mac-camera-run/09`–`11`: with the room removed and a coloured rim, players read as inside the world. Mode A looks like a webcam with stickers on it.
4. **Are both people visible and correctly positioned?** Yes, on Mac and iPad: both were cut out, assigned left/right, and coloured coral/teal. On the iPad, landscape rotation delivered an upright 4:3 frame with no crop. **At 2.5–3 m on the iPad, full bodies fit and stood on the pads** (`16`–`18`). Two framing problems appeared: a tall or close player's head can leave the top of the camera's view (`19`), and zones flip when two people cross the centre line.
5. **Mask quality in fast movement?** Good on a still person. During fast arm swings the mask lags by about a frame, giving a soft halo and semi-transparent patches on loose clothing (see `09`). Held objects (a phone) are included. Acceptable for an arcade look; the rim hides most edge noise.
6. **Does Vision add noticeable lag?** On the iPad, Vision plus compositing take about 28 ms per frame, and camera timestamp to texture is about 68 ms. Feedback is committed in the same frame the pose arrives, so capture-to-reaction is roughly 70 ms plus one display frame. That's under game-feel's ~100 ms "noticeable" threshold. Measured from real squats at play distance on the iPad: **~69 ms**.
7. **Can SpriteKit stay smooth?** Yes. On the iPad Pro M4, every 5-second window over ~5 minutes held 60 fps, with the camera and Vision running and 1–2 people cut out.
8. **Does it fit Premium Playful Arcade?** The palette (navy, violet, electric blue, coral, yellow, teal), the heavy italic type with navy outlines, the bouncy timing and the card HUD all fit. The art is placeholder, so the illustration quality is the team's to provide.
9. **Readable and physically comfortable?** Readability is good: one hazard at a time, colour-coded lanes, a cue above each head, two-channel feedback. On comfort: the world moves away from the camera (players "ride backwards"), so nothing invites stepping toward the iPad. The only input is squatting in place on your own pad. The world eases to a stop with "STEP INTO YOUR ZONE" when nobody is tracked (camera only, autoplay off), and Mode A always shows the real room. Reduce Motion is wired to the system setting and has a manual override.
10. **Feasible in two months?** Yes for direction B. This spike is about 3,100 lines of Swift (built in one session) with no dependencies. The risks that remain are measurable and bounded (§7).

## 6. Pipeline design (performance and safety constraints)

- **Bounded by construction.** Each frame's Vision work runs synchronously inside the capture delegate on one serial queue, with `alwaysDiscardsLateVideoFrames = true`. At most one frame is ever in flight, and AVFoundation drops stale frames instead of queueing them. There's no per-frame `Task` and no unbounded concurrency.
- **Rendering never waits on Vision.** Results go into a lock-protected double buffer, and the render loop takes the newest frame only if one exists. Pixels are copied straight into a reused `SKMutableTexture`, so no new textures or `CGImage`s are created per frame.
- **Mode A skips segmentation entirely.**
- **Degradable:** at `.serious` thermal state, segmentation drops to `.fast`. Speed lines and shake turn off under Reduce Motion.
- **Privacy:** camera permission only (no microphone), nothing is recorded or uploaded, and the camera stops when the app goes to the background. Center Stage is disabled so the framing can't drift away from the zones.

## 7. Limitations and what's unverified

- **The 10-minute iPad thermal run didn't finish.** The iPad auto-locked after about 3 minutes because nobody touches the screen in a squat game. This is now fixed (`isIdleTimerDisabled` while active) but not yet re-run. Only one landscape orientation was tested. Battery drain wasn't measured.
- **The seated false positive is real.** On the iPad a seated tester's bent knees scored 2 reps. Fixed: a person first detected already bent gets no credit until they stand (test 9). Sitting down then standing up still counts as a squat, which is arguably correct (it's the same movement).
- **Squat accuracy is only partly checked.** In run 3, 16 of 18 rep-to-rep gaps were 2.4–59 s, consistent with one squat per gate. **2 were physically implausible (0.37 s and 0.97 s), both during the first minute of setup.** Detected totals were L=8 and R=12; the testers didn't keep a count, so accuracy against ground truth is still unmeasured. **Fixed (unit-tested, installed on the iPad, not yet re-run there):** a rep now needs at least 0.6 s from descent to standing (faster cycles are reported as `aborted`), and movement is ignored for 0.4 s after a person is (re)acquired.
- **Zone flicker.** When two people move around or cross the centre line, assignment flips (repeated `found`/`lost`) and the Parent placeholder briefly reappears. **Fixed (unit-tested, installed, not yet re-run on device):** `ZoneTracker` remembers each zone's last position for 1 s. A lone person keeps their zone unless they're more than 0.1 of the frame width past the centre line, and when one of two people drops out briefly, the remaining person stays in their own zone.
- **Head cropping** at the top of the camera frame for tall or close players at the tested iPad height. Fix: on-screen positioning guidance in Mode A ("step back until your head is inside the frame"), and testing a lower iPad stand angle. The hip-drop fallback (used when ankles are out of frame) could count leaning as squatting.
- **Body auto-fit needs feet in frame.** It only engages when someone stands with ankles visible. Otherwise the cutout uses a default scale, and it fits to the tallest person, so a child playing alone is shown at adult scale.
- **The rim colour is split at the frame centre**, not per person, so someone crossing the midline gets a two-tone rim. Per-person colour would need `VNGeneratePersonInstanceMaskRequest`.
- **One combined mask**, by design. No per-player effects on the cutouts.
- **Placeholder art and sound.** The Sketch assets weren't reachable (the MCP server was offline).
- **The Simulator was letterboxed in portrait.** Its window couldn't be rotated without Accessibility permission. Proportions are correct; text looks relatively larger.
- **The hitch counter includes launch frames** for its first minute, so early "hitches/min" values overstate steady-state.

## 8. Production directions

| | A. Camera + overlays | **B. Cutouts + 2.5D SpriteKit (built)** | C. Cutouts + true 3D (RealityKit/SceneKit) |
|---|---|---|---|
| Visual payoff | Low: reads as a webcam | High: players inside the world | Highest: orbiting cameras, lighting, real geometry |
| Runtime cost | Lowest (pose only) | Measured: about 20 ms Vision per frame, 60 fps render | Similar Vision cost, plus 3D render, plus getting the camera texture into a 3D material (RealityKit `TextureResource` updates, or SceneKit with a Metal texture) |
| Engineering | Days | Proven in this spike | New renderer, 3D asset pipeline (modelling, rigging, lighting), billboards still needed for the cutouts |
| Delivery risk (2 months) | Low, but under-delivers the fantasy | **Medium-low**: remaining risk is iPad tuning and squat accuracy | High: the cutouts would still be flat cards, so most of the extra 3D effort goes into environment art |

**Recommendation: 2.5D (B) for production.** The cutouts are flat whatever the renderer, and a locked forward camera, which is what Shape Up itself mostly uses, gets almost no benefit from real 3D. The money is better spent on illustration, more obstacle types and squat accuracy. Revisit C only if the design later needs camera orbits or banking.

## 9. Next steps (in order)

1. ~~Plug in an iPad Pro M4 and measure FPS, Vision ms, rotation/crop, play-distance framing, real-squat latency~~ (done, see §4). Still to do: **a full 10-minute run** for thermal state (keep the app in the foreground), and **compare detected reps with a manual count.**
2. ~~Add a minimum rep duration and zone hysteresis~~ (done). Re-run on the iPad with a manual count to confirm.
3. Squat ground-truth session: about 50 reps each from an adult and a child, comparing detected with actual, then tune `SquatConfig`.
4. Per-person instance masks (correct rim colours, per-player effects) if the cost stays under ~10 ms.
5. Replace the procedural art with the Sketch illustrations. The obstacle catalogue needs a second movement only after squat accuracy holds up.

## Run it

- **Simulator:** open `StuntRunSpike.xcodeproj` and run on an iPad simulator. You get a synthetic test card instead of a camera, and autoplay drives both players. The `1`, `2` and `3` keys simulate squats.
- **iPad:** select the device and run. Autoplay turns off when the camera starts. For a measured run: `xcrun devicectl device process launch --device <id> --console com.kevinfaith.c5.stuntrunspike -- -evidenceDir documents -evidenceInterval 20`, then `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.kevinfaith.c5.stuntrunspike --source Documents/evidence`.
- **Mac camera test:** run the "My Mac (Mac Catalyst)" destination. The `StuntRunSpike-Mac.entitlements` file grants camera access under the Hardened Runtime.
- **Tests:** `./LogicTests/run.sh`.

Side effects of this session: this MacBook Pro was registered as a device in your developer team (needed for Mac signing), and Mac Catalyst support was enabled on the target.

---

## Revision 2: forward motion, depth and environment (20 Oct 2026)

Same architecture: one SpriteKit scene, the same pinhole projection, the same camera pipeline. No SceneKit, no RealityKit, no new dependencies. Evidence is in `Evidence/revision2/`, including `before-after.png` (top row is before, bottom row is after) and a 40-second clip.

### Why the motion felt reversed, and what changed

Frame-by-frame checks showed the geometry was already correct: things approach and grow. The *feeling* came from weak cues:

- low-contrast near-field ground motion;
- a narrow ~58° field of view;
- clouds drifting **sideways**, which the eye reads as lateral travel;
- 0.75-unit sleepers sitting near the 30 fps aliasing limit, so they could crawl backwards in recordings.

Fixes:

- **Wider field of view** (player plane 2.5 → 1.9 units). The players look identical, but everything beyond them changes scale far more as it approaches.
- **FOV kick on boost:** a dolly zoom that widens the view while the player plane stays fixed.
- **Track curves:** OutRun-style bends beyond the players. The sky, mountains and skyline pan against the bend.
- **Big, high-contrast roof features:** 3-unit panels, hazard chevrons on both edges, and runway lights that streak past near the camera. No sub-unit patterns remain.
- **Approach lanes:** when a gate is inbound, each player's lane lights up between the gate and the players, with chevrons racing toward the camera.
- **Clouds drift outward** from the vanishing point and grow, which is the forward-travel grammar.
- **Gate staging:** a beacon column makes the gate readable as a speck on the horizon. Posts spring up, the beam drops in with overshoot, and the beam's shadow crosses the roof before the beam arrives. The warning lead went from 2.2 s to 2.5 s.

### 3D-feeling components (all SpriteKit)

- **Volumetric buildings:** each has a front billboard plus a **perspective-warped side wall** (`SKWarpGeometryGrid`, 4 columns, recomputed each frame from the projection), so walls converge to the vanishing point and slide past instead of popping.
- **Shadows:**
  - roof shadows under gates and the bridge (warped quads);
  - **cast shadows from the live cutout itself** (the body texture, sheared back-left from the feet);
  - contact shadows at each player's feet.
- **Tunnels:** 14 neon rings, each offset in rotation, forming a twisting vortex. They fade out before the player plane so they never cover the cutouts.
- **Rotation in depth:** the STUNT RUN sign turns on its vertical axis (`xScale = |cos θ|`, darkened when you see its back), and the ferris wheel spins.

### Environment

- **Landmarks** approach slowly from beyond the fog: a ferris wheel, a STUNT RUN sign tower, and a suspension bridge the train passes under.
- **Atmosphere:** sweeping searchlights, tunnel sections that dim the world, fireworks on TEAM DUCK and TURBO, and the existing dusk-to-night transition.

### RealityKit and SceneKit evaluation

- **No RealityKit skill is installed** (only `create-game-assets` has a general 3D-pipeline reference).
- **RealityKit can't render inside a SpriteKit scene.** It would need a separate `RealityView`/`ARView` layer under a transparent SpriteKit layer, with the cutout either in a third layer or moved into RealityKit as a per-frame texture on a plane. That's a second renderer, depth-sorting across layers, and a 3D asset pipeline.
- **SceneKit (`SK3DNode`)** is soft-deprecated and was excluded by request.
- **Verdict:** warped SpriteKit geometry delivered the volume this design needs (walls, shadows, tunnels) at about 30 extra draw calls. True 3D still isn't justified for a locked forward camera.

### Measurements

| | Before | After |
|---|---|---|
| Simulator: nodes / draw calls / fps | 235 / ~79–85 / 60 | ~320 / 100–116 / 60 |
| Mac (M5) live camera: render / Vision / pose / segmentation | 60 / ~30 fps / 5.6 ms / 14.6 ms | 60 / ~30 fps / 5.6 ms / 14.2 ms |
| iPad Pro M4 | 60 fps (measured, §4) | **not re-measured: the iPad disconnected** |

### Readability and compositing (checked live on the Mac camera)

The cutout still separates clearly from the busier backdrop, thanks to the player-coloured rim and the person's size. Tunnel rings, gates and pylons layer correctly in front of or behind the body. The Mac test person was seated close to the camera, so the body cast shadow wasn't visible there; it was verified only on the stand-in figures.

### Risks

- **Draw calls rose about 30%,** and ~22 warp grids are rebuilt each frame. Fine on the Mac and simulator, but **unmeasured on the iPad**, where Vision already uses about 28 ms of each 33 ms frame. If iPad frame time suffers, drop building side walls beyond z ≈ 40 first.
- **Curves and the FOV kick add vestibular motion.** Both are off under Reduce Motion, but they need a comfort check with a child.
- **Background busyness behind players.** Watch it on the iPad at play distance. Fallback: lower building window brightness within ±0.3 of screen width from centre.

---

## Revision 3: one complete cooperative loop, validated in the simulator (20 Oct 2026)

Same project, same architecture. The environment from Revision 2 is kept; only real defects were fixed. All results below come from the **iPad Pro 13" (M5) simulator, iOS 26.2 runtime, Xcode 26.6**, using **simulated movement**. Nothing here is evidence of camera, Vision or iPad performance. Evidence is in `Evidence/revision3/`.

### The cooperative loop

**Anticipation → physical action → response → shared consequence → reward → next challenge**

1. **Anticipation.** A beacon marks the gate on the horizon. The posts spring up, then at 2.5 s out the panels drop into each lane and DUCK! appears, telling **both** players to squat before it arrives. A **0/2 team lock** appears under Team Power, with cue arrows over each head, approach lanes racing toward the players, and rising ticks.
2. **Movement starts (provisional).** The lane panel lifts and turns mint, and the player's lock slot pulses. Nothing is counted yet.
3. **Eligible phase reached (contribution).** At the squat bottom, the lock fills with a check (**1/2**), that player's half of the beam lights in their colour, and +1 Team Power is banked immediately. Contributions are never removed.
4. **Partner contributes at their own time.** 2/2, both halves lit. There's no sync requirement; anywhere inside the window counts (the script includes a deliberately late Child).
5. **Shared consequence (resolution at the gate).**
   - **TEAM DUCK!** if everyone contributed: the gate shatters, fireworks fire, the train surges, and +1 team bonus is added.
   - **NICE!** otherwise: "Squat together for the TEAM bonus". The successful player keeps their credit and the other gets a gentle "ALMOST!". Nobody is penalised.
6. **Full cycle (rep).** Standing back up counts a squat on the player's card, separately from the contribution.
7. **Reward.** Team Power fills toward TURBO: a 2× surge plus the dusk-to-night transition.
8. **Recovery.** The next gate spawns 14 world units after resolution (≈5.5 s to its warning) and never during a boost. Every third gate is followed by a tunnel ride and every fifth by the bridge; gates wait until those have passed.

**Flow:** camera or simulated input → `SquatDetector` (movement state) → `SquatEvent` (validated event) → `handle(_:)` → `TeamChallenge` / `SessionFlow` (pure, unit-tested) → SpriteKit feedback.

- Counts and Team Power come only from the events and the challenge model, never from animations.
- Simulated input goes through the **same detector with the same thresholds**. It's tagged as simulated, never recorded as latency, and can be removed by deleting `ScenarioScript` and the debug buttons.

### State handling (all validated with the scripted run; see `game-log-scripted-run.log`)

| State | Behaviour |
|---|---|
| Pause | The world eases to a stop and the inbound challenge is **withdrawn** (one policy: no result, banked contributions kept). Game time freezes, so simulated movements and timers can't fire stale. Events are ignored. Resume is explicit, then a 3-2-1 countdown. |
| Tracking lost | Same suspension. The banner names the player ("PARENT: STEP BACK IN"), their figure is ghosted and their card shows ✕ LOST. A detector that loses tracking resets, so a half-done squat can never complete. |
| Recovered | **READY!**: hazards stay off until an explicit Resume. Resume is refused while anyone is still lost. |
| Resume / countdown | Detectors are **re-armed**: a squat begun while halted can't become a rep (the log shows `ignored repCompleted … countdown`). The next gate comes ≥ 22 units after GO. |
| Replay | New session number. Squats, combos, Team Power, challenges, banners, floats and any pending TURBO are reset. Settings are kept, and closures from the old session check the session number before acting. |

**Found and fixed during validation:**

- **No gates after a withdrawn challenge:** the next gate was only scheduled on resolution. Fixed.
- **TURBO dropped** when a pause came within 0.35 s of filling the meter. It's now deferred to the next GO.
- **Lane panels ballooning across the screen** when the gate passed the camera after resolving. They now exit within 0.12 s and are hidden past the players.
- **Ferris wheel rim overhanging the track:** moved out to x = 15.5.
- **Tunnel and bridge colliding with gate cues:** now staged in recovery windows.
- **Tunnel and bridge popping in** when staged closer: they fade in over 0.6–0.8 s.
- **Inconsistent warning windows during boosts:** gates no longer spawn while a boost is active.
- **The lock fill grew from zero:** it now starts visible at 60%, the front-loaded response.

### Tests

- `./LogicTests/run.sh` runs **18 tests with 47 assertions**, all passing. They cover:
  - the squat state machine;
  - zone hysteresis;
  - `TeamChallenge` (contribution once, partner miss keeps credit, no award after resolve or cancel, non-participants ignored);
  - `SessionFlow` (pause, tracking lost for one and both players, recovered → ready, resume refused while lost, countdown, replay);
  - re-arming after a halt, and shallow simulated squats.
- Scripted end-to-end run (`-scenario coop`, or **Run script** in the controls):
  - **Session 2:**
    1. both, staggered → TEAM
    2. Parent only → partial
    3. Child late → TEAM
    4. Parent too shallow → partial + GO DEEPER
    5. tracking lost → withdrawn → ready → resume
    6. pause mid-challenge → withdrawn, TURBO deferred
    7. both → TEAM
    8. both → TEAM, then replay
  - **Session 3:** 9. both → TEAM, with counters reset.

### Simulator measurements (same simulator as Revisions 1 and 2, but different content and sampling)

| | Revision 1 | Revision 2 | Revision 3 |
|---|---|---|---|
| Nodes | 235 | ~320 | 310–332 |
| Draw calls | ~79–85 | 100–116 | 93–114 |
| FPS | 60 | 60 | 60: all 18 five-second windows, longest frame 16.7 ms |
| App footprint (phys_footprint) | 37–43 MB | 41 MB | 38–39 MB (220 MB RSS including shared) |
| Host CPU (simulator process) | — | — | 37% avg / 40% max of one core |

**Caveats:**

- Earlier counts were spot samples taken at different moments, so this isn't a controlled A/B, only "no regression visible".
- Simulator rendering runs on the Mac GPU and says nothing about iPad GPU cost or thermals.

### Still unverified: needs the physical iPad

1. Two-person live segmentation in the Revision 2/3 world at 2.5–3 m (cutout readability against busier backgrounds).
2. Parent/Child pose association under real movement (zone hysteresis on device).
3. Squat detection accuracy against a manual count (adult and child, ~50 reps each).
4. Real camera-to-feedback latency for real squats (~69 ms measured on the Revision 1 world; re-measure).
5. Frame-time stability with Vision running (~28 ms/frame of Vision on M4) plus ~100 draw calls and warped geometry.
6. A 10-minute thermal run with the app kept in the foreground.
7. Readability at play distance: lock widget, banners, lane panels.
8. Parent–child usability: understanding "both squat", comfort with curves and FOV kicks, and the need for a hands-free resume (e.g. both raise arms) instead of a tap.

### Recommendation

1. **Continued game design exploration: yes.** The loop is understandable, cooperative without requiring sync, and rewarding, and the state handling is sound.
2. **Integration with real Vision movement detection: yes, next.** The game consumes source-agnostic events; the real detector already feeds the same path.
3. **Production: not yet.** Every gameplay result here is from simulated input in the simulator. The on-device checklist above has to pass first, especially frame time with Vision and squat accuracy with a child.

---

## Revision 4: does true 3D beat Revision 3? (RealityKit experiment, 20 Oct 2026)

**Verdict: keep SpriteKit 2.5D (Option A).** True 3D was built, runs, and plays the same co-op loop. On iPad with this art direction, though, it delivered only a small visual gain, cost more memory and frame stability, and lost the one advantage that would have justified it (real-time lighting and shadows).

All results come from the iPad Pro 13" (M5) simulator, iOS 26.2, using simulated players. No device, camera, Vision or thermal claims are made. Evidence is in `Evidence/revision4-3d/`.

### What was built (isolated; Revision 3 untouched)

- **Separate app target `StuntRun3D`** (folder `StuntRun3D/`, ~1,270 lines).
  - It compiles Revision 3's shared sources, except Revision 3's `@main`, through a synchronized-folder exception.
  - Revision 3 still builds and runs independently, and all 19 logic tests still pass.
  - Source backup: `../Backups/StuntRunSpike-revision3-baseline-2026-10-20.zip`.
- **Host:** `RealityView` with `content.camera = .virtual`, a `PerspectiveCamera`, and per-frame work on `SceneEvents.Update`.
- **Framing matches Revision 3:** camera 1.0 above the roof, players at 1.9, 58° vertical FOV, 3.8° pitch, the same curve function and the same speed.
- **Procedural geometry only:**
  - a train roof and body;
  - a ground grid with rails;
  - pylons and neon arches;
  - volumetric buildings with per-face shading;
  - a three-quarter ferris wheel with twin rims, spokes and gondolas;
  - a suspension bridge with towers and cables;
  - a 10-ring twisting tunnel;
  - gates with posts, beam and lane panels, shattering into 3D shards;
  - a sky sphere, sun, mountains and skyline.
- **True-3D camera moves:** a FOV kick on boost, banking into curves, and a ride bob.
- **Gameplay:** `Coop3D` is a thin adapter over the *same* `SquatDetector`, `SimulatedSquat` and `TeamChallenge` code. It has no scoring rules of its own. The scripted demo runs both-succeed, staggered, and every third gate Child-misses (partial), and the log shows TEAM / partial outcomes resolving through `TeamChallenge`.
- **Compositing probe** (`-liveTexture YES`): the existing `CameraPipeline` output streams every frame into a `LowLevelTexture` (Metal blit) on a plane at player depth.

### Gameplay invariant reviewed

Reaching the bottom, provisional avoidance, a completed rep, a committed contribution and the team reward are separate events.

- **A held squat** earns exactly one contribution: new test 19, held across two challenges.
- **A shallow squat** is acknowledged but never counted (test 18).
- **Duplicate contributions** are ignored (test 13).
- **Interrupted squats** can't complete after a halt (test 17).

### What we learned building it

1. **Lighting fought the art direction.** Lit PBR materials rendered this dark neon palette as pale grey. An A/B in one frame (`3d-lighting-AB-unlit-left-vs-PBR-right.png`) confirmed RealityKit's exposure and tone mapping lift dark albedo. Lowering lights, removing environment lighting and fixing texture colour space didn't help. To keep the Premium Playful Arcade look, **most surfaces had to be unlit**, which forfeits RealityKit's real-time shading and shadows. Shading and shadows ended up faked (per-face tints, shadow planes): the same tricks Revision 3 already uses.
2. **No fog or bloom on iOS RealityKit.** Revision 3's shader fog and additive glow give it more atmosphere. The 3D version reads cleaner but flatter (see `side-by-side-rev3-left-vs-3d-right.png`).
3. **Genuine wins:**
   - solid, perspective-correct volumes everywhere;
   - a ferris wheel that really turns in depth;
   - a camera that can bank, roll and kick its FOV with the whole world staying consistent;
   - bodies placed *in* the scene, so 3D objects occlude them by real depth.
4. **The compositing path works:**
   - streaming the 640×480 texture costs about **0.21 ms CPU per frame (max 0.64 ms)**, measured in the simulator with the synthetic test card;
   - frame orientation is correct.

   **Risk found:** transparent planes at similar depth sort incorrectly (a cue's transparent area showed the buildings instead of the plane behind it). Real cutouts surrounded by transparent effects would need explicit sort control (e.g. `ModelSortGroupComponent`) and testing. The alternative layered stack (3D view, then a 2D cutout layer, then an overlay) avoids sorting problems but **can't put 3D objects in front of the bodies**, which our gates require.

### Controlled simulator comparison (same simulator, 60 s each, same in-app frame timer, `ps` sampling)

| | Revision 3 SpriteKit | 3D RealityKit |
|---|---|---|
| FPS (5 s windows) | 60.0 in all 13 windows | 59.8 avg (59.6 min) |
| Long frames | none: the longest frame in every window was 16.7 ms | 42 frames over 17.5 ms (up to 33 ms) across 8 of 12 windows |
| App memory (phys_footprint) | 38–41 MB | 70–78 MB (84–87 MB with the live-texture probe) |
| Host CPU (simulator process) | 41% avg | 30% avg |
| Scene objects | ~310–330 SpriteKit nodes | 627 model entities |

How to read this:

- **CPU isn't like-for-like.** Revision 3 also runs its simulator camera test card through Vision every frame; the 3D app doesn't.
- **Object counts aren't comparable** across renderers, and RealityKit draw calls couldn't be measured: Instruments' RealityKit Trace refuses the iPad simulator ("not supported on iPadOS Simulator"), and the `ARView` statistics overlay didn't appear there.
- **Simulator rendering uses the Mac GPU.** The iPad GPU, thermals and how 3D interacts with Vision's ~28 ms/frame are unmeasured.

### Option assessment

- **A. Keep SpriteKit 2.5D (recommended).**
  - It already matches 3D's perspective and volume closely, and has better atmosphere.
  - It runs on half the memory with steadier frames in this comparison.
  - It's proven with live Vision on an iPad Pro M4.
  - The whole team can iterate on it in the two months.
- **B. Hybrid (RealityKit world + SpriteKit/SwiftUI on top).**
  - The 3D/cutout/overlay stack composes, but bodies can't be occluded by 3D obstacles unless they're inside the RealityKit scene.
  - Putting them inside brings the transparency-sorting risk, a second renderer to maintain, and new failure modes, for a modest visual gain.
  - Not justified now.
- **C. Wider RealityKit adoption.**
  - Only worth it if the design needs orbiting or cinematic camera moves or lit 3D characters; it currently needs neither.
  - It would also need a 3D asset pipeline and lighting work to beat the exposure problem.
  - Not justified for Challenge 5.

**Cheaper way to get the 3D "wow" inside SpriteKit:** pre-render a few hero assets as sprite sequences (the rotating ferris wheel, the gate shatter, a mascot). Render them from this RealityKit scene, or from a DCC tool later, into texture atlases. That gives real 3D motion where it shows, with no runtime cost from a second renderer.

### Skills used

- `realitykit`: installed for this experiment (docs-only, PolyForm Perimeter licence). It drove the virtual camera, `SceneEvents.Update` instead of timers, entities built once in `make`, pooling with `isEnabled`, and few unique materials.
- `spritekit`: the comparison baseline and the pre-render recommendation.
- `game-feel`: matched anticipation, provisional versus committed feedback, and the TEAM reward; FOV kick and bank as speed cues.
- `motion-design`: entrance easing for gate posts and beam, a restrained bank and bob.
- `swiftui-expert-skill`: HUD state in an `@Observable` model separate from RealityKit's update loop.
- `vision-framework`: reused `CameraPipeline` unchanged for the compositing probe.
- `create-game-assets`: procedural-only assets; it informed the decision not to start a 3D pipeline.

**Fix (20 Oct 2026): camera upside down when running as "Designed for iPad" on a Mac.** iOS emulates an iPad orientation on the Mac, so `RotationCoordinator` reported 90°/180°. On a Mac (`isiOSAppOnMac` / Mac Catalyst), `CameraPipeline` now locks rotation to 0°. Confirmed upright on the MacBook camera. The iPad path is unchanged.

---

## Revision 5: hero TEAM DUCK moment, with 3D-authored and pre-rendered debris (20 Oct 2026)

**Goal:** make the one moment that rewards cooperation feel premium, without adding a runtime engine. SpriteKit Revision 3 stays the baseline. The RealityKit experiment is kept but not expanded. Movement detection, gameplay logic and scoring are unchanged: an A/B of the scripted run produced an **identical 38-event gameplay sequence** (contributions, reps, outcomes, TURBO) with hero and legacy presentation. All results are from the iPad Pro 13" (M5) simulator, iOS 26.2.

### The pipeline: author in 3D, play back as 2D

- `Tools/BakeTeamDuck/` is a macOS command-line tool, **not shipped**; re-run it with `./Tools/BakeTeamDuck/bake.sh`.
  - It uses RealityKit's offline `RealityRenderer` from the **same camera** as the game (1.0 m height, players at 1.9 m, 58° FOV, 3.8° pitch).
  - The gate beam is split into 22 lit, rotating 3D chunks: coral on Parent's half, teal on Child's, so the debris carries both players' colours. 14 spark bits fly with them.
  - Physics is seeded, so every re-bake is identical.
  - Tone mapping is off, which keeps the palette exact (the Revision 4 grey-wash problem doesn't apply to an unlit-background bake).
  - 4× sub-frame accumulation gives real motion blur.
- **Output:** `TeamDuckShatter.png` (18 frames at 30 fps = 0.6 s; 4128×795; 2.6 MB in the app bundle) plus `TeamDuckShatter.json` with screen-space placement.
- **In game:** one `SKSpriteNode` plays `SKAction.animate`. The sheet is preloaded at scene start, so there's no upload hitch at the big moment.

### The hero sequence (`WorldScene+Hero.swift`, applied by game-feel and motion-design)

| Time | Beat |
|---|---|
| 0–70 ms | **Anticipation:** both beam halves flare and the beam swells; **hit-stop** freezes world motion for 70 ms. Input, detectors and the game clock keep running, so responsiveness is untouched. A "lock" chime plays. |
| 70 ms | **Impact:** the baked 3D shatter plays, flung *ahead* down the track (shrinking toward the horizon, never toward the players' bodies). A mint shockwave ring, a spark burst, a soft 0.18 flash, and a **directional camera kick** (9 pt down, springing back) replace the random shake. |
| 70 ms+ | **Layered audio:** synthesised low *impact* thump, glassy *shatter*, and whoosh; the team chord follows 80 ms later. Three seeded variants of each, so repeats don't sound identical. |
| 70 ms+ | **Reward:** "TEAM DUCK!" slams in from 1.9× and settles with overshoot (previously popped up from small); fireworks at +300 ms; the boost is unchanged. |
| Reduce Motion | The beam dissolves, a small sparkle, the banner fades in. No hit-stop, kick, flash or flying debris. |

- **A/B switch:** the "Hero TEAM DUCK" toggle in the dev panel, or the launch argument `-heroFX legacy`.
- **Fixed during validation:** the flare was additive at full white while the beam is right in front of the camera, which over-exposed the top band. It's now capped at 0.7 / 25% white.

### Verified in the simulator

- **Visuals:**
  - `teamduck-hero-top-vs-legacy-bottom.png` shows matched frames from 0 to 1 s.
  - Legacy is a few small confetti triangles. Hero is large, lit, motion-blurred 3D debris in both players' colours, a shockwave and a slam banner.
  - The debris stays in the upper band and doesn't cover the figures; the HUD stays on top.
- **Frame time:** in the 1.2 s after each TEAM DUCK, all frames were ≤ 16.7 ms (71–72 frames each, across four events). Whole 2-minute runs: 60 fps in every 5 s window for both hero and legacy.
- **Memory:** 39–54 MB in both runs, with no measurable difference. The sheet loads in both modes, about 13 MB decoded GPU texture by calculation, not measured.
- **Audio** (offline mix of the same layers):
  - hero peaks at −4.7 dBFS versus −10.9 dBFS for legacy, with no clipping;
  - RMS in the first 100 ms is +4.4 dB, which is the impact layer;
  - the tail is similar.
  - WAVs are in the evidence folder for a listening check.
- **Tests:** 19/19 logic tests pass. Revision 3 and the RealityKit experiment both still build.

### Not verified (needs the physical iPad or real players)

- iPad GPU cost of the 4128×795 sheet and the additive layers, with Vision running at the same time.
- How it reads at 2.5–3 m on a 13" screen, and over real body cutouts instead of stand-in figures.
- Audio loudness on iPad speakers in a room.
- Whether a 70 ms hit-stop feels good during real squats (timing is experimental).
- Whether children find the moment more rewarding. That's a playtest question.

### Next, if this lands well

Use the same bake pipeline for 1–2 more beats only: the TURBO surge, and a mascot reaction on a partial success. Expand only after the iPad playtest confirms the improvement.

---

## Revision 6: travel direction and a warning-first obstacle sequence (20 Oct 2026)

### What actually caused the "moving backwards" feeling

Previous revisions changed field of view, speed and curves, but never the real cue. **The train roof the players stand on was itself scrolling under their feet toward the camera.** Players face the camera, so the floor slid in the direction they face. Near-field ground texture under the feet is the dominant self-motion cue, and a floor sliding forward under you reads as *you* being dragged backwards: a treadmill or a moonwalk. Nothing in the scene contradicted this. There was no vehicle front, no locomotive, no headlights: just an endless sliding surface.

There's also a geometric point worth recording, because it limits what's possible. A front camera shows players' *faces*. If obstacles come from the horizon and exit toward the camera (the requested design, and what Shape Up does), then in world terms the players travel toward the horizon while facing backwards. That's fine and readable **if they are clearly passengers on a moving vehicle** (like riding backwards on a train). It reads wrong if they seem to be on a sliding floor. The only fully "facing forward" alternative would be for the world to recede into the horizon, with obstacles arriving from the camera side, which contradicts the requested horizon reveal. So the fix makes the vehicle unambiguous rather than reversing the flow.

### Fix (SpriteKit only; no engine change)

- **The deck travels with the players.** Carriage panels, gaps and couplings, hazard edges, rails and marker lights are fixed in the train's frame. The lights blink in place and never slide.
- **The world streams past the train:** the ground grid, our own track continuing ahead, neighbouring track, sleepers, pylons, buildings, landmarks, tunnels, bridges and gates.
- **The train has a front.** A locomotive (rear view with red tail lights) leads the train 24 m ahead, and its headlights throw a warm cone onto the track in front of it. The carriages and locomotive bend with the track curves, because the train follows the track.
- **Approach lanes no longer slide along the deck.** They glow and pulse in place between the gate and each player.
- **Measured from the rendered video** (block matching / frame difference, simulator recordings):
  - deck under the players: frame-to-frame change **6.7 → 0.5** (it no longer moves);
  - side ground: still flows outward and down from the vanishing point (≈5.5 px/frame outward, ≈3 px/frame down), unchanged.
  - See `Evidence/revision6-direction/motion-before-top-vs-after-bottom-frame-difference.png`: before, the deck lines under the players light up; after, the deck is dark and only the world moves.

### The new encounter sequence (pure `EncounterTiming`, separately configurable)

| Phase | Default | What happens |
|---|---|---|
| A. Warning | 1.6 s | **"DUCK INCOMING!"** with a pulsing "!" where the track disappears. No obstacle, **nothing judged**. |
| B. Reveal + approach | 5.0 s to arrival | The gate appears at about 51 m, fading in out of the haze (fog-tinted, posts springing up, beacon). It grows as the train carries the players toward it. No speed boosts during an encounter, and TURBO is deferred until it resolves. |
| C. Action | opens 2.6 s before arrival | **"DUCK!"**, lane panels, cues over heads, the shared 0/2 lock, approach lanes and ticks. The `TeamChallenge` is created *now*, so only squats reaching the bottom inside this window contribute. |
| D. Interaction | — | Movement started (provisional), bottom reached (the contribution, recorded once), rep completed (on standing). All separate, all unchanged. |
| E. Pass | at arrival | The gate continues past the players toward the camera and leaves the frame. If both players have already contributed, the beam breaks **0.3 s before arrival** while still visible above them. The **hero debris was re-baked** to keep moving toward the camera and exit through the top and sides; it no longer recedes. |
| F. Reward + recovery | 3.0 s | TEAM DUCK / NICE feedback, then at least 3 s neutral before the next warning. The minimum rest between judging windows is **7 s**, enforced by a test. |

- **Timings are provisional** (tuned for simulator readability, not validated reaction times). Override them with launch arguments: `-warningDuration`, `-approachDuration`, `-actionLead`, `-lateGrace`, `-recoveryDuration`, `-impactLead`.
- **If you change `impactLead` or the camera, re-bake the debris:** `./Tools/BakeTeamDuck/bake.sh`.

### Validation (iPad Pro 13" M5 simulator, iOS 26.2, simulated movement only)

- **Scripted run: 11 encounters across 2 sessions, all behaving as designed.**
  1. Both players, staggered: TEAM.
  2. Parent only: partial.
  3. Child late but inside the window: TEAM.
  4. **Child late (bottom after the beam passed)**: partial, but the child's rep still counted.
  5. **Parent early during the warning**: no contribution, rep counted.
  6. **Parent early during the approach**: no contribution, rep counted.
  7. Shallow squat: "GO DEEPER", not counted.
  8. **Tracking lost during the approach**: encounter withdrawn → READY → resume → countdown.
  9. Pause inside the DUCK window: withdrawn; the in-progress rep was ignored during the countdown.
  10. Both, then replay.
  11. New session: counters at zero, no stale obstacles.
- **No duplicates:** all 36 contributions in the run are unique per player per challenge.
- **Tests:** 21/21 logic tests pass, including new test 20 (phase order and boundaries, late grace, minimum rest, invalid configs) and test 21 (early, in-window and late squats contribute correctly and reps still count).
- **Performance:** 60 fps in all 39 windows (longest frame 16.7 ms); 0 long frames in the 1.2 s after each TEAM DUCK; memory 40–49 MB.
- **Evidence:** in `Evidence/revision6-direction/`, a 30 s clip covering two full encounters, the storyboard, the pass/debris grid, the warning frame and the game log.
- **Also fixed during validation:**
  - a shader uniform named `u_time` collided with SpriteKit's built-in, which made the floor render white; it's renamed, and runs now check the log for shader compile failures;
  - the script finished one encounter early;
  - an orphaned simulator screen recorder had to be cleared by rebooting the simulator.

### Not verified

- Whether *people* now perceive forward travel. The measurements show the cue conflict is gone, but this needs the playtest: show 3–5 people the before/after clips and then the live game.
- How the locomotive and headlights read at 2.5–3 m on the 13" screen.
- Real-squat timing against the 2.6 s action window (simulated squats only).
- All camera, Vision and iPad items from earlier revisions.

---

## Revision 7: second game mode, Jungle Drift (21 Oct 2026)

**Fantasy:** Parent and Child are stranded on one raft, drifting deeper into an endless Amazon river. They keep the raft level together, duck flocks of birds that swoop out of the canopy, and fight off alligators that lunge at the raft's edge and try to drag it under.

**How to open it:** the "Game" picker in the dev panel (Stunt Run | Jungle Drift) recreates the scene; camera and settings carry over. Or launch with `-gameMode jungle`; add `-scenario coop` for the deterministic script, or use **Run script** in the panel. Jungle lean buttons: **A/D** (P1 lean left/right) and **J/L** (P2). Stunt Run is unchanged: identical scripted outcome sequence to Revision 6, 60 fps.

### Movement vocabulary: two actions, kept small for a parent and child

| Action | Body movement | Used for | Later camera mapping (unvalidated) |
|---|---|---|---|
| **Duck** | squat (existing `SquatDetector`) | birds | unchanged |
| **Lean** | small sideways weight shift | raft balance and alligator strikes | `LeanEstimator`: torso angle from neck vs hips, 2.5° dead zone, full lean at 12°. Mirrored like a mirror, so screen-right is the player's own right |

Leaning needs only a gentle torso tilt, not a step. The camera doesn't roll, only the raft does (capped at 9°, or 4° under Reduce Motion), so nothing on screen invites big or unsafe movements. That still needs checking with real people.

### How the systems interlock (one shared raft)

- **Balance (`RaftBalance`):** a damped rocking model.
  - River currents push predictably; drift arrows on the water show the direction. Ignored, the raft lists about 9°: uncomfortable, never a splash on its own.
  - **Both players' leans add up.** One helps, two recover clearly faster. Lean toward the *high* side; the gauge and a "LEAN LEFT/RIGHT" arrow say which way.
  - **Crouching damps rocking**, so ducking for birds also steadies the raft.
  - Past 16° the low edge glows coral and spray flies. After **1.6 s** in danger, water washes over: **SPLASH**, −2 Team Power, and the raft is righted.
  - 6 s level during a calm stretch earns **STEADY RAFT +1**.
- **Birds (DUCK):** the same `EncounterTiming` phases and `TeamChallenge` as Stunt Run gates.
  1. **BIRDS INCOMING!** with the canopy rustling and a caw.
  2. The flock appears above the canopy far ahead.
  3. It swoops down to head height.
  4. **DUCK!**, with the 0/2 lock.
  5. Each player's squat bottom counts once.
  - **TEAM DUCK:** the flock sails over and the jungle reacts with light, stirring canopy and a bright flock.
  - **Partial:** the late player gets bonked with feathers, **and the raft lurches toward them**. A missed duck becomes a balance problem.
- **Alligators (LEAN):** a different role, an attack on the shared raft rather than an obstacle to dodge.
  1. **GATOR — LEFT!** with bubbles; nothing visible yet.
  2. Eyes surface and swim in.
  3. **STRIKE:** a jolt; it clamps onto that edge and drags it down for 2.4 s.
  4. **LEAN RIGHT!** Each player counts once they've held a correct lean for 0.4 s.
  5. It lets go, and the raft must be level for 0.5 s.
  - Outcomes: **TEAM STEADY** (both leaned, bonus) / **STEADY** (one leaned) / **PHEW** (still rocking at time-out) / **SPLASH** (nobody leaned).
- **Director:** birds → gator → calm + landmark → *gator then birds* → birds → calm, repeating with the alligator sides mirrored on alternate laps.
  - In the combo, the bird warning arrives while the raft is still rocking, but the duck window opens only after the alligator window closes. A test enforces this, so two demands never overlap.
  - Every beat ends with ≥ 3 s of calm drifting.

### Endless living river (same projection and lessons as Stunt Run)

- **The raft rides the current.** The water near it shimmers in place and drifts slowly; the banks and scenery are land and stream past at travel speed. **Measured on the recording:** deck under the players frame-difference 0.8 (still); the sides flow outward and down from the vanishing point at ≈3.6–4.1 px/frame outward, ≈1.2–1.4 down. Same forward-travel signature as the fixed Stunt Run, no reversal.
- **Endless, without seams:**
  - 48 pooled bank props and 10 water props, recycled 90–96 units ahead with fresh biome-weighted picks and a 0.8 s fade-in;
  - bank width varies (two sine terms) and the river bends (curvature, with the sky and treeline panning);
  - **four biomes**, cross-faded over 40 units: Open River, Deep Canopy, Lost Ruins, Misty Backwater. They change density, palms, mist, light shafts, fog and haze;
  - landmarks are staged in calm stretches: lost temple, giant kapok, a fallen tree spanning the river.
- **Alive:**
  - swaying trees, reeds and vines;
  - canopy corners framing the top band only, never the players;
  - light shafts, mist, ambient flocks crossing between the trees;
  - ripples, wake and spray around the raft;
  - a looping ambience bed (insects, distant birds, water).
- **Raft:**
  - perspective log deck with lashings and log-end faces;
  - a mast with a fluttering flag;
  - contact shadows; gentle buoyancy bob and roll;
  - a jolt and spray when the alligator strikes.
  - Riders (cutout or stand-ins), pads and labels sit inside the raft rig, so they rise and tilt with it.
- **Audio:** synthesised caw, splash, wood creak and growl, plus the ambience loop, all on the existing SFX bus.

### Verification (iPad Pro 13" M5 simulator, iOS 26.2, simulated players only)

- **Tests:** 27/27 logic tests pass, 6 of them new (22–27), covering:
  - balance under current;
  - an alligator grip with nobody / one / both players leaning;
  - a team reacting after **0.9 s** still succeeding;
  - crouch damping;
  - the steady-streak and splash cooldown;
  - the lean estimator;
  - alligator contributions (once each; wrong-way leans never count) and outcomes;
  - director order, mirroring and combo sequencing.
- **Scripted run** (`-gameMode jungle -scenario coop`): all 11 steps produced the intended outcome.
  1. Birds, both duck: TEAM.
  2. Gator, both lean: TEAM STEADY.
  3. Calm + lost temple.
  4. Gator + birds, only the Parent leans: STEADY, then birds TEAM.
  5. Child late: bonk + raft wobble.
  6. Child's tracking lost → READY → resume.
  7. Pause inside the DUCK window: withdrawn.
  8. **Nobody leans: SPLASH.**
  9. Calm + giant kapok.
  10. Gator + birds, both: TEAM STEADY + TEAM, then replay.
  11. New session: counters reset, TEAM.
- **Performance** (clean run, no snapshot harness): 60 fps in all 24 windows, longest frame 16.7 ms; 219–230 nodes, 83–100 draw calls; 52–56 MB.
- **Defects found and fixed during validation:**
  1. The world rendered black (the world root was only attached in Stunt Run's build path).
  2. The raft was too wide and hid the water.
  3. The alligator was anchored by its tail, so it covered a player.
  4. **Recycled scenery vanished:** SpriteKit stores `size` divided by the current scale, so far-scaled sprites ballooned when reused.
  5. The tuning only worked for instant reactions, so it was retuned for ~0.6–0.9 s parent-child reactions.
  6. Steady rewards fired during hazards and while halted.
  7. The script's replay fired before the combo birds finished.
  8. Landmark textures hitched on first use; they're now preloaded.

### Not verified (needs the physical iPad and real families)

- Live cutouts on the raft at 2.5–3 m: do the bodies read as "standing on the raft"? The whole cutout rolls with the raft; check it doesn't look odd.
- **Lean detection from real poses:** threshold, dead zone, and whether children lean clearly enough; whether a squat is misread as a lean.
- Whether players naturally lean *toward the high side* or need teaching. The prompt arrow is there, but untested.
- Real camera-to-feedback latency for leans, and frame time with Vision running alongside this scene.
- Comfort: raft roll and river curves for a child; whether anyone over-leans or steps out of their zone.
- Whether the alligator is fun-scary or too scary for young children (tone, growl volume).

---

## Revision 8: Jungle Drift creature animation and river art direction (21 Oct 2026)

**Goal:** make the crocodile, the birds and the river look art-directed and alive (Premium Playful Arcade) without touching gameplay. **Style contract:** [JUNGLE_ART_DIRECTION.md](JUNGLE_ART_DIRECTION.md), which covers:
- shape language, a single ink outline at about 2% of body length, flat cel shading (base, shadow, highlight);
- palette roles, light, and detail hierarchy;
- a timing palette and easing rules;
- anticipation, follow-through, controlled variation, and restraint (no random particles, no glow, no idle bounce).

**Skills used:** `create-game-assets` (style brief, parametric families, contact-sheet QA), `motion-design` (Disney principles, timing and easing), `spritekit`, `game-feel`, `audio-design`.

### What changed (gameplay rules and timing untouched)

| | Before | Now |
|---|---|---|
| **Crocodile** | One static jaw image, scaled up at the strike | A layered rig in two views sharing one eye design (see below) |
| **Birds** | 2-frame dark silhouettes | Macaws (shared coral/yellow/teal cues) with 8-frame flap cycles and authored poses (see below) |
| **River** | Noise glints plus a fixed wake | Water that reacts to the raft and the crocodile (see below) |
| **Sound** | growl, caw, splash | Adds a jaw **chomp** (tooth click, jaw thud, wood crunch), a lurking **gurgle**, a rising **hiss** before the lunge, and a wingbeat **flutter** at the flare. Variants rotate on the existing SFX bus. |

**Crocodile rig**
- **Head-on (approach):** eye bumps and snout above the water.
- **Side (attack):** upper head with teeth and fang, a hinged lower jaw, a throat that opens with the jaw, and an eye with a dilating slit pupil, sliding lid, angry brow and glint. Also a body with scute ridge, a tail with crest, and a reaching front leg.
- **Waterline:** everything is cut at the water by a crop mask.
- **Bite:** the lower jaw and throat draw *under* the raft deck, so the deck hides the part beneath the logs and the jaws visibly clamp the edge.
- **Water contact:** a soft submerged silhouette and a foam collar.
- **Performance** is a pure function of the encounter clock (`CrocAnimator`): lurking → surfacing → swimming → anticipation → lunging → impact → clinging → retreat → gone.
  - **Lurking:** only a shadow under the water.
  - **Surfacing:** eyes first, lids heavy.
  - **Swimming:** an S-swim, one blink, eyes fixed on the riders.
  - **Anticipation:** eyes narrow, a small pull-back, then it sinks and the water bulges. Sinking also hides the switch from the head-on view to the side view.
  - **Lunging:** 0.18 s. It bursts out with jaw wide, nose up, stretched, pupils dilated.
  - **Impact:** the snap lands exactly on `GatorTiming.strikeTime` (squash, jolt, splash crown).
  - **Clinging:** it yank-thrashes on two out-of-step rhythms, and the tail and body lag the head. When the players lean away, it is hauled up and struggles harder.
  - **Retreat:** it lets go, falls back, the entry splash lands, and the silhouette glides away.
  - The performance outlives the encounter (`crocExits`), so gameplay timing is unchanged.

**Bird flight**
- Every frame and pose is rendered by one parametric drawing function, so proportions never drift.
- **Flap cycle:** the power downstroke takes 42% of the beat; on the upstroke the wing is partly folded.
- **Poses:** glide, tucked dive, flare (wings high, feet out), and startled (crest up, beak open).
- **Flight** (`BirdFlight`, pure): take-off from just above the canopy with fast beats, then a flap-glide cruise converging on the lanes, then a tucked dive, then a flare (anticipation) and hard beats through the pass.
  - **TEAM duck:** the flock skims over the heads and climbs away.
  - **Partial:** the lead bird in the late player's lane goes startled, does one full tumble (ending upright) and flaps off.
- **Controlled variation per bird:** flap rate ±12%, phase, size ±6%, weave, staggered take-off, and two palettes of the same species. Banking follows lateral velocity.
- The far ambient flocks use the same macaw cycle.

**River shader**
- Layered surface: a swell along the flow plus two wind-ripple trains and fine chop. Analytic slopes light the facets, and a slow noise warp keeps crests from reading as ruled lines.
- Reflections: sky haze at grazing angles, and the dark forest mirrored near the banks, broken by ripples.
- Sun glitter along the sun path, and short current dashes near the raft.
- **Responds to the raft:**
  - contact shade on the water;
  - crisp lumpy foam hugging the logs, plus wavelet crests moving out, stronger with the bob and on the low side;
  - a bow pillow and a wake;
  - when the raft rolls hard, the low edge plunges and spreads a ring, with spray only when it's tipping.
- **Responds to the croc:**
  - a V-wake behind the swimming head;
  - a pressure trail over the lurking body;
  - a snout pillow and thrash foam while it clings;
  - expanding rings at surfacing, lunge, bite and retreat;
  - a 6-frame authored splash crown, drawn behind the croc so it bursts through its own splash.
- The ripple sprite lost its glow. Every water effect is caused by something touching the water.

### Inspected, found, fixed (from recorded frames)

| Seen in the recording | Fix |
|---|---|
| Head-on croc read as a frog (big round eye bumps) | Low, wide skull; almond eye bumps under heavy brows; a snout running to a separate nostril pad |
| Approach ended overlapping the raft corner | Approach ends in open water beside the raft |
| Clinging croc mostly off-screen in the bottom-left corner, head too big | Bite point moved to z = 2.5 along the raft side; head 0.78 units |
| Foam collar smeared across the jaw | Smaller, behind the head at the neck |
| Splash crown hid the lunge | Crown drawn behind the croc, smaller |
| Lower jaw visible below the waterline | The under-deck jaw layer got its own waterline crop |
| Clinging looked static | Yank: a head wrench plus a downward tug on the same beat |
| River: straight "scratch" lines converging on the horizon | Warped wave phases, sparkle-broken glints, flow dashes faded with distance |
| Raft foam invisible (under the floating deck), then a soft glow band with a hard horizontal cut | Foam drawn around a footprint wider than the deck; crisp lumpy edge; near bound moved off-screen |
| Flock crossed the HUD team indicator for ~1 s in its dive, and over the TEAM banner after the pass | Take-off height 5.4 → 4.3; pull-up skims just over the heads. Now ~0.25 s over the indicator while diving. |
| Splash crown dropped abruptly; drops clipped | Fast-rise, slow-fall heights; drops kept in frame |

### Verification (iPad Pro 13" M5 simulator, iOS 26.2; simulated players)

- **Tests:** 31/31 logic tests pass. The 4 new ones (28–31) cover:
  - croc state order, nothing above water before the reveal, sink-before-lunge, jaw wide just before the strike and shut right after;
  - no body pops between 60 fps frames, and the jaw snap spread over several frames;
  - a short configured approach keeps every state, and lifting the edge hauls the croc up and makes it struggle harder;
  - the flap cycle's 42% downstroke with every frame used, arrival at head height, tucked dive, flare before the pass, a smooth flight path;
  - variation bounds and determinism, two palettes, no two birds in phase, the tumble ending upright, the TEAM pull-up.
- **Scripted run** (`-gameMode jungle -scenario coop`): all 11 steps give the intended outcomes and **the outcome lines match Revision 7 exactly**. The script finishes at 123.8 s (Revision 7: 123.7 s).
- **Stunt Run:** scripted outcome lines **match Revision 6 through the end of the script** (45 lines). After the first window it runs at 60 fps with a 16.7 ms longest frame. Its first window also has one 79–100 ms load frame. That isn't from this change (jungle art is only built in Jungle Drift), but Revision 6's first-window metrics weren't kept, so it can't be compared.
- **Motion grammar** (optical flow on the new recording):
  - deck under the players: still (change 0.8);
  - left bank: dx −4.50, dy +1.46 px/frame;
  - right bank: dx +5.00, dy +1.42 px/frame;
  - i.e. outward and down from the vanishing point, forward travel as before.
- **Performance, clean scripted run** (no recording or snapshots):
  - after the first 5 s window, all 24 windows run at 60 fps with the longest frame 16.7 ms;
  - steady memory 53–57 MB;
  - host CPU 35% average (38% max), RSS 215 MB (Revision 7: 37%/43%, 242 MB).
- **One-time load hitch:** generating the 70 jungle textures takes **65 ms** when the mode loads, which shows as one 56–84 ms frame during the opening countdown, before any hazard. If it's noticeable on device, move the generation to app launch.
- **Evidence** is in `Evidence/revision8-animation/`:
  - contact sheets: croc layered parts; macaw flap cycle and poses in both palettes; splash crown;
  - frame sequences: croc approach → anticipation → lunge at 10 fps, cling → lift → retreat, bird take-off → dive, flare → pass → pull-up at 15 fps, and the right-side mirror + bird bonk + croc splash;
  - river foam close-up and calm frames;
  - clips: croc encounter, bird encounter, calm river segment, and the full 11-step run;
  - game log, clean-run metrics and CPU, optical flow.

### Known limitations

- **All art is drawn in code** (Core Graphics, parametric and seeded). No image-generation tool was available, and no external assets or licences are involved.
- **Where creatures overlap players:**
  - In a partial duck, the lead bird still flies at head height toward a player who ducked early and has stood back up. This is the existing duck-window timing, not something the art can fix without changing gameplay.
  - The croc's head draws behind the Parent when it's in front of it (correct depth, but it can hide part of the snout).
- **Simulator only:** not judged at 2.5–3 m on a real iPad, under live Vision load, or with children. Check on device:
  - croc scariness and sound levels for young children;
  - bird readability as they pass;
  - shader cost on the iPad GPU alongside segmentation.

---

## Revision 9: Piranha Jump, a third movement for Jungle Drift (21 Oct 2026)

**Goal:** add a JUMP hazard that feels natural in the river fantasy, without replacing anything. The movement language is now one action per hazard:

| Hazard | Movement | What it asks of the body |
|---|---|---|
| Birds (overhead) | **DUCK** | squat under a flock at head height |
| Crocodile (on the raft edge) | **BALANCE** | lean away together to level the shared raft |
| **Piranhas (across the deck)** | **JUMP** | both feet off the logs while a fish arcs low through the foot zone |

Everything here was validated in the **iPad Pro 13" (M5) simulator, iOS 26.2, with simulated movement only**. Nothing is evidence of camera, Vision or real-jump detection.

### The encounter (`PiranhaLogic.swift`, `WorldScene+Piranha.swift`)

| Phase | Time from warning | What players see and hear |
|---|---|---|
| **A · Warning** | 0–1.8 s | Banner **PIRANHAS — LEFT!** "Get ready to JUMP over them"; a yellow badge (leaping fish + up arrow) at that side's screen edge, never over a player; dorsal fins circling and water boiling (bubbles, ripples, a dense bloop sound) **in the river ahead, in the gap between the two players**. Nothing leaps. |
| **B · Reveal** | 1.8 s → | The fins race in down that gap, then swing out to the raft edge beside the players. A **dashed leap path** glows across the deck at shin height (drawn behind the bodies, on the logs) and the attack side glows yellow at foot height. |
| **JUMP! cue** | 1.4 s before the first crossing | Banner **JUMP!**, the 0/2 team lock, up-chevrons over both heads, and a light chase running along the path in the direction of travel. Three rising ticks lead to each leap ("3-2-1-hop"). |
| **C · Leap** | 3.4 s | The fins dip (anticipation), then the fish bursts out of the water beside the near player (splash crown, water ring, bright rising "leap" sound) and arcs **low across the deck**: ~0.3 units above the logs at each lane, the apex between the players. It passes the near player first and the far player **~0.46 s later**, snapping its jaws at each pair of feet (tiny tooth clack). A soft shadow slides along the deck under it; a smaller school fish follows behind the players. |
| **D · Resolve** | per lane | **Feet off the deck in the window** → the lock fills on the spot, **CLEARED!** pops as the fish passes underneath. **On the deck** → **NIPPED!** (or **TOO EARLY!**), a cartoon "nyip", a little splash at that edge, the raft jostles slightly, the stand-in gives a startled hop. Taking off just after the window relabels it **TOO LATE!**. Shared result: **TEAM JUMP!** (bonus, sparks, the jungle lights up) / **NICE!** "Jump together for the TEAM bonus" / **CHOMP!** "Jump when they leap — watch the fins!". Splashdown on the far side; the river carries on. |

**Judging (pure, unit-tested `PiranhaLeap`):** a player clears a leap if they are airborne at any moment in **[crossing − 0.35 s, crossing + 0.20 s]**. With a ~0.4 s hop, that accepts a takeoff from about 0.76 s before to 0.15 s after the fish reaches their lane (~0.9 s), which includes ~70 ms of camera latency. Each clear banks **+1 Team Power once**; all participants clearing adds the **+1 team bonus**. Misses cost nothing (no power lost). The labels are feedback only:
- **TOO EARLY:** landed after the cue but before the window opened.
- **TOO LATE:** took off within 0.6 s after the window closed.
- **no jump:** neither.

A later leap in a burst only starts watching after the previous leap's windows close, so the landing from leap 1 can never be called "early" for leap 2.

**Burst and escalation (challenge without unfairness):** bursts keep the same side, so the warning stays truthful, and space launches 1.6 s apart (≥ 0.5 s from one leap's last window to the next leap's first crossing). Each lap adds one fish per burst, up to three.

### Jump input

- **`JumpDetector`:** hip rise above a calibrated standing height, in torso lengths.
  - Takeoff above 0.14, landed below 0.07 (hysteresis), light smoothing.
  - With ankles visible, the feet must have risen too, so tiptoes and stretches don't count.
  - The baseline adapts only while grounded and never follows the hips down (squats, the crouch before a jump).
  - "Airborne" longer than 1.2 s recalibrates instead of sticking.
  - It runs on the same poses as the squat detector (live) or on a `SimulatedJump` (crouch, then a ballistic hop) through the same code path.
- **Feedback is front-loaded:** the pad flares and a soft hop sounds on the frame the takeoff is detected; landing gives a thud and a squash. Live takeoffs feed the existing capture-to-feedback latency meter.
- **Stand-ins** use the same detector values the judge uses: crouch squash, stretch in the air, landing squash, lift exaggerated ×1.4 for staging. The contact shadow stays on the deck and shrinks.
- **Dev tools:** **E** / **I** = P1 / P2 jump, **4** = both (buttons in the jungle panel). All timings are launch arguments: `-piranhaWarning`, `-piranhaApproach`, `-piranhaCueLead`, `-piranhaFlight`, `-piranhaSpacing`, `-jumpBefore`, `-jumpAfter`.

### Fitting into the director

- **New lap (9 beats):** birds → **piranhas ×1** → gator → calm + landmark → **gator then piranhas** → birds → **piranhas ×2** → gator + birds → calm.
- Sides are mirrored on odd laps.
- **Gator then piranhas:** the piranhas come from the side opposite the bite, 2.6 s after the strike, while the raft is still settling. Their JUMP cue comes only after the gator's recovery window closes (a test enforces this for both sides), so two demands never overlap.
- **Reused, not rebuilt:**
  - `TeamChallenge` (contribution once, partial and team outcomes, cancel);
  - `SessionFlow`: pause, tracking loss and replay withdraw the hazard with no result and keep banked power;
  - the team lock, banners, ratings, cues (now pointing up or down);
  - water rings, splash crowns, ripples, droplets, the SFX bus;
  - the script harness and evidence capture.
- **Unchanged:** the gator stays the shared-raft balance hazard and the birds stay the duck hazard; neither's rules or timing changed.

### Art and sound (code-drawn, `Art+Piranha.swift`, per JUNGLE_ART_DIRECTION.md)

- **Piranha:** a layered side-view rig. Body: tall rounded disc with a slate back, the one warm accent (a coral-red belly), a big white eye with a heavy brow and three upper teeth. A hinged underbite jaw with four big teeth and a beating tail fan. Same ink outline on every part, flat cel shading.
- **Pure `PiranhaAnimator`:** circling → surging → leaping → splashed. Volume-preserving stretch on the burst and squash into the splash (≤ 15%), the jaw snapping around each lane crossing, the body following the arc's tangent.
- **Also drawn:** dorsal fin, warning badge, path dash.
- **Sounds** (synthesised, with variants, on the existing bus): `boil`, `leap`, `snap`, `hop`, `land`, `nip`. They layer with the existing tick, whoosh, pop, chime, splash and team sounds. The ambience loop keeps running underneath.

### Validation

**Logic tests: all 39 pass** (8 new, 32–39, plus an extended 27):
- jump detector: hop, jitter, tracking loss; poses: real jump vs tiptoes vs squat; baseline drift;
- the path: shin height, near lane first, cue before launch, timing validity;
- judging: on time → cleared once (+1) and TEAM (+1); too early / too late / no jump labels, partial; end-of-window and long early hops still count; a hop before the cue earns nothing;
- solo play; cancel keeps banked credit;
- burst spacing and per-leap judging;
- animator order, launch on the gameplay clock, jaw snaps, fins stay in the gap, smooth arc;
- director: new cycle, mirroring, burst growth (cap 3), combo sequencing.

**Scripted run (`-gameMode jungle -scenario coop`, 16 steps, all as intended).** Outcomes were identical across three evidence runs and the clean run:

| Requested case | Step | Result in the log |
|---|---|---|
| 1. Single piranha jump · 2. warning before the leap · 3. success · 7. both succeed · 10. after birds | 2 | warning 1.8 s and reveal before the JUMP! cue; Parent and Child cleared (+1 each); **TEAM** (+1 bonus) |
| 4. Too early · 8. one succeeds, one fails · 9. after crocodile recovery | 5 | gator TEAM STEADY first; Parent cleared; Child **TOO EARLY** → partial, no bonus |
| 5. Too late · 6. no jump · burst | 7 | leap 1: Child no jump, Parent **TOO LATE** → CHOMP; leap 2: both cleared → TEAM |
| 11. Pause during the warning | 11 | paused 0.9 s into the warning → **withdrawn**, no result, clean resume → next beat |
| 12. Replay does not keep stale state | 14 → 15–16 | replay with the fish in the air → withdrawn; new session: counters 0, ids restart (#2), birds then piranhas → TEAM |

The existing cases are unchanged: birds TEAM / bonk, gator TEAM STEADY / steady / SPLASH, tracking lost → READY → resume, pause in the DUCK window.

**Readability check from the recordings.** Three defects were found and fixed before the final run:
1. The warning badge sat over the Parent's head. It's now at the screen edge.
2. The warning fins were hidden behind the Parent. They now gather and approach in the gap between the players.
3. TOO EARLY / NIPPED labels sat over the Child's body. They're now above the head, like every other rating.

The "LEAP 2/2" counter that overlapped the CHOMP banner was moved beside the team lock. A sim jump planned just before a replay landed in the new session; replay now clears it.

**Performance, clean scripted run** (no snapshots, no recording):
- after the first 5 s window (the 67 ms jungle art generation, now 76 textures), **all 32 windows ran at 60 fps with the longest frame 16.7 ms**;
- memory 55–76 MB;
- host CPU 34% average (40% max), RSS 225 MB (Revision 8: 35% / 38%, 215 MB).
- With the snapshot harness and screen recording on, the simulator stalls while PNGs encode (game time ran at ~0.8× real time). Outcomes were unaffected because judging and simulated jumps run on the game clock.

**Stunt Run is unchanged:** its 11-step script produced **43 outcome lines identical to Revision 6** through "script finished", at 60 fps after the first window. The shared code touched was stand-in positioning, the input loop, replay, and cue rotation.

**Evidence** (`Evidence/revision9-piranha/`, from the final build):
- four storyboards:
  - a single leap from warning to TEAM JUMP;
  - too early after the gator;
  - the ×2 burst with no jump, TOO LATE, then TEAM;
  - pause in the warning and replay mid-leap;
- two clips: single leap, ×2 burst. Re-encoded from the portrait simulator recording, so the game sits in a letterboxed band;
- 39 event screenshots;
- the 16-step game log;
- clean-run metrics and host CPU/RSS;
- the Stunt Run regression log.

### Not verified (needs the physical iPad and real families)

- **Real jump detection:** the 0.14 torso-length takeoff threshold, the feet-up check, and whether a child's small hop, or a parent's cautious one, reliably clears it at 2.5–3 m. Also whether Vision keeps ankles and hips during the jump (motion blur, cropping at the top of the frame when they rise).
- **The crouch before a jump may register as a squat.** It counts a rep on the player card and could contribute to a bird window if a duck and a jump ever overlapped. The director never overlaps them, but rep counts may be inflated.
- **The judging window (−0.35 / +0.20 s)** against real takeoffs plus ~70 ms latency; whether 1.4 s of cue lead and the 0.46 s lane gap are enough for children.
- **Real cutouts:** whether the fish visibly passes *under* a real person's feet at play distance, given the cutout's scale and how high people actually jump.
- **Safety and comfort:** jumping on a hard floor near the iPad, landing impact, repeated jumps for small children, and whether anyone moves toward the screen. The raft roll during combos needs checking too.
- **Sound balance** on iPad speakers; whether the nip is playful rather than scary.

---

## Revision 10: two more JUMP hazards, River Log Sweep and Crocodile Tail Sweep (21 Oct 2026)

**Starting point:** Piranha Leap (Revision 9) already existed. It provides the JUMP movement, `JumpDetector`, `SimulatedJump`, per-lane window judging and a ram → piranhas combo. Nothing was duplicated: both new sweeps plug into the same judging, input, lock, cues, script harness and session flow. Validated in the **iPad Pro 13" (M5) simulator, iOS 26.2, simulated movement only**.

| Encounter | Movement | How the body reads it |
|---|---|---|
| Bird Flock | DUCK | something at head height |
| Crocodile Ram | BALANCE | the shared raft is dragged down on one side |
| Piranha Leap | JUMP | a fish arcs across the deck from one side |
| **River Log Sweep** | **JUMP** | a log rolls down the deck *at* you, low, both lanes at once (a hurdle) |
| **Crocodile Tail Sweep** | **JUMP** | a tail swings round from the bow corner, low across both lanes (a scythe) |

### River Log Sweep: the physical logic

A turbulent stretch has a standing wave at the bow. The wave **lifts the bow**: the deck pitches about the players' feet, far edge up, near edge down, so their feet stay put. It **heaves the drifting log over the front edge**, and the log **rolls downhill** through both lanes, rumbling over the rope lashings, and off the near edge. You see why to jump (it's rolling at your feet) and why it rolls (the deck is tilted). The log is 0.28 tall and 2.4 long (low on the shins, the raft's full width), with a contact shadow on the deck.

| Phase | Time | What players see and hear |
|---|---|---|
| Warning | 0–2.0 s | **DRIFTWOOD AHEAD!** with a jump badge at both screen edges (log + tucked jumper). Whitewater churns ahead and a foam ridge marks the standing wave; leaves swirl into a line. A low rapids roar and a distant wooden knock. |
| Reveal | 2.0 s | The log surfaces far ahead (a ring, a small splash) and is carried in at the river's pace, half-submerged (cut at the waterline), tumbling slowly, foam hugging it. A two-lane dash guide glows on the deck. |
| **JUMP!** | 1.4 s before it reaches the feet | Banner, 0/2 lock, up-chevrons, chasing dashes toward you, then three rising ticks. |
| Lift | 5.2 s | The wave heaves it over the bow on an arc: two splash crowns, a ring, a creak. The bow rises. |
| Roll | 5.65 s | A heavy thunk, then the raft jolts. It rolls downhill, accelerating, with roll frames tied to distance. Small hops over the lashings, each with a knock. Behind the players until it reaches their feet, then in front (it passes under them). |
| Resolve | per lane, ~0.4 s into the roll | Feet up in the window → **CLEARED!** as it passes under. On the deck → **BUMPED!** / **TOO EARLY!** / **TOO LATE!**: a stagger and a bonk, the raft jostles, no power lost. Shared: **TEAM JUMP!** / **NICE!** / **BUMP!** |
| Exit | ~0.7 s into the roll | Off the near edge. The edge is below the frame, so the splash shows as two crowns rising from the bottom and a fan of droplets. The bow drops, overshoots and settles (damped bounce). The river carries on. |

### Crocodile Tail Sweep: distinct from the Ram

The ram is a side-on lunge that bites the raft edge. Its warning is the coral **GATOR — side!** with a growl, and a lowered, angry brow.

The tail sweep is a **head-on croc** off the bow corner. It has a **yellow "TAIL SWEEP — side!"** warning with its own badge (a scuted tail, a sweep arrow and a jumper), a sly hiss instead of a growl, and heavy-lidded eyes watching the players. The croc is not angry.

| Phase | What happens |
|---|---|
| Warning (1.6 s) | Bubbles and a swirl at the bow corner, the badge on the attack side. |
| Reveal + settle (1.0 s) | Eyes and snout surface, facing the players, eyes tracking them. |
| **Anticipation: coil** (1.3 s) | The tail rises out of the water **behind its head** into a tall curl, then pulls back the other way just before the release (the counter-move). Water drips off it. JUMP! comes here. |
| **Sweep** (0.8 s) | The whip accelerates out of the coil (eased ramp, then full speed). The tail swings round over the water ahead of the raft, then **across the deck toward the players, low through the feet, like a gate swinging shut**. The tip trails the hips by 0.16 s (follow-through). The spray where it crosses the edge and a deep swoosh mark the strike. Contact shadows sit on the deck under it. |
| Resolve | **CLEARED!** as it passes under; **SWEPT!** with a cartoon slap if not. |
| Reaction | The tail overshoots, slaps the water past the edge (a crown and a ring) and swings back, with damped settling. After a TEAM jump the croc is **dizzy**: pupils swirl out of step, the head wobbles. If it caught someone it looks **pleased with itself**: heavy lids, eyes on them. Then it sinks away. |

The tail is an articulated chain of 16 tapered, overlapping segments plus a tip. Each point follows the hips' angle, delayed by its distance along the tail. It is projected in perspective and drawn in front of the players only where it is nearer the camera than they are.

### Rules (pure, unit-tested, `JumpSweepLogic.swift`)

- **One shared judge for all three jump hazards** (`JumpSweepJudge`; `PiranhaLeap` now delegates to it, unchanged behaviour). A player clears if airborne at any moment in **[crossing − 0.35 s, crossing + 0.20 s]**. Each hazard computes its crossings from its own path:
  - **log:** constant-acceleration roll, the axis reaching each lane; the root end leads by 0.05 s;
  - **tail:** the swing angle reaching each lane's direction from the hips, plus the follow-through lag at that radius; both lanes are reached within 0.05 s.

  Each clear banks +1 once; all clear adds +1 bonus. Misses cost nothing. Labels: TOO EARLY / TOO LATE / no jump.
- **Four separate concepts:**
  1. warning time (the encounter clock);
  2. action eligibility (the window);
  3. collision (the crossing);
  4. **the completed rep.**

  For the rep, the detector gained a `.settled` event: landed **and** held near standing for 0.2 s. Rep counters now increment only on `.settled`, never on an animation. Tracking lost on landing gives no rep; a bounce into a second hop counts one cycle. This applies to the piranhas too.
- **Pacing:**
  - The log and tail beats **wait for a steady raft** before their warning starts.
  - In the **ram → tail combo** the tail starts only **after the ram's result has landed** (+1 s) and the raft is steady. Its JUMP cue comes after the ram's recovery window; a test covers both sides.
  - The lap never puts two jump beats back to back (tested), and sides mirror on odd laps.
  - Difficulty comes from **pattern variety**: three jump shapes (side arc, frontal roll, sweeping gate), mixed with duck and balance beats. Reaction windows are not shortened.
- **Endless lap (15 beats):** birds → piranhas → ram → **log** → calm + landmark → ram→piranhas → birds → **tail** → ram→birds → piranhas ×2 → calm → **ram→tail** → birds → **log** → calm.
- **Scripts:** the coop script now pins the Revision 9 lap, so its 16 steps stay comparable. A new **`-scenario sweeps`** script (also the **Jump script** button, key **G**) plays a fixed 13-beat playlist. Timings are launch arguments: `-logWarning`, `-logDrift`, `-logCueLead`, `-tailWarning`, `-tailCoil`, `-tailSweep`, `-tailCueLead`, `-jumpBefore`, `-jumpAfter`.

### Verification

**Logic tests: 45/45 pass.**
- Six new tests (40–45):
  - rep only after neutral; tracking lost on landing gives no rep; a bounce counts once;
  - log: warning before the cue, in view ≥ 1.5 s before JUMP!, shin height on the deck at each crossing, the axis at the feet, states in order, no pops, the bow up while rolling and settled after;
  - log judging: on time → TEAM; early and late labels; nobody → no power; solo credit kept;
  - tail: valid timing, cue during the coil, reaches both lanes low, states in order, no jump at the release, the whip accelerates, overshoot and settle, the tip trails, the tail up and wound before the sweep;
  - tail reactions (dizzy vs pleased), tail judging, cancel keeps banked credit;
  - director: all three jump hazards in the lap, no back-to-back jumps, mirroring, combo sequencing, playlist through a replay, the Revision 9 lap still available.
- Tests 32 and 33 were updated for the new `.settled` event.

**Jump script** (`-scenario sweeps`, final build): all 13 steps gave the intended outcome.

| Requested case | Step | Result |
|---|---|---|
| Log: warning, reveal, approach, success, exit · both succeed | 1 | warning 2.0 s, reveal, drift, lift, roll; both cleared; **TEAM** (+1) |
| Tail: anticipation, warning, sweep, success, recovery | 3 | both cleared (0.03 s apart); **TEAM**; dizzy, swims off |
| No regression: birds | 4 | TEAM DUCK |
| Log: early jump, late jump, both miss | 5 | Parent **TOO EARLY**, Child bumped then **TOO LATE**; no power, no penalty |
| Tail: one succeeds, miss reaction | 6 | Child cleared; Parent **SWEPT**; partial "NICE!"; croc pleased |
| Ram and tail distinct · signature combo | 7 | ram: both leaned → **TEAM STEADY**; 1.0 s later the TAIL warning; both cleared → **TEAM** |
| Pause during warning · resume | 8 | log withdrawn, no result, clean resume |
| Tracking loss during encounter | 9 | Child lost during the coil → tail withdrawn → READY → resume |
| No regression: piranhas | 10 | TEAM JUMP |
| Log: miss | 11 | both bumped (no jump) |
| Replay · no stale state | 12 → 13 | tail TEAM, replay → session 3: fresh ids, counters 0, log TEAM |

After the script ends, the endless lap continues and autoplay bots handle the new beats.

**Visual QA** (recorded, consecutive frames inspected). Defects found and fixed:
1. **The log vanished once it was on the deck:** the waterline mask covered the wrong range.
2. **At the bow the log was layered by distance:** fixed with a players'-plane rule near the raft.
3. **The exit splash was below the frame:** now shown as spray thrown up from the bottom edge.
4. **A 0.38-tall log made a good jump look like a shin hit:** now 0.28 tall and 2.4 long, which a hop visibly clears.
5. **Badges unreadable at game scale:** an inverted-V "figure" and a blob tail. Redrawn with a tucked jumper, a scuted tail and a sweep arrow.
6. **The side-on tail croc was mostly off the right edge,** its tail read as a pole, and its coil was edge-on to the camera. Restaged head-on at the bow corner, with the tail coiling up behind the head.
7. **Tail segments kinked in the coil:** 16 overlapping, tapered segments.
8. **The croc head sat behind the Child's legs:** moved out (x 1.75) and enlarged.
9. **Combo:** the TAIL warning was overwritten by the ram's TEAM STEADY banner. The tail now starts 1 s after the ram resolves.

**Reduced motion:** deck pitch at 40%, no badge bob or head wobble, same encounters; both stay readable.

**Readability without text:**
- **Log:** a log rolling at your feet down a tilted deck.
- **Tail:** a raised, coiled tail, then a low sweep across the feet.

Both read as "jump" in the frame sheets. With real children this is still unverified.

**Performance, clean jump-script run** (no recording, overlay or snapshots):
- after the first 5 s window, **all 28 windows at 60 fps, longest frame 16.7 ms**;
- memory 61–87 MB (Revision 9: 55–76);
- host CPU 33% average (36% max), RSS 214 MB.
- **First window:** the one-time art generation, now 93 textures in 81 ms, causes one 86 ms frame during the opening countdown.
- **Node and draw counts** (overlay run, 60 fps):

  | Moment | Nodes | Draws |
  |---|---|---|
  | Baseline | 222 | ~84 |
  | Log | 245–254 | 91–98 |
  | Tail | 280–297 | 91–105 |

- **New textures:** 10 log roll frames (1120×196 px) plus 9 parts and badges, about 10 MB uncompressed in total.

**Regressions:**
- **Coop script (Revision 9, 16 steps):** all **71 hazard and step outcome lines identical**. Steady-streak and TURBO counts are equal (10, 3). Only one streak/TURBO reward moved 0.3 s relative to a step start: that reward runs on real frame time, and Revision 9's reference was recorded under the snapshot harness at ~0.8× speed.
- **Stunt Run:** its scripted outcome lines **match Revision 6 through the end of the script** (45 lines). All 25 windows after the first ran at 60 fps with a 16.7 ms longest frame.

**Evidence:** `Evidence/revision10-jump-sweeps/`.

### Skills used

- **`create-game-assets`:** parametric families and contact-sheet QA at game scale. It caught the unreadable badges and the stick-like tail, and drove the redraws.
- **`motion-design`:**
  - counter-moves before every action: the tail pulls back before the release, the wave lifts the log before the roll;
  - eased acceleration: the roll accelerates downhill and the whip ramps up;
  - follow-through: the tail tip lags the hips;
  - damped overshoot: the tail swings past and settles, the bow drops and bounces back;
  - arcs: the lift and the sweep.
- **`spritekit`:**
  - crop nodes for the waterline;
  - texture-frame roll tied to distance;
  - an articulated chain projected per joint;
  - depth by the players' plane;
  - pooled crowns and droplets;
  - deck pitch through the existing warp quad.
- **`game-feel`:**
  - front-loaded takeoff feedback (reused);
  - credit when the feet leave, praise as the hazard passes under;
  - nonviolent hits;
  - eligibility, collision and rep kept separate;
  - the rep only on a complete cycle.
- **`audio-design`:** five new synthesised sounds with variants on the existing SFX bus: rapids `rumble`, wooden `knock`, log `roll`, tail `swish`, cartoon `slap`. They are layered per beat with the existing splash, creak, tick, team and bonk.
- **Not loaded this revision:**
  - **`swiftui-expert-skill`:** the only SwiftUI change is one button.
  - **`vision-framework`:** the Vision pipeline is unchanged; only the detector's event sequence gained `.settled`.

### Art that would benefit from a designer pass

- **Log:** the root ball is a 2D fan that flips to suggest rotation, not true 3D roots. The snapped end and the bark are slightly stretched (canvas 7.4:1 drawn at 8.6:1).
- **Head-on croc:** it has no visible jaw or grin, so its reactions rely on the eyes. A head-on expression set (grin, dizzy, smug) would make the reactions much stronger.
- **Tail:** segments are flat strips with repeating scutes. An authored tapered strip or a warp-mesh tail would be smoother. A dedicated "slap" pose would help the overshoot.
- **Splashes:** the exit spray reuses the generic crown and droplets; a bespoke "log hits water" sheet would sell the weight.
- **Badges:** consistent with the piranha badge but pictographic placeholders.
- **Sound:** synthesised placeholders. Mixing and loudness need iPad speakers.

### Not verified (needs the physical iPad and real families)

- Whether children read the coil and the rolling log as "jump" without the banner. The frames suggest yes; people haven't confirmed it.
- Live cutouts: whether a real person's hop visibly clears the 0.28-unit log or the tail at 2.5–3 m, given cutout scale and real jump heights.
- The judging window (−0.35 / +0.20 s) and the 1.4 s cue lead for children, plus camera latency.
- Jump frequency for parents (physical intensity, the goal) versus fatigue and safety for children: hard floors, landing impact, moving toward the screen.
- Whether the tilting deck (bow lift) is comfortable to watch, and whether the dizzy or pleased croc reads as playful.

---

## Revision 11: a layered, living jungle; creature acting (22 Oct 2026)

**Goal:** make Jungle Drift feel like a premium stylized arcade world rather than a flat prototype, without changing gameplay:
- depth through layering;
- a river that lives;
- expressive croc and bird acting;
- less repetition on the endless journey.

The SpriteKit pipeline is unchanged. Skills applied: `create-game-assets` (style contract extended in `JUNGLE_ART_DIRECTION.md`, contact-sheet QA), `motion-design`, `spritekit`, `game-feel`.

### Environment: far → near

- **Sky:** low humid clouds drift with slow parallax.
- **Far ridges (new):** distant tepui mesas, then forested hills. Single-tone silhouettes tinted by the biome's haze (atmospheric perspective: the farther, the paler and bluer), with their own parallax rates against the river's bends.
- **Forest wall (new):** a back row of 32 tall, darker trees 6–10 units inland, so the river runs through a jungle corridor instead of past a strip of lawn.
- **Bank (reworked shader):**
  - undergrowth clumps with lit fern tops;
  - dappled light that flickers as the canopy moves;
  - a wet mud lip;
  - darkening toward the forest wall;
  - the old stripes are gone.
- **New bank life:** flowering heliconia (the warm colour accent) and egrets fishing in the shallows. Each egret watches, then strikes, with its own rhythm.
- **Wind (new):** gusts travel through the scene as a band. Trees, palms, reeds, leaning trees, the canopy frame and the vines sway harder and lean as a gust passes them, so the wind is seen *moving*.
- **Foreground (new):** trees lean out over the water from the banks (trunk, sagging bough, leaf clumps, hanging vines). Their boughs pass close overhead at the screen edges, giving scale and speed.
- **Morpho butterflies (new):** flutter in loose figure-eights over the river's edges, with flaps and short open-wing glides.

### River: more life on the water

- **Dragonflies ride along with the raft:** hover, dart (fast ease-out), and sometimes dip to touch the water (a ripple).
- **Fish** break the surface mid-river now and then: ring, arc, ring.
- **Debris:** leaves and lily blossoms drift on the current, spin and bob. The **raft's wake pushes them aside** when they come alongside.
- **Midstream rocks** carry a foam wake streaming downstream.

These sit on top of Revision 8's layered swell, raft lapping, wake, croc wake and rings.

### Landmarks and variation

Two new landmarks:
- **Stone gateway:** a ruined arch spanning the river. The raft passes underneath and a brief shade falls across the deck and riders.
- **Hidden falls:** a waterfall cliff on the bank, with water moving down the sheet (3 frames) and spray off the plunge pool.

There are now five landmarks in rotation: temple → gateway → kapok → falls → fallen giant. **Incidental landmarks** also appear every ~150 units between calm stretches, so the horizon keeps changing even in long hazard runs.

### Creature acting

- **Crocodile ram:**
  - **Snarl (anticipation):** it now gets a head-on mouth. After the lids narrow, it **lifts its head and bares its teeth**, then sinks before exploding up. The foam moves behind the mouth while it snarls so the teeth read.
  - **Recovery depends on the result:** shaken off (eyes screwed shut, a dazed head-shake) when the team pushed back; pleased (grin, lazy lids, no hurry) when it got its splash. It reads the result as it lets go, so its mood never flips mid-retreat.
- **Tail-sweep croc:** the same mouth gives it a sly grin while coiling and a pleased grin after catching someone. The head lifts so the mouth clears the water.
- **Birds:**
  - wingbeats cascade from the leader back through the flock (rates within ±6%);
  - after a TEAM duck the flock **splits to both sides over the players**, banking into the turn;
  - a soft shadow sweeps across the deck under each bird as it flies over the raft;
  - a slight stretch at the closest moment of the flyby.

### Inspected, found, fixed (recorded frames)

| Seen | Fix |
|---|---|
| The overhanging boughs read as long straight brown bars hanging in mid-air ("power lines") | Redesigned as **trees leaning out from the bank**: trunk base on the bank, a sagging bough, uneven leaf clumps, vines |
| The croc's snarl was invisible: the mouth sat at the waterline under the foam collar | The head lifts higher while it snarls (rise 1.45); the foam is drawn behind the head during the grin |
| The ram's result (TEAM STEADY) is decided ~0.5 s after the retreat starts, so the acting would switch mood mid-retreat | The croc reads the result when it lets go (did anyone lean?); a later splash still makes it pleased |

### Verification (iPad Pro 13" M5 simulator, simulated players)

- **Logic tests: 47/47 pass.**
  - **46:** croc snarl (teeth bared, head up) before it sinks, smooth; beaten vs won recoveries.
  - **47:** wingbeat cascade order; the flock splits after a TEAM duck.
- **Coop script (Revision 9's 16 steps):** all **71 hazard and step outcome lines identical** (rewards that depend on frame pacing excluded, as in Revision 10). The calm stretch's landmark now differs because the rotation has five landmarks and incidental ones; that's set dressing, not an outcome.
- **Stunt Run:** outcome lines **identical to Revision 6 through the end of the script** (45 lines); all 25 windows after the first at 59.9–60.1 fps, longest frame 16.7 ms.
- **Performance, clean coop run** (no recording or snapshots):
  - after the first window, **all 34 windows at 59.9–60 fps, longest frame 16.7 ms**;
  - memory 64–94 MB (Revision 10: 61–87);
  - host CPU 35% average (38% max), RSS 247 MB (Revision 10: 33% / 214 MB).
  - The first window carries the one-time art generation, now **115 textures in 90 ms** (one 54 ms frame during the countdown).
- **Evidence:** `Evidence/revision11-living-jungle/`.

### Not verified / next

- Everything is judged in the simulator at desktop GPU speed. On the iPad, the extra ~70 sprites, the bank shader and Vision segmentation together need measuring.
- **Visual hierarchy with live cutouts:** the scene is busier and darker around the river. The stand-ins still pop (saturated coral and teal); real camera cutouts may not.
- **Designer pass:**
  - the egret and dragonfly are simple;
  - the waterfall has 3 frames;
  - the forest wall reuses the bank tree silhouettes;
  - the head-on croc has only two mouth shapes.
