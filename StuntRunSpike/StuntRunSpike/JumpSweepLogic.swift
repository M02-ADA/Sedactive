import Foundation

// Low sweeps through the foot zone — JUMP. Pure and renderer-free (compiled into the macOS logic tests).
//
//   • Piranha Leap         (PiranhaLogic.swift)  a fish arcs across the deck from one side, lanes ~0.46 s apart
//   • River Log Sweep      a wave sets a drifting log on the bow; it rolls down the tilted deck through both lanes
//   • Crocodile Tail Sweep the croc beside the bow coils its tail, then whips it low across the deck
//
// Four separate concepts, kept separate on purpose:
//   1. warning time       — the encounter clock (nothing to do yet)
//   2. action eligibility — the jump window around each lane's crossing (JumpWindow)
//   3. collision          — the moment the hazard reaches a lane's feet (per-hazard crossing times)
//   4. the completed rep  — JumpDetector's .settled event (feet back down, still), never the animation
// All numbers are provisional, tuned for simulator readability — not validated with people.

// MARK: - Shared judging

nonisolated struct JumpWindow: Equatable, Sendable {
    /// A player clears if airborne at any moment in [crossing − clearBefore, crossing + clearAfter].
    var clearBefore = 0.35
    var clearAfter = 0.2
    /// A miss is labelled TOO LATE if the player takes off within this long after the window closed.
    var lateLabelWindow = 0.6
    /// An airborne spell that ended this long before the window (after the cue) is labelled TOO EARLY.
    var earlyLookback = 1.2

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> JumpWindow {
        var w = JumpWindow()
        if defaults.object(forKey: "jumpBefore") != nil { w.clearBefore = defaults.double(forKey: "jumpBefore") }
        if defaults.object(forKey: "jumpAfter") != nil { w.clearAfter = defaults.double(forKey: "jumpAfter") }
        return w.clearBefore >= 0 && w.clearAfter >= 0 ? w : JumpWindow()
    }
}

nonisolated enum JumpJudgeResult: Equatable, Sendable { case cleared, tooEarly, tooLate, noJump }

nonisolated enum JumpJudgeEvent: Equatable, Sendable {
    /// Feet were off the deck inside the window: the contribution (banked once).
    case cleared(Zone, power: Int)
    /// The window closed with the player on the deck: the hazard connects (feedback only, no penalty).
    case nipped(Zone)
    /// Final label for a miss, for feedback (decided a little after the nip for TOO LATE).
    case labelled(Zone, JumpJudgeResult)
    case resolved(TeamChallenge.Outcome, bonus: Int)
}

/// Per-player judging of one low sweep through the foot zone; one shared TeamChallenge outcome.
nonisolated struct JumpSweepJudge: Sendable {
    let crossings: [Zone: Double]
    let cueTime: Double
    let window: JumpWindow
    private(set) var team: TeamChallenge
    private(set) var results: [Zone: JumpJudgeResult] = [:]
    private var nipped: Set<Zone> = []
    private var wasAirborne: [Zone: Bool] = [:]
    private var lastLanding: [Zone: Double] = [:]
    private var lateTakeoff: [Zone: Double] = [:]

    init(id: Int, crossings: [Zone: Double], cueTime: Double, participants: Set<Zone>, window: JumpWindow) {
        self.crossings = crossings
        self.cueTime = cueTime
        self.window = window
        team = TeamChallenge(id: id, participants: participants)
    }

    var isOpen: Bool { team.isOpen }
    var participants: Set<Zone> { team.participants }
    func crossing(_ zone: Zone) -> Double { crossings[zone] ?? cueTime }
    var lastWindowClose: Double { (crossings.values.max() ?? cueTime) + window.clearAfter }
    var labelsFinal: Bool { participants.allSatisfy { results[$0] != nil } }

    /// Feed every player's airborne state each frame (encounter clock). Returns what happened this frame.
    mutating func update(at t: Double, airborne: [Zone: Bool]) -> [JumpJudgeEvent] {
        var events: [JumpJudgeEvent] = []
        for zone in participants {
            let up = airborne[zone] ?? false
            let was = wasAirborne[zone] ?? false
            if was, !up { lastLanding[zone] = t }
            if !was, up, nipped.contains(zone), lateTakeoff[zone] == nil { lateTakeoff[zone] = t }
            wasAirborne[zone] = up
            guard results[zone] == nil else { continue }
            let tc = crossing(zone)
            if !nipped.contains(zone), up, t >= tc - window.clearBefore, t <= tc + window.clearAfter, team.isOpen {
                results[zone] = .cleared
                events.append(.cleared(zone, power: team.contribute(zone, at: t)))
            } else if !nipped.contains(zone), t > tc + window.clearAfter {
                nipped.insert(zone)
                events.append(.nipped(zone))
                if let landed = lastLanding[zone], landed >= cueTime - 0.2, landed < tc - window.clearBefore,
                   landed >= tc - window.clearBefore - window.earlyLookback {
                    results[zone] = .tooEarly
                    events.append(.labelled(zone, .tooEarly))
                }
            } else if nipped.contains(zone) {
                if let late = lateTakeoff[zone], late <= tc + window.clearAfter + window.lateLabelWindow {
                    results[zone] = .tooLate
                    events.append(.labelled(zone, .tooLate))
                } else if t > tc + window.clearAfter + window.lateLabelWindow {
                    results[zone] = .noJump
                    events.append(.labelled(zone, .noJump))
                }
            }
        }
        // The shared outcome is decided as soon as every participant is judged (cleared or nipped).
        if team.isOpen, participants.allSatisfy({ results[$0] == .cleared || nipped.contains($0) }) {
            let (outcome, bonus) = team.resolve()
            events.append(.resolved(outcome, bonus: bonus))
        }
        return events
    }

    mutating func cancel() { team.cancel() }
}

/// The players' feet: lane centres and the plane they stand in (Projection.baseZp).
nonisolated enum FootZone {
    static let laneX = 0.65
    static let playerZ = 1.9
    static func x(_ zone: Zone) -> Double { zone == .left ? -laneX : laneX }
}

// MARK: - River Log Sweep

/// The log's world: a turbulent stretch with a standing wave at the bow. The wave lifts the bow (the deck tilts
/// down toward the camera) and sets the log on the front logs; it rolls downhill through both lanes and off the
/// near edge. Units: x across, z depth from the camera, h above the deck plane.
nonisolated enum LogPath {
    /// ~0.28 tall: low on the shins, under a child's knee — a hop clears it (checked against the stand-ins' jump).
    static let radius = 0.14
    /// As long as the raft is wide, so it plainly sweeps both lanes at once.
    static let halfLength = 1.2
    static let surfaceZ = 16.0
    /// Held against the standing wave just off the bow.
    static let bowZ = 3.3
    /// Where the wave sets it down on the deck.
    static let landZ = 2.62
    static let farEdgeZ = 2.75
    /// Rolls off the near edge of the deck here.
    static let exitZ = 1.12
    static let waterH = -0.22
    /// The root end leads a little: driftwood never lies perfectly square (the left lane is reached first).
    static let yaw = 0.1
    /// The rope lashings it rumbles over (deck rows at 12% and 88% of its length).
    static let lashingZs = [2.56, 1.39]
    /// Bow lift: the far edge rises this much at full lift; the pivot is the players' plane so their feet stay put.
    static let pitchH = 0.2

    static func deckH(z: Double, bowLift: Double) -> Double { bowLift * pitchH * (z - FootZone.playerZ) / (farEdgeZ - FootZone.playerZ) }
    /// Depth of the log's axis at lateral position x, for a centre depth zc.
    static func axisZ(x: Double, centre zc: Double) -> Double { zc + x * tan(yaw) }
}

nonisolated struct LogSweepTiming: Equatable, Sendable {
    /// Rapids churn ahead and leaves swirl into a line; nothing to jump yet.
    var warningDuration = 2.0
    /// The log surfaces far ahead and the current carries it to the bow.
    var driftDuration = 3.2
    /// The standing wave lifts it over the bow and sets it on the deck.
    var liftDuration = 0.45
    /// Rolling down the tilted deck: speed as it lands and acceleration downhill (units/s, units/s²).
    var rollSpeed = 1.0
    var rollAccel = 3.2
    /// "JUMP!" and the team lock appear this long before the first lane is reached.
    var cueLead = 1.4
    var window = JumpWindow()

    var revealTime: Double { warningDuration }
    var liftStart: Double { warningDuration + driftDuration }
    var rollStart: Double { liftStart + liftDuration }
    func rollTime(distance d: Double) -> Double { (-rollSpeed + (rollSpeed * rollSpeed + 2 * rollAccel * max(0, d)).squareRoot()) / rollAccel }
    func rollDistance(after tau: Double) -> Double { rollSpeed * tau + 0.5 * rollAccel * tau * tau }
    var exitTime: Double { rollStart + rollTime(distance: LogPath.landZ - LogPath.exitZ) }
    var exitSpeed: Double { rollSpeed + rollAccel * (exitTime - rollStart) }
    /// When the log's axis reaches a lane's feet.
    func crossingTime(_ zone: Zone) -> Double {
        let centre = FootZone.playerZ - FootZone.x(zone) * tan(LogPath.yaw)
        return rollStart + rollTime(distance: LogPath.landZ - centre)
    }
    var crossings: [Zone: Double] { [.left: crossingTime(.left), .right: crossingTime(.right)] }
    var firstCrossing: Double { min(crossingTime(.left), crossingTime(.right)) }
    var cueTime: Double { firstCrossing - cueLead }
    /// Splashdown behind the raft plus the bow settling.
    var endTime: Double { exitTime + 1.8 }

    var isValid: Bool {
        warningDuration > 0 && driftDuration > 0.8 && liftDuration > 0.1 && rollSpeed > 0 && rollAccel >= 0 && cueLead > 0
            && cueTime > revealTime
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> LogSweepTiming {
        var t = LogSweepTiming()
        func read(_ key: String, _ value: inout Double) { if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) } }
        read("logWarning", &t.warningDuration)
        read("logDrift", &t.driftDuration)
        read("logCueLead", &t.cueLead)
        t.window = JumpWindow.fromDefaults(defaults)
        return t.isValid ? t : LogSweepTiming()
    }
}

nonisolated struct LogPose: Equatable, Sendable {
    enum State: String, Sendable { case churning, floating, lifting, rolling, falling, gone }
    var state: State = .churning
    /// Axis centre depth, height of the axis above the deck plane, accumulated roll (radians, + = rolling toward us).
    var zc = LogPath.surfaceZ
    var h = LogPath.waterH
    var roll = 0.0
    /// How much of the log is under water (0 … 1).
    var submerge = 1.0
    /// The bow riding up the standing wave (0 … 1, damped bounce as it settles).
    var bowLift = 0.0
    /// Rapids intensity ahead (warning), 0 … 1.
    var rapids = 0.0
    /// Leaves and root tendrils trailing the motion (−1 … 1).
    var trail = 0.0
}

/// The log's performance on the encounter clock:
/// churning (warning) → floating (surfaces, carried in, tumbling slowly) → lifting (the wave sets it on the bow;
/// the bow rises) → rolling (downhill through both lanes, rumbling over the lashings) → falling (off the near edge)
/// → gone (splashdown behind; the bow settles with a damped bounce).
nonisolated struct LogAnimator: Sendable {
    let timing: LogSweepTiming
    static let surfaceTime = 0.6

    /// Centre depth during the roll and after it leaves the deck.
    func zCentre(at t: Double) -> Double {
        if t < timing.rollStart { return LogPath.landZ }
        if t < timing.exitTime { return LogPath.landZ - timing.rollDistance(after: t - timing.rollStart) }
        return LogPath.exitZ - timing.exitSpeed * (t - timing.exitTime)
    }

    func pose(at t: Double) -> LogPose {
        var p = LogPose()
        let r = LogPath.radius
        p.rapids = smoothstepD(0, 0.8, t) * (1 - smoothstepD(timing.rollStart, timing.exitTime + 1.2, t))
        if t < timing.revealTime {
            p.state = .churning
            return p
        }
        let floatH = LogPath.waterH + r * 0.3
        if t < timing.liftStart {
            // Carried in at the river's pace, easing in as it surfaces and slowing a touch as it meets the wave.
            let k = (t - timing.revealTime) / timing.driftDuration
            let travel = 0.8 * k + 0.2 * smoothstepD(0, 1, k)
            p.state = .floating
            p.zc = mixD(LogPath.surfaceZ, LogPath.bowZ, travel)
            let surfacing = smoothstepD(0, Self.surfaceTime, t - timing.revealTime)
            p.submerge = 1 - 0.45 * surfacing
            p.h = mixD(LogPath.waterH - r, floatH, surfacing) + 0.035 * sin(2 * .pi * 0.9 * t)
            // A slow tumble in the current (it isn't rolling on anything yet).
            p.roll = 0.6 * sin(2 * .pi * 0.35 * (t - timing.revealTime))
            p.trail = sin(2 * .pi * 0.9 * t + 1)
            return p
        }
        if t < timing.rollStart {
            // The standing wave lifts the bow and heaves the log over the front edge (an arc, not a slide).
            let k = (t - timing.liftStart) / timing.liftDuration
            p.state = .lifting
            p.bowLift = smoothstepD(0, 1, k)
            p.zc = mixD(LogPath.bowZ, LogPath.landZ, easeOutD(k))
            let deck = LogPath.deckH(z: LogPath.landZ, bowLift: p.bowLift) + r
            p.h = mixD(floatH, deck, easeOutD(k)) + 0.16 * sin(.pi * k)
            p.submerge = 0.55 * (1 - smoothstepD(0, 0.5, k))
            p.roll = 0.6 * sin(2 * .pi * 0.35 * (t - timing.revealTime)) * (1 - k) + 0.8 * k
            p.trail = -0.8 * sin(.pi * k)
            return p
        }
        let landRoll = 0.8
        if t < timing.exitTime {
            // Downhill: constant acceleration; the roll angle follows the distance (no slipping).
            let d = timing.rollDistance(after: t - timing.rollStart)
            p.state = .rolling
            p.bowLift = 1
            p.zc = LogPath.landZ - d
            var bump = 0.0
            for z in LogPath.lashingZs { bump += 0.035 * exp(-pow((p.zc - z) / 0.07, 2)) }
            // A small settle bounce right after it lands (weight), then the lashings.
            let settle = 0.05 * exp(-(t - timing.rollStart) * 14) * cos((t - timing.rollStart) * 40)
            p.h = LogPath.deckH(z: p.zc, bowLift: 1) + r + bump + settle
            p.roll = landRoll + d / r
            p.submerge = 0
            p.trail = min(1, (timing.rollSpeed + timing.rollAccel * (t - timing.rollStart)) / 3)
            return p
        }
        // Off the near edge: it keeps its speed toward us and drops into the river behind the raft.
        let tau = t - timing.exitTime
        let fallTime = 0.32
        let edgeH = LogPath.deckH(z: LogPath.exitZ, bowLift: 1) + r
        p.zc = zCentre(at: t)
        p.roll = landRoll + (LogPath.landZ - LogPath.exitZ) / r + timing.exitSpeed * tau / r
        // The bow drops back as the wave passes, overshoots and settles (damped).
        p.bowLift = exp(-3.2 * tau) * cos(2 * .pi * 1.1 * tau)
        p.trail = 1
        if tau < fallTime {
            p.state = .falling
            p.h = edgeH - 4.9 * tau * tau
            return p
        }
        p.state = .gone
        p.h = LogPath.waterH
        p.submerge = 0.5
        return p
    }
}

// MARK: - Crocodile Tail Sweep

/// The croc surfaces head-on in the water just off the bow corner (eyes and snout toward the players); its tail lies
/// behind it. The tail swings around the hips in the x–z plane: up out of the water behind the head (the coil), round
/// over the water ahead of the raft, then across the deck toward the camera — low through the players' feet — like
/// a gate swinging shut. Angles (right-side frame): direction from the hips, radians, 0 = +x (out to the croc's
/// side), π/2 = +z (away from the camera), π = −x (across the raft). Mirrored for the left side.
nonisolated enum TailPath {
    /// Out past the Child's shoulder line so the head is never hidden behind a player.
    static let pivotX = 1.75
    static let pivotZ = 3.6
    static let length = 3.35
    /// Enough segments that the coil and the trailing whip bend smoothly (no visible kinks).
    static let segments = 16
    /// Height over the deck while it sweeps: low, through the foot zone.
    static let sweepH = 0.15
    /// Coiled up behind the head (anticipation) → swung round ahead of the raft → across the deck → past the near lane.
    static let startAngle = 80.0 * .pi / 180
    /// The coil pulls back a little the other way just before the release (the counter-move); the sweep starts here.
    static let windUpAngle = startAngle - 0.22
    static let endAngle = 262.0 * .pi / 180
    /// +1: the right-side croc sweeps counter-clockwise (seen from above).
    static var direction: Double { endAngle > windUpAngle ? 1 : -1 }

    static func sign(_ side: Zone) -> Double { side == .left ? -1 : 1 }
    static func pivot(_ side: Zone) -> (x: Double, z: Double) { (sign(side) * pivotX, pivotZ) }
    /// Where the head floats: in front of the hips (nearer the camera), facing the players.
    static func head(_ side: Zone) -> (x: Double, z: Double) { (sign(side) * pivotX, pivotZ - 0.55) }
    /// Mirror an angle for the left-side croc (reflect across the z axis).
    static func mirrored(_ a: Double, side: Zone) -> Double { side == .right ? a : .pi - a }

    /// Direction (unwrapped into the sweep's range) and distance from the hips to a lane's feet, right-side frame.
    static func lane(_ zone: Zone, side: Zone) -> (angle: Double, radius: Double) {
        let dx = FootZone.x(zone) * sign(side) - pivotX   // into the right-side frame
        let dz = FootZone.playerZ - pivotZ
        var a = atan2(dz, dx)
        while a < windUpAngle { a += 2 * .pi }
        return (a, (dx * dx + dz * dz).squareRoot())
    }
}

nonisolated struct TailSweepTiming: Equatable, Sendable {
    /// Swirl at the bow corner, the badge, a sly growl; nothing to jump yet.
    var warningDuration = 1.6
    /// Surfaces side-on and swims into place beside the bow, eyes on the players.
    var settleDuration = 1.0
    /// Tail rises out of the water and coils back (anticipation). The JUMP! cue falls in here.
    var coilDuration = 1.3
    /// The whip itself: accelerates out of the coil, then sweeps at speed through both lanes.
    var sweepDuration = 0.8
    /// Follow-through lag from the hips to the tip (the tip trails the base).
    var tipLag = 0.16
    /// Overshoot spin and reaction (dizzy after a TEAM jump, smug after a hit), then it sinks away.
    var reactDuration = 1.5
    var retreatDuration = 1.0
    var cueLead = 1.4
    var window = JumpWindow()

    var revealTime: Double { warningDuration }
    var coilStart: Double { warningDuration + settleDuration }
    var sweepStart: Double { coilStart + coilDuration }
    var sweepEnd: Double { sweepStart + sweepDuration }
    var endTime: Double { sweepEnd + reactDuration + retreatDuration }
    /// Ease-in for the first `ramp` of the sweep (it gathers speed out of the coil), then full speed.
    static let ramp = 0.35

    /// Base angle progress 0 … 1 at sweep time τ (continuous speed at the ramp's end).
    func progress(sweepTime tau: Double) -> Double {
        let s = max(0, min(1, tau / sweepDuration)), a = Self.ramp
        return s < a ? s * s / (a * (2 - a)) : (2 * s - a) / (2 - a)
    }
    /// Inverse of `progress`, in sweep time.
    func sweepTime(progress u: Double) -> Double {
        let a = Self.ramp, uA = a / (2 - a)
        let s = u < uA ? (u * a * (2 - a)).squareRoot() : (u * (2 - a) + a) / 2
        return s * sweepDuration
    }
    /// When the tail reaches a lane's feet: the base angle reaches the lane's direction, plus the follow-through lag
    /// for the point of the tail at that lane's distance from the hips. (The far lane is reached by the outer part of
    /// the tail; both lanes are crossed within a fraction of a second.)
    func crossingTime(_ zone: Zone, side: Zone) -> Double {
        let lane = TailPath.lane(zone, side: side)
        let u = (TailPath.windUpAngle - lane.angle) / (TailPath.windUpAngle - TailPath.endAngle)
        return sweepStart + sweepTime(progress: u) + tipLag * lane.radius / TailPath.length
    }
    func crossings(side: Zone) -> [Zone: Double] { [.left: crossingTime(.left, side: side), .right: crossingTime(.right, side: side)] }
    func firstCrossing(side: Zone) -> Double { min(crossingTime(.left, side: side), crossingTime(.right, side: side)) }
    func cueTime(side: Zone) -> Double { firstCrossing(side: side) - cueLead }

    var isValid: Bool {
        warningDuration > 0 && settleDuration > 0 && coilDuration > 0.4 && sweepDuration > 0.3 && cueLead > 0
            && cueTime(side: .right) > revealTime
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> TailSweepTiming {
        var t = TailSweepTiming()
        func read(_ key: String, _ value: inout Double) { if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) } }
        read("tailWarning", &t.warningDuration)
        read("tailCoil", &t.coilDuration)
        read("tailSweep", &t.sweepDuration)
        read("tailCueLead", &t.cueLead)
        t.window = JumpWindow.fromDefaults(defaults)
        return t.isValid ? t : TailSweepTiming()
    }
}

nonisolated struct TailPose: Equatable, Sendable {
    enum State: String, Sendable { case hidden, surfacing, settling, coiling, sweeping, reacting, retreating, gone }
    var state: State = .hidden
    /// How far the croc is out of the water (0 under … 1 surfaced).
    var rise = 0.0
    /// Base angle of the tail at the hips (right-side frame; mirror with TailPath.mirrored).
    var baseAngle = TailPath.startAngle
    /// Extra bend per unit of tail (coil curls it back on itself; negative trails behind a fast sweep).
    var curl = 0.0
    /// Tail height: arched out of the water while coiled, low over the deck while sweeping.
    var lift = -0.3
    /// Body twist toward the sweep (radians, rig roll) and the whole-body spin after the overshoot (0 … 1 turns).
    var twist = 0.0
    var spin = 0.0
    /// Eyes: pupil look (−1 toward the raft … 1 away), lid (0 open … 1 shut), dizzy swirl phase (0 = off).
    var look = -1.0
    var lid = 0.25
    var dizzy = 0.0
    /// Jaw grin (0 shut … 1 open) — a sly half-smile during the coil, wide when pleased.
    var jaw = 0.0
}

/// The tail sweep performance on the encounter clock. `hit`: whether anyone was caught (smug vs dizzy reaction).
nonisolated struct TailSweepAnimator: Sendable {
    let timing: TailSweepTiming

    /// Base angle at absolute encounter time (before, during and after the sweep, with a damped overshoot).
    func baseAngle(at t: Double) -> Double {
        if t < timing.coilStart { return TailPath.startAngle }
        if t < timing.sweepStart {
            // Wind-up: pulls further back (the counter-move) as it coils.
            let k = (t - timing.coilStart) / timing.coilDuration
            return TailPath.startAngle + (TailPath.windUpAngle - TailPath.startAngle) * smoothstepD(0.55, 1, k)
        }
        if t < timing.sweepEnd {
            return mixD(TailPath.windUpAngle, TailPath.endAngle, timing.progress(sweepTime: t - timing.sweepStart))
        }
        // Overshoot: momentum carries it past the end, then it swings back and settles (damped).
        let tau = t - timing.sweepEnd
        return TailPath.endAngle + TailPath.direction * 0.3 * exp(-4 * tau) * sin(2 * .pi * 1.2 * tau)
    }

    /// Angle of the tail at fraction f (0 hips … 1 tip): the base angle delayed by the follow-through lag, plus curl.
    func angle(at t: Double, fraction f: Double, pose: TailPose) -> Double {
        // Curl bends the tail back against the sweep direction (wound up in the coil, trailing in the whip).
        baseAngle(at: t - timing.tipLag * f) - TailPath.direction * pose.curl * f * f * 2.4
    }

    func pose(at t: Double, hit: Bool = false) -> TailPose {
        var p = TailPose()
        if t < timing.revealTime * 0.55 { return p }
        p.baseAngle = baseAngle(at: t)
        if t < timing.revealTime {
            // Surfacing during the warning's second half: a ridge of back and the eyes breaking the water.
            p.state = .surfacing
            p.rise = smoothstepD(timing.revealTime * 0.55, timing.revealTime, t) * 0.6
            p.look = -1
            p.lid = 0.3
            return p
        }
        if t < timing.coilStart {
            let k = (t - timing.revealTime) / timing.settleDuration
            p.state = .settling
            p.rise = mixD(0.6, 1, smoothstepD(0, 0.6, k))
            p.lift = -0.3 + 0.1 * k
            p.look = -1
            p.lid = 0.3
            p.twist = 0.05 * sin(2 * .pi * 0.8 * t)
            return p
        }
        if t < timing.sweepStart {
            // Coil: the tail rises out of the water and curls back; the body twists away (loading the spring);
            // eyes stay on the players with a sly half-grin.
            let k = (t - timing.coilStart) / timing.coilDuration
            p.state = .coiling
            p.rise = 1 - 0.12 * smoothstepD(0.6, 1, k)          // settles lower just before the release
            p.curl = 0.9 * smoothstepD(0, 0.7, k)
            p.lift = mixD(-0.3, 0.55, smoothstepD(0, 0.5, k))
            p.twist = -0.12 * smoothstepD(0.3, 1, k)
            p.look = -1
            p.lid = 0.35
            p.jaw = 0.18 * smoothstepD(0.2, 0.6, k)
            return p
        }
        if t < timing.sweepEnd {
            // The whip: the coil unwinds into a trailing bend (the tip lags), low through the foot zone.
            let s = (t - timing.sweepStart) / timing.sweepDuration
            p.state = .sweeping
            p.rise = 0.88 + 0.12 * s
            p.curl = mixD(0.9, 0.12, smoothstepD(0, 0.35, s))
            p.lift = mixD(0.55, TailPath.sweepH, smoothstepD(0, 0.3, s))
            p.twist = mixD(-0.12, 0.22, smoothstepD(0, 0.6, s))
            p.look = -1
            p.lid = 0.15
            p.jaw = 0.35
            return p
        }
        let react = t - timing.sweepEnd
        if react < timing.reactDuration {
            // Overshoot: momentum spins the body half round. After a TEAM jump it's dizzy (lids droop, pupils
            // swirl, a wobble); after catching someone it's pleased with itself (slow grin, lazy tail).
            let k = react / timing.reactDuration
            p.state = .reacting
            p.rise = 1
            p.curl = 0.12 * (1 - smoothstepD(0, 0.4, k))
            p.lift = mixD(TailPath.sweepH, -0.25, smoothstepD(0, 0.35, k))
            p.twist = 0.22 * (1 - smoothstepD(0, 0.5, k)) + (hit ? 0 : 0.08 * sin(2 * .pi * 2.2 * react) * (1 - k))
            p.spin = smoothstepD(0, 0.45, k) * 0.5
            p.look = hit ? -1 : 0
            p.lid = hit ? 0.55 : 0.5
            p.dizzy = hit ? 0 : 2 * .pi * 1.6 * react
            p.jaw = hit ? 0.45 : 0.1
            return p
        }
        let r = react - timing.reactDuration
        if r < timing.retreatDuration {
            let k = r / timing.retreatDuration
            p.state = .retreating
            p.rise = 1 - easeInD(k)
            p.lift = -0.3
            p.spin = 0.5
            p.look = 0
            p.lid = 0.4
            return p
        }
        p.state = .gone
        return p
    }
}

// MARK: - Director helpers

extension JungleBeat {
    /// Beats whose first demand is a jump.
    nonisolated var startsWithJump: Bool {
        switch self {
        case .piranhas, .logSweep, .tailSweep: true
        default: false
        }
    }
    /// The sweeps wait for a steady raft before their warning starts (players must be able to land on a level deck).
    nonisolated var waitsForSteadyRaft: Bool {
        switch self {
        case .logSweep, .tailSweep: true
        default: false
        }
    }
}
