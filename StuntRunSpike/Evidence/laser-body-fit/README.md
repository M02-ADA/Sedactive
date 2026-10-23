# Laser Breakout — Body-Fit Security Gate (local only, not committed)

Run with `-gameMode laser -scenario bodyfit` (scripted trial) or `-laserTrial bodyfit` (the gate repeated, no script).
Add `-laserDebug YES` for the perspective overlay.

## What is evidence of what
- **Stand-ins** (`01–12`, clips): iPad Simulator, scripted simulated input. These prove the gate's choreography, depth
  ordering, judging and feedback. They are **not** evidence about real players.
- **Real bodies** (`real-camera-LOCAL-ONLY/`, never push): one real two-person camera frame played through the live-body path.
  It is a still, so it proves occlusion and depth with real cutouts, not real squats or jumps.

## Screenshots (taken from the recording, not the snapshot harness)
| File | Moment |
|---|---|
| 01 | Warning: the banner says who does what |
| 02 | Deploy: the shutter drops and the sill rises while the gate is far away |
| 03 | Approach: "FIT THROUGH!", lane chevrons, both openings readable |
| 04 | **Contact**: the gate slams to a stop just in front of the players; the Parent's ducked head is under the shutter edge and the Child is airborne over the sill |
| 05 | Bypass: both through, the panels spring open, the bodies light cyan |
| 06 | The open gate passes in front of them |
| 07 | Partial: the Parent stays standing, the shutter covers his head and bites red; the Child got through |
| 08 | Partial: the Child jumps too late, the sill bites his feet; the Parent got through |
| 09 | Both blocked |
| 10–12 | Debug overlay. Red: the duck edge and jump sill while being judged. Cyan: each body's crown and soles at the players' plane. Magenta: the interaction plane |

## Clips (960×540, the full 125 s scripted recording in four parts)
| Clip | What it shows |
|---|---|
| `clip-01` | Both through → BYPASS |
| `clip-02` | Parent blocked; Child too late; both blocked |
| `clip-03` | Pause and tracking loss withdraw the gate, which is then retried; a Child jump 0.3 s late still counts (child allowance) |
| `clip-04` | Escape → replay → a new run |

## Logs
- `trial-outcomes.txt`: every step, with each body's measured clearance at the crossing.
- `real-body-run-log.txt`: the same for the real-body frame.
- `perf-clean-recording.txt`: METRICS from the clean recording.
- `regressions.txt`: the other modes' results (Stunt Run, Jungle co-op and sweeps identical; Moonbound differs only by a known rounding).
