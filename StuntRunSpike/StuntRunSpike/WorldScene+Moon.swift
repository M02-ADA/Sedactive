import AVFoundation
import QuartzCore
import SpriteKit

/// Arcade announcer: short, spaced-out call-outs (built-in speech, no assets). Each line has a cooldown so it never
/// chatters over the players; the music ducks under it.
@MainActor
final class Announcer {
    private let synth = AVSpeechSynthesizer()
    private var lastSaid: [String: Double] = [:]
    private var lastAny = -100.0
    var enabled = UserDefaults.standard.object(forKey: "announcer") == nil || UserDefaults.standard.bool(forKey: "announcer")

    @discardableResult
    func say(_ text: String, now: Double, cooldown: Double = 6, interrupt: Bool = false) -> Bool {
        guard enabled, now - (lastSaid[text] ?? -100) >= cooldown, interrupt || now - lastAny > 1.2 else { return false }
        lastSaid[text] = now
        lastAny = now
        if interrupt { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.53
        u.pitchMultiplier = 1.2
        u.volume = 0.95
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
        return true
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

/// Everything Moonbound needs at runtime (scene extensions cannot store properties).
@MainActor
final class MoonRuntime {
    var config = RaceConfig.fromDefaults()
    lazy var race = MoonRace(config: config)
    var ascents: [Zone: RocketAscent] = [.left: RocketAscent(), .right: RocketAscent()]
    var shownPhase: MoonPhase = .launch
    var cameraAltitude: CGFloat = 0
    var climbRate: CGFloat = 0
    var launchLift: CGFloat = 0
    var launchedAt: Double?
    var cloudBreakDone = false
    var spaceDone = false
    var lastCount: Int?
    var result: RaceResult?
    var finishAt: Double?
    var touchedDown = false
    var finaleDone = false
    var peakDepth: [Zone: Double] = [:]
    var lastSlipCallout: [Zone: Double] = [:]
    var nextBot: [Zone: Double] = [:]
    var bodyHalves: [Zone: SKSpriteNode] = [:]
    var bodyMasks: [Zone: SKSpriteNode] = [:]
    var bodyCrops: [Zone: SKCropNode] = [:]
    var bodyPull: [Zone: CGFloat] = [:]
    var bodyLift: [Zone: CGFloat] = [:]
    var script: MoonScript?
    let announcer = Announcer()
    // HUD.
    var cards: [Zone: SKShapeNode] = [:]
    var cardLabels: [Zone: SKLabelNode] = [:]
    let timerBack = SKSpriteNode(texture: Art.pill)
    let timerLabel = SKLabelNode()
    let phaseLabel = SKLabelNode()
    let track = SKShapeNode()
    var markers: [Zone: SKSpriteNode] = [:]
    let earthIcon = SKSpriteNode(texture: Art.earthDisc)
    let moonIcon = SKSpriteNode(texture: Art.moonDisc)
    var ticks: [SKSpriteNode] = []
    let crown = SKSpriteNode(texture: Art.crown)
    let bannerBack = SKSpriteNode(texture: Art.pill)
    var crownZone: Zone?
}

extension WorldScene {
    private var trackRange: (CGFloat, CGFloat) { (size.height * 0.42, size.height * 0.84) }

    // MARK: - Build

    func buildMoon() {
        let start = CACurrentMediaTime()
        SKTexture.preload(Art.moonTextures) {}
        let world = MoonWorld()
        if worldRoot.parent == nil { addChild(worldRoot) }
        worldRoot.addChild(world.root)
        moon = world
        let rt = moonRuntime
        for zone in Zone.allCases {
            guard let lane = world.lanes[zone] else { continue }
            lane.color = Palette.color(for: zone, swapped: swapped)
            addChild(lane.node)
            // The live body: the camera cutout masked to this player's half, inside their lane (it moves with the
            // rocket). A crop node rather than a sub-texture: sub-textures don't follow SKMutableTexture updates.
            let crop = SKCropNode()
            let mask = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            mask.anchorPoint = .zero
            crop.maskNode = mask
            crop.zPosition = Layer.body
            crop.isHidden = true
            let body = SKSpriteNode(texture: bodyTexture)
            body.anchorPoint = CGPoint(x: 0.5, y: 0)
            crop.addChild(body)
            lane.node.addChild(crop)
            rt.bodyHalves[zone] = body
            rt.bodyMasks[zone] = mask
            rt.bodyCrops[zone] = crop
            // Simulator stand-ins ride the same lane.
            placeholders[zone]?.move(toParent: lane.node)
        }
        // HUD: compact player cards (name + squats; the leader's card wears the crown), a round timer, the vertical
        // Earth → Moon race track between the rockets, and a phase caption.
        for zone in Zone.allCases {
            let card = SKShapeNode(rect: CGRect(x: -120, y: -27, width: 240, height: 54), cornerRadius: 27)
            card.fillColor = Palette.color(for: zone, swapped: swapped)
            card.strokeColor = Palette.deepNavy
            card.lineWidth = 5
            card.zPosition = 5
            hud.addChild(card)
            rt.cards[zone] = card
            let label = SKLabelNode()
            label.verticalAlignmentMode = .center
            label.zPosition = 5.1
            hud.addChild(label)
            rt.cardLabels[zone] = label
            let marker = SKSpriteNode(texture: Art.rocketIcon)
            marker.color = Palette.color(for: zone, swapped: swapped)
            marker.colorBlendFactor = 0.55
            marker.zPosition = 5.3
            hud.addChild(marker)
            rt.markers[zone] = marker
        }
        rt.timerBack.color = Palette.deepNavy
        rt.timerBack.colorBlendFactor = 1
        rt.timerBack.alpha = 0.82
        rt.timerLabel.verticalAlignmentMode = .center
        rt.phaseLabel.verticalAlignmentMode = .center
        rt.track.fillColor = Palette.deepNavy.withAlphaComponent(0.55)
        rt.track.strokeColor = UIColor.white.withAlphaComponent(0.35)
        rt.track.lineWidth = 2
        for phase in [MoonPhase.sky, .upperAtmosphere, .space, .approach] {
            let tick = SKSpriteNode(texture: Art.white)
            tick.alpha = 0.6
            tick.name = "\(phase.rawValue)"
            rt.ticks.append(tick)
        }
        rt.crown.zPosition = 6
        rt.crown.alpha = 0
        // A dark band behind the low banners keeps them readable over the rockets.
        rt.bannerBack.color = Palette.deepNavy
        rt.bannerBack.colorBlendFactor = 1
        rt.bannerBack.alpha = 0
        rt.bannerBack.zPosition = hudNodes.banner.zPosition - 0.5
        hud.addChild(rt.bannerBack)
        for node in [rt.timerBack, rt.timerLabel, rt.phaseLabel, rt.track, rt.earthIcon, rt.moonIcon, rt.crown] + rt.ticks as [SKNode] {
            if node.zPosition == 0 { node.zPosition = 5 }
            hud.addChild(node)
        }
        audio.startMusic()
        gameLog(String(format: "mode: Moonbound race (art %.0f ms; first to the Moon, %.0f full-thrust squats, %.0f s cap)",
                       (CACurrentMediaTime() - start) * 1000, rt.config.goalReps, rt.config.duration))
    }

    func layoutMoon() {
        guard let world = moon else { return }
        let rt = moonRuntime
        world.layout(size: size, proj: proj)
        // The shared HUD's big counters, Team Power and distance belong to the other modes.
        var hidden: [SKNode] = [hudNodes.meterBack, hudNodes.meterFill, hudNodes.meterLabel, hudNodes.distanceLabel, hudNodes.lockRoot]
        for zone in Zone.allCases {
            hidden += [hudNodes.cards[zone], hudNodes.roleLabels[zone], hudNodes.countLabels[zone], hudNodes.comboLabels[zone], hudNodes.statusLabels[zone]].compactMap { $0 }
        }
        hidden.forEach { $0.isHidden = true }
        let top = size.height - 46
        for zone in Zone.allCases {
            let x = zone == .left ? 150 : size.width - 150
            rt.cards[zone]?.position = CGPoint(x: x, y: top)
            rt.cardLabels[zone]?.position = CGPoint(x: x, y: top)
            rt.markers[zone]?.size = CGSize(width: 30, height: 40)
        }
        rt.timerBack.size = CGSize(width: 150, height: 52)
        rt.timerBack.position = CGPoint(x: size.width / 2, y: top)
        rt.timerLabel.position = rt.timerBack.position
        rt.phaseLabel.position = CGPoint(x: size.width / 2, y: top - 52)
        let (y0, y1) = trackRange
        rt.track.path = CGPath(roundedRect: CGRect(x: -7, y: 0, width: 14, height: y1 - y0), cornerWidth: 7, cornerHeight: 7, transform: nil)
        rt.track.position = CGPoint(x: size.width / 2, y: y0)
        rt.earthIcon.size = CGSize(width: 34, height: 34)
        rt.earthIcon.position = CGPoint(x: size.width / 2, y: y0 - 22)
        rt.moonIcon.size = CGSize(width: 38, height: 38)
        rt.moonIcon.position = CGPoint(x: size.width / 2, y: y1 + 24)
        for tick in rt.ticks {
            let phase = MoonPhase(rawValue: Int(tick.name ?? "0") ?? 0) ?? .sky
            tick.size = CGSize(width: 24, height: 2)
            tick.position = CGPoint(x: size.width / 2, y: y0 + (y1 - y0) * CGFloat(phase.start))
        }
        rt.crown.size = CGSize(width: 64, height: 48)
        // Banners sit low (over the rocket hulls), never over the players' faces.
        hudNodes.banner.position = CGPoint(x: size.width / 2, y: size.height * 0.20)
        hudNodes.subBanner.position = CGPoint(x: size.width / 2, y: size.height * 0.20 - 54)
        updateMoonCards()
    }

    // MARK: - Frame

    func updateMoon(dt rawDT: CGFloat, motionDT: CGFloat) {
        guard let world = moon else { return }
        let rt = moonRuntime
        world.root.isHidden = mode != .immersive
        let halted = flow.isHalted
        updateLaunch()
        // Race clock (game time: frozen while halted, so pauses never cost anyone).
        if !halted, rt.result == nil { for e in rt.race.tick(at: gameTime) { raceEvent(e) } }
        // Each rocket eases toward what its player's reps earned (frozen while halted: no phantom movement).
        if !halted {
            for zone in Zone.allCases {
                rt.ascents[zone]?.earn((rt.race.progress[zone] ?? 0) * rt.config.goalReps, goal: rt.config.goalReps)
                rt.ascents[zone]?.step(dt: Double(motionDT), climbTime: rt.config.climbTime)
            }
        }
        let shown = Zone.allCases.map { CGFloat(rt.ascents[$0]?.shown ?? 0) }
        let mean = shown.reduce(0, +) / 2
        let lead = shown.max() ?? 0
        // The world camera rides at the midpoint of the two rockets; each lane shows its own lead as a capped offset.
        let A = CGFloat(RocketAscent.altitude(Double(mean))) + rt.launchLift
        rt.climbRate = rawDT > 0 ? max(0, (A - rt.cameraAltitude) / rawDT) : 0
        rt.cameraAltitude = A
        let maxOffset = size.height * 0.065
        for zone in Zone.allCases {
            guard let lane = world.lanes[zone] else { continue }
            let mine = CGFloat(rt.ascents[zone]?.shown ?? 0)
            let target = maxOffset * tanh((mine - mean) / 0.05)
            lane.raceOffset += (target - lane.raceOffset) * min(1, rawDT * 5)
            lane.slipstream = max(0, lane.slipstream - rawDT * 0.6)
            // Anticipation: the lane charges with the player's squat depth on the way down.
            if let slot = slots[zone] {
                if slot.detector.phase != .standing { rt.peakDepth[zone] = max(rt.peakDepth[zone] ?? 0, slot.detector.depth) }
                let going = [.descending, .down].contains(slot.detector.phase) && !halted
                lane.charge = going ? min(1, CGFloat(slot.detector.depth) * 1.5) : 0
            }
        }
        layoutMoonBodies()
        world.update(dt: motionDT, cameraAltitude: A, climbRate: rt.climbRate, lead: lead, now: now, proj: proj, size: size, reduceMotion: reduceMotion)

        let phase = MoonPhase.at(progress: Double(mean))
        if phase != rt.shownPhase, rt.result == nil, phase != .arrived { announcePhase(phase) }
        if !rt.cloudBreakDone, A > MoonWorld.cloudShellAltitude + 3 { cloudBreak() }
        if !rt.spaceDone, A > 300 { enterSpace() }
        updateMoonHUD(lead: lead)
        updateMoonFinale(dt: Double(rawDT))
        if !halted, rt.result == nil { runMoonBots() }
        let close = rt.race.isRunning && abs(rt.race.gap) < rt.config.closeGap * 1.6 && min(shown[0], shown[1]) > 0.06
        audio.updateMusic(dt: Double(rawDT), intensity: Float(min(1, rt.climbRate / 45 + CGFloat(phase.rawValue) * 0.08)), close: close,
                          sprint: rt.race.sprint && rt.result == nil, engine: Float(min(1, 0.2 + rt.climbRate / 40)), now: now)
        rt.script?.tick(scene: self)
        if let s = rt.script, s.isFinished {
            rt.script = nil
            model?.scriptRunning = false
            model?.autoplay = autoplayBeforeScript
            gameLog("moon script finished")
        }
    }

    /// Live bodies: each player's half of the cutout, pulled horizontally onto their rocket's deck (smoothly), feet on
    /// the deck line; the lane node adds the race offset. The full-frame cutout sprite is not shown in this mode.
    private func layoutMoonBodies() {
        let rt = moonRuntime
        bodySprite.isHidden = true
        let showLive = mode == .immersive && (lastSnapshot?.hasCutout ?? false) && inputSource == .camera
        // Split the camera frame between the two people (midway between their bodies), not at its centre, so a
        // player leaning or squatting across the middle isn't cut in half or shown in the other lane.
        var split: CGFloat = 0.5
        if let l = slots[.left]?.livePose?.centerX, let r = slots[.right]?.livePose?.centerX, slots[.left]?.driver == .live, slots[.right]?.driver == .live {
            split = min(0.8, max(0.2, CGFloat(l + r) / 2))
        }
        let splitX = bodyRect.minX + split * bodyRect.width
        for zone in Zone.allCases {
            guard let body = rt.bodyHalves[zone], let mask = rt.bodyMasks[zone], let crop = rt.bodyCrops[zone], let lane = moon?.lanes[zone] else { continue }
            let live = showLive && slots[zone]?.driver == .live
            crop.isHidden = !live
            guard live, let foot = slots[zone]?.footPoint, foot != .zero else { continue }
            // Each player is grounded on their own deck: pulled across onto the lane and up/down so their own feet
            // (not the other player's) meet the deck line. Smoothed so pose jitter never shakes the body.
            let pull = lane.screenX - foot.x
            let lift = proj.feetY - foot.y
            rt.bodyPull[zone] = (rt.bodyPull[zone] ?? pull) + (pull - (rt.bodyPull[zone] ?? pull)) * 0.25
            rt.bodyLift[zone] = (rt.bodyLift[zone] ?? lift) + (lift - (rt.bodyLift[zone] ?? lift)) * 0.25
            let p = rt.bodyPull[zone] ?? 0, q = rt.bodyLift[zone] ?? 0
            body.size = bodyRect.size
            body.position = CGPoint(x: bodyRect.midX + p, y: bodyRect.minY + q)
            // A lone live player keeps the whole frame (nobody to split from).
            let other: Zone = zone == .left ? .right : .left
            let alone = slots[other]?.driver != .live
            let x0 = zone == .left || alone ? bodyRect.minX : splitX
            let x1 = zone == .right || alone ? bodyRect.maxX : splitX
            mask.position = CGPoint(x: x0 + p, y: bodyRect.minY + q - 400)
            mask.size = CGSize(width: x1 - x0, height: bodyRect.height + 800)
        }
    }

    /// The point above a player's head, including their lane's race offset.
    func moonHead(_ zone: Zone) -> CGPoint {
        let h = slots[zone]?.headPoint ?? .zero
        let lane = moon?.lanes[zone]
        let live = slots[zone]?.driver == .live
        let pull = live ? (moonRuntime.bodyPull[zone] ?? 0) : 0
        let lift = live ? (moonRuntime.bodyLift[zone] ?? 0) : 0
        return CGPoint(x: h.x + pull, y: h.y + lift + (lane?.node.position.y ?? 0))
    }

    // MARK: - Hero moment 1: countdown → clamps release → LIFT-OFF

    private func updateLaunch() {
        let rt = moonRuntime
        if case .countdown(let endsAt) = flow.state, rt.launchedAt == nil {
            let remaining = Int(ceil(endsAt - now))
            if remaining != rt.lastCount, remaining > 0 {
                rt.lastCount = remaining
                audio.play(.countBeep, dB: -4)
                rt.announcer.say(["One", "Two", "Three"][min(2, remaining - 1)], now: now, cooldown: 0.5, interrupt: true)
                for zone in Zone.allCases { moon?.lanes[zone]?.flare = 0.25 * CGFloat(4 - remaining) }   // engines spooling up
            }
        }
        if rt.launchedAt == nil, flow.state == .running {
            rt.launchedAt = gameTime
            rt.race.start(at: gameTime)
            moon?.launchSmoke(cameraAltitude: rt.cameraAltitude, now: now)
            for zone in Zone.allCases { moon?.fire(zone, strength: 1.4, cameraAltitude: rt.cameraAltitude, ppu: proj.ppu(proj.zp), now: now, reduceMotion: reduceMotion) }
            audio.play(.launchRoar, dB: -1)
            audio.duckMusic(for: 1.2, now: now)
            rt.announcer.say("Lift off!", now: now, cooldown: 1, interrupt: true)
            showBanner("LIFT-OFF!", sub: "Squat to fire your rocket — first to the Moon wins!", color: Palette.yellow, hold: 1.8)
            shakeUntil = now + 0.6
            shakeAmplitude = reduceMotion ? 0 : 6
            gameLog("moon: LIFT-OFF — race started (\(Int(rt.config.duration)) s)")
            captureEvent("m-launch", after: 0.35)
        }
        // The clamps swing away and both rockets rise clear of the pad together (equal for both: presentation only).
        if let t0 = rt.launchedAt {
            let k = CGFloat(min(1, (gameTime - t0) / 1.4))
            moon?.clampsOpen = 1 - pow(1 - k, 3)
            rt.launchLift = 2.2 * (1 - pow(1 - k, 2))
        } else {
            moon?.clampsOpen = 0
            rt.launchLift = 0
        }
    }

    // MARK: - Hero moments 2 & 3: through the clouds, into space

    private func cloudBreak() {
        let rt = moonRuntime
        rt.cloudBreakDone = true
        moon?.flash = reduceMotion ? 0.2 : 0.6
        audio.play(.phaseUp, dB: -4)
        audio.duckMusic(for: 1.0, now: now)
        rt.announcer.say("Through the clouds!", now: now)
        showBanner("THROUGH THE CLOUDS!", sub: nil, color: .white, hold: 1.2)
        gameLog("moon: cloud break")
        captureEvent("m-cloud-break", after: 0.6)
    }

    private func enterSpace() {
        let rt = moonRuntime
        rt.spaceDone = true
        audio.play(.phaseUp, dB: -2)
        audio.duckMusic(for: 1.2, now: now)
        rt.announcer.say("Welcome to space!", now: now)
        showBanner("SPACE!", sub: "Look down — that's the Earth!", color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), hold: 1.6)
        gameLog("moon: entered space")
        captureEvent("m-space", after: 0.8)
    }

    private func announcePhase(_ phase: MoonPhase) {
        let rt = moonRuntime
        rt.shownPhase = phase
        rt.phaseLabel.attributedText = arcadeText(phase.title, size: 17, color: phase >= .space ? UIColor(red: 0.7, green: 0.85, blue: 1, alpha: 1) : .white, strokeWidth: -5)
        rt.phaseLabel.run(popAction())
        if phase == .approach {
            showBanner("THE MOON!", sub: "Final stretch — race for the gate!", color: Palette.yellow, hold: 1.4)
            audio.play(.phaseUp, dB: -3)
            rt.announcer.say("There's the Moon!", now: now)
        }
        gameLog(String(format: "moon phase: %@ (camera altitude %.0f units)", phase.title, rt.cameraAltitude))
        captureEvent("m-phase-\(phase.rawValue + 1)-\(phase.title.lowercased().replacingOccurrences(of: " ", with: "-"))", after: 0.9)
    }

    // MARK: - Squat → propulsion

    /// DESCENT → the rocket charges and compresses (continuous, from depth) · BOTTOM → primed · STAND UP (rep) →
    /// IGNITION, THRUST, the lane kicks up and settles, the world climbs · shallow → a sputter, no thrust.
    func handleMoon(_ event: SquatEvent, zone: Zone) {
        let rt = moonRuntime
        switch event {
        case .descentStarted:
            rt.peakDepth[zone] = 0
        case .bottomReached:
            moon?.lanes[zone]?.band.run(.sequence([.fadeAlpha(to: 1, duration: 0.05), .fadeAlpha(to: 0.85, duration: 0.3)]))
            audio.play(.tick, dB: -14)
        case .repCompleted:
            guard rt.race.isRunning else { return }
            thrust(zone)
        case .aborted:
            guard rt.race.isRunning else { return }
            moon?.sputter(zone, cameraAltitude: rt.cameraAltitude, ppu: proj.ppu(proj.zp), now: now)
            popRating(zone, text: "A BIT LOWER!", color: Palette.yellow, at: moonHead(zone))
            gameLog("moon: \(role(for: zone)) shallow squat — sputter, no thrust")
        default:
            break
        }
    }

    private func thrust(_ zone: Zone) {
        let rt = moonRuntime
        let before = rt.race.progress[zone] ?? 0
        let events = rt.race.rep(zone, at: gameTime)
        guard case .boost(_, let gain, let catchUp, let pace)? = events.first else { return }
        // Feedback strength follows the actual thrust (so a slipstream boost looks bigger, a rushed rep smaller).
        let strength = CGFloat(gain * rt.config.goalReps)
        moon?.fire(zone, strength: strength, cameraAltitude: rt.cameraAltitude, ppu: proj.ppu(proj.zp), now: now, reduceMotion: reduceMotion)
        audio.play(.thrust, dB: -3 + Float(min(2, (strength - 1) * 4)))
        let peak = rt.peakDepth[zone] ?? 0
        let head = moonHead(zone)
        // Quality from the depth the detector measured (simulator-proven only; needs iPad validation).
        popRating(zone, text: pace < 0.95 ? "STEADY!" : (peak >= 0.72 ? "PERFECT!" : "GOOD!"), color: pace < 0.95 ? .white : (peak >= 0.72 ? Palette.yellow : .white), at: CGPoint(x: head.x, y: head.y + 40))
        floatText("+1", color: Palette.color(for: zone, swapped: swapped), at: CGPoint(x: head.x + 70, y: head.y))
        if catchUp > 0.12 {
            moon?.lanes[zone]?.slipstream = 1
            if now - (rt.lastSlipCallout[zone] ?? -100) > 7 {
                rt.lastSlipCallout[zone] = now
                floatText("SLIPSTREAM +\(Int(catchUp * 100))%", color: UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1), at: CGPoint(x: head.x, y: head.y + 90))
            }
        }
        updateMoonCards()
        gameLog(String(format: "moon: %@ rep → thrust %.3f (slipstream +%.0f%%, pace ×%.2f): %.3f → %.3f", role(for: zone), gain, catchUp * 100, pace, before, rt.race.progress[zone] ?? 0))
        captureEvent("m-thrust-\(role(for: zone))", after: 0.12)
        for e in events.dropFirst() { raceEvent(e) }
    }

    // MARK: - Race events: lead changes, neck and neck, final sprint, finish

    private func raceEvent(_ event: RaceEvent) {
        let rt = moonRuntime
        switch event {
        case .boost:
            break
        case .leadChange(let zone):
            let first = rt.crownZone == nil
            moveCrown(to: zone)
            updateMoonCards()
            if !first {
                popRating(zone, text: "OVERTAKE!", color: Palette.color(for: zone, swapped: swapped), at: CGPoint(x: moonHead(zone).x, y: moonHead(zone).y + 80))
                audio.play(.overtake, dB: -3)
                rt.announcer.say("\(role(for: zone).capitalized) takes the lead!", now: now, cooldown: 8)
                captureEvent("m-overtake-\(role(for: zone))", after: 0.3)
            }
            gameLog("moon: LEAD → \(role(for: zone))")
        case .neckAndNeck:
            showBanner("NECK AND NECK!", sub: nil, color: UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1), hold: 1.0)
            rt.announcer.say("Neck and neck!", now: now, cooldown: 10)
            gameLog("moon: neck and neck")
            captureEvent("m-neck-and-neck", after: 0.3)
        case .finalSprint:
            showBanner("FINAL SPRINT!", sub: nil, color: VaultPalette.laser, hold: 1.2)
            audio.play(.sprintHorn, dB: -4)
            audio.duckMusic(for: 0.8, now: now)
            rt.announcer.say("Final sprint!", now: now, cooldown: 30, interrupt: true)
            gameLog("moon: FINAL SPRINT (\(Int(rt.race.timeLeft(at: gameTime))) s left)")
            captureEvent("m-final-sprint", after: 0.4)
        case .finished(let result):
            finishRace(result)
        }
    }

    private func moveCrown(to zone: Zone) {
        let rt = moonRuntime
        let target = moonHead(zone)
        let to = CGPoint(x: target.x, y: target.y + 50)
        rt.crown.removeAllActions()
        if rt.crownZone == nil || reduceMotion {
            rt.crown.position = to
            rt.crown.run(.fadeIn(withDuration: 0.2))
        } else {
            // The crown hops across on an arc to the new leader.
            let from = rt.crown.position
            rt.crown.run(.customAction(withDuration: 0.45) { node, t in
                let x = t / 0.45
                let e = 1 - pow(1 - x, 3)
                node.position = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e + sin(.pi * x) * 90)
                node.zRotation = sin(.pi * x * 2) * 0.3
            })
        }
        rt.crownZone = zone
    }

    private func finishRace(_ result: RaceResult) {
        let rt = moonRuntime
        rt.result = result
        rt.finishAt = gameTime
        let winner = result.winner
        moon?.flash = reduceMotion ? 0.3 : 1
        audio.play(.victory, dB: -1)
        audio.duckMusic(for: 3, now: now)
        let photo = result.margin < 0.03
        if let w = winner {
            let color = Palette.color(for: w, swapped: swapped)
            showBanner("\(role(for: w)) WINS!", sub: result.reason == .moon ? (photo ? "Photo finish at the Moon!" : "First to the Moon!") : "Highest when the time ran out!", color: color, hold: 4)
            rt.announcer.say("\(role(for: w).capitalized) wins!", now: now, cooldown: 1, interrupt: true)
            moveCrown(to: w)
            moon?.lanes[w]?.kickVelocity += 380
            for b in 0..<(reduceMotion ? 1 : 5) {
                run(.wait(forDuration: Double(b) * 0.22)) { [weak self] in
                    guard let self else { return }
                    let p = CGPoint(x: self.moonHead(w).x + CGFloat.random(in: -160...160), y: self.size.height * CGFloat.random(in: 0.6...0.85))
                    self.burstSparks(at: p, color: [color, Palette.yellow, .white][b % 3], count: 14)
                }
            }
            let loser: Zone = w == .left ? .right : .left
            run(.wait(forDuration: 1.6)) { [weak self] in
                guard let self else { return }
                self.popRating(loser, text: "GREAT RACE!", color: .white, at: CGPoint(x: self.moonHead(loser).x, y: self.moonHead(loser).y + 40))
            }
        } else {
            showBanner("DEAD HEAT!", sub: "You reached the Moon together!", color: Palette.yellow, hold: 4)
            rt.announcer.say("It's a tie!", now: now, cooldown: 1, interrupt: true)
        }
        let p = rt.race.reps[swapped ? .right : .left] ?? 0, c = rt.race.reps[swapped ? .left : .right] ?? 0
        gameLog(String(format: "moon: FINISH — %@ (%@, margin %.3f); squats P %d · C %d", winner.map { role(for: $0) } ?? "DEAD HEAT",
                       result.reason == .moon ? "first to the Moon" : "time cap", result.margin, p, c))
        captureEvent("m-finish-a-winner", after: 0.5)
    }

    private func updateMoonFinale(dt: Double) {
        let rt = moonRuntime
        guard let t0 = rt.finishAt, let world = moon else { return }
        let k = gameTime - t0
        // Both rockets fly on to the Moon: it swings down past the decks (over its limb), a landing burn, touchdown.
        world.moonSlide = CGFloat(min(1, max(0, (k - 2.0) / 1.6)))
        for zone in Zone.allCases where !rt.touchedDown {
            // Everyone finishes the trip (the race result is already decided): the rockets' climbs complete.
            rt.ascents[zone]?.earn(1, goal: 1)
        }
        if k >= 3.6, world.landingAltitude == nil {
            world.flash = 1
            world.landingAltitude = 40
            gameLog("moon: landing burn")
            captureEvent("m-finish-b-landing", after: 0.9)
        }
        if k >= 3.6, !rt.touchedDown {
            let x = min(1, (k - 3.6) / 3.0)
            world.landingAltitude = CGFloat(40 * pow(1 - x, 2.2))
            for zone in Zone.allCases where (world.lanes[zone]?.flare ?? 0) < 0.6 {
                world.fire(zone, strength: 0.35, cameraAltitude: world.landingAltitude ?? 0, ppu: proj.ppu(proj.zp), now: now, reduceMotion: true)
            }
            if x >= 1 {
                rt.touchedDown = true
                world.landingAltitude = 0
                audio.play(.touchdown, dB: -2)
                shakeUntil = now + 0.3
                shakeAmplitude = reduceMotion ? 0 : 5
                let p = rt.race.reps[swapped ? .right : .left] ?? 0, c = rt.race.reps[swapped ? .left : .right] ?? 0
                showBanner("TOUCHDOWN!", sub: "Parent \(p) squats · Child \(c) squats", color: Palette.yellow, hold: 4)
                if let w = rt.result?.winner { moveCrown(to: w) }
                gameLog("moon: TOUCHDOWN")
                captureEvent("m-finish-c-touchdown", after: 1.0)
            }
        }
        if rt.touchedDown { world.landingAltitude = 0 }
        if k > 12, !rt.finaleDone {
            rt.finaleDone = true
            gameLog("moon: race complete")
            if let script = rt.script { script.finished(scene: self) } else { replay(source: "moon race complete") }
        }
    }

    // MARK: - HUD

    private func updateMoonHUD(lead: CGFloat) {
        let rt = moonRuntime
        let (y0, y1) = trackRange
        for zone in Zone.allCases {
            let p = CGFloat(rt.ascents[zone]?.shown ?? 0)
            rt.markers[zone]?.position = CGPoint(x: size.width / 2 + (zone == .left ? -20 : 20), y: y0 + (y1 - y0) * p)
        }
        // Timer: calm white; red and pulsing in the final sprint.
        let left = rt.race.startedAt == nil ? rt.config.duration : rt.race.timeLeft(at: gameTime)
        let sprint = rt.race.sprint && rt.result == nil
        let secs = Int(ceil(left))
        rt.timerLabel.attributedText = arcadeText(rt.result != nil ? "FINISH" : String(format: "%d:%02d", secs / 60, secs % 60), size: 28,
                                                  color: sprint ? VaultPalette.laser : .white, strokeWidth: -5)
        rt.timerBack.setScale(sprint && !reduceMotion ? 1 + 0.06 * abs(sin(CGFloat(now) * 4)) : 1)
        rt.bannerBack.position = CGPoint(x: size.width / 2, y: hudNodes.banner.position.y - 4)
        rt.bannerBack.size = CGSize(width: min(size.width * 0.9, hudNodes.banner.frame.width + 120), height: 150)
        rt.bannerBack.alpha = hudNodes.banner.alpha * 0.55
        // The crown follows the leader's head (it rides the lane).
        if let z = rt.crownZone, !rt.crown.hasActions() {
            let h = moonHead(z)
            rt.crown.position = CGPoint(x: h.x, y: h.y + 50 + (reduceMotion ? 0 : sin(CGFloat(now) * 3) * 4))
        }
    }

    private func updateMoonCards() {
        let rt = moonRuntime
        for zone in Zone.allCases {
            let leading = rt.crownZone == zone
            rt.cardLabels[zone]?.attributedText = arcadeText("\(role(for: zone))  \(rt.race.reps[zone] ?? 0)", size: 24, color: .white, strokeWidth: -5)
            rt.cards[zone]?.run(.scale(to: leading ? 1.08 : 0.94, duration: 0.2))
            rt.cards[zone]?.alpha = leading ? 1 : 0.85
            rt.cardLabels[zone]?.setScale(leading ? 1.08 : 0.94)
        }
    }

    // MARK: - Simulated players (autoplay): calm, controlled reps at slightly different paces

    private func runMoonBots() {
        let rt = moonRuntime
        guard rt.script == nil, model?.autoplay == true, flow.state == .running else { return }
        for zone in Zone.allCases {
            guard var slot = slots[zone], slot.driver == .simulated, now - slot.lastManualSim > 20 else { continue }
            if rt.nextBot[zone] == nil { rt.nextBot[zone] = gameTime + (zone == .left ? 0.8 : 1.4) }
            if gameTime >= rt.nextBot[zone]!, slot.sim == nil {
                slot.sim = SimulatedSquat(start: gameTime)
                slots[zone] = slot
                rt.nextBot[zone] = gameTime + Double.random(in: zone == .left ? 2.2...3.2 : 2.4...3.4)
            }
        }
    }

    // MARK: - Halt, replay, script, debug

    func withdrawMoon() {
        for lane in moon?.lanes.values.map({ $0 }) ?? [] { lane.charge = 0 }
    }

    func resetMoon() {
        let rt = moonRuntime
        rt.race = MoonRace(config: rt.config)
        rt.ascents = [.left: RocketAscent(), .right: RocketAscent()]
        rt.shownPhase = .launch
        rt.cameraAltitude = 0
        rt.launchLift = 0
        rt.launchedAt = nil
        rt.cloudBreakDone = false
        rt.spaceDone = false
        rt.lastCount = nil
        rt.result = nil
        rt.finishAt = nil
        rt.touchedDown = false
        rt.finaleDone = false
        rt.peakDepth = [:]
        rt.nextBot = [:]
        rt.crownZone = nil
        rt.crown.removeAllActions()
        rt.crown.alpha = 0
        rt.phaseLabel.attributedText = arcadeText(MoonPhase.launch.title, size: 17, color: .white, strokeWidth: -5)
        moon?.landingAltitude = nil
        moon?.moonSlide = 0
        for lane in moon?.lanes.values.map({ $0 }) ?? [] { lane.raceOffset = 0; lane.kick = 0; lane.kickVelocity = 0; lane.flare = 0 }
        updateMoonCards()
    }

    func startMoonScript() {
        let rt = moonRuntime
        if rt.script == nil { autoplayBeforeScript = model?.autoplay ?? false }
        rt.script = MoonScript()
        model?.scriptRunning = true
        model?.autoplay = false
        for zone in Zone.allCases { slots[zone]?.simLost = false }
        replay(source: "moon script start")
    }

    func toggleMoonDebug() {
        guard let world = moon else { return }
        world.debugOn.toggle()
        gameLog("moon: ascent debug \(world.debugOn ? "on" : "off")")
    }

    /// Scripted squat with an explicit depth profile and timing (scripts only; the same detector judges it).
    func scriptedSquat(_ zone: Zone, peak: Double = 0.85, hold: Double = 0.25, down: Double = 0.45, up: Double = 0.5) {
        guard var slot = slots[zone], slot.driver != .live, !slot.simLost else { return }
        slot.sim = SimulatedSquat(start: gameTime, peak: peak, downDuration: down, holdDuration: hold, upDuration: up)
        slots[zone] = slot
    }
}

/// Deterministic Moonbound race script. Squats run on the game clock (frozen while halted); halts use real time.
/// Simulated input through the real squat detector — never evidence of real tracking accuracy.
@MainActor
final class MoonScript {
    struct Squat { var at: Double; var zone: Zone; var peak = 0.85; var hold = 0.25; var down = 0.45; var up = 0.5 }
    struct Step {
        var name: String
        var length: Double
        var squats: [Squat] = []
        var control: Control = .none
    }
    enum Control { case none, pause(at: Double, resume: Double), loseTracking(Zone, at: Double, recover: Double, resume: Double), raceToFinish }

    static let steps: [Step] = [
        Step(name: "PARENT squat → Parent's rocket fires and climbs; Child's unchanged", length: 2.6, squats: [Squat(at: 0.3, zone: .left)]),
        Step(name: "CHILD squat → slipstream catch-up (level again)", length: 2.6, squats: [Squat(at: 0.3, zone: .right)]),
        Step(name: "BOTH squat together → both rockets climb", length: 2.6, squats: [Squat(at: 0.3, zone: .left), Squat(at: 0.4, zone: .right)]),
        Step(name: "PARENT shallow squat → sputter, no thrust", length: 2.4, squats: [Squat(at: 0.3, zone: .left, peak: 0.35)]),
        Step(name: "CHILD holds a squat 5 s → exactly one thrust, on standing", length: 7.2, squats: [Squat(at: 0.3, zone: .right, hold: 5)]),
        Step(name: "PARENT rapid reps (every 1.0 s) → reduced thrust on the rushed ones", length: 4.8,
             squats: (0..<4).map { Squat(at: 0.3 + Double($0) * 1.0, zone: .left, hold: 0.1, down: 0.4, up: 0.4) }),
        Step(name: "CHILD squat, then PAUSE mid-climb → frozen; resume", length: 4.5, squats: [Squat(at: 0.3, zone: .right)], control: .pause(at: 1.75, resume: 2.0)),
        Step(name: "PARENT tracking lost → halt → READY → resume (no progress lost)", length: 3.5, control: .loseTracking(.left, at: 0.5, recover: 2.0, resume: 1.5)),
        Step(name: "Race to the finish: Child faster, then Parent faster, then both flat out → lead changes, sprint, winner",
             length: 0, control: .raceToFinish),
        Step(name: "new race: both rockets reset; PARENT squat → fresh counters", length: 3.0, squats: [Squat(at: 0.6, zone: .left)]),
    ]

    private(set) var index = -1
    private var stepStart = 0.0
    private var fired = Set<Int>()
    private var timers: [(fireAt: Double, real: Bool, action: (WorldScene) -> Void)] = []
    private var racing = false
    private var nextRep: [Zone: Double] = [:]
    var isFinished: Bool { index >= Self.steps.count }

    func finished(scene: WorldScene) {
        guard racing else { return }
        racing = false
        scene.replay(source: "moon script (after the finish)")
        index += 1
        begin(scene: scene, delay: SessionFlow.countdownDuration + 0.8)
    }

    private func begin(scene: WorldScene, delay: Double = 0) {
        stepStart = scene.gameTime + delay
        fired = []
        guard index < Self.steps.count else { return }
        let step = Self.steps[index]
        scene.gameLog("moon script step \(index + 1)/\(Self.steps.count): \(step.name)")
        switch step.control {
        case .pause(let at, let resume):
            schedule(at: stepStart + at, real: false) { scene in
                scene.pauseGame(source: "moon script")
                self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "moon script") }
            }
        case .loseTracking(let zone, let at, let recover, let resume):
            schedule(at: stepStart + at, real: false) { scene in
                scene.setSimulatedTrackingLost(zone, lost: true)
                self.schedule(at: scene.now + recover + 0.6, real: true) { scene in
                    scene.setSimulatedTrackingLost(zone, lost: false)
                    self.schedule(at: scene.now + resume, real: true) { $0.resumeGame(source: "moon script") }
                }
            }
        case .raceToFinish:
            racing = true
            nextRep = [.left: stepStart + 0.4, .right: stepStart + 0.2]
        case .none:
            break
        }
    }

    func tick(scene: WorldScene) {
        if index < 0 {
            guard scene.flow.state == .running else { return }
            index = 0
            begin(scene: scene, delay: 0.8)
        }
        let due = timers.enumerated().filter { $0.element.fireAt <= ($0.element.real ? scene.now : scene.gameTime) }
        if !due.isEmpty {
            timers = timers.enumerated().filter { item in !due.contains { $0.offset == item.offset } }.map(\.element)
            for item in due { item.element.action(scene) }
        }
        guard index < Self.steps.count, scene.flow.state == .running else { return }
        let step = Self.steps[index]
        let t = scene.gameTime - stepStart
        for (i, s) in step.squats.enumerated() where t >= s.at && !fired.contains(i) {
            fired.insert(i)
            scene.scriptedSquat(s.zone, peak: s.peak, hold: s.hold, down: s.down, up: s.up)
        }
        if case .raceToFinish = step.control {
            guard racing, scene.moonRuntime.result == nil else { return }
            // Child leads the first 12 s, the Parent the next 12 s, then both flat out (but never frantic: ≥ 1.6 s).
            let phase = t < 12 ? 0 : (t < 24 ? 1 : 2)
            let interval: [Zone: Double] = phase == 0 ? [.left: 2.8, .right: 1.9] : (phase == 1 ? [.left: 1.7, .right: 2.9] : [.left: 1.75, .right: 1.8])
            for zone in Zone.allCases where scene.gameTime >= (nextRep[zone] ?? 0) {
                scene.scriptedSquat(zone)
                nextRep[zone] = scene.gameTime + interval[zone]!
            }
            return
        }
        if t >= step.length, timers.isEmpty {
            index += 1
            if index < Self.steps.count { begin(scene: scene) } else { scene.gameLog("moon script: all steps done") }
        }
    }

    private func schedule(at time: Double, real: Bool, _ action: @escaping (WorldScene) -> Void) {
        timers.append((time, real, action))
    }
}
