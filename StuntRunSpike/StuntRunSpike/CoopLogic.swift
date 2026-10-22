import Foundation

/// One shared obstacle that both players work on together.
///
/// - The eligible movement phase (squat bottom) is a *contribution*. It is recorded once per player and
///   never removed, whatever the partner does. Each contribution banks shared Team Power immediately.
/// - Players may contribute at different times anywhere inside the window; there is no sync requirement.
/// - The challenge resolves exactly once: `team` if every participant contributed, otherwise `partial`.
/// - Cancelling (pause / tracking lost) awards nothing further, but keeps what was already banked.
nonisolated struct TeamChallenge: Sendable {
    enum Outcome: Equatable, Sendable {
        case team(Set<Zone>)
        case partial(contributed: Set<Zone>, missing: Set<Zone>)
        case cancelled(contributed: Set<Zone>)
    }

    /// Shared Team Power per contribution, and the extra bonus when everyone contributed.
    static let powerPerContribution = 1
    static let teamBonus = 1

    let id: Int
    let participants: Set<Zone>
    private(set) var started: Set<Zone> = []
    private(set) var contributions: [Zone: Double] = [:]
    private(set) var outcome: Outcome?

    init(id: Int, participants: Set<Zone>) {
        self.id = id
        self.participants = participants
    }

    var isOpen: Bool { outcome == nil }
    var contributed: Set<Zone> { Set(contributions.keys) }

    /// Provisional acknowledgement only (descent started). Returns true the first time per player.
    mutating func movementStarted(_ zone: Zone) -> Bool {
        guard isOpen, participants.contains(zone) else { return false }
        return started.insert(zone).inserted
    }

    /// Records the eligible phase. Returns the Team Power to bank now (0 if ignored or a duplicate).
    mutating func contribute(_ zone: Zone, at time: Double) -> Int {
        guard isOpen, participants.contains(zone), contributions[zone] == nil else { return 0 }
        contributions[zone] = time
        started.insert(zone)
        return Self.powerPerContribution
    }

    /// Resolves once; later calls return the same outcome and award nothing more.
    mutating func resolve() -> (outcome: Outcome, bonus: Int) {
        if let outcome { return (outcome, 0) }
        let done = contributed
        let result: Outcome = !participants.isEmpty && done == participants
            ? .team(done)
            : .partial(contributed: done, missing: participants.subtracting(done))
        outcome = result
        if case .team = result { return (result, Self.teamBonus) }
        return (result, 0)
    }

    mutating func cancel() {
        guard isOpen else { return }
        outcome = .cancelled(contributed: contributed)
    }
}

/// Session play states. Movement only counts while `running`.
nonisolated enum PlayState: Equatable, Sendable {
    case countdown(endsAt: Double)
    case running
    case paused
    case trackingLost(Set<Zone>)
    /// Tracking is back; hazards stay off until someone explicitly resumes.
    case ready
}

nonisolated struct SessionFlow: Sendable {
    static let countdownDuration = 3.0

    private(set) var state: PlayState
    private(set) var session = 1

    init(startingAt time: Double) {
        state = .countdown(endsAt: time + Self.countdownDuration)
    }

    var acceptsMovement: Bool { state == .running }
    /// The world (and challenge progression) is halted in these states.
    var isHalted: Bool {
        switch state {
        case .paused, .trackingLost, .ready: true
        case .running, .countdown: false
        }
    }

    @discardableResult
    mutating func tick(at time: Double) -> Bool {
        if case .countdown(let endsAt) = state, time >= endsAt {
            state = .running
            return true
        }
        return false
    }

    @discardableResult
    mutating func pause() -> Bool {
        switch state {
        case .running, .countdown: state = .paused; return true
        default: return false
        }
    }

    /// Explicit resume from `paused` or `ready`. Never resumes while someone is still lost.
    @discardableResult
    mutating func resume(at time: Double) -> Bool {
        switch state {
        case .paused, .ready:
            state = .countdown(endsAt: time + Self.countdownDuration)
            return true
        default:
            return false
        }
    }

    mutating func trackingLost(_ zone: Zone) {
        switch state {
        case .trackingLost(let zones): state = .trackingLost(zones.union([zone]))
        default: state = .trackingLost([zone])
        }
    }

    mutating func trackingRecovered(_ zone: Zone) {
        guard case .trackingLost(var zones) = state else { return }
        zones.remove(zone)
        state = zones.isEmpty ? .ready : .trackingLost(zones)
    }

    /// New session: callers reset counters; anything tagged with the old session number is stale.
    mutating func replay(at time: Double) {
        session += 1
        state = .countdown(endsAt: time + Self.countdownDuration)
    }
}

/// Encounter phases, in order: WARNING (nothing visible, no judging) → APPROACH (obstacle revealed at the horizon,
/// growing, still no judging) → ACTION (the "DUCK!" cue; squats reaching the bottom now count) → PASSED.
nonisolated enum EncounterPhase: Equatable, Sendable {
    case warning, approach, action, passed
}

/// Provisional timing values (seconds), tuned for simulator readability, NOT validated human reaction times.
/// Each one is separately configurable with a launch argument of the same name (e.g. `-actionLead 3.0`).
nonisolated struct EncounterTiming: Equatable, Sendable {
    /// "DUCK INCOMING!" before anything is visible.
    var warningDuration = 1.6
    /// From the obstacle's reveal at the horizon to it arriving over the players.
    var approachDuration = 5.0
    /// The "DUCK!" cue and the judging window open this long before arrival.
    var actionLead = 2.6
    /// The window stays open this long after arrival (0 = the beam has passed, too late).
    var lateGrace = 0.0
    /// Neutral time after the pass before the next warning.
    var recoveryDuration = 3.0
    /// When every participant has already contributed the outcome is decided, so the TEAM DUCK break may happen
    /// this long before arrival — while the beam is still in view above the players. Must match the baked shatter.
    var impactLead = 0.3

    var revealTime: Double { warningDuration }
    var cueTime: Double { warningDuration + approachDuration - actionLead }
    var arrivalTime: Double { warningDuration + approachDuration }
    var windowCloseTime: Double { arrivalTime + lateGrace }

    /// Phase at `t` seconds after the warning began.
    func phase(at t: Double) -> EncounterPhase {
        if t < revealTime { return .warning }
        if t < cueTime { return .approach }
        if t <= windowCloseTime { return .action }
        return .passed
    }

    /// Shortest time between one judging window closing and the next one opening, assuming the next warning
    /// starts as soon as recovery ends. Guards against unavoidable back-to-back squats.
    var minimumRestBetweenWindows: Double { recoveryDuration + warningDuration + (approachDuration - actionLead) }

    var isValid: Bool {
        warningDuration > 0 && approachDuration > 0 && actionLead > 0 && actionLead < approachDuration && lateGrace >= 0 && recoveryDuration >= 0
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> EncounterTiming {
        var t = EncounterTiming()
        func read(_ key: String, _ value: inout Double) { if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) } }
        read("warningDuration", &t.warningDuration)
        read("approachDuration", &t.approachDuration)
        read("actionLead", &t.actionLead)
        read("lateGrace", &t.lateGrace)
        read("recoveryDuration", &t.recoveryDuration)
        read("impactLead", &t.impactLead)
        return t.isValid ? t : EncounterTiming()
    }
}
