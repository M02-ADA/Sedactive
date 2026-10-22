import Foundation

// Piranha Jump rules. Pure and renderer-free (compiled into the macOS logic tests).
//
// Movement vocabulary becomes three actions, one per hazard:
//   • DUCK  (squat)        → birds overhead
//   • LEAN  (weight shift) → the alligator dragging the raft down
//   • JUMP  (feet off)     → piranhas leaping low across the deck, through the players' foot zone
// All numbers are provisional, tuned for simulator readability — not validated with people.

// MARK: - Jump input

nonisolated struct JumpConfig: Sendable {
    /// Lift (hip rise above the calibrated standing height, in torso lengths) that counts as feet off the deck,
    /// and the lower level that counts as landed again (hysteresis: jitter around one threshold can't re-trigger).
    var takeoffLift = 0.14
    var landLift = 0.07
    /// With ankles visible, the feet must have risen too: rules out reaching up or rising onto tiptoes.
    var footLift = 0.05
    /// Weight of each new sample (higher = less smoothing, less lag). Jumps are fast, so lighter than squats.
    var smoothing = 0.75
    /// Airborne longer than any real hop means the standing baseline drifted (someone stepped closer): recalibrate.
    var maxAirtime = 1.2
    var lostTimeout = 0.6
    /// After a person is (re)acquired, the baseline settles for this long before jumps count.
    var settleDuration = 0.4
    /// A jump cycle is complete only once the feet are back down and still (near standing) this long after landing.
    var neutralHold = 0.2
}

nonisolated enum JumpEvent: Equatable, Sendable {
    /// Feet left the deck (initiated and elevated: the hips crossed the takeoff level).
    case takeoff
    /// Back below the landing level.
    case landed(airtime: Double)
    /// The complete jump cycle: landed and held near standing for `neutralHold`. The only event that counts a rep.
    case settled(airtime: Double)
}

/// Turns a stream of lift values (from poses or simulation) into takeoff / landing events.
nonisolated struct JumpDetector: Sendable {
    var config = JumpConfig()
    private(set) var isAirborne = false
    private(set) var lift = 0.0
    private(set) var takeoffAt = -Double.infinity
    private(set) var isTracking = false
    private var lastSeen = -Double.infinity
    private var settleUntil = -Double.infinity
    private var standingHipY: Double?
    private var standingFootY: Double?
    private var pendingLanding: (at: Double, airtime: Double)?

    init(config: JumpConfig = JumpConfig()) { self.config = config }

    mutating func update(pose: PersonPose?, at time: Double) -> [JumpEvent] {
        update(lift: pose.flatMap { estimateLift($0) }, at: time)
    }

    mutating func update(lift raw: Double?, at time: Double) -> [JumpEvent] {
        guard let raw else {
            if isTracking, time - lastSeen > config.lostTimeout {
                isTracking = false
                lift = 0
                if isAirborne { isAirborne = false }
                pendingLanding = nil   // never confirmed back on the deck: no rep
            }
            return []
        }
        if isTracking {
            lift += (raw - lift) * config.smoothing
        } else {
            isTracking = true
            lift = raw
            settleUntil = time + config.settleDuration
        }
        lastSeen = time
        guard time >= settleUntil else { isAirborne = false; return [] }

        if !isAirborne, lift > config.takeoffLift {
            isAirborne = true
            takeoffAt = time
            pendingLanding = nil   // a bounce straight into another hop: one cycle, completed after the last landing
            return [.takeoff]
        }
        if !isAirborne, let pending = pendingLanding {
            if abs(lift) > config.landLift {
                pendingLanding = (time, pending.airtime)   // still moving: the hold restarts
            } else if time - pending.at >= config.neutralHold {
                pendingLanding = nil
                return [.settled(airtime: pending.airtime)]
            }
        }
        if isAirborne {
            let airtime = time - takeoffAt
            if lift < config.landLift {
                isAirborne = false
                pendingLanding = (time, airtime)
                return [.landed(airtime: airtime)]
            }
            if airtime > config.maxAirtime {
                // Not a jump: the baseline is stale. Land silently and recalibrate from here.
                isAirborne = false
                standingHipY = nil
                standingFootY = nil
                return [.landed(airtime: airtime)]
            }
        }
        return []
    }

    /// Hip rise above the standing height, in torso lengths. The baseline only adapts while grounded and still, and
    /// never follows the hips *down* (a squat or the crouch before a jump must not drag it).
    mutating func estimateLift(_ pose: PersonPose) -> Double? {
        guard let hip = pose.hipCenter, let torso = pose.torsoLength else { return nil }
        let footY = pose.footY
        guard let baseHip = standingHipY else {
            standingHipY = hip.y
            standingFootY = footY
            return 0
        }
        let rise = (hip.y - baseHip) / torso
        if !isAirborne, abs(rise) < config.landLift {
            standingHipY = baseHip + (hip.y - baseHip) * 0.05
            if let footY { standingFootY = (standingFootY ?? footY) + (footY - (standingFootY ?? footY)) * 0.05 }
        }
        if let footY, let baseFoot = standingFootY, (footY - baseFoot) / torso < config.footLift, rise > config.landLift {
            // Hips up but feet planted: tiptoes or a stretch, not a jump.
            return min(rise, config.landLift)
        }
        return max(0, rise)
    }
}

/// A simulated two-footed hop: a short crouch (negative lift, shown on the stand-in only), then a ballistic arc.
/// Feeds the same JumpDetector as camera poses.
nonisolated struct SimulatedJump: Sendable {
    var start: Double
    var crouch = 0.12
    var airtime = 0.46
    var peak = 0.34

    var takeoffTime: Double { start + crouch }
    var end: Double { takeoffTime + airtime }

    func lift(at time: Double) -> Double? {
        let t = time - start
        guard t >= 0, time <= end + 0.15 else { return nil }
        if t < crouch { return -0.06 * sin(.pi * t / crouch) }
        let u = (time - takeoffTime) / airtime
        guard u <= 1 else { return 0 }
        return peak * 4 * u * (1 - u)
    }
}

// MARK: - Encounter timing and the leap path

/// WARNING (fins and boiling water on one side, nothing leaps) → APPROACH (fins race along the raft toward the
/// players; the leap path glows across the deck) → JUMP! cue → LEAP (each fish arcs low across the deck at shin
/// height, from one edge to the other) → SPLASHDOWN. Each leap passes the near lane first, the far lane ~0.4 s later.
nonisolated struct PiranhaTiming: Equatable, Sendable {
    var warningDuration = 1.8
    var approachDuration = 1.6
    /// "JUMP!" and the team lock appear this long before the first crossing of the first leap.
    var cueLead = 1.4
    /// Launch → splashdown on the far side.
    var flightDuration = 0.9
    /// Between launches in a burst (longer than a jump plus landing, so leaps never overlap demands).
    var burstSpacing = 1.6
    /// A player clears a leap if they are airborne at any moment in [crossing − clearBefore, crossing + clearAfter].
    /// Generous on both sides: parent-child jump timing plus ~70 ms of camera latency.
    var clearBefore = 0.35
    var clearAfter = 0.2
    /// A miss is labelled TOO LATE if the player takes off within this long after the window closed.
    var lateLabelWindow = 0.6
    /// An airborne spell that ended this long before the window (after the cue) is labelled TOO EARLY.
    var earlyLookback = 1.2

    var revealTime: Double { warningDuration }
    func launchTime(_ leap: Int) -> Double { warningDuration + approachDuration + Double(leap) * burstSpacing }
    func crossingTime(leap: Int, zone: Zone, from side: Zone) -> Double {
        launchTime(leap) + flightDuration * PiranhaPath.progress(atLane: zone, from: side)
    }
    func firstCrossing(from side: Zone) -> Double { crossingTime(leap: 0, zone: side, from: side) }
    func cueTime(from side: Zone) -> Double { firstCrossing(from: side) - cueLead }
    func windowClose(leap: Int, zone: Zone, from side: Zone) -> Double { crossingTime(leap: leap, zone: zone, from: side) + clearAfter }
    func endTime(count: Int) -> Double { launchTime(max(0, count - 1)) + flightDuration + 0.6 }

    var window: JumpWindow { JumpWindow(clearBefore: clearBefore, clearAfter: clearAfter, lateLabelWindow: lateLabelWindow, earlyLookback: earlyLookback) }

    var isValid: Bool {
        warningDuration > 0 && approachDuration > 0 && cueLead > 0 && flightDuration > 0.3 && clearBefore >= 0 && clearAfter >= 0
            && burstSpacing >= flightDuration * 0.5 + clearBefore + clearAfter + 0.5
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> PiranhaTiming {
        var t = PiranhaTiming()
        func read(_ key: String, _ value: inout Double) { if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) } }
        read("piranhaWarning", &t.warningDuration)
        read("piranhaApproach", &t.approachDuration)
        read("piranhaCueLead", &t.cueLead)
        read("piranhaFlight", &t.flightDuration)
        read("piranhaSpacing", &t.burstSpacing)
        read("jumpBefore", &t.clearBefore)
        read("jumpAfter", &t.clearAfter)
        return t.isValid ? t : PiranhaTiming()
    }
}

/// The leap in world units (x across, h above the deck), just in front of the players' plane so the fish draws in
/// front of their shins. Horizontal speed is constant (ballistic), height is a parabola peaking between the players.
nonisolated enum PiranhaPath {
    /// Launch and splashdown just off the raft's edges (raft half-width 1.1), on screen at the player plane.
    static let halfSpan = 1.25
    static let laneX = 0.65
    static let waterH = -0.2
    static let apexH = 0.48
    /// Draw depth offset from the player plane (negative = nearer the camera than the bodies).
    static let depthOffset = -0.15
    /// The players' plane (Projection.baseZp).
    static let playerZ = 1.9

    /// 0 at launch, 1 at splashdown.
    static func x(_ u: Double, from side: Zone) -> Double {
        let dir: Double = side == .left ? 1 : -1
        return dir * (-halfSpan + 2 * halfSpan * u)
    }

    static func h(_ u: Double) -> Double { waterH + (apexH - waterH) * 4 * u * (1 - u) }

    /// Nose angle along the arc (radians, + = nose up), in the direction of travel.
    static func pitch(_ u: Double) -> Double {
        let dh = (apexH - waterH) * 4 * (1 - 2 * u)
        return atan2(dh, 2 * halfSpan)
    }

    static func progress(atLane zone: Zone, from side: Zone) -> Double {
        let lane = zone == .left ? -laneX : laneX
        let dir: Double = side == .left ? 1 : -1
        return (lane * dir + halfSpan) / (2 * halfSpan)
    }

    /// Height of the fish as it passes over a lane: the foot zone the players must clear.
    static var laneHeight: Double { h(progress(atLane: .left, from: .left)) }
}

// MARK: - One leap: per-player judging

/// One leap, judged by the shared JumpSweepJudge (the same rule as the log and tail sweeps).
nonisolated struct PiranhaLeap: Sendable {
    typealias Result = JumpJudgeResult
    typealias Event = JumpJudgeEvent

    let index: Int
    let side: Zone
    let timing: PiranhaTiming
    private(set) var judge: JumpSweepJudge

    init(id: Int, index: Int, side: Zone, participants: Set<Zone>, timing: PiranhaTiming = PiranhaTiming()) {
        self.index = index
        self.side = side
        self.timing = timing
        let crossings = Dictionary(uniqueKeysWithValues: Zone.allCases.map { ($0, timing.crossingTime(leap: index, zone: $0, from: side)) })
        judge = JumpSweepJudge(id: id, crossings: crossings, cueTime: timing.cueTime(from: side), participants: participants, window: timing.window)
    }

    var cueTime: Double { judge.cueTime }
    var team: TeamChallenge { judge.team }
    var results: [Zone: Result] { judge.results }
    var isOpen: Bool { judge.isOpen }
    var participants: Set<Zone> { judge.participants }
    func crossing(_ zone: Zone) -> Double { judge.crossing(zone) }
    var lastWindowClose: Double { judge.lastWindowClose }
    var labelsFinal: Bool { judge.labelsFinal }

    /// Feed every player's airborne state each frame (encounter clock). Returns what happened this frame.
    mutating func update(at t: Double, airborne: [Zone: Bool]) -> [Event] { judge.update(at: t, airborne: airborne) }

    mutating func cancel() { judge.cancel() }
}

// MARK: - Piranha performance (pure; the renderer only applies it)

nonisolated struct PiranhaPose: Equatable, Sendable {
    enum State: String, Sendable { case hidden, circling, surging, leaping, splashed }
    var state: State = .hidden
    /// Fin cluster position while in the water (world x, z) and how much of the fins shows (0 … 1).
    var finX = 0.0
    var finZ = 0.0
    var finRise = 0.0
    /// Leap progress 0 … 1 (only while leaping).
    var u = 0.0
    /// Tail beat (−1 … 1), jaw opening (0 shut … 1 wide), squash-stretch along the body (> 1 stretched).
    var tail = 0.0
    var jaw = 0.0
    var stretch = 1.0
}

/// Maps the encounter clock onto one leap's fish: circling far off one side (warning) → fins racing in along the raft
/// (approach) → a dip and burst (anticipation) → the leap, stretching on the way up, snapping as it passes each lane
/// → splashdown on the far side.
nonisolated struct PiranhaAnimator: Sendable {
    let timing: PiranhaTiming
    let side: Zone
    let leap: Int

    /// Where the fins gather during the warning: in the open river ahead, in the gap between the players' bodies on
    /// the attack side, so the warning is never hidden behind a player.
    static let gatherZ = 6.0
    static let gatherX = 0.45
    /// The approach runs straight at the raft down that gap, then swings out to the launch point at the edge.
    static let channelX = 0.3
    static let channelZ = 3.0

    func pose(at t: Double) -> PiranhaPose {
        var p = PiranhaPose()
        let sideX: Double = side == .left ? -1 : 1
        let launch = timing.launchTime(leap)
        let surgeStart = leap == 0 ? timing.revealTime : launch - min(1.2, timing.burstSpacing * 0.75)
        let launchZ = PiranhaPath.playerZ + PiranhaPath.depthOffset
        if t < 0 { return p }
        if t < surgeStart {
            // The whole school circles from the first warning, so a burst reads as "several fish" from the start.
            p.state = .circling
            let a = t * 2.4 + Double(leap) * 1.7
            p.finX = sideX * (PiranhaAnimator.gatherX + 0.08 * sin(a))
            p.finZ = PiranhaAnimator.gatherZ + 0.8 * cos(a)
            p.finRise = smoothstepD(0, 0.5, t)
            p.tail = sin(t * 14)
            return p
        }
        if t < launch {
            // Fins race in down the gap between the players (always in view), then swing out to just off the raft
            // edge beside them; the last 0.18 s they dip under (anticipation) before bursting out.
            p.state = .surging
            let turn = launch - min(0.7, (launch - surgeStart) * 0.45)
            let k1 = smoothstepD(surgeStart, turn, t), k2 = smoothstepD(turn, launch - 0.18, t)
            let channel = (x: sideX * PiranhaAnimator.channelX, z: PiranhaAnimator.channelZ)
            let edge = (x: sideX * (PiranhaPath.halfSpan + 0.1), z: launchZ)
            p.finX = mixD(mixD(sideX * PiranhaAnimator.gatherX, channel.x, k1), edge.x, k2) + sideX * 0.08 * sin(t * 9) * (1 - k2)
            p.finZ = mixD(mixD(PiranhaAnimator.gatherZ, channel.z, k1), edge.z, k2)
            p.finRise = t > launch - 0.18 ? 1 - smoothstepD(launch - 0.18, launch - 0.04, t) : 1
            p.tail = sin(t * 22)
            return p
        }
        let u = (t - launch) / timing.flightDuration
        if u <= 1 {
            p.state = .leaping
            p.u = u
            p.tail = sin(t * 30) * (1 - 0.6 * u)
            // Stretch on the burst out of the water, squash into the splashdown (volume-preserving, ≤ 15%).
            p.stretch = 1 + 0.14 * (1 - smoothstepD(0, 0.3, u)) - 0.12 * smoothstepD(0.85, 1, u)
            // Snapping at the feet as it passes each lane: a quick open → shut around each crossing.
            for lane in Zone.allCases {
                let lu = PiranhaPath.progress(atLane: lane, from: side)
                let d = abs(u - lu) * timing.flightDuration
                if d < 0.12 { p.jaw = max(p.jaw, 1 - d / 0.12) }
            }
            p.jaw = max(p.jaw, 0.25)
            return p
        }
        p.state = t < launch + timing.flightDuration + 0.5 ? .splashed : .hidden
        return p
    }
}
