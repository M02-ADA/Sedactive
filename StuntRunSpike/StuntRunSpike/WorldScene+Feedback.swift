import QuartzCore
import SpriteKit

struct HUDNodes {
    var cards: [Zone: SKSpriteNode] = [:]
    var roleLabels: [Zone: SKLabelNode] = [:]
    var countLabels: [Zone: SKLabelNode] = [:]
    var comboLabels: [Zone: SKLabelNode] = [:]
    var statusLabels: [Zone: SKLabelNode] = [:]
    var cues: [Zone: SKSpriteNode] = [:]
    var ratings: [Zone: SKLabelNode] = [:]
    var meterBack = SKSpriteNode(texture: Art.pill)
    var meterFill = SKSpriteNode(texture: Art.pill)
    var meterLabel = SKLabelNode()
    var distanceLabel = SKLabelNode()
    var banner = SKLabelNode()
    var subBanner = SKLabelNode()
    /// Shared-challenge widget: one slot per player that fills when their contribution counts.
    var lockRoot = SKNode()
    var lockBack = SKSpriteNode(texture: Art.pill)
    var lockSlots: [Zone: SKSpriteNode] = [:]
    var lockFills: [Zone: SKSpriteNode] = [:]
    var lockLabel = SKLabelNode()
}

extension WorldScene {
    // MARK: - HUD build & layout

    func buildHUD() {
        hud.zPosition = Layer.hud
        addChild(hud)

        flash.zPosition = Layer.flash
        flash.alpha = 0
        flash.blendMode = .add
        addChild(flash)

        for zone in Zone.allCases {
            let card = SKSpriteNode(texture: Art.card(color: Palette.color(for: zone, swapped: swapped)))
            card.size = CGSize(width: 260, height: 105)
            hud.addChild(card)
            hudNodes.cards[zone] = card

            let role = SKLabelNode()
            role.horizontalAlignmentMode = .left
            role.position = CGPoint(x: -105, y: 12)
            role.zPosition = 1
            card.addChild(role)
            hudNodes.roleLabels[zone] = role

            let count = SKLabelNode()
            count.horizontalAlignmentMode = .right
            count.verticalAlignmentMode = .center
            count.position = CGPoint(x: 108, y: 2)
            count.attributedText = arcadeText("0", size: 54, color: .white, strokeWidth: -5)
            count.zPosition = 1
            card.addChild(count)
            hudNodes.countLabels[zone] = count

            let status = SKLabelNode()
            status.horizontalAlignmentMode = .left
            status.position = CGPoint(x: -105, y: -26)
            status.zPosition = 1
            card.addChild(status)
            hudNodes.statusLabels[zone] = status

            let combo = SKLabelNode()
            combo.position = CGPoint(x: 0, y: -78)
            combo.zPosition = 1
            card.addChild(combo)
            hudNodes.comboLabels[zone] = combo

            let cue = SKSpriteNode(texture: Art.chevron)
            cue.size = CGSize(width: 96, height: 80)
            cue.colorBlendFactor = 0.6
            cue.isHidden = true
            cue.zPosition = 5
            hud.addChild(cue)
            hudNodes.cues[zone] = cue

            let rating = SKLabelNode()
            rating.alpha = 0
            rating.zPosition = 6
            hud.addChild(rating)
            hudNodes.ratings[zone] = rating
        }

        hudNodes.meterBack.color = Palette.deepNavy
        hudNodes.meterBack.colorBlendFactor = 1
        hudNodes.meterBack.alpha = 0.78
        hud.addChild(hudNodes.meterBack)
        hudNodes.meterFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hudNodes.meterFill.color = Palette.yellow
        hudNodes.meterFill.colorBlendFactor = 1
        hudNodes.meterFill.zPosition = 1
        hud.addChild(hudNodes.meterFill)
        hudNodes.meterLabel.attributedText = arcadeText("TEAM POWER", size: 18, color: .white, strokeWidth: -5)
        hudNodes.meterLabel.zPosition = 2
        hud.addChild(hudNodes.meterLabel)
        hudNodes.distanceLabel.zPosition = 2
        hud.addChild(hudNodes.distanceLabel)

        hudNodes.banner.alpha = 0
        hudNodes.banner.verticalAlignmentMode = .center
        hudNodes.banner.zPosition = 10
        hud.addChild(hudNodes.banner)
        hudNodes.subBanner.alpha = 0
        hudNodes.subBanner.verticalAlignmentMode = .center
        hudNodes.subBanner.zPosition = 10
        hud.addChild(hudNodes.subBanner)

        let lock = hudNodes.lockRoot
        lock.zPosition = 9
        lock.isHidden = true
        hud.addChild(lock)
        hudNodes.lockBack.size = CGSize(width: 250, height: 64)
        hudNodes.lockBack.color = Palette.deepNavy
        hudNodes.lockBack.colorBlendFactor = 1
        hudNodes.lockBack.alpha = 0.8
        lock.addChild(hudNodes.lockBack)
        for zone in Zone.allCases {
            let slot = SKSpriteNode(texture: Art.ring)
            slot.size = CGSize(width: 52, height: 52)
            slot.position = CGPoint(x: zone == .left ? -80 : 80, y: 0)
            slot.color = Palette.color(for: zone, swapped: swapped)
            slot.colorBlendFactor = 1
            slot.zPosition = 1
            lock.addChild(slot)
            hudNodes.lockSlots[zone] = slot
            let fill = SKSpriteNode(texture: Art.check)
            fill.size = CGSize(width: 40, height: 40)
            fill.position = slot.position
            fill.setScale(0)
            fill.zPosition = 2
            lock.addChild(fill)
            hudNodes.lockFills[zone] = fill
        }
        hudNodes.lockLabel.verticalAlignmentMode = .center
        hudNodes.lockLabel.zPosition = 2
        lock.addChild(hudNodes.lockLabel)

        for _ in 0..<28 {
            let spark = SKSpriteNode(texture: Art.star)
            spark.isHidden = true
            spark.colorBlendFactor = 1
            spark.zPosition = 8
            hud.addChild(spark)
            sparks.append(spark)
        }
        for zone in Zone.allCases {
            hudNodes.roleLabels[zone]?.attributedText = arcadeText(role(for: zone), size: 22, color: .white, strokeWidth: -5)
        }
    }

    func layoutHUD() {
        let top = size.height - 24
        hudNodes.cards[.left]?.position = CGPoint(x: 24 + 130, y: top - 52)
        hudNodes.cards[.right]?.position = CGPoint(x: size.width - 24 - 130, y: top - 52)
        let meterWidth = min(460, size.width * 0.34)
        hudNodes.meterBack.size = CGSize(width: meterWidth, height: 30)
        hudNodes.meterBack.position = CGPoint(x: size.width / 2, y: top - 52)
        hudNodes.meterFill.position = CGPoint(x: size.width / 2 - meterWidth / 2 + 4, y: top - 52)
        hudNodes.meterLabel.position = CGPoint(x: size.width / 2, y: top - 28)
        hudNodes.distanceLabel.position = CGPoint(x: size.width / 2, y: top - 98)
        hudNodes.banner.position = CGPoint(x: size.width / 2, y: size.height * 0.70)
        hudNodes.subBanner.position = CGPoint(x: size.width / 2, y: size.height * 0.70 - 62)
        hudNodes.lockRoot.position = CGPoint(x: size.width / 2, y: top - 150)
        updateMeter(animated: false)
    }

    func updateHUD(dt: CGFloat) {
        hudNodes.distanceLabel.attributedText = arcadeText("\(Int((distance - sessionDistanceStart) * 1.5)) m", size: 20, color: Palette.yellow, strokeWidth: -5)
        var lostZones: Set<Zone> = []
        if case .trackingLost(let zones) = flow.state { lostZones = zones }
        for zone in Zone.allCases {
            guard let slot = slots[zone] else { continue }
            let status: (String, UIColor) = if lostZones.contains(zone) || slot.simLost {
                ("✕ LOST", Palette.coral.mixed(with: .white, amount: 0.4))
            } else {
                switch slot.driver {
                case .live: ("● LIVE", Palette.mint)
                case .simulated: (anyScriptRunning ? "● SCRIPT" : model?.autoplay == true && now - slot.lastManualSim > 20 ? "● AUTO" : "● SIM", Palette.yellow)
                case .absent: ("STEP IN", .white)
                }
            }
            if hudNodes.statusLabels[zone]?.userData?["text"] as? String != status.0 {
                hudNodes.statusLabels[zone]?.attributedText = arcadeText(status.0, size: 15, color: status.1, strokeWidth: -5)
                hudNodes.statusLabels[zone]?.userData = ["text": status.0]
            }
        }
    }

    func updateMeter(animated: Bool) {
        let width = hudNodes.meterBack.size.width - 8
        let progress = CGFloat(teamPower) / CGFloat(teamPowerMax)
        let target = CGSize(width: max(22, width * progress), height: 22)
        hudNodes.meterFill.alpha = teamPower == 0 ? 0 : 1
        if animated {
            hudNodes.meterFill.run(.resize(toWidth: target.width, height: target.height, duration: 0.25).easeOut())
        } else {
            hudNodes.meterFill.size = target
        }
    }

    // MARK: - Player visuals

    /// Fits the cutout so the tallest standing person matches adult scale and their feet meet the roof.
    func layoutLiveBody() {
        guard mode == .immersive else { return }
        let standing = Zone.allCases.compactMap { slots[$0] }.filter { $0.driver == .live && $0.detector.phase == .standing }
        let poses = standing.compactMap(\.livePose)
        guard !poses.isEmpty,
              let span = poses.compactMap(\.standingSpan).max(),
              let foot = poses.compactMap(\.footY).min() else { return }
        let adultUnits: CGFloat = 1.15 * 0.88
        let targetHeight = max(size.height * 0.6, min(size.height * 1.9, adultUnits * proj.ppu(proj.zp) / CGFloat(span)))
        let targetMinY = proj.feetY - CGFloat(foot) * targetHeight
        bodyLayoutTarget = (targetHeight, targetMinY)
    }

    func updatePlayersVisuals(dt: CGFloat) {
        if let target = bodyLayoutTarget {
            let blend = min(1, dt * 1.6)
            let height = bodySprite.size.height + (target.height - bodySprite.size.height) * blend
            let minY = bodyRect.minY + (target.minY - bodyRect.minY) * blend
            setBodyRect(height: height, minY: minY)
        }

        let immersive = mode == .immersive
        let rect = immersive ? bodyRect : cameraRect
        for zone in Zone.allCases {
            guard var slot = slots[zone], let placeholder = placeholders[zone], let pad = pads[zone] else { continue }
            let depth = CGFloat(slot.detector.depth)
            let defaultFoot = proj.screen(x: zone == .left ? -playerX : playerX, h: 0, z: proj.zp)

            if slot.driver == .live, let pose = slot.livePose {
                let foot = CGPoint(x: rect.minX + CGFloat(pose.footX ?? 0.5) * rect.width,
                                   y: rect.minY + CGFloat(pose.footY ?? 0) * rect.height)
                slot.footPoint = slot.footPoint == .zero ? foot : CGPoint(x: slot.footPoint.x + (foot.x - slot.footPoint.x) * 0.35,
                                                                        y: slot.footPoint.y + (foot.y - slot.footPoint.y) * 0.35)
                if let head = pose.headPoint {
                    slot.headPoint = CGPoint(x: rect.minX + CGFloat(head.x) * rect.width, y: rect.minY + CGFloat(head.y) * rect.height + 30)
                }
                placeholder.isHidden = true
            } else {
                slot.footPoint = defaultFoot
                // Placeholder squash mirrors the same detector depth that drives gameplay.
                placeholder.isHidden = !immersive || slot.driver == .absent
                // A player who is out of tracking is shown as a ghost, so it is obvious who must step back in.
                var lost = slot.simLost
                if case .trackingLost(let zones) = flow.state, zones.contains(zone) { lost = true }
                placeholder.alpha = lost ? 0.3 + 0.1 * sin(CGFloat(now) * 5) : 1
                // Jumps (same detector values that gameplay judges): crouch squash → stretched while airborne →
                // squash on landing. A nipped stand-in gives a startled little hop. Lift is exaggerated ×1.4 (staging).
                let lift = CGFloat(slot.jump.lift)
                let sinceLand = CGFloat(now - slot.landedAt), sinceNip = CGFloat(now - slot.nippedAt)
                var stretch: CGFloat = lift < 0 ? 1 + lift * 2 : (slot.jump.isAirborne ? 1.06 : 1)
                if sinceLand < 0.16, !reduceMotion { stretch *= 0.9 + 0.1 * sinceLand / 0.16 }
                let ouch: CGFloat = sinceNip < 0.35 ? sin(.pi * sinceNip / 0.35) * 0.12 : 0
                let raise = (max(0, lift) * 1.4 + ouch) * proj.ppu(proj.zp)
                placeholder.position = CGPoint(x: defaultFoot.x, y: defaultFoot.y + raise)
                placeholder.yScale = (1 - 0.32 * depth) * stretch
                placeholder.xScale = (1 + 0.10 * depth) / max(0.9, stretch)
                placeholder.color = Palette.coral
                placeholder.colorBlendFactor = sinceNip < 0.3 ? 0.5 * (1 - sinceNip / 0.3) : 0
                slot.headPoint = CGPoint(x: defaultFoot.x, y: defaultFoot.y + raise + placeholder.size.height * (1 - 0.32 * depth) + 40)
            }
            slots[zone] = slot

            pad.position = slot.footPoint
            let padWidth = 1.25 * proj.ppu(proj.zp)
            pad.size = CGSize(width: padWidth, height: padWidth * 150 / 440)
            pad.xScale = 1 + 0.22 * depth
            pad.yScale = 1 + 0.22 * depth
            pad.alpha = slot.driver == .absent ? 0.35 + 0.25 * sin(CGFloat(now) * 4) : 0.75 + 0.25 * depth
            pad.isHidden = false
            padLabels[zone]?.position = CGPoint(x: slot.footPoint.x, y: slot.footPoint.y - pad.size.height * 0.62)
            padLabels[zone]?.isHidden = slot.footPoint.y - pad.size.height * 0.62 < 10

            if let cue = hudNodes.cues[zone], !cue.isHidden {
                cue.position = CGPoint(x: slot.headPoint.x, y: min(size.height - 150, slot.headPoint.y + 50))
            }
        }
    }

    func updateCues(gate: Gate, urgency: CGFloat) {
        for zone in Zone.allCases {
            guard let cue = hudNodes.cues[zone], !cue.isHidden, cue.action(forKey: "respond") == nil else { continue }
            if gate.challenge?.started.contains(zone) == true { continue }
            let bob = reduceMotion ? 0 : sin(CGFloat(now) * (7 + 10 * urgency)) * 8
            cue.position.y += bob
        }
    }

    func hideCue(_ zone: Zone) {
        guard let cue = hudNodes.cues[zone], !cue.isHidden else { return }
        cue.removeAllActions()
        cue.run(.sequence([.group([.fadeOut(withDuration: 0.15), .scale(to: 0.6, duration: 0.15)]), .hide()]))
    }

    // MARK: - Reactions

    /// Earliest acknowledgement of a squat: changes on the same frame the descent is detected.
    func laneResponds(_ zone: Zone, gate: Gate) {
        guard let panel = gate.panels[zone] else { return }
        panel.removeAllActions()
        panel.alpha = 1
        panel.run(.group([
            .colorize(with: Palette.mint, colorBlendFactor: 0.9, duration: 0.06),
            .moveBy(x: 0, y: 0.1 * Gate.unit, duration: 0.12).easeOut(),
            .sequence([.scaleX(to: 1.12, y: 0.86, duration: 0.06), .scaleX(to: 1, y: 1, duration: 0.14).easeOutBack()]),
        ]), withKey: "respond")
        if let cue = hudNodes.cues[zone] {
            cue.run(.group([
                .colorize(with: Palette.mint, colorBlendFactor: 1, duration: 0.06),
                .sequence([.scaleX(to: 1.25, y: 0.7, duration: 0.07), .scaleX(to: 1, y: 1, duration: 0.18).easeOutBack()]),
            ]), withKey: "respond")
        }
        audio.play(.whoosh, dB: -12)
    }

    func laneArmed(_ zone: Zone, gate: Gate) {
        if gate.panels[zone]?.action(forKey: "respond") == nil, gate.panels[zone]?.colorBlendFactor != 0.9 {
            laneResponds(zone, gate: gate)
        }
        gate.checks[zone]?.run(.sequence([.scale(to: 1.25, duration: 0.12).easeOut(), .scale(to: 1, duration: 0.12)]))
        // The player's half of the shared beam lights up: their part of the team goal is done.
        gate.beamGlows[zone]?.run(.sequence([.fadeAlpha(to: 0.9, duration: 0.08), .fadeAlpha(to: 0.55, duration: 0.3)]))
        audio.play(.lock, dB: -6)
    }

    func laneReset(_ zone: Zone, gate: Gate) {
        guard let panel = gate.panels[zone] else { return }
        panel.run(.group([
            .colorize(with: Palette.color(for: zone, swapped: swapped), colorBlendFactor: 0.85, duration: 0.12),
            .moveTo(y: Gate.panelTop * Gate.unit, duration: 0.15),
        ]))
    }

    func laneSuccess(_ zone: Zone, gate: Gate, perfect: Bool) {
        if let panel = gate.panels[zone] {
            // Quick exit: the gate keeps flying toward the camera after resolving, so anything slower
            // would balloon across the screen.
            panel.removeAllActions()
            panel.run(.sequence([
                .group([.scale(to: 1.15, duration: 0.12).easeOut(), .fadeOut(withDuration: 0.12),
                        .moveBy(x: 0, y: 0.3 * Gate.unit, duration: 0.12).easeOut()]),
                .hide(),
            ]))
        }
        let head = slots[zone]?.headPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)
        burstSparks(at: head, color: perfect ? Palette.yellow : Palette.color(for: zone, swapped: swapped), count: reduceMotion ? 4 : 10)
        let combo = slots[zone]?.combo ?? 0
        popRating(zone, text: perfect ? "PERFECT!" : "GREAT!", color: perfect ? Palette.yellow : .white, at: head)
        if combo >= 2 {
            hudNodes.comboLabels[zone]?.attributedText = arcadeText("x\(combo) COMBO", size: 24, color: Palette.yellow, strokeWidth: -5)
            hudNodes.comboLabels[zone]?.run(popAction())
        }
        audio.play(.chime, dB: perfect ? -2 : -5)
    }

    func laneMiss(_ zone: Zone, gate: Gate) {
        if let panel = gate.panels[zone] {
            panel.removeAllActions()
            panel.alpha = 1
            let wobble: SKAction = reduceMotion ? .fadeAlpha(to: 0.5, duration: 0.2) : .sequence([
                .rotate(toAngle: 0.12, duration: 0.05), .rotate(toAngle: -0.1, duration: 0.08),
                .rotate(toAngle: 0.06, duration: 0.07), .rotate(toAngle: 0, duration: 0.07),
            ])
            // Wobble, then clear out quickly so the panel never balloons across the screen as it passes.
            panel.run(.sequence([
                .group([wobble, .colorize(with: Palette.coral.mixed(with: Palette.deepNavy, amount: 0.35), colorBlendFactor: 1, duration: 0.1)]),
                .fadeOut(withDuration: 0.12), .hide(),
            ]))
        }
        hudNodes.comboLabels[zone]?.attributedText = nil
        let head = slots[zone]?.headPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)
        popRating(zone, text: "ALMOST!", color: .white, at: head)
        audio.play(.bonk, dB: -10)
    }

    /// Both players made it: the gate shatters toward the camera and the train surges.
    func teamSuccess(_ gate: Gate) {
        if model?.heroFX ?? true {
            heroTeamDuck(gate)
            return
        }
        legacyTeamSuccess(gate)
    }

    /// Revision 3's original TEAM DUCK (kept for A/B with `-heroFX legacy`).
    func legacyTeamSuccess(_ gate: Gate) {
        heroStart = now
        heroFrames = []
        for (name, t) in [("fx-a-070ms", 0.07), ("fx-b-170ms", 0.17), ("fx-c-320ms", 0.32), ("fx-d-520ms", 0.52)] {
            captureEvent(name, after: t)
        }
        gate.beam.isHidden = true
        for post in gate.posts { post.run(.fadeOut(withDuration: 0.2)) }
        let colors = [Palette.coral, Palette.teal, Palette.yellow, Palette.violet, .white]
        let count = reduceMotion ? 12 : shards.count
        for (i, shard) in shards.prefix(count).enumerated() {
            // Burst up and outward from the beam, so the debris frames the players instead of covering them.
            shard.x = CGFloat.random(in: -2.4...2.4)
            shard.h = CGFloat.random(in: 1.45...1.85)
            shard.z = gate.z + 0.4
            shard.vx = shard.x * CGFloat.random(in: 0.5...1.4)
            shard.vh = CGFloat.random(in: 2.5...5.5)
            shard.vz = -CGFloat.random(in: 4...9)   // carried past the players toward the camera, never receding
            shard.spin = CGFloat.random(in: -9...9)
            shard.life = CGFloat.random(in: 0.6...0.95)
            shard.sizeUnits = CGFloat.random(in: 0.06...0.13)
            shard.node.color = colors[i % colors.count]
            shard.node.isHidden = false
        }
        if !reduceMotion {
            flash.removeAllActions()
            flash.alpha = 0.32
            flash.run(.fadeOut(withDuration: 0.22))
            shakeUntil = now + 0.3
            shakeAmplitude = 6
        }
        showBanner("TEAM DUCK!", sub: "Both of you made it!", color: Palette.mint, hold: 1.0)
        audio.play(.team, dB: -1)
        launchFireworks(bursts: 2)
        boost(multiplier: 1.6, duration: 1.6)
        // Team Power for this gate was banked per contribution plus the team bonus (see resolve).
    }

    func repCompleted(_ zone: Zone) {
        guard var slot = slots[zone] else { return }
        slot.squats += 1
        slots[zone] = slot
        if let label = hudNodes.countLabels[zone] {
            label.attributedText = arcadeText("\(slot.squats)", size: 54, color: .white, strokeWidth: -5)
            label.run(popAction())
        }
        hudNodes.cards[zone]?.run(.sequence([.scale(to: 1.06, duration: 0.07), .scale(to: 1, duration: 0.18).easeOutBack()]))
        floatText("+1", color: Palette.yellow, at: CGPoint(x: slot.headPoint.x + 50, y: slot.headPoint.y))
        audio.play(.pop, dB: -6)
    }

    func padPulse(_ zone: Zone) {
        pads[zone]?.run(.sequence([.colorize(with: Palette.mint, colorBlendFactor: 1, duration: 0.05),
                                   .colorize(with: Palette.color(for: zone, swapped: swapped), colorBlendFactor: 1, duration: 0.35)]))
    }

    func addTeamPower(_ amount: Int) {
        teamPower = min(teamPowerMax, teamPower + amount)
        updateMeter(animated: true)
        hudNodes.meterBack.run(.sequence([.scaleX(to: 1.04, y: 1.15, duration: 0.07), .scale(to: 1, duration: 0.15)]))
        if teamPower >= teamPowerMax {
            teamPower = 0
            let session = flow.session
            // Guarded: never fires into a new session; if the game halts first, it is deferred to the next
            // GO rather than lost (the players earned it).
            run(.wait(forDuration: 0.35)) { [weak self] in
                guard let self, flow.session == session else { return }
                if flow.isHalted || encounterActive {
                    pendingTurbo = true
                    gameLog(flow.isHalted ? "TURBO deferred (game halted)" : "TURBO deferred (encounter in progress)")
                } else {
                    gameLog("TURBO (team power full)")
                    turbo()
                }
            }
        }
    }

    /// Meter full: a longer surge plus an environment transition (dusk ↔ night).
    func turbo() {
        updateMeter(animated: true)
        if gameMode == .jungleDrift {
            showBanner("RIVER SPIRIT!", sub: "Team power full — the jungle cheers you on", color: Palette.yellow, hold: 1.4)
            audio.play(.turbo, dB: -6)
            celebrateWorld()
            gameLog("RIVER SPIRIT (team power full)")
            captureEvent("j-river-spirit", after: 0.6)
            return
        }
        palettePhaseTarget = palettePhaseTarget < 0.5 ? 1 : 0
        boost(multiplier: 2.0, duration: 2.6)
        showBanner("TURBO!", sub: "Team power full", color: Palette.yellow, hold: 1.3)
        audio.play(.turbo, dB: -4)
        launchFireworks(bursts: 4)
        captureEvent("turbo", after: 0.7)
        captureEvent("turbo-night", after: 3.5)
    }

    func boost(multiplier: CGFloat, duration: TimeInterval) {
        boostMultiplier = max(multiplier, now < boostUntil ? boostMultiplier : 1)
        boostUntil = max(boostUntil, now + duration)
    }

    // MARK: - Effect helpers

    func showBanner(_ text: String, sub: String?, color: UIColor, hold: TimeInterval?) {
        let banner = hudNodes.banner, subBanner = hudNodes.subBanner
        banner.removeAllActions(); subBanner.removeAllActions()
        banner.attributedText = arcadeText(text, size: 76, color: color, strokeWidth: -4)
        subBanner.attributedText = sub.map { arcadeText($0, size: 26, color: .white, strokeWidth: -5) }
        let appear: SKAction = reduceMotion
            ? .sequence([.scale(to: 1, duration: 0), .fadeIn(withDuration: 0.15)])
            : .sequence([.group([.fadeIn(withDuration: 0.08), .scale(to: 0.4, duration: 0)]), .scale(to: 1, duration: 0.3).easeOutBack(overshoot: 2.4)])
        let disappear: SKAction = hold.map { .sequence([.wait(forDuration: $0), .group([.fadeOut(withDuration: 0.2), .scale(to: 1.15, duration: 0.2)])]) } ?? .wait(forDuration: 0)
        banner.alpha = 0
        banner.run(.sequence([appear, disappear]))
        subBanner.alpha = 0
        subBanner.setScale(1)
        subBanner.run(.sequence([.wait(forDuration: 0.1), .fadeIn(withDuration: 0.15),
                                 hold.map { .sequence([.wait(forDuration: $0 - 0.1), .fadeOut(withDuration: 0.2)]) } ?? .wait(forDuration: 0)]))
    }

    func popRating(_ zone: Zone, text: String, color: UIColor, at point: CGPoint) {
        guard let label = hudNodes.ratings[zone] else { return }
        label.removeAllActions()
        label.attributedText = arcadeText(text, size: 46, color: color, strokeWidth: -4)
        label.position = CGPoint(x: point.x, y: min(size.height - 170, point.y + 20))
        label.setScale(0.3)
        label.alpha = 1
        let rise: SKAction = reduceMotion ? .wait(forDuration: 0.5) : .moveBy(x: 0, y: 50, duration: 0.7).easeOut()
        label.run(.group([
            .sequence([.scale(to: 1.15, duration: 0.16).easeOut(), .scale(to: 1, duration: 0.12)]),
            rise,
            .sequence([.wait(forDuration: 0.55), .fadeOut(withDuration: 0.2)]),
        ]))
    }

    func floatText(_ text: String, color: UIColor, at point: CGPoint) {
        let label = SKLabelNode()
        label.name = "float"
        label.attributedText = arcadeText(text, size: 34, color: color, strokeWidth: -5)
        label.position = point
        label.zPosition = 7
        hud.addChild(label)
        label.setScale(0.5)
        label.run(.sequence([
            .group([.scale(to: 1, duration: 0.15).easeOutBack(), .moveBy(x: 10, y: 60, duration: 0.6).easeOut(),
                    .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.2)])]),
            .removeFromParent(),
        ]))
    }

    func burstSparks(at point: CGPoint, color: UIColor, count: Int) {
        for i in 0..<count {
            let spark = sparks[nextSpark]
            nextSpark = (nextSpark + 1) % sparks.count
            spark.removeAllActions()
            spark.isHidden = false
            spark.alpha = 1
            spark.color = i % 3 == 0 ? .white : color
            spark.position = point
            spark.setScale(CGFloat.random(in: 0.5...0.9))
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let distance = CGFloat.random(in: 70...150) * (reduceMotion ? 0.5 : 1)
            spark.run(.sequence([
                .group([.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.45).easeOut(),
                        .rotate(byAngle: CGFloat.random(in: -4...4), duration: 0.45),
                        .scale(to: 0, duration: 0.45), .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.2)])]),
                .hide(),
            ]))
        }
    }

    func popAction() -> SKAction {
        .sequence([.scale(to: 1.35, duration: 0.08).easeOut(), .scale(to: 1, duration: 0.2).easeOutBack()])
    }

    func arcadeText(_ string: String, size: CGFloat, color: UIColor, strokeWidth: CGFloat) -> NSAttributedString {
        let font = UIFont(name: "AvenirNext-HeavyItalic", size: size) ?? .systemFont(ofSize: size, weight: .black)
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .strokeColor: Palette.deepNavy,
            .strokeWidth: strokeWidth,
        ])
    }
}

/// Rolling performance numbers. Everything here is measured on the running device, not estimated.
struct MetricsAccumulator {
    private var frameTimes: [Double] = []
    private var hitches = 0
    private var hitchWindowStart: TimeInterval = 0
    private var snapshotTimes: [TimeInterval] = []
    private var stats: [PipelineStats] = []
    private var captureToTexture: [Double] = []
    private var feedback: [Double] = []
    private var lastPublish: TimeInterval = 0
    private var lastLog: TimeInterval = 0
    private var allFeedback: [Double] = []

    mutating func recordFrame(dt: TimeInterval) {
        frameTimes.append(dt * 1000)
        if dt > 1.5 / 60 { hitches += 1 }
    }

    mutating func recordSnapshot(_ snapshot: VisionSnapshot, uploadedAt now: TimeInterval) {
        snapshotTimes.append(now)
        stats.append(snapshot.stats)
        let latency = (now - snapshot.captureTime) * 1000
        if latency > 0, latency < 2000 { captureToTexture.append(latency) }
    }

    mutating func recordFeedbackLatency(ms: Double) {
        guard ms > 0, ms < 2000 else { return }
        feedback.append(ms)
        allFeedback.append(ms)
    }

    mutating func shouldPublish(now: TimeInterval) -> Bool {
        if lastPublish == 0 { lastPublish = now; hitchWindowStart = now }
        return now - lastPublish >= 0.5
    }

    mutating func makeSnapshot(now: TimeInterval, last: VisionSnapshot?) -> MetricsSnapshot {
        let window = now - lastPublish
        lastPublish = now
        var m = MetricsSnapshot()
        if !frameTimes.isEmpty {
            m.renderFPS = Double(frameTimes.count) / window
            m.frameTimeAvgMs = frameTimes.reduce(0, +) / Double(frameTimes.count)
            m.frameTimeMaxMs = frameTimes.max() ?? 0
        }
        let minutes = max(1.0 / 60, (now - hitchWindowStart) / 60)
        m.hitchesPerMin = Double(hitches) / minutes
        m.visionFPS = Double(snapshotTimes.count) / window
        if !stats.isEmpty {
            m.poseMs = stats.map(\.poseMs).reduce(0, +) / Double(stats.count)
            m.segmentationMs = stats.map(\.segmentationMs).reduce(0, +) / Double(stats.count)
            m.compositeMs = stats.map(\.compositeMs).reduce(0, +) / Double(stats.count)
        }
        if !captureToTexture.isEmpty { m.captureToTextureMs = captureToTexture.reduce(0, +) / Double(captureToTexture.count) }
        m.feedbackLatencyLastMs = allFeedback.last
        if !allFeedback.isEmpty { m.feedbackLatencyAvgMs = allFeedback.reduce(0, +) / Double(allFeedback.count) }
        if let last {
            m.droppedCameraFrames = last.stats.droppedFrames
            m.maskSize = last.stats.maskWidth > 0 ? "\(last.stats.maskWidth)×\(last.stats.maskHeight)" : "—"
            m.sourceSize = "\(last.stats.sourceWidth)×\(last.stats.sourceHeight)"
        }
        frameTimes.removeAll(keepingCapacity: true)
        snapshotTimes.removeAll(keepingCapacity: true)
        stats.removeAll(keepingCapacity: true)
        captureToTexture.removeAll(keepingCapacity: true)
        feedback.removeAll(keepingCapacity: true)
        if now - hitchWindowStart > 60 { hitchWindowStart = now; hitches = 0 }
        return m
    }

    mutating func logIfNeeded(_ m: MetricsSnapshot, now: TimeInterval) -> String? {
        guard now - lastLog >= 5 else { return nil }
        lastLog = now
        let line = String(format: "[METRICS] fps=%.1f frame=%.1f/%.1fms hitch/min=%.1f vision=%.1ffps pose=%.1fms seg=%.1fms comp=%.1fms cap→tex=%.1fms feedback(avg)=%@ dropped=%d mem=%.0fMB thermal=%@ people=%d mask=%@ src=%@",
                     m.renderFPS, m.frameTimeAvgMs, m.frameTimeMaxMs, m.hitchesPerMin, m.visionFPS, m.poseMs, m.segmentationMs,
                     m.compositeMs, m.captureToTextureMs, m.feedbackLatencyAvgMs.map { String(format: "%.0fms", $0) } ?? "n/a",
                     m.droppedCameraFrames, m.memoryMB, m.thermal, m.people, m.maskSize, m.sourceSize)
        print(line)
        fflush(stdout)
        return line
    }
}
