import SpriteKit

/// Laser Breakout's heist presentation layer: set pieces (vault door, bulkheads, lockdown gate, city reveal), the
/// security drone, live-body lanes, the escape HUD and camera choreography. Gameplay rules stay in LaserLogic.
@MainActor
final class HeistRuntime {
    enum DroneMood { case hidden, patrol, suspicious, alert, annoyed, smug, panic }
    enum Reaction { case warning, armed, zapped, teamDodge, perfectSplit }

    /// Extra cart speed multiplier (vault opener holds the cart, the lockdown gate brakes it, team slow-mo).
    var speedMul: CGFloat = 0
    var slowUntil = 0.0
    var failFlash: CGFloat = 0
    var dodges: [Zone: Int] = [:]

    // Vault door (Phase A opener).
    let vaultFrame = SKSpriteNode(texture: Art.bulkhead)
    let vaultDoor = SKSpriteNode(texture: Art.vaultDoorBody)
    let vaultWheel = SKSpriteNode(texture: Art.vaultWheel)
    var vaultBolts: [SKSpriteNode] = []
    var vaultDistance: CGFloat = 0
    var vaultStart: Double?

    // Structure streaming past.
    var bulkheads: [SKSpriteNode] = []

    // Lockdown gate (Phase C hero moment).
    var override: DualOverride?
    var overrideStartDistance: CGFloat = 0
    var overrideStoppedAt: Double?
    var overrideOpenedAt: Double?
    let gateHalves = [SKSpriteNode(texture: Art.lockGateHalf), SKSpriteNode(texture: Art.lockGateHalf)]
    var dials: [Zone: SKSpriteNode] = [:]
    var dialSpin: [Zone: CGFloat] = [:]
    var handles: [Zone: SKSpriteNode] = [:]
    var handleDrop: CGFloat = 0

    // Security checkpoint (cover panels, scanners) and the calm after a breach.
    var checkpoint: CheckpointState?
    var safeUntil = 0.0
    /// Brief light on each body (laser pass, success, spotted).
    var light: [Zone: (color: UIColor, amount: CGFloat, at: Double)] = [:]
    /// Each live player's standing nose height (world units), remembered while they stand: beams and cover are set
    /// from it, so someone who is mid-squat when a gate appears still gets a beam they can duck under.
    var standingRef: [Zone: CGFloat] = [:]

    // The way out.
    let skyline = SKSpriteNode(texture: Art.citySkyline)

    // Security drone.
    let drone = SKNode()
    let droneBody = SKSpriteNode(texture: Art.droneBody)
    let droneEye = SKSpriteNode(texture: Art.droneEye)
    let dronePupil = SKSpriteNode(texture: Art.dronePupil)
    let droneLid = SKSpriteNode(texture: Art.droneLid)
    var rotors: [SKSpriteNode] = []
    var mood: DroneMood = .hidden
    var moodUntil = 0.0
    var droneShow: CGFloat = 0
    var droneFlee: CGFloat = 0

    // Live bodies (one crop per player, grounded in their lane).
    var crops: [Zone: SKCropNode] = [:]
    var bodies: [Zone: SKSpriteNode] = [:]
    var masks: [Zone: SKSpriteNode] = [:]
    var pull: [Zone: CGFloat] = [:]
    var lift: [Zone: CGFloat] = [:]

    // HUD.
    let track = SKShapeNode()
    let trackFill = SKSpriteNode(texture: Art.pill)
    let vaultIcon = SKSpriteNode(texture: Art.vaultDoorBody)
    let exitIcon = SKSpriteNode(texture: Art.exitSign)
    let diamondMarker = SKSpriteNode(texture: Art.diamond)
    var pips: [SKSpriteNode] = []
    let alertCaption = SKLabelNode()
    var cards: [Zone: SKShapeNode] = [:]
    var cardLabels: [Zone: SKLabelNode] = [:]
    let bannerBack = SKSpriteNode(texture: Art.pill)
    var progress: CGFloat = 0

    /// Cart speed factor: the set-piece multiplier, with a short slow-motion beat after a team dodge.
    func cartSpeed(gameTime: Double) -> CGFloat { speedMul * (gameTime < slowUntil ? 0.35 : 1) }
}

extension WorldScene {
    // MARK: - Build / layout

    func buildHeist() {
        let rt = laserRuntime, h = rt.heist
        SKTexture.preload(Art.heistTextures) {}
        guard let root = laser?.root else { return }
        // Vault door set (in the world, fixed to the corridor ahead of the cart at the start).
        for node in [h.vaultFrame, h.vaultDoor, h.vaultWheel] { root.addChild(node) }
        h.vaultFrame.anchorPoint = CGPoint(x: 0.5, y: 0)
        h.vaultFrame.colorBlendFactor = 0.3
        h.vaultFrame.color = VaultPalette.cyan
        for _ in 0..<12 {
            let b = SKSpriteNode(texture: Art.vaultBolt)
            root.addChild(b)
            h.vaultBolts.append(b)
        }
        for _ in 0..<5 {
            let b = SKSpriteNode(texture: Art.bulkhead)
            b.anchorPoint = CGPoint(x: 0.5, y: 0)
            b.colorBlendFactor = 0.2
            root.addChild(b)
            h.bulkheads.append(b)
        }
        for (i, half) in h.gateHalves.enumerated() {
            half.anchorPoint = CGPoint(x: i == 0 ? 1 : 1, y: 0)
            half.xScale = i == 0 ? 1 : -1
            half.isHidden = true
            root.addChild(half)
        }
        for zone in Zone.allCases {
            let d = SKSpriteNode(texture: Art.lockDial)
            d.colorBlendFactor = 0.6
            d.isHidden = true
            root.addChild(d)
            h.dials[zone] = d
            let handle = SKSpriteNode(texture: Art.pullHandle)
            handle.anchorPoint = CGPoint(x: 0.5, y: 1)
            handle.zPosition = 2
            handle.isHidden = true
            addChild(handle)
            h.handles[zone] = handle
        }
        h.skyline.anchorPoint = CGPoint(x: 0.5, y: 0)
        h.skyline.isHidden = true
        root.addChild(h.skyline)   // camera-frame backdrop at the corridor's far end (see updateSkyline)

        // Drone: hovers ahead in the corridor (between and behind the players' heads), flies with the cart.
        for node in [h.droneBody, h.droneEye, h.dronePupil, h.droneLid] { h.drone.addChild(node) }
        h.droneEye.position = CGPoint(x: 0, y: -2)
        h.droneEye.zPosition = 0.1
        h.dronePupil.zPosition = 0.2
        h.dronePupil.colorBlendFactor = 1
        h.droneLid.zPosition = 0.3
        for side in [-1.0, 1.0] as [CGFloat] {
            let r = SKSpriteNode(texture: Art.droneRotor)
            r.position = CGPoint(x: side * 76, y: 36)
            r.zPosition = 0.4
            h.drone.addChild(r)
            h.rotors.append(r)
        }
        h.drone.zPosition = -400
        h.drone.alpha = 0
        addChild(h.drone)

        // Live bodies: the camera cutout masked to each player's side, grounded in their lane.
        for zone in Zone.allCases {
            let crop = SKCropNode()
            let mask = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            mask.anchorPoint = .zero
            crop.maskNode = mask
            crop.zPosition = Layer.body
            crop.isHidden = true
            let body = SKSpriteNode(texture: bodyTexture)
            body.anchorPoint = CGPoint(x: 0.5, y: 0)
            crop.addChild(body)
            addChild(crop)
            h.crops[zone] = crop; h.bodies[zone] = body; h.masks[zone] = mask
        }

        // HUD: one escape track (vault → exit, the diamond is you), alert pips, compact cards, a low banner band.
        h.track.fillColor = Palette.deepNavy.withAlphaComponent(0.7)
        h.track.strokeColor = UIColor.white.withAlphaComponent(0.3)
        h.track.lineWidth = 2
        h.trackFill.color = VaultPalette.cyan
        h.trackFill.colorBlendFactor = 1
        h.trackFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        for _ in 0..<5 {
            let p = SKSpriteNode(texture: Art.pill)
            p.colorBlendFactor = 1
            h.pips.append(p)
        }
        h.alertCaption.attributedText = arcadeText("ALERT", size: 13, color: VaultPalette.laser, strokeWidth: -4)
        h.alertCaption.horizontalAlignmentMode = .right
        h.alertCaption.verticalAlignmentMode = .center
        for zone in Zone.allCases {
            let card = SKShapeNode(rect: CGRect(x: -110, y: -24, width: 220, height: 48), cornerRadius: 24)
            card.fillColor = Palette.color(for: zone, swapped: swapped)
            card.strokeColor = Palette.deepNavy
            card.lineWidth = 5
            h.cards[zone] = card
            let label = SKLabelNode()
            label.verticalAlignmentMode = .center
            h.cardLabels[zone] = label
        }
        h.bannerBack.color = Palette.deepNavy
        h.bannerBack.colorBlendFactor = 1
        h.bannerBack.alpha = 0
        var hudParts: [SKNode] = [h.track, h.trackFill, h.vaultIcon, h.exitIcon, h.diamondMarker, h.alertCaption, h.bannerBack] + h.pips
        hudParts += Zone.allCases.compactMap { h.cards[$0] } + Zone.allCases.compactMap { h.cardLabels[$0] }
        for node in hudParts { node.zPosition = 5; hud.addChild(node) }
        h.trackFill.zPosition = 5.1
        h.diamondMarker.zPosition = 5.3
        h.bannerBack.zPosition = hudNodes.banner.zPosition - 0.5
        for zone in Zone.allCases { h.cardLabels[zone]?.zPosition = 5.2 }
        audio.startMusic(style: .heist)
        resetHeist()
    }

    func layoutHeist() {
        let h = laserRuntime.heist
        // The shared HUD's big counters, Team Power, the team lock and the old alert bar give way to the escape HUD.
        var hidden: [SKNode] = [hudNodes.meterBack, hudNodes.meterFill, hudNodes.meterLabel, hudNodes.distanceLabel, hudNodes.lockRoot,
                                laserRuntime.alertBack, laserRuntime.alertFill, laserRuntime.alertLabel]
        for zone in Zone.allCases {
            hidden += [hudNodes.cards[zone], hudNodes.roleLabels[zone], hudNodes.countLabels[zone], hudNodes.comboLabels[zone], hudNodes.statusLabels[zone]].compactMap { $0 }
        }
        hidden.forEach { $0.isHidden = true }
        let top = size.height - 40
        let w: CGFloat = 400
        h.track.path = CGPath(roundedRect: CGRect(x: -w / 2, y: -9, width: w, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil)
        h.track.position = CGPoint(x: size.width / 2, y: top)
        h.trackFill.position = CGPoint(x: size.width / 2 - w / 2 + 3, y: top)
        h.vaultIcon.size = CGSize(width: 40, height: 40)
        h.vaultIcon.position = CGPoint(x: size.width / 2 - w / 2 - 30, y: top)
        h.exitIcon.size = CGSize(width: 66, height: 22)
        h.exitIcon.position = CGPoint(x: size.width / 2 + w / 2 + 42, y: top)
        h.diamondMarker.size = CGSize(width: 34, height: 29)
        for (i, p) in h.pips.enumerated() {
            p.size = CGSize(width: 34, height: 12)
            p.position = CGPoint(x: size.width / 2 - 70 + CGFloat(i) * 40, y: top - 28)
        }
        h.alertCaption.position = CGPoint(x: size.width / 2 - 96, y: top - 28)
        laserRuntime.phaseLabel.position = CGPoint(x: size.width / 2, y: top - 56)
        for zone in Zone.allCases {
            let x = zone == .left ? 140 : size.width - 140
            h.cards[zone]?.position = CGPoint(x: x, y: top)
            h.cardLabels[zone]?.position = CGPoint(x: x, y: top)
        }
        // Banners sit high over the ceiling, never over faces; the drone hovers between the players.
        hudNodes.banner.position = CGPoint(x: size.width / 2, y: size.height * 0.80)
        hudNodes.subBanner.position = CGPoint(x: size.width / 2, y: size.height * 0.80 - 50)
        updateHeistCards()
    }

    // MARK: - Frame

    func updateHeist(dt: CGFloat, motionDT: CGFloat) {
        let rt = laserRuntime, h = rt.heist
        updateVault()
        updateBulkheads()
        updateOverride(dt: dt)
        updateCheckpoint(dt: dt)
        updateSkyline()
        updateDrone(dt: dt)
        layoutHeistBodies()
        // Floor threat lanes in the shader (what is coming, per lane) and the patrol spotlights.
        if let shader = laser?.shader {
            var threat = SIMD4<Float>(0, 0, 0, 0)
            if let g = rt.leadGate, g.revealed {
                let z = g.depth(rt.timing)
                let fadeOut = max(0, min(1, (z - Corridor.playerZ) / 1.2))
                func type(_ zone: Zone) -> Float { g.pattern.action(for: zone) == .duck ? 1 : 2 }
                threat = SIMD4(type(.left), type(.right), Float(z), Float(min(1, (g.t - rt.timing.revealTime) / 0.6) * fadeOut))
            }
            shader.uniformNamed("u_threat")?.vectorFloat4Value = threat
            shader.uniformNamed("u_spots")?.floatValue = rt.finaleAt == nil && rt.phase != nil ? 1 : 0.25
        }
        // Camera: push in a touch while a gate closes in, pull back for the lockdown gate reveal, otherwise neutral.
        var fov: CGFloat = 1
        if let g = rt.leadGate, g.armed {
            let z = CGFloat(g.depth(rt.timing))
            if z > 2.2, z < 9 { fov = 0.95 }
        }
        if let opened = h.overrideOpenedAt, gameTime - opened < 2.2 { fov = 1.07 }
        if reduceMotion { fov = 1 }
        rt.fov = fov
        updateHeistHUD()
        hudNodes.lockRoot.isHidden = true   // per-lane feedback replaces the shared team-lock counter here
        // Score: the drive follows the alarm, the spy riff comes in while a beam is armed, the lockdown carries the
        // sprint layer; after the override everything but the riff falls away (release before the escape).
        let lockdown = rt.phase == .lockdown || (h.override != nil && h.overrideOpenedAt == nil)
        let armed = rt.leadGate?.armed ?? false
        audio.updateMusic(dt: Double(dt), intensity: Float(rt.finaleAt != nil ? 0 : 0.2 + rt.alarm * 0.6), close: armed || lockdown,
                          sprint: lockdown && rt.finaleAt == nil, engine: Float(0.15 + 0.5 * min(1, worldSpeed / laserCruise)), now: now)
    }

    // MARK: - Phase A: the vault door opens, then the cart launches

    func startVaultOpen() {
        let h = laserRuntime.heist
        h.vaultStart = gameTime
        audio.play(.servo, dB: -4)
        showBanner("THE DIAMOND IS OURS!", sub: "Now get out — the vault is opening!", color: VaultPalette.gold, hold: 1.8)
        gameLog("laser: vault door opening")
        captureEvent("l-vault-a-opening", after: 0.9)
    }

    private func updateVault() {
        let rt = laserRuntime, h = rt.heist
        let z = 6.5 - (distance - h.vaultDistance)
        let visible = z > 0.4 && z < 60
        // Opening choreography on the game clock: wheel spins (anticipation) → bolts retract → the door rolls aside.
        let k = h.vaultStart.map { CGFloat(gameTime - $0) } ?? 0
        let spin = smoothstep(0, 0.9, k) * 1.5 * 2 * .pi
        let bolts = smoothstep(0.6, 1.1, k)
        let roll = smoothstep(1.1, 2.3, k)
        if h.vaultStart != nil, k >= 1.1, k - CGFloat(1.0 / 60) < 1.1 { audio.play(.doorSlam, dB: -6) }
        let ppu = proj.ppu(max(z, 0.3))
        let depth = proj.depthZ(z)
        h.vaultFrame.position = proj.screen(x: 0, h: CGFloat(Corridor.floorH), z: z)
        h.vaultFrame.setScale(ppu / 100)
        h.vaultFrame.zPosition = depth - 0.2
        let cx = roll * 2.4
        let centre = proj.screen(x: cx, h: 0.975, z: z)
        h.vaultDoor.position = centre
        h.vaultDoor.setScale(ppu * 2.6 / 260)
        h.vaultDoor.zRotation = -roll * 1.4
        h.vaultDoor.zPosition = depth - 0.1
        h.vaultWheel.position = centre
        h.vaultWheel.setScale(ppu * 1.3 / 160)
        h.vaultWheel.zRotation = spin - roll * 1.4
        h.vaultWheel.zPosition = depth - 0.05
        for (i, b) in h.vaultBolts.enumerated() {
            let a = CGFloat(i) / 12 * 2 * .pi - roll * 1.4
            let r = 1.32 - 0.22 * bolts
            b.position = proj.screen(x: cx + cos(a) * r, h: 0.975 + sin(a) * r, z: z)
            b.setScale(ppu * 0.4 / 40)
            b.zRotation = a
            b.zPosition = depth - 0.15
        }
        for node in [h.vaultFrame, h.vaultDoor, h.vaultWheel] + h.vaultBolts as [SKNode] { node.isHidden = !visible }
        // The door rolls into its wall pocket: it disappears as it passes the wall line (no door floating outside).
        let pocket = 1 - smoothstep(0.55, 0.85, roll)
        for node in [h.vaultDoor, h.vaultWheel] + h.vaultBolts as [SKNode] { node.alpha = pocket }
        // The cart waits for the door, then launches (and the beat hands over to the alarm).
        if rt.beat == .vaultOpen {
            if k > 2.0 {
                h.speedMul = min(1, h.speedMul + CGFloat(1.0 / 60) / 1.2)
                if k > 2.6 {
                    rt.beat = nil
                    rt.nextBeatAt = gameTime + 0.2
                    showBanner("GO! GO! GO!", sub: nil, color: VaultPalette.cyan, hold: 0.8)
                    gameLog("laser: vault open — cart launches")
                    captureEvent("l-vault-b-open", after: 0.1)
                }
            }
        } else if h.vaultStart == nil {
            h.speedMul = 0
        } else if h.override == nil {
            h.speedMul = min(1, h.speedMul + CGFloat(1.0 / 60) / 1.2)
        }
    }

    private func updateBulkheads() {
        let rt = laserRuntime, h = rt.heist
        let spacing: CGFloat = 9
        let phase = distance.truncatingRemainder(dividingBy: spacing)
        for (i, b) in h.bulkheads.enumerated() {
            let z = spacing * CGFloat(i + 1) - phase + 3
            let visible = z > 1.3 && z < 48 && rt.finaleAt == nil
            b.isHidden = !visible
            guard visible else { continue }
            b.position = proj.screen(x: 0, h: CGFloat(Corridor.floorH), z: z)
            b.setScale(proj.ppu(z) / 100)
            b.zPosition = proj.depthZ(z) - 0.3
            b.color = rt.alarm > 0.3 ? VaultPalette.laser : VaultPalette.cyan
            b.colorBlendFactor = 0.12 + 0.18 * rt.alarm
            b.alpha = min(1, (48 - z) / 10)
        }
    }

    // MARK: - Phase C: the lockdown gate (dual security override)

    func startOverride() {
        let rt = laserRuntime, h = rt.heist
        h.override = DualOverride(participants: Set(activeZones()))
        h.overrideStartDistance = distance
        h.overrideStoppedAt = nil
        h.overrideOpenedAt = nil
        h.handleDrop = 0
        for zone in Zone.allCases { h.dialSpin[zone] = 0; h.dials[zone]?.color = VaultPalette.laser }
        for half in h.gateHalves { half.isHidden = false }
        for zone in Zone.allCases { h.dials[zone]?.isHidden = false }
        showBanner("LOCKDOWN GATE!", sub: "The final door is sealing — get ready!", color: VaultPalette.laser, hold: 1.8)
        audio.play(.siren, dB: -3)
        setDroneMood(.alert, for: 99)
        gameLog("laser: lockdown gate ahead (participants \(h.override?.participants.count ?? 0))")
        captureEvent("l-override-a-gate", after: 1.0)
    }

    private func updateOverride(dt: CGFloat) {
        let rt = laserRuntime, h = rt.heist
        guard let o = h.override else {
            guard h.checkpoint == nil else { return }   // the checkpoint uses the same gate and locks
            for half in h.gateHalves { half.isHidden = true }
            for zone in Zone.allCases { h.dials[zone]?.isHidden = true; h.handles[zone]?.isHidden = true }
            return
        }
        let z = max(5.5, 30 - (distance - h.overrideStartDistance))
        // The cart brakes into the gate: speed eases out to a stop 5.5 units before it.
        if h.overrideOpenedAt == nil {
            h.speedMul = min(h.speedMul, max(0, min(1, (z - 5.5) / 9)))
            if z <= 5.6, h.overrideStoppedAt == nil {
                h.overrideStoppedAt = gameTime
                showBanner("PULL THE LEVERS!", sub: "Arms up — squat to pull your lever down (2 pulls each)", color: VaultPalette.gold, hold: 2.4)
                audio.play(.servo, dB: -3)
                gameLog("laser: override — levers down, waiting for both players")
                captureEvent("l-override-b-levers", after: 0.8)
            }
        }
        let open = h.overrideOpenedAt.map { CGFloat(smoothstep(0, 1.4, CGFloat(gameTime - $0))) } ?? 0
        let ppu = proj.ppu(z)
        let depth = proj.depthZ(z)
        for (i, half) in h.gateHalves.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            half.position = proj.screen(x: side * open * 2.1, h: CGFloat(Corridor.floorH), z: z)
            half.setScale(ppu / 100)
            half.xScale = (ppu / 100) * (i == 0 ? 1 : -1)
            half.zPosition = depth - 0.1
        }
        for zone in Zone.allCases {
            guard let dial = h.dials[zone], let handle = h.handles[zone] else { continue }
            let side: CGFloat = zone == .left ? -1 : 1
            dial.position = proj.screen(x: side * (1.0 + open * 2.1), h: 1.25, z: z)
            dial.setScale(ppu * 1.0 / 100)
            dial.zPosition = depth
            let depthNow = CGFloat(slots[zone]?.detector.depth ?? 0)
            let target = (h.dialSpin[zone] ?? 0) + depthNow * 0.6
            dial.zRotation += (target - dial.zRotation) * min(1, dt * 10)
            // The handle hangs over the player's lane; their squat pulls it down (the lever follows their body).
            let laneX = proj.screen(x: CGFloat(Corridor.laneX(zone)), h: 0, z: proj.zp).x
            let waiting = h.overrideStoppedAt != nil && h.overrideOpenedAt == nil && o.participants.contains(zone) && !o.unlocked.contains(zone)
            h.handleDrop += ((waiting ? 1 : 0) - h.handleDrop) * min(1, dt * 4)
            handle.isHidden = h.handleDrop < 0.02 && !waiting
            handle.setScale(size.height * 0.36 / 220)
            let pullDown = waiting ? depthNow * size.height * 0.14 : 0
            handle.position = CGPoint(x: laneX, y: size.height + 30 - h.handleDrop * size.height * 0.08 - pullDown)
            handle.alpha = waiting ? 1 : max(0, handle.alpha - dt * 3)
        }
        // Assist: if nobody can finish (e.g. one player stepped away), the drone's panic opens it after 18 s.
        if let stopped = h.overrideStoppedAt, h.overrideOpenedAt == nil, gameTime - stopped > 18 { openOverride(assisted: true) }
        if let opened = h.overrideOpenedAt {
            h.speedMul = min(1, max(h.speedMul, CGFloat((gameTime - opened - 0.8) / 1.5)))
            if gameTime - opened > 2.4, rt.beat == .override {
                rt.beat = nil
                rt.nextBeatAt = gameTime + 0.3
                h.override = nil
            }
        }
        // Autoplay: simulated agents crank at a calm pace.
        if model?.autoplay == true, rt.script == nil, h.overrideStoppedAt != nil, h.overrideOpenedAt == nil {
            for zone in o.participants where !o.unlocked.contains(zone) {
                guard var slot = slots[zone], slot.driver == .simulated, slot.sim == nil, Double.random(in: 0...1) < 0.03 else { continue }
                slot.sim = SimulatedSquat(start: gameTime)
                slots[zone] = slot
            }
        }
    }

    /// A completed rep during the lockdown: that player's lever pulls once and their lock dial turns a third.
    func crankOverride(_ zone: Zone) {
        let h = laserRuntime.heist
        guard h.overrideStoppedAt != nil, h.overrideOpenedAt == nil, var o = h.override else { return }
        let events = o.crank(zone)
        h.override = o
        for e in events {
            switch e {
            case .crank(let z, let n):
                h.dialSpin[z, default: 0] -= 2 * .pi / 3
                h.dials[z]?.color = VaultPalette.gold
                audio.play(.clunk, dB: -3)
                burstSparks(at: h.dials[z]?.position ?? .zero, color: VaultPalette.gold, count: 6)
                floatText("LOCK \(n)/\(o.cranksNeeded)", color: Palette.color(for: z, swapped: swapped), at: CGPoint(x: (h.handles[z]?.position.x ?? 0), y: size.height * 0.62))
                gameLog("laser: override — \(role(for: z)) cranks (\(n)/\(o.cranksNeeded))")
            case .unlocked(let z):
                h.dials[z]?.color = UIColor(red: 0.3, green: 0.95, blue: 0.5, alpha: 1)
                audio.play(.chime, dB: -4)
                popRating(z, text: "UNLOCKED!", color: UIColor(red: 0.3, green: 0.95, blue: 0.5, alpha: 1), at: slots[z]?.headPoint ?? .zero)
                setDroneMood(.annoyed, for: 1.2)
                gameLog("laser: override — \(role(for: z))'s lock released")
                captureEvent("l-override-c-unlock-\(role(for: z))", after: 0.2)
            case .open:
                openOverride(assisted: false)
            }
        }
    }

    private func openOverride(assisted: Bool) {
        let rt = laserRuntime, h = rt.heist
        guard h.overrideOpenedAt == nil else { return }
        h.overrideOpenedAt = gameTime
        rt.phase = nil                    // alarms down: the lights calm to cyan
        rt.flash = reduceMotion ? 0.4 : 1
        audio.play(.hydraulic, dB: -2)
        audio.play(.alarmOff, dB: -4)
        audio.play(.team, dB: -3)
        showBanner(assisted ? "OVERRIDE HACKED!" : "SECURITY OVERRIDE!", sub: assisted ? "The drone fried the lock — go!" : "Both locks released — the gate is opening!",
                   color: VaultPalette.cyan, hold: 1.8)
        setDroneMood(.panic, for: 99)
        addTeamPower(2)
        gameLog("laser: override — GATE OPEN\(assisted ? " (assisted after 18 s)" : "")")
        captureEvent("l-override-d-open", after: 0.7)
    }

    // MARK: - The way out

    private func updateSkyline() {
        let rt = laserRuntime, h = rt.heist
        // The way out: the night city fills the far end of the corridor as the exit opens, and stays as the agents
        // burst out into it (the corridor's own exit light glows around it).
        let show = max(rt.finaleAt != nil ? 1 : 0, laser?.doors.map { $0.mode == .exit ? min(1, $0.open * 1.5) : 0 } ?? 0)
        h.skyline.isHidden = show <= 0.01
        guard !h.skyline.isHidden else { return }
        let grow: CGFloat = rt.finaleAt.map { CGFloat(min(1, (gameTime - $0) / 3)) } ?? 0
        h.skyline.position = CGPoint(x: proj.cx, y: proj.horizonY - size.height * (0.10 + 0.12 * grow))
        h.skyline.setScale(size.width * (0.42 + 0.6 * grow) / 800)
        h.skyline.zPosition = Layer.floor + 5
        h.skyline.alpha = show
    }

    // MARK: - The security drone

    func setDroneMood(_ mood: HeistRuntime.DroneMood, for seconds: Double) {
        let h = laserRuntime.heist
        guard h.mood != .panic || mood == .hidden else { return }
        h.mood = mood
        h.moodUntil = gameTime + seconds
        if mood == .annoyed || mood == .smug { audio.play(.droneChirp, dB: -8) }
    }

    func heistReact(_ reaction: HeistRuntime.Reaction) {
        let h = laserRuntime.heist
        switch reaction {
        case .warning: setDroneMood(.suspicious, for: 99)
        case .armed: setDroneMood(.alert, for: 99)
        case .zapped:
            h.failFlash = reduceMotion ? 0.4 : 1
            setDroneMood(.smug, for: 1.1)
        case .teamDodge, .perfectSplit:
            setDroneMood(.annoyed, for: 1.3)
            if !reduceMotion { h.slowUntil = gameTime + (reaction == .perfectSplit ? 0.5 : 0.35) }
        }
    }

    private func updateDrone(dt: CGFloat) {
        let rt = laserRuntime, h = rt.heist
        if h.mood != .hidden, h.mood != .panic, gameTime > h.moodUntil { h.mood = rt.leadGate?.armed == true ? .alert : .patrol }
        if rt.phase != nil, h.mood == .hidden { h.mood = .patrol }
        let shown: CGFloat = h.mood == .hidden ? 0 : 1
        h.droneShow += (shown - h.droneShow) * min(1, dt * 2)
        if h.mood == .panic { h.droneFlee = min(1, h.droneFlee + dt * 0.6) }
        let t = CGFloat(now)
        let sway = reduceMotion ? 0 : sin(t * 0.7) * 50
        var x = size.width / 2 + sway
        var y = size.height * 0.66 + (1 - h.droneShow) * size.height * 0.4
        var rot: CGFloat = 0
        var scale: CGFloat = size.height * 0.11 / 150
        var iris = VaultPalette.cyan
        var lid: CGFloat = 0.15
        switch h.mood {
        case .hidden, .patrol: break
        case .suspicious: iris = VaultPalette.gold; lid = 0.45
        case .alert: iris = VaultPalette.laser; lid = 0.05; scale *= 1.06
        case .annoyed:
            iris = VaultPalette.laser; lid = 0.55
            if !reduceMotion { x += sin(t * 60) * 7; rot = sin(t * 30) * 0.06 }
        case .smug:
            iris = VaultPalette.laser.mixed(with: VaultPalette.gold, amount: 0.4); lid = 0.5
            if !reduceMotion { y += abs(sin(t * 9)) * 14 }
        case .panic:
            iris = .white; lid = 0
            if !reduceMotion { rot = t * 9 }
            x += h.droneFlee * size.width * 0.6
            y += h.droneFlee * size.height * 0.5
        }
        if !reduceMotion { y += sin(t * 2.3) * 6 }
        h.drone.position = CGPoint(x: x, y: y)
        h.drone.setScale(scale)
        h.drone.zRotation += (rot - h.drone.zRotation) * min(1, dt * 8)
        h.drone.alpha = h.droneShow * (1 - h.droneFlee)
        // The eye tracks whoever must act next (the lane of the incoming beam), else scans.
        var look = CGPoint(x: reduceMotion ? 0 : sin(t * 1.3) * 12, y: -4)
        if let g = rt.leadGate, g.revealed, let enc = g.encounter, let target = enc.participants.sorted(by: { $0 == .left && $1 == .right }).first(where: { enc.results[$0] == nil }) {
            look = CGPoint(x: target == .left ? -14 : 14, y: -10)
        }
        h.dronePupil.position = CGPoint(x: h.dronePupil.position.x + (look.x - h.dronePupil.position.x) * min(1, dt * 10),
                                        y: h.dronePupil.position.y + (look.y - h.dronePupil.position.y) * min(1, dt * 10))
        h.dronePupil.color = iris
        h.droneLid.position = CGPoint(x: 0, y: -2 + 40 * (1 - 2 * lid))
        for (i, r) in h.rotors.enumerated() { r.xScale = reduceMotion ? 1 : 0.6 + 0.4 * abs(sin(t * 40 + CGFloat(i))) }
    }

    // MARK: - Live bodies: each agent in their own lane, feet on the cart

    private func layoutHeistBodies() {
        let h = laserRuntime.heist
        let showLive = mode == .immersive && (lastSnapshot?.hasCutout ?? false) && inputSource == .camera
        if showLive { bodySprite.isHidden = true }
        var split: CGFloat = 0.5
        if let l = slots[.left]?.livePose?.centerX, let r = slots[.right]?.livePose?.centerX, slots[.left]?.driver == .live, slots[.right]?.driver == .live {
            split = min(0.8, max(0.2, CGFloat(l + r) / 2))
        }
        let splitX = bodyRect.minX + split * bodyRect.width
        for zone in Zone.allCases {
            guard let crop = h.crops[zone], let body = h.bodies[zone], let mask = h.masks[zone] else { continue }
            let live = showLive && slots[zone]?.driver == .live
            crop.isHidden = !live
            guard live, let foot = slots[zone]?.footPoint, foot != .zero else { continue }
            let laneX = proj.screen(x: CGFloat(Corridor.laneX(zone)), h: 0, z: proj.zp).x
            let p0 = laneX - foot.x, q0 = proj.feetY - foot.y
            h.pull[zone] = (h.pull[zone] ?? p0) + (p0 - (h.pull[zone] ?? p0)) * 0.25
            // Grounding follows the feet only while they are on the deck: during a jump the offset holds, so the real
            // body rises off the cart (and over a low beam) instead of being pulled back down to the floor.
            let jumping = (slots[zone]?.jump.isAirborne ?? false) || abs(slots[zone]?.jump.lift ?? 0) > 0.05
            if !jumping, slots[zone]?.detector.phase == .standing, let span = slots[zone]?.livePose?.standingSpan {
                let current = CGFloat(span) * bodyRect.height / proj.ppu(proj.zp)
                // Follows the tallest recent standing height; drifts down slowly (a player stepping back gets smaller).
                h.standingRef[zone] = max(current, (h.standingRef[zone] ?? current) - 0.02 / 60)
            }
            if !jumping || h.lift[zone] == nil { h.lift[zone] = (h.lift[zone] ?? q0) + (q0 - (h.lift[zone] ?? q0)) * 0.25 }
            let p = h.pull[zone] ?? 0, q = h.lift[zone] ?? 0
            body.size = bodyRect.size
            body.position = CGPoint(x: bodyRect.midX + p, y: bodyRect.minY + q)
            if let tint = laserBodyTint(zone) { body.color = tint.0; body.colorBlendFactor = tint.1 } else { body.colorBlendFactor = 0 }
            let other: Zone = zone == .left ? .right : .left
            let alone = slots[other]?.driver != .live
            let x0 = zone == .left || alone ? bodyRect.minX : splitX
            let x1 = zone == .right || alone ? bodyRect.maxX : splitX
            mask.position = CGPoint(x: x0 + p, y: bodyRect.minY + q - 400)
            mask.size = CGSize(width: x1 - x0, height: bodyRect.height + 800)
        }
    }

    // MARK: - HUD

    private func updateHeistHUD() {
        let rt = laserRuntime, h = rt.heist
        // Escape progress: beats played of the getaway (the diamond travels from the vault to the exit).
        let beats = CGFloat(max(1, rt.director.beats.count))
        let target: CGFloat = rt.finaleAt != nil ? 1 : CGFloat(rt.director.index) / beats
        h.progress += (target - h.progress) * 0.05
        let w: CGFloat = 400
        h.trackFill.size = CGSize(width: max(1, (w - 6) * h.progress), height: 12)
        h.diamondMarker.position = CGPoint(x: size.width / 2 - w / 2 + w * h.progress, y: h.track.position.y)
        // Alert: five pips (it's the facility getting angrier, never a fail state).
        let lit = Int((rt.alert.level * 5).rounded(.up))
        for (i, p) in h.pips.enumerated() {
            let on = i < lit
            p.color = on ? VaultPalette.laser : Palette.deepNavy
            p.alpha = on ? (lit >= 4 && !reduceMotion ? 0.7 + 0.3 * abs(sin(CGFloat(now) * 6)) : 1) : 0.6
        }
        h.bannerBack.position = CGPoint(x: size.width / 2, y: hudNodes.banner.position.y - 6)
        h.bannerBack.size = CGSize(width: min(size.width * 0.9, hudNodes.banner.frame.width + 120), height: 140)
        h.bannerBack.alpha = hudNodes.banner.alpha * 0.55
        updateHeistCards()
    }

    private func updateHeistCards() {
        let h = laserRuntime.heist
        for zone in Zone.allCases {
            h.cardLabels[zone]?.attributedText = arcadeText("\(role(for: zone))  ✓\(h.dodges[zone] ?? 0)", size: 21, color: .white, strokeWidth: -5)
        }
    }

    // MARK: - Reset

    func resetHeist() {
        let h = laserRuntime.heist
        h.speedMul = 0
        h.slowUntil = 0
        h.failFlash = 0
        h.dodges = [:]
        h.vaultDistance = distance
        h.vaultStart = nil
        h.override = nil
        h.overrideStoppedAt = nil
        h.overrideOpenedAt = nil
        h.handleDrop = 0
        h.mood = .hidden
        h.droneShow = 0
        h.droneFlee = 0
        h.progress = 0
        laserRuntime.fov = 1
    }
}
