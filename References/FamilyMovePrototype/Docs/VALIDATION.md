# Validation

## Milestone builds

The iPad device target was built with signing disabled after each milestone. Build logs are in `.build/milestones/`.

| Milestone | Result |
| --- | --- |
| M1 — project, SwiftData models/repositories, app routing and theme | Build passed |
| M2 — onboarding and profiles | Build passed |
| M3 — home, detail and ordered player selection | Build passed |
| M4 — full-body joints, mapping, assignment and debug markers | Build passed; original 15 tracking checks passed |
| M5 — stable readiness, calibration and countdown | Build passed |
| M6 — Whack the Mole | Build passed |
| M7 — Birds & Alligators | Build passed |
| M8 — results, replay, participant records and idempotent persistence | Build passed |
| M9 — progress, calendar statistics and editing | Build passed |
| M10 — lifecycle/settings, safe layout and test target | Build passed |

## Automated checks

The current core suite has **52 passing tests**, including:

- Exact X mirroring, Y inversion, both aspect-fill crop axes and confidence threshold.
- Initial assignment, observation-order changes, spatial continuity, global assignment cost and loss/reacquisition.
- Missing wrists and stale stream expiration.
- Collision radius boundary, wrong owner, nil/low-confidence wrist and already-hit targets.
- Repetition limits, safe player halves, and side-reach direction.
- Single-hit scoring, timeout/miss behavior and delayed respawn.
- Standing immunity, return-to-standing requirements, jump landing, cooldown and tracking-loss cancellation.
- Timestamp clock pause exclusion and zero clamp.
- Both games completing simulated 60-second rounds, replay IDs, full-body readiness, and pause/recalibration/resume.
- Actual SwiftData initialization, relationship inverses, profile saving/editing, duplicate-save prevention and unchanged historical energy.
- Per-member/week counts, household minutes, calories, high scores, goal capping, empty histories, duplicate-day streaks, yesterday grace, and DST.

All **three Simulator UI tests pass** on iPad Pro 11-inch (M5), iOS 27.0, including a second complete run after the named-color alpha correction:

1. Fresh-store onboarding → two profiles → Home → relaunch preserves profiles.
2. Game card → detail → selection; Play requires exactly two profiles.
3. Progress → weight edit → relaunch preserves the new weight.

Final results are in `.build/FamilyMoveFinalUITests.xcresult`, screenshots in `.build/FinalScreenshots/`, and the log in `.build/final-ui-tests.log`. UI tests use a separate local store. Simulator app-window screenshots carry inconsistent landscape cropping/orientation metadata, so full-display screenshots are used for subsequent visual checks. The extra onboarding/relaunch visual check passes; its full-display Home and Onboarding captures are saved in `Docs/Screenshots/`.

An additional **iPad mini (A17 Pro), iOS 27.0** run passes the weight-edit/relaunch test, asserts landscape dimensions and a visible third metric card, and confirms the smaller progress layout. Its capture is `Docs/Screenshots/Progress.png`; results are in `.build/MiniVisualCheck.xcresult`.

The final app build (`.build/milestones/final-verified.log`) passes. Remaining compiler notices are the documented available-but-deprecated camera orientation APIs.

## Physical-iPad checklist

No physical hardware testing is claimed.

- [ ] Sign, install, and launch on a physical iPad (minimum iPadOS 17).
- [ ] Test camera permission denial, Settings return and interrupted capture recovery.
- [ ] Check preview mirroring and every joint overlay at center and all visible edges in both landscape orientations.
- [ ] Check adult/child side assignment, short losses, and realistic movement without crossing.
- [ ] Verify full-body guidance, comfortable standing calibration, and calibration repeatability.
- [ ] Measure camera/Vision rate, action-to-feedback latency, intentional-hit rate and false hits.
- [ ] Tune reaches for comfortable overhead/side/low targets across body sizes.
- [ ] Tune squat/jump displacement, knee/ankle evidence and two-second movement window.
- [ ] Complete real rounds of both games; verify independent players, score, reaction stats, replay and persistence.
- [ ] Interrupt and resume an active round; ensure timer excludes pause/setup and score remains correct.
- [ ] Review minimum iPad landscape layout, large accessibility text, and final artwork/audio needs.

## Refinement validation

- Debug iPad build: `.build/milestones/perfecting-complete.log` passed.
- Release iPad build: `.build/milestones/perfecting-release.log` passed; synthetic poses are disabled in Release.
- Latest 45-test unit suite: `.build/perfecting-core-tests.log`. It adds stable/noisy calibration cases, geometry invalidation, explicit manual-resume requirements, rotation while manually paused, personal movement/achievement counts, decimal parsing, and session-cascade cleanup.
- Primary accent, P1 blue, and P2 coral white-text contrast ratios: 5.49:1, 4.82:1, and 4.64:1.
- The three SVG assets parse successfully. All three audio assets are valid mono 16-bit WAVs under one second. Actual speaker behavior still needs a device check.
- Extended UI run: `.build/PerfectingFinalUITests.xcresult`. The first extended run caught a test-store batch-delete relationship error after saving a round. Test cleanup now deletes linked models individually and saves participant cleanup before resetting remaining test records.

The five UI flows are verified across the final regression run and a targeted replay rerun:

| Flow | Evidence |
| --- | --- |
| Onboarding + persistence | Passed in `PerfectingFinalUITests.xcresult` |
| Detail + two-player selection | Passed in `PerfectingFinalUITests.xcresult` |
| Weight editing + relaunch | Passed in `PerfectingFinalUITests.xcresult` |
| Synthetic Birds game + protected exit + results | Passed in `PerfectingFinalUITests.xcresult` |
| Synthetic Mole game + manual pause + replay + single save | Passed in `PerfectingReplayVerified.xcresult` |

The replay check originally raced the one-second positioning title. Its captured hierarchy showed the new round correctly in countdown; the test now checks the persistent replay controls and absence of results, then verifies only one completed session was stored. The targeted rerun passes.

Final Release build: `.build/milestones/perfecting-verified-release.log` passed. Synthetic game screenshots show fixture data and a flat background, not camera output.

The final iPad mini run (`PerfectingMiniFinal.xcresult`) also passes the complete Mole/pause/replay/single-save flow, including an assertion that the displayed player status agrees with the tracked input. HUD and debug markers now consume the coordinator’s same read-only published player state as gameplay. Updated screenshots are in `Docs/Screenshots/`; result screenshots explicitly contain synthetic test data. Final Release build `.build/milestones/perfecting-final-build.log` passes.

## Interactive Simulator controls

The manual-control suite adds seven unit tests (52 total), with no automatic score while idle, target-owner scoring, no carryover to a replacement target, ordinary movement-detector validation, wrong-action rejection, and action cancellation/reset. Log: `.build/manual-simulator-core-tests.log`.

The four targeted UI flows in `.build/ManualSimulatorVerified.xcresult` pass: manual Mole clicks through results/save, manual Birds buttons through score/pause/exit, and both existing automated pose flows. Manual Mole verifies zero score while idle and a final score of exactly 20 after two clicks. Game-flow UI tests pre-create profiles only in the isolated test store; onboarding remains covered by its own UI flow.

At this stage, the Simulator scheme stopped supplying autoplay/test arguments and Simulator launches used manual input. The subsequent camera arcade correction below supersedes that default: manual input now requires the dedicated preview scheme's explicit flag.

Project synchronization now parses the property list instead of matching single-line text. This preserves settings after Xcode reformats the project file.

Manual Birds controls also pass on iPad mini with the normal 60-second game duration (the round is explicitly ended by the test). The separate extra onboarding probe was stopped after repeated Simulator keyboard-animation waits; no profile-form changes are included in this feature. Its prior implementation is retained. The final Release build log is `.build/milestones/manual-simulator-ready.log` (passed).

## Camera arcade correction

The normal FamilyMove scheme now always chooses camera input. The FamilyMove Simulator scheme supplies `--simulator-controls`, accepted only by Debug builds on Simulator. Simulated/manual and automated modes visibly state that no camera is in use. The camera's unavailable screen explains the physical-iPad requirement instead of silently replacing physical movement with touch.

Seven camera-gameplay tests bring the core suite to **59 passing tests** (`.build/camera-arcade-core-tests.log`). Coverage includes normalized observations through mirrored aspect-fill mapping/player assignment to the rendered wrist and collision, hand disappearance on loss/low confidence/stale frames, independent hands, bounded trails, jump discontinuities, non-finite coordinates, fixed hole/spawn alignment, and separate adult/child reach scale and bounds.

The **four targeted UI tests pass** in `.build/CameraArcadeUITests.xcresult`: camera mode's Simulator guidance without manual controls, manual Mole scoring/results, synthetic Birds pause/exit/results, and synthetic Mole pause/replay/save. These are interface and deterministic game-loop checks, not real-camera evidence. The affected Mole flow passes again after the visual trail discontinuity fix (`.build/CameraArcadeFinalMole.xcresult`); its screenshot was inspected for arena spacing, wrist effects, and the absence of long trail artifacts.

Unsigned generic iOS Debug and Release builds succeed. Final Release log: `.build/milestones/camera-arcade-final.log`. Existing camera orientation deprecation notices remain; they are unrelated to these changes. The test diagnostic collector still reports its global `xcrun simctl` lookup issue after the successful run; the `.xcresult` itself reports **TEST SUCCEEDED**.

The Facebook video was unavailable to the browsing tool. The attached screenshot guided the camera background, glowing wrist controls, mole holes, and compact HUD. No physical two-person camera test has been performed; mirror alignment, latency, detection reliability, and comfortable reach remain on the physical-iPad checklist above. See `CAMERA-GAMEPLAY.md` for the run procedure.

## Native MacBook camera support

The existing app target now supports Mac Catalyst on macOS 14+, with a dedicated local Mac bundle identifier and sandbox/camera entitlements. Xcode exposes **My Mac (Mac Catalyst)**. Local Debug and Release builds pass (`.build/milestones/mac-Debug.log`, `.build/milestones/mac-Release.log`). Release is universal arm64/x86_64, and its local signature passes `codesign --verify --deep --strict`.

The MacBook app was launched through its app bundle. Its onboarding camera check requested macOS permission, opened **MacBook Pro Camera**, and delivered real frames at approximately 30 fps in AVFoundation diagnostics. The live tracking UI reported one player detected, both wrist confidence values, approximately 10 detections/s, and 7 ms Vision processing during a brief check. No webcam image was saved. Closing Camera Setup returned to onboarding and stopped its capture controller. No sample profiles were created. The final standalone Release app was opened for the user.

The core suite remains **59 passing tests** (`.build/mac-support-core-tests.log`). The generic iOS build also passes (`.build/milestones/mac-support-ipad.log`). Both selected UI regressions pass in `.build/MacSupportRegressions.xcresult`: the updated Simulator camera guidance and synthetic Mole pause/replay/results flow. These UI tests do not validate real camera motion.

Two simultaneous real players, a full movement-controlled round, adult/child reach tuning, actual action-to-hit latency, USB cameras, Intel hardware, and camera denial/recovery still require manual checks. The observed single-player MacBook camera path is verified; it does not replace those checks. See `MACBOOK.md` for normal launch instructions. Simulator webcam bridging was omitted in accordance with the user's clarified priority of playing directly on the MacBook.
