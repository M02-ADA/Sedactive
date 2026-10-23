# Laser Breakout — reference research and next mechanics (23 Oct 2026)

Design document only. Nothing here is implemented yet.

## 1. References: what is verified and what is my interpretation

I read text sources only: official pages, store pages, press and reviews. **I did not watch any gameplay footage.** For the
Laser Thief YouTube link, only the video title was readable; its description and the video itself were not accessible to
me. Every "Verified" line below comes from the sources listed at the end.

| Reference | Verified (from sources) | Interpretation for us (not verified) |
|---|---|---|
| **Laser Dance** (Quest 3, mixed reality) | Your room becomes the course: you walk between two buttons at opposite ends and dance, dodge and crawl past lasers. 24 levels, 118 patterns. Levels adapt to the room's size and layout; accessibility settings adapt to mobility. The Mimic Update (announced 6 May 2026, press kit dated 13 Aug 2026) adds 6 levels and **green lasers that "only move when you do."** An earlier update added Grid Overlay and Invisible Lasers modifiers. | The adaptation is to the room, not the body. The Mimic laser turns *your own motion* into the hazard's clock, so stillness becomes a skill. Exactly how the lasers track you is not public. |
| **Laser Thief** (Quest, mixed reality) | A prison break through 7 worlds and 150+ levels that adapt to the room. Each world adds a mechanic: a slingshot to destroy laser devices, a shrinking shield, and tracking lasers in the last world. **Bomb mode: a 120 s timer to grab loot, and every laser you touch costs time.** There is also a random free-play mode. | A heist objective with time pressure. A hit costs time instead of ending the run, which is a forgiving penalty. Tracking lasers are saved for the end of the game. |
| **OhShape** (VR) | Walls arrive in time with the music. You "make your body into the shape of the hole," or dodge or punch some walls. Choreographed levels; adjustable accuracy and Small Room mode were added, and a No Fail mode was planned for younger players. One review says that at speed it is hard to tell the next shape until it is close. | The obstacle *is* the required pose, so you read the pose from the obstacle's silhouette, not from text. Lenient tracking keeps it fun. Showing the next shape early matters. |
| **Pistol Whip** (VR) | On-rails: you never steer. You shoot on the beat and dodge slow bullets and duck walls with your head and body. Enemies move in time with the music. Cinematic "Scenes" are themed by film genre. | Like our cart, the rails free you to focus on your body. Choreographing threats to the music builds flow and anticipation. |
| **Laser Escape** (Quest, mixed reality) | From a safe zone you preview the room, then cross laser traps to a switch on the far wall. Laser types are colour-coded: red static, blue pulsing in time windows, yellow moving, purple fanning and sensing, orange warning. Moves: duck, lean, crouch, crawl, timed steps; your real furniture works as cover. A body setup adjusts laser height. | Colour = behaviour is a readable rule. Real objects as cover is close to our checkpoint cover panels. Body-relative laser height matches what we already do. |
| **Laser League** (arena) | Touching a node turns its laser walls your team's colour: safe for your team, deadly for opponents. Teammates revive a downed player by running over their marker. 3 points per round, best of 3. | Lasers *owned* by a team: one player's action changes what is safe for the partner. Rescue is something a partner does for you. |
| **SUPERHOT VR** | Time advances only as you physically move; standing still freezes the world. Reviewers instinctively dodge bullets with their real body. | Stillness as a deliberate tactic. The same idea as Laser Dance's Mimic lasers. |

## 2. What Laser Breakout already has

- **Gates:** high, low and split gates that approach the players.
- **Beams that move:** a scanner sweep, a rail-turret rotating sweep, and an iris gate.
- **Sequences:** double pulse, combo, crossfire and gauntlet.
- **Body checks:** beams are judged against the body *as drawn*, so a squat must put the crown under the beam and a jump must lift the soles over it.
- **Checkpoint and finale:** a checkpoint where players hide behind cover from tracking scanners, and a lockdown gate opened by cranking levers with squats.
- **Pressure:** a Security Alert that rises and falls, but never speeds the game up.

So two of the five candidates already exist in part (scanner, override). The gap is that **every encounter still asks the
same two questions: duck or jump, now or not yet.** The references point to three other questions:
- **What shape?** (OhShape)
- **Can you stay still?** (Mimic, SUPERHOT)
- **Who does what for whom?** (Laser League)

## 3. The five candidates

Ratings: ●●● strong · ●● medium · ● weak. Complexity: S / M / L.

| | Body-Fit Security Gate | Rotating Laser Scanner | Rhythm Laser Gauntlet | Dual-Agent Override | Mimic Laser |
|---|---|---|---|---|---|
| **Fantasy** | "Slip through the security aperture shaped exactly like you" ●●● | "Dodge the sweeping turret" ●● | "Move like a heist movie set to music" ●●● | "Spy teamwork: you hold the door, I run" ●●● | "Freeze — the sensors only see motion" ●●● |
| **Movement** | Pose held at the crossing: squat, arms up (tall), lean left or right, star (arms out) ●●● | Duck or jump as the beam passes (exists) ● | The duck/jump we already have, on the beat ●● | Asymmetric: one player holds a squat or arms-up; the other jumps or ducks the gap ●●● | Hold still (low intensity), then burst past ●● |
| **Co-op** | Parallel: each fits their own shape; a team fit gets a bonus ●● | Parallel ● | Parallel, shared rhythm ●● | **Interdependent**: one player's hold makes the other's path safe, then they swap ●●● | Shared: either player moving advances *both* lanes' grid ●●● |
| **Real-body cutouts** | Strongest: the aperture is drawn around the real silhouette; a fit lights the cutout's rim ●●● | Beam passes the body (exists) ●● | Same as now ●● | The holding body visibly braces the barrier ●● | The grid creeps visibly toward a moving real body and stops when it freezes ●●● |
| **Animation / feel** | Aperture irises open around the body; "fit" snap; miss = the gate slams shut on the shape ●●● | Exists ●● | Music-locked telegraphs, beats as countdown ●●● | Strain meter, braced shield, a release when roles swap ●● | Very strong contrast: silence and creeping grid, then a burst ●●● |
| **Feasibility (SpriteKit / Vision)** | New pose classes from joints we already read (wrists, shoulders, lean). Arms-up exists experimentally (`ReachPullDetector`). Aperture art is drawn sprites ●● | Done ●●● | Music stems are sample-locked at 112 BPM. Needs the game clock locked to the audio clock, and pause/resume handling ●● | Existing detectors (squat-hold time, jump); new pure judge ●●● | Motion energy from joint velocity, body-relative. **Risk: pose jitter**, needs hysteresis and a dead zone ●● |
| **Parent–child fairness** | Shapes defined relative to each body (torso units). Some shapes are harder for small kids; each lane chooses its own shape ●● | Exists, with a wider child window ●●● | 4–6 beats between moves (≥ 2.2 s) is slow for a beat game; must not pressure the child ●● | Give the child the dynamic role and the parent the hold (or swap) ●●● | Kids fidget: needs a looser child threshold; holds ≤ 3 s ●● |
| **Complexity** | **M–L** | S (done) | M | **M** | **M** |
| **Changes how the game feels?** | Yes: matching instead of reacting | No | Partly (it's a layer) | Yes: real interdependence | Yes: stillness as a skill |

## 4. Recommendation: prototype these three, in this order

1. **Mimic Laser ("Motion-Sensor Grid")** comes first. It is the cheapest big change, uses the real body directly, and gives
   the run its first *low-intensity* beat (recovery after combos, which matters for parent–child fitness pacing).
   - **Rule:** a green sensor grid advances toward the cart **only while either player moves** (body-relative motion energy above a dead zone).
   - **Win:** freeze until the grid's power cycle drops (a visible 3–4 s charge bar). Then the grid goes dark, and one quick duck or jump passes it.
   - **Prove first:** that real pose jitter doesn't count as motion. Needs real-camera recordings, not stills.
2. **Dual-Agent Override ("Hold & Run")** turns the existing override into interdependence.
   - **Rule:** a floor-beam fence closes in. The Parent holds a squat on a pressure plate (a strain bar shows the remaining hold, max 3 s). That keeps the Child's lane open, and the Child jumps the low beam. Then roles swap.
   - **Win:** both locks open the gate.
   - **Fairness:** the child never has to hold for the parent's benefit first.
3. **Body-Fit Security Gate** is the hero mechanic, built after the two above prove the pose pipeline.
   - **Rule:** each lane's gate panel has a silhouette aperture (TALL arms-up, LOW squat, LEAN left/right, STAR arms-out).
   - **Feel:** the aperture shows from the reveal, so players read the shape early (the OhShape lesson). At the crossing the aperture "irises" around the real cutout and its rim lights.
   - **Start small:** two shapes (LOW and TALL), then add LEAN using Jungle Drift's `LeanEstimator`.

**Not now:**
- **Rotating Laser Scanner** already exists (turret wave, checkpoint scanners).
- **Rhythm Gauntlet** is best added later as a *layer* on the existing sequences: lock telegraphs and crossings to the 112 BPM stems at 4–6 beats per move. It is not a separate mechanic.

## 5. Proposed encounter choreography (one getaway, about 3 minutes)

| Phase | Beat | Body demand | Purpose |
|---|---|---|---|
| A · Alarm | High beam → low beam → **Body-Fit LOW** gate | Duck, jump, squat-fit | Teach the moves, then introduce "shape" with a move they already know |
| A | **Mimic grid #1** (both freeze 3 s, then one duck) | Stillness | First rest beat; teaches "motion = detected" |
| B · Pursuit | Turret wave → double pulse | Duck ×3 | Rising action |
| B | **Body-Fit TALL / LOW split** (Parent arms-up, Child squat; then swapped) | Two different shapes | Each player reads their own aperture |
| B | **Mimic grid #2** with a scanner sweeping overhead (freeze *and* stay low) | Hold a low squat, still | Combines hiding and stillness |
| C · Lockdown | Iris crossfire | Duck/jump split | Spectacle |
| C | **Dual-Agent Override "Hold & Run"** (Parent holds → Child jumps, then swap) | Hold squat ≤ 3 s, jump | Hero co-op moment, both locks |
| Escape | Gate opens → exit | — | Payoff |

**Rules carried over:**
- Moves in a lane stay at least 1.8–2.4 s apart.
- Holds last 3 s at most.
- The child gets a wider window, and every shape is body-relative.
- A miss raises the Alert but never ends the run.
- Each new mechanic first appears alone before it is combined.

## 6. Risks to check first (before any art)

- **Mimic:** real pose jitter, kids fidgeting, and the camera's ~30 fps pose rate. Record real frames of two people standing
  "still" and measure the motion-energy noise floor. Our only real fixture is a still frame, which cannot answer this.
- **Body-Fit:** whether arms-up and star are reliable when the camera crops the head or hands (one of our two real players
  had their head out of frame). Framing guidance may be needed.
- **Interdependence:** whether the parent's hold timing is understandable to a child without text. Test with a family.

## Sources

- Laser Dance press kit: https://laserdancegame.com/presskit/
- UploadVR on the Mimic update: https://www.uploadvr.com/laser-dance-mimic-update/ · https://www.uploadvr.com/laser-dance-mimic-update-2/
- Laser Thief video (title only readable): https://www.youtube.com/watch?v=nJUCtXsU2Rw · Mixed News: https://mixed-news.com/en/vr-giveaway-laser-thief-meta-quest/
- OhShape official site: https://ohshapevr.com/ · UploadVR review: https://uploadvr.com/ohshape-review/ · Wikipedia: https://en.wikipedia.org/wiki/OhShape
- Pistol Whip official page: https://www.cloudheadgames.com/pistol-whip · Road to VR review: https://www.roadtovr.com/?p=91871 · Checkpoint Gaming review: https://checkpointgaming.net/reviews/2020/08/pistol-whip-review-the-john-wick-sim-refined/
- Laser Escape (Meta store): https://www.meta.com/experiences/laser-escape/1526176065959564/
- Laser League official page: https://www.sprungstudios.com/laser-league/ · PlayStation Blog: https://blog.eu.playstation.com/2018/04/25/ready-your-reflexes-for-the-high-speed-multiplayer-action-of-laser-league-out-on-ps4-next-month · Push Square review: https://www.pushsquare.com/reviews/ps4/laser_league
- SUPERHOT VR official page: https://superhotgame.com/superhot-vr · Road to VR review: https://roadtovr.com/superhot-vr-review-oculus-touch-rift/ · UploadVR review: https://uploadvr.com/superhot-vr-review/
