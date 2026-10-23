import Foundation

// LASER BREAKOUT — The Great Getaway. Pure, renderer-free rules (compiled into the macOS logic tests).
//
// Spatial model (shared with the renderer, which only projects it):
//   • The players ride a getaway cart down a straight vault corridor. They face the camera, so — exactly like the
//     train and the raft — they travel toward the vanishing point while facing backwards. The cart deck under their
//     feet travels with them and never slides (a sliding floor under the feet reads as being dragged backwards; see
//     Revision 6). The corridor (floor, walls, ceiling lights) and the security gates stream past from the far end of
//     the corridor toward the camera.
//   • Units: x across (players at ±0.65), h above the cart deck, z depth from the camera (players' plane at 1.9).
//   • A security gate is fixed to the corridor. Its beam is a straight line across one or both lanes at a fixed
//     height; it crosses the players' plane when the gate's z reaches 1.9. That crossing is the moment that is judged.

// MARK: - Corridor space

nonisolated enum Corridor {
    static let playerZ = 1.9
    static let laneX = 0.65
    /// Walls, floor (the cart hovers above it) and ceiling, relative to the deck.
    static let halfWidth = 2.0
    static let floorH = -0.35
    static let ceilingH = 2.3
    /// The cart's deck footprint (static under the players).
    static let deckHalfWidth = 1.15
    static let deckNearZ = 1.15
    static let deckFarZ = 3.05
    /// Gates appear out of the corridor haze here.
    static let revealZ = 30.0
    /// Low beams sweep the deck at shin height; high beams at a share of each player's own standing height.
    static let lowBeamH = 0.13
    static let highBeamShare = 0.8

    static func laneX(_ zone: Zone) -> Double { zone == .left ? -laneX : laneX }

    /// Height of a high beam for a player whose head is `headH` above the deck: below the standing head (it would
    /// hit them standing), above the head of the same player in a full squat (≈ 0.66 of standing height).
    static func highBeamH(forHeadHeight headH: Double) -> Double { max(0.45, headH * highBeamShare) }
}

// MARK: - Hazards

nonisolated enum LaserAction: String, Sendable { case duck, jump }

nonisolated enum LaserPattern: Equatable, Sendable {
    /// A high beam across both lanes: both DUCK.
    case highBeam
    /// A low beam sweeping the deck: both JUMP.
    case floorSweep
    /// The signature: each lane gets its own beam. `parentHigh` → the Parent (left lane) ducks a high beam while the
    /// Child (right lane) jumps a low one; otherwise the other way round.
    case splitGrid(parentHigh: Bool)

    func action(for zone: Zone) -> LaserAction {
        switch self {
        case .highBeam: .duck
        case .floorSweep: .jump
        case .splitGrid(let parentHigh): (zone == .left) == parentHigh ? .duck : .jump
        }
    }

    var isSplit: Bool { if case .splitGrid = self { true } else { false } }
}

nonisolated struct LaserTiming: Equatable, Sendable {
    /// Alarm, banner and lane warnings before anything is visible.
    var warningDuration = 1.8
    /// Cart speed through the corridor (units/s). The gate's approach time follows from it.
    var speed = 6.5
    /// "DUCK!"/"JUMP!" lead before the crossing.
    var cueLead = 1.4
    /// Judging window around the crossing (jump: airborne; duck: low in a fresh squat).
    var window = JumpWindow(clearBefore: 0.35, clearAfter: 0.25, lateLabelWindow: 0.6, earlyLookback: 1.2)
    /// After the crossing: reward and recovery before the next warning may start.
    var recovery = 3.0

    var revealTime: Double { warningDuration }
    var approachDuration: Double { (Corridor.revealZ - Corridor.playerZ) / speed }
    var crossingTime: Double { revealTime + approachDuration }
    var cueTime: Double { crossingTime - cueLead }
    /// The gate's depth at encounter time t (it rides with the corridor).
    func gateZ(at t: Double) -> Double { Corridor.playerZ + speed * (crossingTime - t) }
    var judgeOpen: Double { crossingTime - window.clearBefore }
    var judgeClose: Double { crossingTime + window.clearAfter }
    var endTime: Double { crossingTime + window.clearAfter + window.lateLabelWindow + 0.2 }

    var isValid: Bool { warningDuration > 0.5 && speed > 1 && cueLead > 0.6 && cueTime > revealTime + 0.5 }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> LaserTiming {
        var t = LaserTiming()
        func read(_ key: String, _ value: inout Double) { if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) } }
        read("laserWarning", &t.warningDuration)
        read("laserSpeed", &t.speed)
        read("laserCueLead", &t.cueLead)
        read("laserRecovery", &t.recovery)
        if defaults.object(forKey: "jumpBefore") != nil { t.window.clearBefore = defaults.double(forKey: "jumpBefore") }
        if defaults.object(forKey: "jumpAfter") != nil { t.window.clearAfter = defaults.double(forKey: "jumpAfter") }
        return t.isValid ? t : LaserTiming()
    }
}

// MARK: - Fresh squats (no reward for holding a movement)

/// A duck counts only from a squat that began after this encounter's warning, and each squat can clear one beam.
/// Holding a squat through two beams clears the first only; standing up and squatting again clears the next.
nonisolated struct DuckFreshness: Sendable {
    private(set) var serial: [Zone: Int] = [:]
    private var consumed: [Zone: Int] = [:]

    /// Call on every `descentStarted`.
    mutating func descentStarted(_ zone: Zone) { serial[zone, default: 0] += 1 }

    /// The squat serial at an encounter's warning: only squats after it count for that encounter.
    func mark() -> [Zone: Int] { serial }

    /// Low in a squat that started after `mark` and hasn't cleared anything yet.
    func isFreshLow(_ zone: Zone, low: Bool, since mark: [Zone: Int]) -> Bool {
        let s = serial[zone, default: 0]
        return low && s > mark[zone, default: 0] && consumed[zone] != s
    }

    mutating func consume(_ zone: Zone) { consumed[zone] = serial[zone, default: 0] }
}

// MARK: - One encounter: per-lane judging, one shared outcome

nonisolated struct LaserEncounter: Sendable {
    let pattern: LaserPattern
    let timing: LaserTiming
    private(set) var judge: JumpSweepJudge
    let duckMark: [Zone: Int]

    /// Each lane's own judging window (a child may get a more generous one); the judge runs with the widest and each
    /// lane only counts inside its own.
    let laneWindows: [Zone: JumpWindow]

    /// `crossings`: per-lane crossing times when they differ (a rotating turret reaches the lanes one after the
    /// other); otherwise every lane crosses at the gate's `timing.crossingTime`.
    init(id: Int, pattern: LaserPattern, participants: Set<Zone>, timing: LaserTiming, duckMark: [Zone: Int],
         crossings: [Zone: Double]? = nil, cueTime: Double? = nil, laneWindows: [Zone: JumpWindow] = [:]) {
        self.pattern = pattern
        self.timing = timing
        self.duckMark = duckMark
        self.laneWindows = laneWindows
        let crossings = crossings ?? Dictionary(uniqueKeysWithValues: Zone.allCases.map { ($0, timing.crossingTime) })
        var widest = timing.window
        for w in laneWindows.values {
            widest.clearBefore = max(widest.clearBefore, w.clearBefore)
            widest.clearAfter = max(widest.clearAfter, w.clearAfter)
        }
        judge = JumpSweepJudge(id: id, crossings: crossings, cueTime: cueTime ?? timing.cueTime, participants: participants, window: widest)
    }

    func window(_ zone: Zone) -> JumpWindow { laneWindows[zone] ?? timing.window }
    func crossing(_ zone: Zone) -> Double { judge.crossing(zone) }

    var isOpen: Bool { judge.isOpen }
    var participants: Set<Zone> { judge.participants }
    var results: [Zone: JumpJudgeResult] { judge.results }

    /// `airborne`: jump state; `low`: in a squat past the bottom (phase down/rising). Duck lanes also need the squat
    /// to be fresh (see DuckFreshness); cleared ducks consume their squat.
    mutating func update(at t: Double, airborne: [Zone: Bool], low: [Zone: Bool], freshness: inout DuckFreshness) -> [JumpJudgeEvent] {
        var ok: [Zone: Bool] = [:]
        for zone in Zone.allCases {
            switch pattern.action(for: zone) {
            case .jump: ok[zone] = airborne[zone] ?? false
            case .duck: ok[zone] = freshness.isFreshLow(zone, low: low[zone] ?? false, since: duckMark)
            }
            // The judge runs with the widest lane's window: in the part of it outside this lane's own window the move
            // doesn't count. (Outside the widest window the raw state still goes through: it labels TOO EARLY.)
            let w = window(zone), tc = crossing(zone), wide = judge.window
            if (t >= tc - wide.clearBefore && t < tc - w.clearBefore) || (t > tc + w.clearAfter && t <= tc + wide.clearAfter) { ok[zone] = false }
        }
        let events = judge.update(at: t, airborne: ok)
        for case .cleared(let zone, _) in events where pattern.action(for: zone) == .duck { freshness.consume(zone) }
        return events
    }

    mutating func cancel() { judge.cancel() }
}

// MARK: - Security Alert (pressure without a difficulty spiral)

/// 0 … 1. Missed beams raise it, clean team dodges cool it down. It drives the alarm's intensity (lights, siren) and
/// is shown on the HUD; it never changes beam speed, windows or spacing, so a struggling child is never punished with
/// a harder game. At the top it saturates ("LOCKDOWN!") rather than ending the run.
nonisolated struct SecurityAlert: Sendable {
    var perMiss = 0.18
    var perTeamDodge = 0.08
    var perSoloDodge = 0.03
    private(set) var level = 0.0
    private(set) var peaked = false

    enum Event: Equatable, Sendable { case crossedHigh, maxed }

    /// Returns threshold crossings (for the HUD/alarm to react once).
    mutating func record(missed: Int, team: Bool, cleared: Int) -> [Event] {
        let before = level
        level += Double(missed) * perMiss
        if team { level -= perTeamDodge } else if cleared > 0, missed == 0 { level -= perSoloDodge }
        level = max(0, min(1, level))
        var events: [Event] = []
        if before < 0.6, level >= 0.6 { events.append(.crossedHigh) }
        if !peaked, level >= 1 { peaked = true; events.append(.maxed) }
        return events
    }

    mutating func reset() { level = 0; peaked = false }
}

// MARK: - The getaway script (three phases in one run)

nonisolated enum LaserPhase: String, Sendable { case alarm = "ALARM TRIGGERED", pursuit = "SECURITY PURSUIT", lockdown = "FINAL LOCKDOWN" }

nonisolated enum LaserBeat: Equatable, Sendable {
    /// Scenery and set pieces only (vault doors, cameras); no demands.
    case breather(Double)
    case laser(LaserPattern)
    /// A choreographed run of gates (double pulse, alternating combo, split-lane crossfire, sweeps, the gauntlet).
    case sequence(LaserSequence)
    /// The phase changes here (title card, lighting state, doors).
    case phase(LaserPhase)
    /// Opening set piece: the vault door swings open ahead, the alarm trips (Phase A).
    case vaultOpen
    /// Final lockdown hero moment: a gate with one lock per player; each player's squats crank their lever.
    case override
    /// The final exit: the doors open and the finale plays.
    case escape
}

nonisolated struct LaserDirector: Sendable {
    /// One getaway. Teaches duck, then jump, then mixes; split grids only once both moves are familiar; the final
    /// lockdown is a short, readable combination — never a speed-up.
    ///   A · alarm — learn: one duck, one jump, then a sweep (the emitter swings the beam into the lane).
    ///   B · pursuit — vary: a double pulse (same move twice: a fresh squat each time), a split grid, an alternating
    ///       duck → jump → duck combo.
    ///   C · lockdown — combine: the split-lane crossfire (each player a different two-move sequence) and the final
    ///       gauntlet, then the lockdown gate. Harder through choreography, never through speed.
    static let getaway: [LaserBeat] = [
        .vaultOpen, .phase(.alarm), .breather(2.0),
        .laser(.highBeam), .laser(.floorSweep), .sequence(.sweep(.highBeam)),
        .phase(.pursuit), .breather(1.5),
        .sequence(.turret(.highBeam, wave: true)), .sequence(.doublePulse(.highBeam)), .laser(.splitGrid(parentHigh: true)), .sequence(.alternating),
        .phase(.lockdown), .breather(1.5),
        .sequence(.crossfire), .sequence(.gauntlet),
        .override, .escape,
    ]

    /// Easy: one laser at a time with a generous telegraph. Hard: longer mixed sequences, a staggered turret wave, a
    /// three-step crossfire and a four-step final gauntlet — harder through recognition and choreography.
    static let getawayEasy: [LaserBeat] = [
        .vaultOpen, .phase(.alarm), .breather(2.0),
        .laser(.highBeam), .laser(.floorSweep), .laser(.highBeam),
        .phase(.pursuit), .breather(1.5),
        .sequence(.turret(.highBeam, wave: false)), .laser(.splitGrid(parentHigh: true)), .laser(.floorSweep),
        .phase(.lockdown), .breather(1.5),
        .laser(.splitGrid(parentHigh: false)), .sequence(.sweep(.highBeam)),
        .override, .escape,
    ]
    static let getawayHard: [LaserBeat] = [
        .vaultOpen, .phase(.alarm), .breather(2.0),
        .laser(.highBeam), .laser(.floorSweep), .sequence(.turret(.highBeam, wave: true)),
        .phase(.pursuit), .breather(1.5),
        .sequence(.doublePulse(.floorSweep)), .sequence(.alternating4), .sequence(.turret(.floorSweep, wave: true)),
        .phase(.lockdown), .breather(1.5),
        .sequence(.crossfire3), .sequence(.gauntletHard),
        .override, .escape,
    ]

    static func getaway(for level: LaserDifficulty.Level) -> [LaserBeat] {
        switch level {
        case .easy: getawayEasy
        case .normal: getaway
        case .hard: getawayHard
        }
    }

    var beats: [LaserBeat] = Self.getaway
    private(set) var index = 0

    mutating func next() -> LaserBeat? {
        guard index < beats.count else { return nil }
        index += 1
        return beats[index - 1]
    }

    var isFinished: Bool { index >= beats.count }
    var lasersRemaining: Int { beats[index...].filter { if case .laser = $0 { true } else { false } }.count }
    mutating func reset() { index = 0 }

    /// The run's length at a given timing (warnings, approaches, recoveries and breathers), excluding the finale.
    static func runDuration(_ beats: [LaserBeat], timing: LaserTiming) -> Double {
        beats.reduce(0) { total, beat in
            switch beat {
            case .breather(let s): total + s
            case .laser: total + timing.endTime + timing.recovery
            case .sequence(let s): total + timing.endTime + timing.recovery + s.spacing * Double(s.steps.count - 1)
            case .vaultOpen: total + 3.5
            case .override: total + 8
            case .phase, .escape: total
            }
        }
    }
}

// MARK: - Final lockdown: the dual security override

/// The last gate has one lock per player. Each player cranks their own lever with squats (arms up, squat = pull the
/// lever down); `cranksNeeded` completed reps release that lock. The gate opens only when every participant's lock is
/// released — one shared obstacle that needs both players, without any timing pressure between them.
nonisolated struct DualOverride: Sendable {
    let cranksNeeded: Int
    let participants: Set<Zone>
    private(set) var cranks: [Zone: Int] = [:]
    private(set) var isOpen = false

    enum Event: Equatable, Sendable { case crank(Zone, Int), unlocked(Zone), open }

    init(participants: Set<Zone>, cranksNeeded: Int = 2) {
        self.participants = participants
        self.cranksNeeded = cranksNeeded
    }

    var unlocked: Set<Zone> { Set(participants.filter { (cranks[$0] ?? 0) >= cranksNeeded }) }
    func progress(_ zone: Zone) -> Double { min(1, Double(cranks[zone] ?? 0) / Double(cranksNeeded)) }

    /// One completed rep from a player. Ignored for non-participants, released locks and an open gate.
    mutating func crank(_ zone: Zone) -> [Event] {
        guard !isOpen, participants.contains(zone), (cranks[zone] ?? 0) < cranksNeeded else { return [] }
        cranks[zone, default: 0] += 1
        var events: [Event] = [.crank(zone, cranks[zone]!)]
        if cranks[zone]! >= cranksNeeded { events.append(.unlocked(zone)) }
        if unlocked == participants { isOpen = true; events.append(.open) }
        return events
    }
}

// MARK: - Experimental: reach up → pull down (not wired into gameplay; needs real-camera validation)

/// A lever-pull gesture from body pose: a wrist raised clearly above the head, then brought down below the shoulders
/// within `maxPullTime`. Body-relative (torso length), so it doesn't depend on height or distance. One event per cycle:
/// the wrist must rise above the head again before the next pull counts.
nonisolated struct ReachPullDetector: Sendable {
    var reachAbove = 0.15      // wrist above the nose/neck by this × torso length = reaching
    var pullBelow = 0.10       // wrist below the shoulders by this × torso length = pulled
    var maxPullTime = 1.5
    private(set) var reachingSince: Double?

    mutating func update(pose: PersonPose, at t: Double) -> Bool {
        guard let neck = pose.point(.neck), let hip = pose.hipCenter else { return false }
        let torso = max(0.05, neck.y - hip.y)
        let head = pose.point(.nose)?.y ?? neck.y
        let shoulders = [pose.point(.leftShoulder), pose.point(.rightShoulder)].compactMap { $0?.y }
        let shoulderY = shoulders.isEmpty ? neck.y : shoulders.reduce(0, +) / Double(shoulders.count)
        guard let wrist = [pose.point(.leftWrist), pose.point(.rightWrist)].compactMap({ $0?.y }).max() else { return false }
        if wrist > head + reachAbove * torso {
            if reachingSince == nil { reachingSince = t }
            return false
        }
        if let since = reachingSince, wrist < shoulderY - pullBelow * torso {
            reachingSince = nil
            return t - since <= maxPullTime
        }
        if let since = reachingSince, t - since > maxPullTime + 1 { reachingSince = nil }
        return false
    }
}

// MARK: - Choreographed sequences

/// One gate of a sequence. `sweep`: the emitter swings the beam into place (from the ceiling for a high beam, from the
/// floor for a low one) during its approach; it settles at its judged height before the judging window opens.
nonisolated struct LaserStep: Equatable, Sendable {
    var pattern: LaserPattern
    var sweep = false
    /// A rail turret instead of a gate: it rides alongside the cart just ahead of the players and swings its beam
    /// toward the camera through the lanes (see TurretSweep). `stagger` delays the right-hand turret (a "wave").
    var turret = false
    var stagger = 0.0
    /// An iris security gate: an approaching gate whose ring opens its aperture and orbits its emitter pods to the lane
    /// heights before firing (same timeline and judging as a gate).
    var iris = false

    /// The first lane crossing on this step's own clock (sequences space crossings, not warnings).
    func firstCrossing(_ timing: LaserTiming) -> Double {
        turret ? TurretSweep.crossings(timing: timing, stagger: stagger).values.min() ?? timing.crossingTime : timing.crossingTime
    }
}

/// A rotating sweep. Each lane has a turret on its own wall rail, clamped `ahead` units in front of the players' plane
/// (it rides with the cart, so its geometry doesn't change while it attacks). The beam starts straight across the
/// corridor (harmless: in front of the players), then rotates at a constant rate toward the camera; it passes through
/// a lane's centre exactly when the angle reaches atan(ahead / distance from the wall). Each turret's beam stops at
/// the corridor centre line, so it only ever sweeps its own lane. That moment is the lane's
/// crossing: the beam drawn and the beam judged come from this one function.
nonisolated enum TurretSweep {
    /// Far enough ahead that the straight-across beam reads clearly as in front of the players, not through them.
    static let ahead = 2.5
    /// After the reveal: slide along the rail and clamp; deploy and charge; fire (straight across); start rotating.
    static let clampAt = 1.6, fireAt = 2.2, rotateAt = 2.6
    /// Constant angular speed (rad/s) and where the sweep ends (past the players, then shutdown).
    static let omega = 0.6
    static let endAngle = 1.45

    static func angle(at r: Double, stagger: Double = 0) -> Double { min(endAngle, max(0, (r - rotateAt - stagger) * omega)) }
    static func laneAngle(_ zone: Zone) -> Double { atan2(ahead, Corridor.halfWidth - Corridor.laneX) }
    /// Per-lane crossing times on the encounter clock (revealTime + …).
    static func crossings(timing: LaserTiming, stagger: Double) -> [Zone: Double] {
        Dictionary(uniqueKeysWithValues: Zone.allCases.map { zone in
            (zone, timing.revealTime + rotateAt + (zone == .right ? stagger : 0) + laneAngle(zone) / omega)
        })
    }
    /// When the last turret has finished rotating (past the players).
    static func endTime(timing: LaserTiming, stagger: Double) -> Double { timing.revealTime + rotateAt + stagger + endAngle / omega }

    /// The turret's depth over its life (r = time since the reveal): it runs up the wall rail from the far corridor,
    /// decelerates and clamps `ahead` of the players (a small hydraulic settle), stays there while it attacks, then
    /// unclamps after `endR` and falls behind with the corridor.
    static func depth(r: Double, endR: Double, speed: Double) -> Double {
        let clampZ = Corridor.playerZ + ahead
        if r < 0 { return 40 }
        if r < clampAt { return clampZ + (14 - clampZ) * pow(1 - r / clampAt, 3) }
        let release = endR + 0.9
        if r < release {
            let k = r - clampAt
            return clampZ + (k < 0.35 ? 0.07 * sin(k / 0.35 * .pi) : 0)
        }
        return clampZ - speed * (r - release)
    }
}

nonisolated struct LaserSequence: Equatable, Sendable {
    var name: String
    var steps: [LaserStep]
    /// Seconds between consecutive gates' crossings (each gate keeps the full single-gate timeline, shifted).
    var spacing: Double

    static func sweep(_ p: LaserPattern) -> LaserSequence { LaserSequence(name: "SWEEP", steps: [LaserStep(pattern: p, sweep: true)], spacing: 0) }
    static func doublePulse(_ p: LaserPattern) -> LaserSequence {
        LaserSequence(name: "DOUBLE PULSE", steps: [LaserStep(pattern: p), LaserStep(pattern: p)], spacing: 2.8)
    }
    static let alternating = LaserSequence(name: "COMBO", steps: [LaserStep(pattern: .highBeam), LaserStep(pattern: .floorSweep), LaserStep(pattern: .highBeam)], spacing: 3.0)
    /// Parent: DUCK → JUMP · Child: JUMP → DUCK.
    static let crossfire = LaserSequence(name: "CROSSFIRE", steps: [LaserStep(pattern: .splitGrid(parentHigh: true), iris: true), LaserStep(pattern: .splitGrid(parentHigh: false), iris: true)], spacing: 3.0)
    static let gauntlet = LaserSequence(name: "GAUNTLET", steps: [LaserStep(pattern: .highBeam, turret: true), LaserStep(pattern: .floorSweep), LaserStep(pattern: .splitGrid(parentHigh: false))], spacing: 3.0)
    /// The rotating sweep on its own; `wave` staggers the lanes (Parent's first, then the Child's).
    static func turret(_ p: LaserPattern, wave: Bool) -> LaserSequence {
        LaserSequence(name: "TURRET", steps: [LaserStep(pattern: p, turret: true, stagger: wave ? 0.9 : 0)], spacing: 0)
    }
    /// Hard: longer mixed sequences.
    static let alternating4 = LaserSequence(name: "COMBO", steps: [LaserStep(pattern: .highBeam), LaserStep(pattern: .floorSweep), LaserStep(pattern: .highBeam), LaserStep(pattern: .floorSweep)], spacing: 2.85)
    static let crossfire3 = LaserSequence(name: "CROSSFIRE", steps: [LaserStep(pattern: .splitGrid(parentHigh: true), iris: true), LaserStep(pattern: .splitGrid(parentHigh: false), iris: true), LaserStep(pattern: .splitGrid(parentHigh: true), iris: true)], spacing: 2.85)
    static let gauntletHard = LaserSequence(name: "GAUNTLET", steps: [LaserStep(pattern: .highBeam, turret: true), LaserStep(pattern: .splitGrid(parentHigh: true)), LaserStep(pattern: .floorSweep), LaserStep(pattern: .splitGrid(parentHigh: false))], spacing: 2.85)

    /// The moves each lane must make, in order.
    func actions(for zone: Zone) -> [LaserAction] { steps.map { $0.pattern.action(for: zone) } }

    /// Minimum seconds between two consecutive moves in one lane (prototype values to tune with real players):
    /// a duck needs the squat (~1.2 s) plus standing up again; a jump needs the landing and settling.
    static func minGap(_ a: LaserAction, _ b: LaserAction) -> Double {
        switch (a, b) {
        case (.duck, .duck): 2.2
        case (.jump, .jump): 1.8
        case (.duck, .jump): 2.4
        case (.jump, .duck): 2.0
        }
    }

    /// Never asks a lane for a move it can't physically recover into in time (at a spacing scale, e.g. difficulty).
    func isFeasible(spacingScale: Double = 1) -> Bool {
        for zone in Zone.allCases {
            let acts = actions(for: zone)
            for i in acts.indices.dropFirst() where spacing * spacingScale < Self.minGap(acts[i - 1], acts[i]) { return false }
        }
        return true
    }
}

/// Difficulty is choreography, not speed: presets change the telegraph, the gap between moves in a sequence and the
/// recovery after an encounter; beam speed changes only a little. (`-laserDifficulty easy|normal|hard`)
nonisolated struct LaserDifficulty: Equatable, Sendable {
    enum Level: String, Sendable { case easy, normal, hard }
    var level = Level.normal
    var warningScale = 1.0
    var spacingScale = 1.0
    var recoveryScale = 1.0
    var speedScale = 1.0
    /// The child's judging window relative to the parent's (a child's squat and jump take longer to land in time;
    /// the child is never held to the parent's timing).
    var childWindowScale = 1.2

    static let easy = LaserDifficulty(level: .easy, warningScale: 1.3, spacingScale: 1.2, recoveryScale: 1.3, speedScale: 0.92, childWindowScale: 1.35)
    static let normal = LaserDifficulty()
    static let hard = LaserDifficulty(level: .hard, warningScale: 0.85, spacingScale: 0.85, recoveryScale: 0.8, speedScale: 1.08, childWindowScale: 1.15)

    /// `-laserDifficulty easy|normal|hard`, `-laserChildWindow 1.3` overrides the child allowance.
    static func fromDefaults(_ d: UserDefaults = .standard) -> LaserDifficulty {
        var out: LaserDifficulty
        switch d.string(forKey: "laserDifficulty") {
        case "easy": out = .easy
        case "hard": out = .hard
        default: out = .normal
        }
        if d.object(forKey: "laserChildWindow") != nil { out.childWindowScale = max(1, min(2, d.double(forKey: "laserChildWindow"))) }
        return out
    }

    func childWindow(_ w: JumpWindow) -> JumpWindow {
        var out = w
        out.clearBefore *= childWindowScale
        out.clearAfter *= childWindowScale
        return out
    }

    func apply(to t: LaserTiming) -> LaserTiming {
        var out = t
        out.warningDuration *= warningScale
        out.recovery *= recoveryScale
        out.speed *= speedScale
        return out.isValid ? out : t
    }
}
