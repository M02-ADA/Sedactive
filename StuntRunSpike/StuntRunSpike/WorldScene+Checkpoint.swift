import SpriteKit
import UIKit

// Laser Breakout — real-body interaction: where each player's body is actually drawn (live cutout or stand-in), body
// lighting, and the security checkpoint (cover panels, tracking scanners, two locks, the breach).

/// A ceiling scanner that tracks one player: housing, a light cone to an aim point, and a lock reticle.
@MainActor
final class ScannerRig {
    let node = SKNode()
    let housing = SKSpriteNode(texture: Art.securityCamera)
    let cone = SKShapeNode()
    let reticle = SKShapeNode()
    let ticks = SKShapeNode()
    let status = SKLabelNode()
    /// Smoothed aim (screen). Tracking speed is capped so the scanner is predictable and can be out-run by hiding.
    var aim: CGPoint = .zero
    var lock: CGFloat = 0

    init() {
        cone.blendMode = .add
        cone.lineWidth = 0
        reticle.fillColor = .clear
        reticle.lineWidth = 3
        ticks.lineWidth = 3
        housing.anchorPoint = CGPoint(x: 0.5, y: 1)
        status.verticalAlignmentMode = .center
        for (i, n) in [cone, reticle, ticks, housing, status].enumerated() { n.zPosition = CGFloat(i) * 0.01; node.addChild(n) }
    }
}

/// One checkpoint in progress.
@MainActor
final class CheckpointState {
    var startDistance: CGFloat = 0
    var stoppedAt: Double?
    var openedAt: Double?
    var breached = false
    var scanIndex = 0
    var scan: CoverScan?
    var cued = false
    var participants: Set<Zone> = []
    var panels: [Zone: SKSpriteNode] = [:]
    var scanners: [Zone: ScannerRig] = [:]
    /// Screen y of each panel's top edge, fixed when the cart stops (from that player's standing height).
    var panelTop: [Zone: CGFloat] = [:]
    var concealed: [Zone: Bool] = [:]
    var unlocked: Set<Zone> = []
    var nodes: [SKNode] { Array(panels.values) + scanners.values.map(\.node) }
}

extension Art {
    /// Cover panel: an armoured plate that rises from the cart's front rail (120 × 160 pt, hazard band on top).
    static let coverPanel = drawnHi(CGSize(width: 120, height: 160), scale: 2) { ctx, size in
        let body = UIBezierPath(roundedRect: CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6), cornerRadius: 8)
        VaultPalette.metal.setFill(); body.fill()
        ctx.saveGState(); body.addClip()
        for k in stride(from: -2, to: 12, by: 1) {
            let p = UIBezierPath()
            let x = CGFloat(k) * 16
            p.move(to: CGPoint(x: x, y: 3)); p.addLine(to: CGPoint(x: x + 14, y: 3)); p.addLine(to: CGPoint(x: x + 30, y: 19)); p.addLine(to: CGPoint(x: x + 16, y: 19)); p.close()
            (k % 2 == 0 ? VaultPalette.gold : VaultPalette.ink).setFill(); p.fill()
        }
        VaultPalette.metalLight.setFill(); ctx.fill(CGRect(x: 10, y: 30, width: size.width - 20, height: 6))
        VaultPalette.navy.setFill()
        for y in stride(from: CGFloat(50), to: size.height - 16, by: 22) { ctx.fill(CGRect(x: 16, y: y, width: size.width - 32, height: 8)) }
        ctx.restoreGState()
        VaultPalette.ink.setStroke(); body.lineWidth = 5; body.stroke()
        UIColor.white.withAlphaComponent(0.5).setFill()
        for (x, y) in [(12.0, 28.0), (size.width - 16, 28), (12, size.height - 16), (size.width - 16, size.height - 16)] as [(CGFloat, CGFloat)] {
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 5, height: 5))
        }
    }
}

extension WorldScene {
    // MARK: - Where the body really is

    /// Screen position of the player's body as drawn: a live cutout is shifted into its lane (pull/lift), a stand-in is
    /// drawn at its lane (raised when it jumps).
    func displayedCrownY(_ zone: Zone) -> CGFloat? {
        guard let slot = slots[zone] else { return nil }
        let h = laserRuntime.heist
        if slot.driver == .live {
            guard slot.headPoint != .zero, let lift = h.lift[zone] else { return nil }
            let nose = slot.headPoint.y - 30 + lift
            return nose + CGFloat(Corridor.crownShare) * standingNoseH(zone) * proj.ppu(proj.zp)
        }
        guard slot.driver == .simulated else { return nil }
        return slot.headPoint.y - 40     // the stand-in's top (it already includes its jump)
    }

    func displayedFeetY(_ zone: Zone) -> CGFloat? {
        guard let slot = slots[zone] else { return nil }
        if slot.driver == .live {
            guard slot.footPoint != .zero, let lift = laserRuntime.heist.lift[zone] else { return nil }
            return slot.footPoint.y + lift
        }
        guard slot.driver == .simulated else { return nil }
        return slot.footPoint.y + max(0, CGFloat(slot.jump.lift)) * 1.4 * proj.ppu(proj.zp)
    }

    /// Height above the deck (world units, players' plane) of the crown / the soles, from the body as drawn.
    func bodyCrownH(_ zone: Zone) -> CGFloat? { displayedCrownY(zone).map { ($0 - proj.feetY) / proj.ppu(proj.zp) } }
    func bodyFeetH(_ zone: Zone) -> CGFloat? { displayedFeetY(zone).map { ($0 - proj.feetY) / proj.ppu(proj.zp) } }

    /// Standing nose height (world units) of the body as drawn: from the live pose's standing span, or measured off
    /// the stand-in sprite (its top is the crown).
    func standingNoseH(_ zone: Zone) -> CGFloat {
        guard let slot = slots[zone] else { return 1 }
        let ppu = proj.ppu(proj.zp)
        if slot.driver == .live {
            if let ref = laserRuntime.heist.standingRef[zone] { return max(0.6, ref) }
            if let span = slot.livePose?.standingSpan { return max(0.6, CGFloat(span) * bodyRect.height / ppu) }
        }
        if let p = placeholders[zone], p.size.height > 10 { return p.size.height / ppu / CGFloat(1 + Corridor.crownShare) }
        return ((zone == .right) != swapped) ? 0.82 : 1.18
    }

    // MARK: - Body lighting

    /// A brief light on a player's body (laser passing close: white; success: cyan; hit or spotted: red).
    func bodyLight(_ zone: Zone, _ color: UIColor, _ amount: CGFloat) {
        laserRuntime.heist.light[zone] = (color, amount, now)
    }

    /// Current tint for a body (subtle: the cutout must still look like the player). Called by the player visuals.
    func laserBodyTint(_ zone: Zone) -> (UIColor, CGFloat)? {
        guard gameMode == .laserBreakout else { return nil }
        let h = laserRuntime.heist
        var best: (UIColor, CGFloat) = (.white, 0)
        if let l = h.light[zone] {
            let k = CGFloat(max(0, 1 - (now - l.at) / 0.45))
            if l.amount * k > 0.01 { best = (l.color, l.amount * k) }
        }
        // A scanner locked on: a red wash that breathes (none while hidden).
        if let s = h.checkpoint?.scanners[zone], s.lock > 0.05, h.checkpoint?.concealed[zone] != true, h.checkpoint?.openedAt == nil {
            let red = (0.12 + (reduceMotion ? 0 : 0.06 * sin(CGFloat(now) * 8))) * s.lock
            if red > best.1 { best = (VaultPalette.laser, red) }
        }
        return best.1 > 0.01 ? best : nil
    }

    // MARK: - Security checkpoint

    func startCheckpoint() {
        let rt = laserRuntime, h = rt.heist
        let cp = CheckpointState()
        cp.startDistance = distance
        cp.participants = Set(activeZones())
        h.checkpoint = cp
        for half in h.gateHalves { half.isHidden = false }
        for zone in Zone.allCases {
            h.dialSpin[zone] = 0
            h.dials[zone]?.isHidden = false
            h.dials[zone]?.color = VaultPalette.laser
            let panel = SKSpriteNode(texture: Art.coverPanel)
            panel.anchorPoint = CGPoint(x: 0.5, y: 0)
            panel.isHidden = true
            laser?.root.addChild(panel)
            cp.panels[zone] = panel
            let rig = ScannerRig()
            rig.node.alpha = 0
            laser?.root.addChild(rig.node)
            cp.scanners[zone] = rig
        }
        showBanner("SECURITY CHECKPOINT!", sub: "Scanners ahead — hide behind your cover", color: VaultPalette.laser, hold: 2.0)
        audio.play(.siren, dB: -6)
        setDroneMood(.alert, for: 99)
        gameLog("laser: checkpoint ahead (participants \(cp.participants.count))")
        captureEvent("l-checkpoint-a-ahead", after: 1.0)
    }

    /// Every frame while a checkpoint is up (called from updateHeist).
    func updateCheckpoint(dt: CGFloat) {
        let rt = laserRuntime, h = rt.heist
        guard let cp = h.checkpoint else { return }
        let z = max(5.5, 30 - (distance - cp.startDistance))
        if cp.openedAt == nil {
            h.speedMul = min(h.speedMul, max(0, min(1, (z - 5.5) / 9)))
            if z <= 5.6, cp.stoppedAt == nil { checkpointStopped(cp) }
        }
        let k = cp.stoppedAt.map { gameTime - $0 } ?? -1
        let open = cp.openedAt.map { CGFloat(smoothstep(0, 1.4, CGFloat(gameTime - $0))) } ?? 0
        // The sealed gate and its two locks (one per player).
        let ppu = proj.ppu(z), depth = proj.depthZ(z)
        for (i, half) in h.gateHalves.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            half.isHidden = false
            half.position = proj.screen(x: side * open * 2.1, h: CGFloat(Corridor.floorH), z: z)
            half.setScale(ppu / 100)
            half.xScale = (ppu / 100) * (i == 0 ? 1 : -1)
            half.zPosition = depth - 0.1
        }
        for zone in Zone.allCases {
            guard let dial = h.dials[zone] else { continue }
            let side: CGFloat = zone == .left ? -1 : 1
            dial.isHidden = false
            dial.position = proj.screen(x: side * (1.0 + open * 2.1), h: 1.25, z: z)
            dial.setScale(ppu / 100)
            dial.zPosition = depth
            dial.zRotation += ((h.dialSpin[zone] ?? 0) - dial.zRotation) * min(1, dt * 8)
        }
        layoutCoverAndScanners(cp, k: k, dt: dt)
        guard let stopped = cp.stoppedAt, cp.openedAt == nil else {
            if let opened = cp.openedAt { finishCheckpointIfDone(cp, sinceOpen: gameTime - opened) }
            return
        }
        _ = stopped
        // Scans: cue → window → result; one rescan; then the gate opens either way.
        let window = CheckpointTiming.scanWindow(cp.scanIndex)
        let cueAt = window.start - (CheckpointTiming.scanStart - CheckpointTiming.cueAt)
        if !cp.cued, k >= cueAt {
            cp.cued = true
            cp.scan = CoverScan(participants: cp.participants, start: window.start, end: window.end)
            showBanner("HIDE!", sub: "Squat behind your panel — stay down until the scan ends", color: VaultPalette.laser, hold: 1.4, size: 56)
            for zone in cp.participants { showCue(zone, up: false) }
            audio.play(.laserWarn, dB: -5, variant: cp.scanIndex == 0 ? 0 : 1)
            rt.script?.checkpointCued(cp.scanIndex, scene: self)
            planCheckpointBots(cp)
            gameLog("laser: checkpoint scan \(cp.scanIndex + 1) — HIDE! (scan in \(String(format: "%.1f", window.start - k)) s)")
            captureEvent("l-checkpoint-b-hide-\(cp.scanIndex + 1)", after: 0.8)
        }
        if var scan = cp.scan {
            if k >= window.start, k - Double(dt) < window.start {
                audio.play(.sweepScan, dB: -4)
                audio.play(.chargeHigh, dB: -10)
                captureEvent("l-checkpoint-c-scanning-\(cp.scanIndex + 1)", after: 0.7)
            }
            scan.update(at: k, concealed: cp.concealed)
            cp.scan = scan
            if scan.isDone(at: k) { resolveCheckpointScan(cp, scan) }
        }
    }

    private func checkpointStopped(_ cp: CheckpointState) {
        cp.stoppedAt = gameTime
        // Each panel's top edge sits at 80 % of that player's standing height: head and shoulders show above it
        // standing, a real squat drops the head behind it.
        for zone in Zone.allCases {
            let standingCrown = standingNoseH(zone) * CGFloat(1 + Corridor.crownShare)
            cp.panelTop[zone] = proj.feetY + 0.8 * standingCrown * proj.ppu(proj.zp)
        }
        audio.play(.hydraulic, dB: -6)
        audio.play(.deploy, dB: -6)
        gameLog(String(format: "laser: checkpoint — cart stopped; cover tops at P %.2f / C %.2f units (80%% of standing height)",
                       Double(((cp.panelTop[.left] ?? 0) - proj.feetY) / proj.ppu(proj.zp)), Double(((cp.panelTop[.right] ?? 0) - proj.feetY) / proj.ppu(proj.zp))))
        captureEvent("l-checkpoint-b0-deployed", after: 1.4)
    }

    /// Panels in front of the players (drawn over their bodies, so a squat is genuinely hidden), scanners overhead
    /// tracking each player's real head at a capped speed.
    private func layoutCoverAndScanners(_ cp: CheckpointState, k: Double, dt: CGFloat) {
        let ppuP = proj.ppu(proj.zp)
        let panelZ: CGFloat = 1.55
        let opened = cp.openedAt.map { CGFloat(gameTime - $0) } ?? -1
        for zone in Zone.allCases {
            guard let panel = cp.panels[zone], let rig = cp.scanners[zone] else { continue }
            let side: CGFloat = zone == .left ? -1 : 1
            let laneX = proj.screen(x: CGFloat(Corridor.laneX(zone)), h: 0, z: proj.zp).x
            // Panel: rises out of the cart's front rail (overshoot, settle), retracts after the breach.
            let up = cp.stoppedAt == nil ? 0 : easeBack(CGFloat(min(1, max(0, k / 0.6))))
            let down = opened > 0 ? smoothstep(0.2, 0.7, opened) : 0
            let rise = up * (1 - down)
            let bottom = proj.screen(x: CGFloat(Corridor.laneX(zone)), h: 0, z: panelZ).y
            let top = cp.panelTop[zone] ?? (proj.feetY + ppuP)
            let height = max(1, (top - bottom) * rise)
            panel.isHidden = rise < 0.01
            panel.position = CGPoint(x: laneX, y: bottom)
            panel.xScale = ppuP * 0.6 / 120
            panel.yScale = height / 160
            panel.zPosition = proj.depthZ(panelZ)
            let hidden = cp.concealed[zone] == true
            panel.color = cp.unlocked.contains(zone) ? VaultPalette.cyan : VaultPalette.laser
            panel.colorBlendFactor = cp.unlocked.contains(zone) ? 0.35 : (cp.scan != nil && !hidden ? 0.12 : 0)
            // Concealed: the crown of the body as drawn is below the panel's top edge (with a small margin).
            if let crown = displayedCrownY(zone), rise > 0.95 {
                cp.concealed[zone] = crown < top - 0.02 * ppuP
            } else {
                cp.concealed[zone] = false
            }
            // Scanner: drops from the ceiling, aims at the head; it cannot see behind the panel (it searches its top).
            let drop = cp.stoppedAt == nil ? 0 : smoothstep(0.3, 1.2, CGFloat(k))
            let gone = opened > 0 ? smoothstep(0.0, 0.6, opened) : 0
            let mount = proj.screen(x: side * 0.95, h: CGFloat(Corridor.ceilingH) - 0.05 - 0.45 * drop * (1 - gone), z: 3.6)
            rig.housing.position = mount
            rig.housing.setScale(proj.ppu(3.6) * 0.55 / 120)
            rig.housing.xScale = abs(rig.housing.xScale) * (side < 0 ? 1 : -1)
            let crown = displayedCrownY(zone) ?? top
            let headTarget = CGPoint(x: laneX, y: hidden ? top + 0.05 * ppuP : crown - 0.08 * ppuP)
            if rig.aim == .zero { rig.aim = CGPoint(x: laneX, y: top + 0.6 * ppuP) }
            // Capped tracking speed: predictable, and a hiding player is never "chased" behind cover.
            let maxStep = 700 * dt
            let dx = headTarget.x - rig.aim.x, dy = headTarget.y - rig.aim.y
            let dist = hypot(dx, dy)
            if dist > 0.5 { rig.aim = CGPoint(x: rig.aim.x + dx / dist * min(dist, maxStep), y: rig.aim.y + dy / dist * min(dist, maxStep)) }
            let tracking = cp.stoppedAt != nil && cp.openedAt == nil && k > 1.2
            let wantLock: CGFloat = tracking && !hidden && dist < 0.15 * ppuP ? 1 : 0
            rig.lock += (wantLock - rig.lock) * min(1, dt * 3)
            let scanning = cp.scan.map { k >= $0.start && k <= $0.end } ?? false
            // Cone from the lens to a spot around the aim point.
            let lens = CGPoint(x: mount.x + side * -4, y: mount.y - proj.ppu(3.6) * 0.35)
            let spread = ppuP * (0.42 - 0.12 * rig.lock)
            let ang = atan2(rig.aim.y - lens.y, rig.aim.x - lens.x) + .pi / 2
            let path = CGMutablePath()
            path.move(to: lens)
            path.addLine(to: CGPoint(x: rig.aim.x + cos(ang) * spread, y: rig.aim.y + sin(ang) * spread))
            path.addLine(to: CGPoint(x: rig.aim.x - cos(ang) * spread, y: rig.aim.y - sin(ang) * spread))
            path.closeSubpath()
            rig.cone.path = path
            let searching = hidden && tracking
            rig.cone.fillColor = (searching ? UIColor(white: 0.8, alpha: 1) : VaultPalette.laser).withAlphaComponent(scanning ? 0.2 : 0.09)
            rig.cone.isHidden = !tracking
            // Reticle: closes in as it locks; breaks apart when the player hides.
            let r = ppuP * (0.36 - 0.14 * rig.lock)
            // Drawn at its real radius (a scaled-up unit circle would blur its antialiasing into a glow).
            rig.reticle.path = CGPath(ellipseIn: CGRect(x: rig.aim.x - r, y: rig.aim.y - r, width: 2 * r, height: 2 * r), transform: nil)
            rig.reticle.lineWidth = 3
            rig.reticle.strokeColor = searching ? UIColor(white: 0.85, alpha: 1) : VaultPalette.laser
            rig.reticle.alpha = tracking ? (searching ? (reduceMotion ? 0.5 : 0.25 + 0.25 * abs(sin(CGFloat(now) * 9))) : 0.5 + 0.5 * rig.lock) : 0
            let tp = CGMutablePath()
            for a in [0.0, 0.5, 1.0, 1.5] as [CGFloat] {
                let u = CGPoint(x: cos(a * .pi), y: sin(a * .pi))
                let gap: CGFloat = searching ? 1.6 : 1.0
                tp.move(to: CGPoint(x: rig.aim.x + u.x * r * gap, y: rig.aim.y + u.y * r * gap))
                tp.addLine(to: CGPoint(x: rig.aim.x + u.x * r * (gap + 0.45), y: rig.aim.y + u.y * r * (gap + 0.45)))
            }
            rig.ticks.path = tp
            rig.ticks.strokeColor = rig.reticle.strokeColor
            rig.ticks.alpha = rig.reticle.alpha
            rig.status.text = nil
            rig.status.attributedText = tracking ? arcadeText(searching ? "TARGET LOST" : (rig.lock > 0.8 ? "LOCKED" : "TRACKING"), size: 16,
                                                             color: searching ? .white : VaultPalette.laser, strokeWidth: -4) : nil
            rig.status.position = CGPoint(x: rig.aim.x, y: rig.aim.y + r * 1.9)
            rig.node.alpha = drop * (1 - gone)
            rig.node.zPosition = Layer.flash - 40   // overlay on the world (it is the scanner's light, not an object)
        }
    }

    private func easeBack(_ x: CGFloat) -> CGFloat { x >= 1 ? 1 : 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2) }

    private func resolveCheckpointScan(_ cp: CheckpointState, _ scan: CoverScan) {
        let rt = laserRuntime, h = rt.heist
        cp.scan = nil
        cp.cued = false
        let hidden = scan.hidden
        for zone in scan.participants {
            hideCue(zone)
            let share = (scan.concealedTime[zone] ?? 0) / (scan.end - scan.start)
            if hidden.contains(zone) {
                if !cp.unlocked.contains(zone) {
                    cp.unlocked.insert(zone)
                    h.dialSpin[zone, default: 0] -= 2 * .pi / 3
                    h.dials[zone]?.color = UIColor(red: 0.3, green: 0.95, blue: 0.5, alpha: 1)
                    audio.play(.clunk, dB: -4)
                    addTeamPower(1)
                }
                popRating(zone, text: "HIDDEN!", color: VaultPalette.cyan, at: slots[zone]?.headPoint ?? .zero)
                bodyLight(zone, VaultPalette.cyan, 0.35)
            } else {
                popRating(zone, text: "SPOTTED!", color: VaultPalette.laser, at: slots[zone]?.headPoint ?? .zero)
                bodyLight(zone, VaultPalette.laser, 0.4)
                laser?.cameraDetect = 1
                audio.play(.zap, dB: -8)
            }
            gameLog(String(format: "laser: checkpoint scan %d — %@ %@ (concealed %.0f%% of the scan)", cp.scanIndex + 1, role(for: zone),
                           hidden.contains(zone) ? "HIDDEN" : "SPOTTED", share * 100))
        }
        let missed = scan.participants.count - hidden.count
        for e in rt.alert.record(missed: missed, team: scan.allHidden, cleared: hidden.count) { _ = e }
        let allUnlocked = cp.unlocked.isSuperset(of: cp.participants)
        if allUnlocked {
            breachCheckpoint(cp, assisted: false)
        } else if cp.scanIndex + 1 < CheckpointTiming.maxScans {
            cp.scanIndex += 1
            floatText("RESCAN — HIDE TOGETHER!", color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.22))
            setDroneMood(.smug, for: 1.5)
            captureEvent("l-checkpoint-d-spotted", after: 0.2)
        } else {
            breachCheckpoint(cp, assisted: true)
        }
    }

    /// Both locks down: the security system loses its targets — scanners power down and retract, the cover sinks,
    /// the corridor calms (alert → safe for a few seconds), the gate opens and the cart rolls on.
    private func breachCheckpoint(_ cp: CheckpointState, assisted: Bool) {
        let rt = laserRuntime, h = rt.heist
        cp.openedAt = gameTime
        cp.breached = !assisted
        for zone in Zone.allCases { h.dialSpin[zone, default: 0] -= 2 * .pi }
        audio.play(.alarmOff, dB: -3)
        audio.play(.hydraulic, dB: -4)
        audio.play(.powerDown, dB: -6)
        if assisted {
            showBanner("GATE FORCED OPEN", sub: "The drone glitched — keep going!", color: VaultPalette.gold, hold: 1.8)
            setDroneMood(.panic, for: 2)
        } else {
            showBanner("SECURITY BREACHED!", sub: "They lost you both — the gate is open!", color: VaultPalette.cyan, hold: 2.0)
            audio.play(.team, dB: -1)
            audio.duckMusic(for: 1.5, now: now)
            rt.flash = reduceMotion ? 0.5 : 1
            h.safeUntil = gameTime + 4
            addTeamPower(2)
            setDroneMood(.annoyed, for: 2)
            for zone in cp.participants {
                bodyLight(zone, VaultPalette.cyan, 0.45)
                burstSparks(at: h.dials[zone]?.position ?? .zero, color: VaultPalette.cyan, count: reduceMotion ? 4 : 10)
            }
        }
        laser?.cameraLook = 0
        gameLog("laser: checkpoint \(assisted ? "forced open (assist)" : "BREACHED — both hidden, both locks released")")
        captureEvent("l-checkpoint-e-breach", after: 0.6)
    }

    private func finishCheckpointIfDone(_ cp: CheckpointState, sinceOpen: Double) {
        let rt = laserRuntime, h = rt.heist
        h.speedMul = min(1, max(h.speedMul, CGFloat((sinceOpen - 0.8) / 1.5)))
        guard sinceOpen > 2.4, rt.beat == .checkpoint else { return }
        for node in cp.nodes { node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])) }
        for half in h.gateHalves { half.isHidden = true }
        for zone in Zone.allCases { h.dials[zone]?.isHidden = true; hideCue(zone) }
        h.checkpoint = nil
        rt.beat = nil
        rt.nextBeatAt = gameTime + 0.5
    }

    /// A halt during a scan restarts that scan from its cue (no credit for hiding while paused).
    func restartCheckpointScan() {
        guard let cp = laserRuntime.heist.checkpoint, let stopped = cp.stoppedAt, cp.openedAt == nil else { return }
        let window = CheckpointTiming.scanWindow(cp.scanIndex)
        let cueAt = window.start - (CheckpointTiming.scanStart - CheckpointTiming.cueAt)
        let k = gameTime - stopped
        if k > cueAt - 0.5 { cp.stoppedAt = gameTime - (cueAt - 0.8) }
        cp.scan = nil
        cp.cued = false
        for zone in Zone.allCases { hideCue(zone) }
    }

    private func planCheckpointBots(_ cp: CheckpointState) {
        guard laserRuntime.script == nil, model?.autoplay == true else { return }
        for zone in cp.participants {
            guard var slot = slots[zone], slot.driver == .simulated, now - slot.lastManualSim > 20, Double.random(in: 0...1) < 0.9 else { continue }
            slot.sim = SimulatedSquat(start: gameTime, holdDuration: Double.random(in: 2.7...3.0))
            slots[zone] = slot
        }
    }

    func removeCheckpoint() {
        let h = laserRuntime.heist
        guard let cp = h.checkpoint else { return }
        for node in cp.nodes { node.removeFromParent() }
        h.checkpoint = nil
    }
}
