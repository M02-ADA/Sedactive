# Laser Breakout — real-body interaction (local only, not committed)

## What is evidence of what
- **Simulated stand-ins** (`01–07`, clips): the scripted run in the iPad Simulator. These prove the geometry, the judging
  and the compositing rules with bodies that move. They are **not** evidence about real players.
- **Real bodies** (`real-camera-LOCAL-ONLY/`, never push): one real two-person camera frame, segmented and pose-tracked by
  Vision on the Mac (`-recordedFrame`). It is a still: one person is crouched throughout and the other's head is outside
  the camera frame. It proves occlusion, scanner lock and lighting on real cutouts, but no real squat or jump was recorded.

## Clips
| Clip | What it shows |
|---|---|
| `clip-01` | High beams pass over the ducked heads; the short-out comes after the pass. |
| `clip-02` | The low beam passes under the jumping feet. |
| `clip-03` | Split grid: one player ducks, the other jumps. |
| `clip-04` | Checkpoint: cover rises, the scanners track; scan 1 Parent hidden, Child spotted → rescan → both hidden → breach. |

## Logs
- `crossing-clearances.txt`: at every beam crossing, the crown or sole height of the body as drawn against the beam height.
- `real-body-run-log.txt`: the same for the real-body frame.
- `instance-mask-check.txt`: `VNGeneratePersonInstanceMaskRequest` on the real frame: 2 separate masks, about 6 ms per frame
  on this Mac. The app itself still uses one mask for everyone.
- `autoplay-perf-log.txt`: performance with no snapshot harness running.
- `regressions-and-perf.txt`: the other modes' regression results.
