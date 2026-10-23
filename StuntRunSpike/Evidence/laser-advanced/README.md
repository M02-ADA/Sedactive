# Laser Breakout — advanced laser mechanics (local only, not committed)

All gameplay below is **simulated input in the iOS Simulator** (scripted or autoplay). It is not evidence of how well
tracking or detection work with real players.

## Files
- `00a/00b-BEFORE-*`: the previous build (one stretched glow sprite, one scaling turret sprite).
- `01–11`: after. Covers the emitter rig, split heights, the shared beam into a receiver, the sweep (swinging, then locked),
  the double pulse with two gates in flight, a held squat getting no credit, the combo preview, the crossfire, the
  team short-out, and the gauntlet.
- `12–14`: perspective debug overlay.
  - Blue: the beam is far away and cannot collide.
  - Red: the beam is inside the judging window.
  - Magenta: the players' interaction plane, plus the window's depth band on the floor.
  - Each label reads gate#, lane, z, height and time to crossing, plus SWEEP or LOCKED.
- `clip-*.mp4`: 960×540 excerpts of the scripted run (sweep + double pulse, combo + crossfire, gauntlet).
- `scripted-run-game-log.txt` / `scripted-run-outcomes.txt`: the full 17-step scripted run.
- `autoplay-perf-log.txt`: METRICS lines from a 175 s autoplay run.

Frame 11 comes from the screen recording, because the event snapshot fired between banner frames. The recording
predates one cosmetic change: the sequence score text now sits at 0.2 H, off the diamond.

## Scripted run (17 steps), all as intended
1. high → TEAM.
2. low → Child's tracking lost → withdrawn → retried.
3. low → TEAM.
4. high sweep → locks at the judged height 1.34 s before judging opens; Child too late → partial.
5–6. Double pulse: both duck; the Parent holds the squat and gets "STAND · DUCK AGAIN!" on pulse 2 (no credit).
7–8. Split: pause in the warning → withdrawn → retried → perfect split.
9–11. Combo DUCK → JUMP → DUCK: Child too early on step 3 → combo 2/3.
12–13. Crossfire (Parent DUCK → JUMP, Child JUMP → DUCK) → CROSSFIRE CLEARED, +2.
14–16. Gauntlet → SECURITY BROKEN, +3.

Then the lever override → escape → replay → new run (fresh ids). No crash.
