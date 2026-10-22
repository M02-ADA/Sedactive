import Foundation

// Jungle Drift rules. Pure and renderer-free (compiled into the macOS logic tests).
//
// Movement vocabulary is deliberately three actions, one per hazard:
//   • DUCK  (squat, the existing SquatDetector)  → birds
//   • LEAN  (small weight shift left/right)       → the raft's balance, and alligator strikes
//   • JUMP  (both feet off the deck)              → piranhas leaping across the deck (PiranhaLogic.swift)
// All numbers are provisional, tuned for simulator readability — not validated with people.

// MARK: - Raft balance

nonisolated struct RaftParams: Sendable, Equatable {
    /// Buoyancy pulling the raft level (1/s²) and water drag (1/s). Natural period ≈ 3.6 s: a slow, gentle rock.
    var restoring = 3.0
    var damping = 2.2
    /// Crouching lowers the centre of mass: each crouched player adds this much damping.
    var crouchDamping = 1.2
    /// Torque (deg/s²) per player at full lean. Leaning toward a side pushes that side down.
    var leanTorque = 55.0
    var steadyAngle = 5.0
    var warnAngle = 10.0
    var dangerAngle = 16.0
    /// Seconds continuously past `dangerAngle` before water washes over the deck. Generous on purpose: a team
    /// that starts leaning within ~0.6 s of a strike must make it (parent-child reaction times, not gamer ones).
    var splashAfter = 1.6
    var splashCooldown = 2.0
    var maxAngle = 32.0
    /// Seconds of continuous steadiness that earn a small STEADY RAFT reward.
    var steadyStreak = 6.0
}

nonisolated enum RaftZone: Equatable, Sendable { case steady, tilting, warning, danger }

nonisolated enum RaftEvent: Equatable, Sendable { case enteredDanger, splash, steadyStreak }

/// One shared raft. Angle in degrees, positive = right side down. Both players' leans add together, so one
/// player helps, two players recover twice as fast — nobody is irrelevant and nobody carries it alone.
nonisolated struct RaftBalance: Sendable {
    var params = RaftParams()
    private(set) var angle = 0.0
    private(set) var velocity = 0.0
    private(set) var dangerTime = 0.0
    private(set) var cooldown = 0.0
    private(set) var steadyTime = 0.0
    private var wasDanger = false

    init(params: RaftParams = RaftParams()) { self.params = params }

    var zone: RaftZone {
        let a = abs(angle)
        if a < params.steadyAngle { return .steady }
        if a < params.warnAngle { return .tilting }
        if a < params.dangerAngle { return .warning }
        return .danger
    }

    /// Which way to lean to recover: toward the high side (−1 = left, +1 = right, 0 = level enough).
    var recoverDirection: Double {
        abs(angle) < params.steadyAngle ? 0 : (angle > 0 ? -1 : 1)
    }

    mutating func impulse(_ degreesPerSecond: Double) { velocity += degreesPerSecond }

    mutating func reset() {
        angle = 0; velocity = 0; dangerTime = 0; cooldown = 0; steadyTime = 0; wasDanger = false
    }

    /// `leans`: each player's lean in −1…1. `externalTorque`: river current + an alligator hanging on (deg/s²).
    mutating func step(dt: Double, leans: [Double], crouched: Int, externalTorque: Double) -> [RaftEvent] {
        var events: [RaftEvent] = []
        var remaining = max(0, dt)
        let leanSum = leans.reduce(0) { $0 + max(-1, min(1, $1)) }
        let damping = params.damping + params.crouchDamping * Double(crouched)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 120)
            remaining -= h
            let torque = -params.restoring * angle - damping * velocity + externalTorque + params.leanTorque * leanSum
            velocity += torque * h
            angle += velocity * h
            if abs(angle) > params.maxAngle { angle = params.maxAngle * (angle > 0 ? 1 : -1); velocity = 0 }
        }
        cooldown = max(0, cooldown - dt)
        let danger = abs(angle) >= params.dangerAngle
        if danger, !wasDanger { events.append(.enteredDanger) }
        wasDanger = danger
        dangerTime = danger ? dangerTime + dt : 0
        if dangerTime >= params.splashAfter, cooldown == 0 {
            events.append(.splash)
            angle *= 0.35
            velocity = 0
            dangerTime = 0
            cooldown = params.splashCooldown
            wasDanger = false
        }
        if zone == .steady {
            let before = steadyTime
            steadyTime += dt
            if floor(steadyTime / params.steadyStreak) > floor(before / params.steadyStreak) { events.append(.steadyStreak) }
        } else {
            steadyTime = 0
        }
        return events
    }
}

/// River currents push gently and predictably on the raft (shown on the water as drift arrows). If nobody
/// corrects, the raft settles at a visible ~8–9° list: uncomfortable but not dangerous on its own.
nonisolated enum RiverCurrent {
    static let amplitude = 26.0
    static func torque(atDistance d: Double) -> Double {
        amplitude * sin(2 * .pi * d / 260 + 0.6) * (0.65 + 0.35 * sin(2 * .pi * d / 97))
    }
}

// MARK: - Lean input

/// Lean from a body pose (for the later camera build — unvalidated): the torso's sideways angle, neck relative to
/// hips, in square pixels. The image is mirrored like a mirror, so screen-right = the player's own right.
nonisolated struct LeanEstimator: Sendable {
    var deadZoneDegrees = 2.5
    var fullLeanDegrees = 12.0

    func lean(for pose: PersonPose) -> Double? {
        guard let neck = pose.point(.neck, minConfidence: 0.2), let hip = pose.hipCenter else { return nil }
        let dx = (neck.x - hip.x) * pose.aspect
        let dy = neck.y - hip.y
        guard dy > 0.02 else { return nil }
        let degrees = atan2(dx, dy) * 180 / .pi
        let magnitude = max(0, abs(degrees) - deadZoneDegrees) / (fullLeanDegrees - deadZoneDegrees)
        return min(1, magnitude) * (degrees >= 0 ? 1 : -1)
    }
}

/// How a responsive player leans: toward the high side, in proportion to the tilt they see (full lean at `fullAt`
/// degrees). Used by simulated/autoplay players; real players are expected to behave roughly like this.
nonisolated func responsiveLean(raftAngle: Double, effort: Double = 1, fullAt: Double = 6) -> Double {
    max(-1, min(1, -raftAngle / fullAt)) * effort
}

/// Simulated lean: ramps to `direction` over 0.25 s, holds, ramps back. Feeds the same raft as real input.
nonisolated struct SimulatedLean: Sendable {
    var start: Double
    var direction: Double
    var hold = 1.4
    var ramp = 0.25

    func value(at t: Double) -> Double {
        let local = t - start
        guard local >= 0, local <= hold + 2 * ramp else { return 0 }
        if local < ramp { return direction * local / ramp }
        if local < ramp + hold { return direction }
        return direction * (1 - (local - ramp - hold) / ramp)
    }
    var end: Double { start + hold + 2 * ramp }
}

// MARK: - Alligator strike

/// WARNING (bubbles, nothing visible) → APPROACH (eyes surface ahead on one side, swimming in) → STRIKE (it lunges
/// onto that edge: a jolt, then it hangs on, dragging that side down) → RECOVERY WINDOW (lean away together).
nonisolated struct GatorTiming: Equatable, Sendable {
    var warningDuration = 1.6
    var approachDuration = 2.6
    /// Longer than RaftParams.splashAfter, so ignoring the alligator always ends in a splash.
    var clingDuration = 2.4
    /// From the strike: how long the team has to get the raft steady again.
    var recoveryWindow = 4.6
    /// Holding a correct lean this long (cumulative) counts as that player's contribution.
    var holdToContribute = 0.4
    /// After the alligator lets go, the raft must stay steady this long to win.
    var steadyToWin = 0.5
    /// Jolt (deg/s) at the strike and pull (deg/s²) while it hangs on, toward the bitten side.
    var strikeImpulse = 35.0
    var clingTorque = 84.0

    var revealTime: Double { warningDuration }
    var strikeTime: Double { warningDuration + approachDuration }
    var releaseTime: Double { strikeTime + clingDuration }
    var windowCloseTime: Double { strikeTime + recoveryWindow }

    enum Phase: Equatable, Sendable { case warning, approach, clinging, recovering, over }

    func phase(at t: Double) -> Phase {
        if t < revealTime { return .warning }
        if t < strikeTime { return .approach }
        if t < releaseTime { return .clinging }
        if t <= windowCloseTime { return .recovering }
        return .over
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> GatorTiming {
        var t = GatorTiming()
        func read(_ key: String, _ value: inout Double) { if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) } }
        read("gatorWarning", &t.warningDuration)
        read("gatorApproach", &t.approachDuration)
        read("gatorCling", &t.clingDuration)
        read("gatorWindow", &t.recoveryWindow)
        return t
    }
}

nonisolated struct GatorChallenge: Sendable {
    enum Outcome: Equatable, Sendable {
        /// Raft steady again and everyone helped.
        case teamSteady(Set<Zone>)
        /// Raft steady again, but not everyone leaned.
        case steady(contributed: Set<Zone>, missing: Set<Zone>)
        /// Window ran out with the raft still rocking (no splash).
        case wobbly(contributed: Set<Zone>)
        /// The raft dipped and water washed over.
        case splashed(contributed: Set<Zone>)
        case cancelled
    }

    let side: Zone
    let timing: GatorTiming
    private(set) var team: TeamChallenge
    private(set) var leanTime: [Zone: Double] = [:]
    private(set) var steadyRun = 0.0
    private(set) var outcome: Outcome?

    init(id: Int, side: Zone, participants: Set<Zone>, timing: GatorTiming = GatorTiming()) {
        self.side = side
        self.timing = timing
        team = TeamChallenge(id: id, participants: participants)
    }

    /// Lean away from the bitten edge, toward the high side.
    var correctDirection: Double { side == .left ? 1 : -1 }
    var isOpen: Bool { outcome == nil }

    /// Records one frame of a player's lean during the strike/recovery. Returns Team Power to bank (once each).
    mutating func record(_ zone: Zone, lean: Double, dt: Double, at t: Double) -> Int {
        guard isOpen, t >= timing.strikeTime, t <= timing.windowCloseTime, lean * correctDirection >= 0.35 else { return 0 }
        leanTime[zone, default: 0] += dt
        guard leanTime[zone, default: 0] >= timing.holdToContribute else { return 0 }
        return team.contribute(zone, at: t)
    }

    /// Feeds the raft state each frame; resolves exactly once.
    mutating func observe(angle: Double, steadyAngle: Double, splashed: Bool, dt: Double, at t: Double) -> (Outcome, bonus: Int)? {
        guard isOpen, t >= timing.strikeTime else { return nil }
        var result = team
        let done = team.contributed
        if splashed {
            result.cancel()
            team = result
            outcome = .splashed(contributed: done)
            return (outcome!, 0)
        }
        if t >= timing.releaseTime {
            steadyRun = abs(angle) < steadyAngle ? steadyRun + dt : 0
            if steadyRun >= timing.steadyToWin {
                let (teamOutcome, bonus) = result.resolve()
                team = result
                switch teamOutcome {
                case .team(let zones): outcome = .teamSteady(zones)
                case .partial(let c, let m): outcome = .steady(contributed: c, missing: m)
                case .cancelled: outcome = .cancelled
                }
                return (outcome!, bonus)
            }
        }
        if t > timing.windowCloseTime {
            result.cancel()
            team = result
            outcome = .wobbly(contributed: done)
            return (outcome!, 0)
        }
        return nil
    }

    mutating func cancel() {
        guard isOpen else { return }
        var t = team
        t.cancel()
        team = t
        outcome = .cancelled
    }
}

// MARK: - Hazard director

nonisolated enum JungleBeat: Equatable, Sendable {
    case birds
    case gator(Zone)
    /// An alligator, and while the raft is still rocking, a bird warning begins (the duck window opens only after
    /// the alligator's recovery window has closed).
    case gatorThenBirds(Zone)
    /// Piranhas leap across the deck from one side: a single leap, or a short burst on the same side.
    case piranhas(from: Zone, count: Int)
    /// An alligator, then — as the raft settles — piranhas from the other side (the jump window opens only after
    /// the alligator's recovery window has closed).
    case gatorThenPiranhas(Zone)
    /// River Log Sweep: a wave sets driftwood on the bow; it rolls down the deck through both lanes (JUMP).
    case logSweep
    /// Crocodile Tail Sweep: the croc beside the bow coils its tail and whips it low across the deck (JUMP).
    case tailSweep(Zone)
    /// The signature combo: the crocodile rams (BALANCE), and once the raft is steady it comes back round for a
    /// tail sweep (JUMP). The tail's JUMP cue comes only after the ram's recovery window has closed.
    case gatorThenTail(Zone)
    /// A breather: no demands; the raft drifts, sometimes past a landmark.
    case calm(landmark: Bool)
}

nonisolated struct JungleDirector: Sendable {
    /// One lap: every hazard appears, the three movements alternate, and no two jump/duck demands come back to back
    /// without a beat of another kind or a calm stretch between them.
    /// Jumps come from three different hazards with different shapes (a fish arc from the side, a log rolling at you,
    /// a tail swung from the bow), so a lap varies the pattern rather than only the speed.
    static let cycle: [JungleBeat] = [.birds, .piranhas(from: .left, count: 1), .gator(.left), .logSweep, .calm(landmark: true),
                                      .gatorThenPiranhas(.right), .birds, .tailSweep(.right), .gatorThenBirds(.left),
                                      .piranhas(from: .right, count: 2), .calm(landmark: false), .gatorThenTail(.right),
                                      .birds, .logSweep, .calm(landmark: false)]
    /// The Revision 9 lap (before the log and tail sweeps). The coop test script still follows this order.
    static let revision9Cycle: [JungleBeat] = [.birds, .piranhas(from: .left, count: 1), .gator(.left), .calm(landmark: true),
                                               .gatorThenPiranhas(.right), .birds, .piranhas(from: .right, count: 2),
                                               .gatorThenBirds(.left), .calm(landmark: false)]
    static let maxBurst = 3
    /// Neutral time after any beat resolves before the next begins.
    var recovery = 3.0
    var calmDuration = 6.0
    /// Seconds after the alligator strike that the combo bird warning begins.
    var comboBirdDelay = 1.2
    /// Seconds after the alligator strike that the combo piranha warning begins.
    var comboPiranhaDelay = 2.6
    /// Seconds after the alligator strike that the combo tail warning may begin (it also waits for a steady raft).
    var comboTailDelay = 3.4
    /// A fixed order of beats (test scripts); when set, `next()` plays it instead of the cycle and `reset()` keeps
    /// its position (a script's replay step continues the script).
    private(set) var playlist: [JungleBeat]?
    private(set) var playlistIndex = 0
    private(set) var index = 0
    /// Which cycle the endless mode plays (the coop script pins the Revision 9 lap).
    var lap: [JungleBeat] = Self.cycle

    /// Beats repeat. Alligator and piranha sides are mirrored on every other lap so nothing is predictable, and each
    /// lap adds one fish to the piranha bursts (up to three) so the jumping gets busier as the family warms up.
    mutating func next() -> JungleBeat {
        if let playlist, playlistIndex < playlist.count {
            playlistIndex += 1
            return playlist[playlistIndex - 1]
        }
        var beat = self.lap[index % self.lap.count]
        let lap = index / self.lap.count
        func flip(_ z: Zone) -> Zone { lap % 2 == 1 ? (z == .left ? .right : .left) : z }
        switch beat {
        case .gator(let z): beat = .gator(flip(z))
        case .gatorThenBirds(let z): beat = .gatorThenBirds(flip(z))
        case .gatorThenPiranhas(let z): beat = .gatorThenPiranhas(flip(z))
        case .piranhas(let z, let count): beat = .piranhas(from: flip(z), count: min(Self.maxBurst, count + lap))
        case .tailSweep(let z): beat = .tailSweep(flip(z))
        case .gatorThenTail(let z): beat = .gatorThenTail(flip(z))
        default: break
        }
        index += 1
        return beat
    }

    mutating func reset() { index = 0 }

    mutating func setPlaylist(_ beats: [JungleBeat]?) {
        playlist = beats
        playlistIndex = 0
    }

    /// The combo bird's duck window must open only after the alligator's recovery window has closed.
    static func comboIsSequential(gator: GatorTiming, birds: EncounterTiming, delay: Double) -> Bool {
        delay + birds.cueTime >= gator.recoveryWindow
    }

    /// Same rule for the combo piranhas' JUMP cue.
    static func comboIsSequential(gator: GatorTiming, piranhas: PiranhaTiming, from side: Zone, delay: Double) -> Bool {
        delay + piranhas.cueTime(from: side) >= gator.recoveryWindow
    }

    /// Same rule for the combo tail sweep's JUMP cue (it comes back round on the same side it rammed).
    static func comboIsSequential(gator: GatorTiming, tail: TailSweepTiming, side: Zone, delay: Double) -> Bool {
        delay + tail.cueTime(side: side) >= gator.recoveryWindow
    }

    /// The piranhas in a combo come from the side opposite the bite (the raft has just been dragged down there).
    static func comboPiranhaSide(gatorSide: Zone) -> Zone { gatorSide == .left ? .right : .left }
}
