import Foundation

// MOONBOUND — Rocket Together. Pure, renderer-free rules (compiled into the macOS logic tests).
//
// Spatial model (vertical travel; different from the corridor/river modes, which travel along z):
//   • The camera rides on the rocket. It looks horizontally at the players, 1 unit above the launch deck, exactly
//     like the other modes (same Projection: same horizon, feet line, focal length), so the two cutouts keep their
//     scale and their feet stay on the deck. The deck, the boosters and the players never move on screen.
//   • The rocket climbs: its deck altitude A (world units) rises. A world object at altitude a and depth z is drawn
//     at height h = a − A above the deck, so its screen y = horizon − f·(camH − h)/z falls by f/z per unit climbed.
//     Everything outside the rocket therefore moves DOWN while the rocket rises, and near things (small z) faster
//     than far things: vertical parallax from one formula, not from unrelated scrolling layers.
//   • The ground is a planet (radius R) under the camera, ray-cast in a shader with the same camera. As A grows the
//     ground drops away below the deck, its details shrink toward the horizon, and the horizon itself dips
//     (Earth's curvature). Above `limbHold` the world camera pitches down just enough to keep Earth's limb in view.
//   • Stars and the Moon are at infinity (fixed in the camera's frame); the Moon grows as the trip nears its end.
//   • Altitude is stylized gameplay distance, not a physical measurement.

nonisolated enum MoonPhase: Int, CaseIterable, Comparable, Sendable {
    case launch, sky, upperAtmosphere, space, approach, arrived

    var title: String {
        switch self {
        case .launch: "LIFT-OFF"
        case .sky: "SKY ASCENT"
        case .upperAtmosphere: "UPPER ATMOSPHERE"
        case .space: "OUTER SPACE"
        case .approach: "MOON APPROACH"
        case .arrived: "TOUCHDOWN"
        }
    }

    /// Progress at which each phase begins (the trip is 0 … 1).
    var start: Double {
        switch self {
        case .launch: 0
        case .sky: 0.12
        case .upperAtmosphere: 0.42
        case .space: 0.62
        case .approach: 0.86
        case .arrived: 1
        }
    }

    static func at(progress p: Double) -> MoonPhase {
        allCases.last { p >= $0.start - 1e-9 } ?? .launch
    }

    static func < (a: MoonPhase, b: MoonPhase) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - The race: first to the Moon, with a time cap

/// Format (chosen over a pure timed-altitude race): the first rocket to reach the Moon wins on the spot — a real
/// finish line and a final sprint — but the round is capped (75 s) so it stays short and comfortable for a child;
/// at the cap the higher rocket wins. Every valid rep gives the same thrust to everyone; two gentle rules keep it
/// fair and safe: a trailing player's thrust gets a capped "slipstream" bonus, and reps faster than a controlled
/// pace give less (frantic squatting never pays).
nonisolated struct RaceConfig: Equatable, Sendable {
    /// Full-thrust reps from Earth to the Moon (~1 controlled rep every 2.5–3 s finishes in 60–75 s).
    var goalReps = 24.0
    var duration = 75.0
    /// Reps closer together than this (s, same player) give proportionally less thrust, down to `minPaceFactor`.
    var steadyInterval = 1.3
    var minPaceFactor = 0.6
    /// Trailing player's bonus: up to +35 % at a gap of 0.25 of the trip.
    var catchUpMax = 0.35
    var catchUpGap = 0.25
    /// Final sprint: when anyone passes 85 % of the trip, or with 15 s left.
    var sprintProgress = 0.85
    var sprintTime = 15.0
    /// The lead changes hands only past this gap (~0.3 rep) held for `leadConfirm` seconds: trading reps
    /// neck-and-neck shows on the lanes, but the crown (and "OVERTAKE!") only moves for a real overtake.
    var leadHysteresis = 0.012
    var leadConfirm = 1.0
    /// "Neck and neck" when both are under this gap (after the start), at most every 10 s.
    var closeGap = 0.03
    var closeCooldown = 10.0
    /// Seconds for a rocket to complete the climb a rep earned.
    var climbTime = 0.9

    static func fromDefaults(_ d: UserDefaults = .standard) -> RaceConfig {
        var c = RaceConfig()
        if d.object(forKey: "moonReps") != nil { c.goalReps = max(4, d.double(forKey: "moonReps")) }
        if d.object(forKey: "moonDuration") != nil { c.duration = max(15, d.double(forKey: "moonDuration")) }
        return c
    }
}

nonisolated struct RaceResult: Equatable, Sendable {
    enum Reason: Equatable, Sendable { case moon, time }
    /// nil = a dead heat.
    var winner: Zone?
    var reason: Reason
    var margin: Double
    var at: Double
}

nonisolated enum RaceEvent: Equatable, Sendable {
    /// A valid rep: thrust gained (progress), and whether the slipstream bonus or the pace rule changed it.
    case boost(Zone, gain: Double, catchUp: Double, paceFactor: Double)
    case leadChange(Zone)
    case neckAndNeck
    case finalSprint
    case finished(RaceResult)
}

nonisolated struct MoonRace: Sendable {
    let config: RaceConfig
    private(set) var progress: [Zone: Double] = [.left: 0, .right: 0]
    private(set) var reps: [Zone: Int] = [.left: 0, .right: 0]
    private(set) var leader: Zone?
    private(set) var result: RaceResult?
    private(set) var sprint = false
    private(set) var startedAt: Double?
    private var lastRepAt: [Zone: Double] = [:]
    private var lastCloseAt = -1000.0
    private var wasClose = true
    private var pendingLeader: Zone?
    private var pendingSince = 0.0

    init(config: RaceConfig = RaceConfig()) { self.config = config }

    var isRunning: Bool { startedAt != nil && result == nil }
    func timeLeft(at t: Double) -> Double { max(0, config.duration - (t - (startedAt ?? t))) }
    func other(_ z: Zone) -> Zone { z == .left ? .right : .left }
    /// Positive: left is ahead.
    var gap: Double { (progress[.left] ?? 0) - (progress[.right] ?? 0) }

    mutating func start(at t: Double) { if startedAt == nil { startedAt = t } }

    /// One completed rep (the detector guarantees one per squat). Ignored before the start and after the finish.
    mutating func rep(_ zone: Zone, at t: Double) -> [RaceEvent] {
        guard isRunning else { return [] }
        var events: [RaceEvent] = []
        let mine = progress[zone] ?? 0, theirs = progress[other(zone)] ?? 0
        let behind = max(0, theirs - mine)
        let catchUp = config.catchUpMax * min(1, behind / config.catchUpGap)
        let interval = lastRepAt[zone].map { t - $0 } ?? 10
        let pace = min(1, max(config.minPaceFactor, interval / config.steadyInterval))
        lastRepAt[zone] = t
        reps[zone, default: 0] += 1
        let gain = (1 / config.goalReps) * (1 + catchUp) * pace
        progress[zone] = min(1, mine + gain)
        events.append(.boost(zone, gain: gain, catchUp: catchUp, paceFactor: pace))
        events += standings(at: t)
        if (progress[zone] ?? 0) >= 1 {
            let r = RaceResult(winner: zone, reason: .moon, margin: 1 - (progress[other(zone)] ?? 0), at: t)
            result = r
            events.append(.finished(r))
        }
        return events
    }

    /// Time-driven: the final sprint by the clock, and the time cap.
    mutating func tick(at t: Double) -> [RaceEvent] {
        guard isRunning else { return [] }
        var events: [RaceEvent] = []
        events += confirmLead(at: t)
        if !sprint, timeLeft(at: t) <= config.sprintTime { sprint = true; events.append(.finalSprint) }
        if timeLeft(at: t) <= 0 {
            let g = gap
            let r = RaceResult(winner: abs(g) < 0.004 ? nil : (g > 0 ? .left : .right), reason: .time, margin: abs(g), at: t)
            result = r
            events.append(.finished(r))
        }
        return events
    }

    /// Lead with hysteresis and confirmation time: the first lead is immediate; a change needs the new leader ahead
    /// by more than the hysteresis for `leadConfirm` seconds.
    private mutating func confirmLead(at t: Double) -> [RaceEvent] {
        let g = gap
        let candidate: Zone? = abs(g) > config.leadHysteresis ? (g > 0 ? .left : .right) : nil
        guard let c = candidate, c != leader else { pendingLeader = nil; return [] }
        if leader == nil {
            leader = c
            return [.leadChange(c)]
        }
        if pendingLeader != c { pendingLeader = c; pendingSince = t; return [] }
        guard t - pendingSince >= config.leadConfirm else { return [] }
        leader = c
        pendingLeader = nil
        return [.leadChange(c)]
    }

    private mutating func standings(at t: Double) -> [RaceEvent] {
        var events: [RaceEvent] = []
        let g = gap
        events += confirmLead(at: t)
        // Neck and neck: entering a close race after having been apart (not at the very start).
        let close = abs(g) < config.closeGap
        let underway = min(progress[.left] ?? 0, progress[.right] ?? 0) > 0.06
        if close, !wasClose, underway, t - lastCloseAt >= config.closeCooldown {
            lastCloseAt = t
            events.append(.neckAndNeck)
        }
        wasClose = close
        if !sprint, max(progress[.left] ?? 0, progress[.right] ?? 0) >= config.sprintProgress {
            sprint = true
            events.append(.finalSprint)
        }
        return events
    }
}

// MARK: - Ascent: instant kick (presentation) + continuous climb (this)

nonisolated struct RocketAscent: Sendable {
    /// Progress the players have earned (0 … 1).
    private(set) var target = 0.0
    /// Progress the rocket has climbed to; eases toward the target (critically damped, never overshoots or sinks).
    private(set) var shown = 0.0
    private(set) var rate = 0.0

    mutating func earn(_ effectiveReps: Double, goal: Double) {
        target = min(1, max(target, effectiveReps / goal))
    }

    mutating func step(dt: Double, climbTime: Double) {
        guard dt > 0 else { return }
        // Critically damped spring (smooth-damp), clamped so it can never pass the target or go backwards.
        let omega = 5 / max(0.05, climbTime)   // ~96% of a rep's climb done within climbTime
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = shown - target
        let temp = (rate + omega * change) * dt
        var next = target + (change + temp) * decay
        rate = (rate - omega * temp) * decay
        if next > target || target - next < 1e-4 { next = target; rate = 0 }   // settle exactly (arrival is crisp)
        if next < shown { next = shown; rate = max(0, rate) }
        shown = next
    }

    var phase: MoonPhase { shown >= 1 - 1e-6 ? .arrived : MoonPhase.at(progress: shown) }
    var arrived: Bool { shown >= 1 - 1e-6 }

    mutating func reset() { target = 0; shown = 0; rate = 0 }

    /// Deck altitude in world units for a progress: exponential, so each later rep climbs farther than the last
    /// (lift-off clears the tower in a few reps; in space a rep crosses hundreds of units).
    static let topAltitude = 2200.0
    static let steepness = 5.0
    static func altitude(_ p: Double) -> Double {
        topAltitude * (exp(steepness * min(1, max(0, p))) - 1) / (exp(steepness) - 1)
    }
}

// MARK: - The vertical camera (shared with the renderer)

nonisolated enum AscentCamera {
    /// Stylized planet radius: small enough that the curvature shows in the upper atmosphere, large enough that the
    /// launch area looks flat.
    static let planetRadius = 6000.0
    static let camH = 1.0
    /// Above this dip (radians) the world camera pitches down so the limb stays in view.
    static let limbHold = 14.0 * .pi / 180

    /// How far below eye level Earth's horizon is, seen from deck altitude `a`.
    static func horizonDip(altitude a: Double) -> Double {
        acos(planetRadius / (planetRadius + max(0, a) + camH))
    }

    static func worldPitch(altitude a: Double) -> Double { max(0, horizonDip(altitude: a) - limbHold) }

    /// Height above the deck of a world object at altitude `objectAltitude`, seen from deck altitude `deck`.
    static func relativeHeight(objectAltitude: Double, deck: Double) -> Double { objectAltitude - deck }

    /// Screen y (points) of a world object, for a camera with focal length `f` and eye level `horizonY`.
    static func screenY(objectAltitude: Double, z: Double, deck: Double, f: Double, horizonY: Double) -> Double {
        horizonY - f * (camH - relativeHeight(objectAltitude: objectAltitude, deck: deck)) / max(z, 0.05)
    }

    /// Screen velocity (points/s, negative = down) of a world object at depth z while the deck climbs at `climbRate`.
    static func screenVelocity(z: Double, climbRate: Double, f: Double) -> Double { -f * climbRate / max(z, 0.05) }
}
