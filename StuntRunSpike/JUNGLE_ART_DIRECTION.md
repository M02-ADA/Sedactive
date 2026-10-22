# Jungle Drift — character & environment animation style

The contract every Jungle Drift asset and animation is checked against. Direction: **Premium Playful Arcade** —
the same family as the players' stand-ins and HUD: chunky, friendly, clearly outlined, readable from 2.5–3 m.

## Visual system

| Axis | Rule |
|---|---|
| **Shape language** | Characters are built from soft, rounded masses (egg bodies, capsule snouts, teardrop feathers). Danger is signalled by a *few* sharp accents only — croc teeth, scutes, beak hook — never by jagged silhouettes. Friendly-menacing, not horror. |
| **Silhouette** | Each animal must read as a solid shape at native scale: croc = long snout + bumpy eye ridge; macaw = egg body + wide wings + long tail. Wings, jaw and tail never merge into the body mass in a key pose. |
| **Outline** | One ink colour (`JunglePalette.outline`, deep teal-black) for all creatures and props; weight ≈ 2% of the creature's body length (players: 9 px on 520 px). Same weight on every part of a rig so layered parts read as one drawing. No outline on water effects (foam, rings, drops) — water is light, creatures are ink. |
| **Value / shading** | Flat cel: one base, one shadow tone (underside/away from the sky), one highlight shape (upper-left). No gradients on characters. Eyes always white sclera + dark pupil (as on the players) — the main expressive feature. |
| **Palette roles** | Environment: greens + deep teal water (cool, mid/low value). Characters: warm or saturated accents that pop off it — macaws use the shared coral / yellow / teal, croc is olive-green with a warm yellow eye and a coral mouth (the one red note = danger focus). Foam/water highlights: pale mint-white. HUD keeps its own colours. |
| **Light** | Key light from above/behind the horizon (the sun in the haze). Highlights on upper surfaces, shadow tone on undersides; creatures cast a soft dark contact shadow/reflection on the water, never a hard drop shadow. |
| **Texture / detail** | Detail concentrated where the eye goes: croc eye + teeth + scute ridge; macaw face + wing fingers. Bodies stay smooth. No noise or grain on characters. |
| **Water** | Light, layered, never outlined: a slow swell, medium wind ripples, fine glints; foam only where something touches the water (raft edges, banks, croc, splashes). |
| **Visual hierarchy** | 1. Players (biggest, brightest contrast). 2. Active hazard (the croc's eye/jaw, the lead bird). 3. Prompt HUD. 4. Water reaction. 5. Scenery. Effects never cover a player's body. |

## Motion system

| Axis | Rule |
|---|---|
| **Personality** | Playful but weighty. Creatures move with intent: slow, smooth approach → readable anticipation → fast action → visible consequence → settle. |
| **Timing palette** | Quick 0.06–0.12 s (snap, impact), standard 0.18–0.35 s (lunge, flare, react), slow 0.5–1.2 s (surface, sink, retreat). Enter slower than exit. |
| **Easing** | Entrances/settles ease-out; departures/falls ease-in; ambient loops sine. Never linear for spatial moves (only for constant drift/scroll). |
| **Anticipation** | Every hazard action is preceded by a counter-move of ~15–20% of the main action: the croc sinks and narrows its eyes before exploding up; the lead birds flare (wings high, body pitched up) before sweeping past. |
| **Squash & stretch** | Moderate (≤ 15%) and volume-preserving: croc stretches on the lunge, squashes on the bite; birds stretch on the downstroke. |
| **Follow-through / overlap** | Parts lag their parent: croc tail and jaw trail the head by 60–150 ms; macaw tail trails body pitch; water rings and foam outlive the action. |
| **Variation** | Controlled: per-bird flap rate ±12%, phase offset, size ±6%, two palette variants of the *same* species and proportions. Croc thrash uses two incommensurate sines, never a fixed shake. No identical loops side by side. |
| **Deformation vs procedural** | Shape changes (wing stroke, jaw, eyelids, splash crown) are authored drawings — a parametric drawing function renders every frame/part from the same proportions. Positioning, rotation, banking, bob, and water response are procedural. |
| **Restraint** | No random particles, no added glow, no idle bounce loops. Every effect is caused by something (a body hitting water, a wing beat, the raft rolling). |

## Assets (all drawn in code from one parametric source, seeded, generated at launch)

| Asset | Form | Notes |
|---|---|---|
| Croc, head-on (approach) | layers: head mass + eye bumps, 2 eyeballs, 2 pupils, 2 lids, nostril pad | swims toward the raft with eyes above water |
| Croc, side (attack) | layers: tail, body, front leg, lower jaw, mouth, upper head, eye, pupil, lid | jaw hinge, eye and tail pivot procedurally |
| Croc submerged shadow | single soft silhouette | lurking under the surface |
| Macaw | 8-frame flap cycle + glide, tuck, flare, startled poses × 2 palettes | anchored at body centre |
| Splash crown | 6-frame authored sheet | croc impact / retreat, raft dunk |
| River | shader: swell + ripples + glints, flow streaks, raft wake and lapping foam, croc wake, expanding rings, bank and sky reflections | reacts to raft roll/bob and croc position via uniforms |
| Driftwood log (River Log Sweep) | 10 roll frames (bark grooves, knots, moss foreshortened on a turning cylinder) + root ball + leafy branch layers | roll frame follows distance rolled; roots and branch turn with it; cut at the waterline while floating |
| Tail sweep croc | head-on rig (shared eyes) + articulated tail: 16 tapered, overlapping segments with crest scutes, a tip, deck contact shadows | the tail follows the hips with a lag (follow-through); coil, whip, overshoot from `TailSweepAnimator` |
| Jump badges (log, tail) | yellow disc, ink outline, pictogram + tucked jumper — same family as the piranha badge | screen edge, never over a player |

## Depth and life (Revision 11)

| Layer (far → near) | What it is | How it moves | Value / colour |
|---|---|---|---|
| Sky | haze gradient, sun glow, light shafts, low humid clouds | clouds drift, slow parallax | brightest, warm |
| Far ridges | tepui mesas, then forested hills | parallax ×0.22 / ×0.38 of the river's bend | single tone, tinted by haze: the farther, the paler and bluer |
| Treelines | two silhouette bands at the horizon | parallax ×0.55 / ×0.8 | fogged greens |
| Forest wall | back row of tall trees 6–10 units inland | land-fixed, gust sway | darker than the bank (canopy-dark mix) |
| Bank | undergrowth clumps, lit fern tops, dappled light, wet mud lip; trees, palms, ferns, heliconia, egrets | land-fixed; gusts travel through it | full colour; heliconia is the warm accent |
| River | swell, ripples, glints, current, debris, rocks with wakes, fish, dragonflies | water frame; debris pushed by the raft's wake | cool teal; foam only where something touches water |
| Foreground | trees leaning over the water, morphos | pass close to the camera at the edges | full colour, ink outlines |
| Landmarks | temple, stone gateway (passed under), kapok, waterfall, fallen giant | one at a time; incidental ones between calm stretches | fogged with distance |

Rules: life is motivated (wind gusts travel, fish break the surface, dragonflies dart and dip, debris is pushed by
the wake), never random particles; nothing crosses the players' lanes; wildlife stays smaller than the hazards.
