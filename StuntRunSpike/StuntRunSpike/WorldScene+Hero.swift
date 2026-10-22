import QuartzCore
import SpriteKit

/// Pre-rendered 3D shatter (baked offline by Tools/BakeTeamDuck with RealityKit, played back as a SpriteKit sprite
/// sequence). No 3D engine runs in the game.
@MainActor
final class TeamDuckBake {
    let frames: [SKTexture]
    let fps: Double
    /// Placement in the bake's 1376×1032 screen space (normalized; origin top-left).
    let originX: CGFloat, originTop: CGFloat, width: CGFloat, height: CGFloat
    let bakeScreen = CGSize(width: 1376, height: 1032)

    init?() {
        guard let url = Bundle.main.url(forResource: "TeamDuckShatter", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = meta["frames"] as? Int, let cols = meta["cols"] as? Int, let rows = meta["rows"] as? Int,
              let image = UIImage(named: "TeamDuckShatter") else { return nil }
        let sheet = SKTexture(image: image)
        sheet.filteringMode = .linear
        frames = (0..<count).map { i in
            let col = i % cols, row = i / cols
            return SKTexture(rect: CGRect(x: CGFloat(col) / CGFloat(cols), y: CGFloat(rows - 1 - row) / CGFloat(rows),
                                          width: 1 / CGFloat(cols), height: 1 / CGFloat(rows)), in: sheet)
        }
        fps = meta["fps"] as? Double ?? 30
        originX = meta["originX"] as? CGFloat ?? 0
        originTop = meta["originTop"] as? CGFloat ?? 0
        width = meta["width"] as? CGFloat ?? 1
        height = meta["height"] as? CGFloat ?? 1
        SKTexture.preload([sheet]) {}   // avoid a first-use upload hitch at the big moment
    }

    /// The bake camera matches the game projection, which is defined by screen height; centre horizontally.
    func frame(in sceneSize: CGSize) -> CGRect {
        let unit = sceneSize.height / bakeScreen.height
        let w = width * bakeScreen.width * unit, h = height * bakeScreen.height * unit
        let x = sceneSize.width / 2 + (originX * bakeScreen.width - bakeScreen.width / 2) * unit
        let top = sceneSize.height - originTop * bakeScreen.height * unit
        return CGRect(x: x, y: top - h, width: w, height: h)
    }
}

extension WorldScene {
    // MARK: - Hero TEAM DUCK (anticipation → impact → reward)

    func heroTeamDuck(_ gate: Gate) {
        heroStart = now
        heroFrames = []
        gameLog("hero TEAM DUCK (\(reduceMotion ? "reduced" : "full"))")

        if reduceMotion {
            // Gentler equivalent: dissolve the beam, a small sparkle, no hit-stop, kick, flash or flying debris.
            for node in [gate.beam] + gate.posts + Array(gate.beamGlows.values) { node.run(.fadeOut(withDuration: 0.25)) }
            burstSparks(at: beamScreenPoint(gate), color: Palette.yellow, count: 4)
            showBanner("TEAM DUCK!", sub: "Both of you made it!", color: Palette.mint, hold: 1.0)
            audio.play(.team, dB: -1)
            boost(multiplier: 1.6, duration: 1.6)
            return
        }

        // 1. Anticipation (0–70 ms): both halves flare white, the beam swells, the world holds its breath.
        hitStopUntil = now + 0.07
        for glow in gate.beamGlows.values {
            glow.removeAllActions()
            // Additive and very close to the camera at this point, so keep it well below full white.
            glow.run(.group([.fadeAlpha(to: 0.7, duration: 0.03), .colorize(with: .white, colorBlendFactor: 0.25, duration: 0.05)]))
        }
        gate.beam.run(.scaleX(to: 1.03, y: 1.3, duration: 0.07).easeOut())
        audio.play(.lock, dB: -3)

        // 2. Impact (70 ms).
        run(.wait(forDuration: 0.07)) { [weak self] in self?.heroImpact(gate) }
    }

    private func heroImpact(_ gate: Gate) {
        let center = beamScreenPoint(gate)
        gate.beam.isHidden = true
        for glow in gate.beamGlows.values { glow.isHidden = true }
        for post in gate.posts { post.run(.fadeOut(withDuration: 0.15)) }

        if let bake = teamDuckBake {
            let rect = bake.frame(in: size)
            let debris = SKSpriteNode(texture: bake.frames.first)
            debris.size = rect.size
            debris.position = CGPoint(x: rect.midX, y: rect.midY)
            debris.zPosition = 60   // in front of the bodies, below the HUD
            addChild(debris)
            let play = SKAction.animate(with: bake.frames, timePerFrame: 1 / bake.fps, resize: false, restore: false)
            debris.run(.sequence([.group([play, .sequence([.wait(forDuration: 0.36), .fadeOut(withDuration: 0.14)])]), .removeFromParent()]))
        }

        let ring = SKSpriteNode(texture: Art.ring)
        ring.position = center
        ring.size = CGSize(width: 160, height: 160)
        ring.color = Palette.mint
        ring.colorBlendFactor = 1
        ring.blendMode = .add
        ring.zPosition = 61
        ring.yScale = 0.45   // reads as a ring lying in the plane of the beam
        addChild(ring)
        ring.run(.sequence([.group([.scaleX(to: 9, y: 4, duration: 0.42).easeOut(), .fadeOut(withDuration: 0.42)]), .removeFromParent()]))

        burstSparks(at: center, color: Palette.yellow, count: 14)
        flash.removeAllActions()
        flash.alpha = 0.18
        flash.run(.fadeOut(withDuration: 0.2))
        // Directional camera kick (down, then spring back) instead of random jitter.
        worldRoot.removeAction(forKey: "kick")
        worldRoot.run(.sequence([.moveTo(y: -9, duration: 0.05).easeOut(), .moveTo(y: 0, duration: 0.3).easeOutBack(overshoot: 2.5)]), withKey: "kick")

        // Layered audio: low impact first, glassy shatter on top, the team chord a beat later.
        audio.play(.impact, dB: 0)
        audio.play(.shatter, dB: -3)
        audio.play(.whoosh, dB: -9)
        run(.wait(forDuration: 0.08)) { [weak self] in self?.audio.play(.team, dB: -2) }

        // 3. Reward.
        heroBanner()
        run(.wait(forDuration: 0.3)) { [weak self] in self?.launchFireworks(bursts: 2) }
        boost(multiplier: 1.6, duration: 1.6)
        // A/B snapshots at the same offsets from resolution as the legacy path (70/170/320/520 ms).
        captureEvent("fx-a-070ms", after: 0.0)
        captureEvent("fx-b-170ms", after: 0.1)
        captureEvent("fx-c-320ms", after: 0.25)
        captureEvent("fx-d-520ms", after: 0.45)
    }

    /// "TEAM DUCK!" slams in from oversized and settles, instead of popping up from small.
    private func heroBanner() {
        showBanner("TEAM DUCK!", sub: "Both of you made it!", color: Palette.mint, hold: 1.1)
        let banner = hudNodes.banner
        banner.removeAllActions()
        banner.alpha = 0
        banner.setScale(1.9)
        banner.zRotation = -0.05
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.06), .scale(to: 0.94, duration: 0.12).easeOut(), .rotate(toAngle: 0, duration: 0.12)]),
            .scale(to: 1, duration: 0.18).easeOutBack(overshoot: 3),
            .wait(forDuration: 1.0),
            .group([.fadeOut(withDuration: 0.2), .scale(to: 1.12, duration: 0.2)]),
        ]))
    }

    func beamScreenPoint(_ gate: Gate) -> CGPoint {
        proj.screen(x: 0, h: 1.62, z: max(gate.z, proj.zp))
    }

    /// Frame-time sample for the 1.2 s after the hero moment (logged as [HERO]).
    func recordHeroFrame(dt: TimeInterval) {
        guard let start = heroStart else { return }
        if now - start <= 1.2 {
            heroFrames.append(dt * 1000)
        } else {
            let long = heroFrames.filter { $0 > 17.5 }.count
            let line = String(format: "[HERO] frames=%d maxFrame=%.1fms frames>17.5ms=%d mem=%.0fMB", heroFrames.count,
                              heroFrames.max() ?? 0, long, DeviceStats.memoryFootprintMB())
            print(line)
            gameLog(line)
            heroStart = nil
        }
    }
}
