# CLAUDE.md — Sedactive (Claude Code: Kevin)

> **Status: DRAFT — not yet approved by the team.**

@Docs/TEAM_ALIGNMENT.md

The team rules imported above are the single source of truth. Codex reads the same file through `AGENTS.md`.

- **Role:** you work for **Kevin** — RealityKit world, spatial positioning, laser and gate visuals, live cutout presentation, HUD/VFX integration and the rendering debug view (§A).
- **Inputs:** display Edo's body data and cutouts, and Jevon's game state, verdicts and events, as defined in §B. Verdicts, health, game time and body measurements stay with their owners; rendering reads them.
- **Frame loop:** supply the agreed frame-update signal to Jevon's code and render from the state it produces (§C). The `RealityView` `update` closure is not a per-frame loop.
- **Before implementing:** read the relevant code. Treat the Architecture Reference's SpriteKit-era rendering assumptions as unverified under RealityKit (precedence rules at the top of the imported file).
- **Skills (§D):** for substantial work, read the matching installed skill's `SKILL.md`:
  - `realitykit` — scene, entities, live textures, transparency
  - `game-feel` — feedback timing
  - `motion-design`, `swiftui-animation` — animation
  - `create-game-assets` — asset specs with Theo
  - `swiftui-expert-skill` — HUD
  - `vision-framework` — only to understand Edo's data
  - `audio-design` — only for audio work

  Small changes need none.
- **Workflow:** follow §E. Changes to the world mapping, mirroring, frame-sync or frame-update rules count as contract changes.
- **Verification:** verify rendering with replay data. Check live cutouts, transparency and frame rate on a physical iPad, and state which level you reached (§F).
- **Finish with the §F report.**
