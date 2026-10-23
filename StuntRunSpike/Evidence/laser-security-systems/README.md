# Laser Breakout — security systems pass (local only, not committed)

All gameplay here is **simulated input in the iPad Simulator** (scripted or autoplay). It says nothing about how well
real-camera tracking works.

## Clips (960×540, one per mechanic, from the normal-difficulty scripted run)
| Clip | What it shows |
|---|---|
| `clip-01` | Single duck: TEAM DODGE. |
| `clip-02` | Child's tracking lost → the beam is withdrawn → READY → retried as a single jump. |
| `clip-03` | Scanner sweep with nobody moving: missed, cameras flash red, alert rises. |
| `clip-04` | Rotating turret wave: the Parent's lane is hit first, the Child's 0.9 s later. |
| `clip-05` | Double pulse: the Parent's held squat gets no credit on pulse 2. |
| `clip-06` | Pause in the warning → withdrawn → retried → perfect split. |
| `clip-07` | DUCK ▸ JUMP ▸ DUCK combo: the Child's squat on step 3 is too early → combo 2/3. |
| `clip-08` | Iris gate crossfire: aperture opens, pods orbit and lock, reconfigured second iris, CROSSFIRE CLEARED. |
| `clip-09` | Final gauntlet (turret ▸ floor ▸ split) → lockdown levers → escape. |
| `clip-10` | Replay: a new run with fresh ids. |

## Frames
- `00a`/`00b`: before (heist build, previous pass).
- `01–10`: after.
- `11–12`: debug overlay. Red means a beam is inside its judging window; the label shows the turret angle and the time to
  that lane's crossing. Frame 12 shows the turret beam at the Parent's lane centre 0.01 s before the crossing, passing
  over the ducked head.

## Results
- **Scripted run:** 18/18 steps as intended (`scripted-run-outcomes.txt`).
- **Hard autoplay** (`hard-autoplay-outcomes.txt`): a 4-step combo, a 3-step iris crossfire and a 4-step gauntlet.
  Spacing is 2.42 s, above the 2.4 s minimum for duck→jump.
- **Other modes:** Stunt Run, Jungle co-op and sweeps are identical to before. Moonbound differs only by the known
  14-vs-15 s rounding, plus extra lines because this capture ran longer.
- **Performance:** 60 fps, 67–70 MB, in a 175 s autoplay run.
