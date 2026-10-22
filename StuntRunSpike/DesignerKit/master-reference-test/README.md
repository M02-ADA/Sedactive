# One master reference → SpriteKit crocodile (test, 22 Oct 2026)

**Question:** if the designer delivers only **one approved image** of the crocodile, how much of the layered, animated in-game croc can we derive from it?

> [!NOTE]
> No designer reference existed yet, so the **stand-in master** is our current placeholder crocodile flattened into one side-view image (`1-master/`). Everything ran in the **iPad simulator**; no physical iPad.

## What's in this folder

| Folder | Contents |
|---|---|
| `1-master/` | The single flat reference (side view, transparent PNG @2x) |
| `2-auto-sliced/` | Parts cut from that one image along the rig's hinge lines, untouched |
| `3-corrected-for-spritekit/` | The final parts after correction: 12 croc parts + 2 tail-sweep parts, ready for the game |
| `4-in-game-checks/` | Frames from the running game with each set |

## How it was done

1. **Slice:** a technical artist marks lasso outlines and hinge points on the master; ImageMagick cuts each part and rotates it back to its rest pose on the exact canvas and pivot from [`../ASSET_SPEC.md`](../ASSET_SPEC.md).
2. **Load in game:** launch with `-crocParts <folder>`. Any `<name>@2x.png` in that folder replaces the code-drawn part (`Art.designerPart`). Without the argument the game is unchanged.
3. **Run:** the existing scripts play the ram (`-scenario coop`) and tail sweep (`-scenario sweeps`), and the frames are inspected.

## Results

**Usable straight from the slice** (coverage = share of the part's area recovered; wrong pixels = pixels that differ from the intended art):

| Part | Coverage | Wrong pixels | Verdict |
|---|---|---|---|
| Tail | 98% | 0.9% | ✅ usable |
| Upper head | 83% | 1.0% | ⚠️ eye socket hole, tooth tips cut off |
| Body | 91% | 0.4% | ⚠️ holes where the head and leg covered it |
| Leg | 98% | 0.4% | ⚠️ included a piece of the body |
| Brow | 98% | 0.8% | ⚠️ included the top of the eye |
| Lower jaw | 91% | 7.5% | ❌ carries the upper teeth; its own teeth are hidden |
| Eye (ball) | 87% | 29.7% | ❌ pupil, lid and skin baked in, so it can't blink or glare |

**Not derivable at all from one side view:** throat and tongue (never visible when closed), pupil, eyelid, glint (baked into the eye), the head-on view (the approach and tail-sweep croc), and the mouth shapes.

**Generated from the master:** the tail-sweep **segment** and **tail tip** were cut from the master's tail and work in game, but the segment needs a straight, untapered crop (or a dedicated drawing) to avoid a stepped edge when chained.

**Corrections made for the final set** (in production, the designer does these as paint-overs):
- filled the eye socket and the tooth tips on the upper head;
- removed the leg from the body using the leg's outline, and filled the hidden area;
- trimmed the leg and brow to their own outlines;
- used separately drawn lower jaw, throat, eye set (ball, pupil, lid, glint) and head-on view.

**In game:**
- **Auto-sliced set:** it moves correctly, but the open mouth shows a hole, the teeth are wrong, and the eye can't blink.
- **Corrected set:** it looks and moves like the original through approach, snarl, lunge, bite, cling and retreat (`4-in-game-checks/`).

## 2D vs offline 3D

**2D layered was the better result here.** The hard movements (lunge squash, jaw snap, thrash, the tail's whip and follow-through) are already produced in code from flat parts.

Offline 3D was **not** built, for three reasons:
- **No modelling tool is installed:** no Blender, and image-to-3D services were excluded.
- **A primitive RealityKit model wouldn't match the art style:** it has no ink outline or flat cel shading (see Revision 4 in `FINDINGS.md`).
- **The one thing 3D would add is more work, not less:** extra views such as head-on would need a modelled 3D croc, which is more work than drawing one extra view.

Offline 3D stays the right tool for rare hero effects (like the TEAM DUCK shatter).

## Formats SpriteKit accepts

- Transparent **PNG @2x**, one file per part, named and sized exactly as in `ASSET_SPEC.md`; pivots come from the canvas size.
- Frame sequences named `name-0…n@2x.png`.
- For shipping, put the parts in an `.atlas` folder or an asset catalog sprite atlas. This is recommended but not tested yet.

## Recommendation for the designer workflow

**"One master" works if it is one *layered source file*, not one flat image.**

- **Designer delivers:** a PSD or Procreate file with each part on its own layer, the hidden areas painted (mouth interior, lower teeth, the skin under the eye, the tail base), plus one head-on view. Exports go through `ASSET_SPEC.md`.
- **Developer generates in code:** every movement from those parts (anticipation, lunge, bite, thrash, tail sweep, recovery).

## Still needs designer review

- Style approval of the corrected parts against a real master.
- The head-on view and expressions.
- A straight tail-segment drawing.
- Whether eye and brow shapes hold up when scaled and rotated.
- Readability at 2.5–3 m on a real iPad.
