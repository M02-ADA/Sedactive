// Deterministic tests for the squat state machine and zone assignment.
// Run: ./LogicTests/run.sh  (compiles Pose.swift + SquatDetector.swift for macOS)
import Foundation

var failures = 0
@MainActor func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

/// Builds a side-view-ish pose whose knee angle is `kneeAngle` degrees, standing at horizontal position `x`.
@MainActor func pose(kneeAngle: Double, x: Double = 0.3, aspect: Double = 4.0 / 3.0) -> PersonPose {
    let thigh = 0.18, shin = 0.18
    let ankle = (x: x, y: 0.10)
    let knee = (x: ankle.x, y: ankle.y + shin)
    // Thigh direction rotated from straight-up by (180 - kneeAngle).
    let bend = (180 - kneeAngle) * .pi / 180
    let hip = (x: knee.x + sin(bend) * thigh / aspect, y: knee.y + cos(bend) * thigh)
    let neck = (x: hip.x, y: hip.y + 0.25)
    func jp(_ p: (x: Double, y: Double)) -> JointPoint { JointPoint(x: p.x, y: p.y, confidence: 0.9) }
    return PersonPose(joints: [
        .leftAnkle: jp(ankle), .rightAnkle: jp(ankle),
        .leftKnee: jp(knee), .rightKnee: jp(knee),
        .leftHip: jp(hip), .rightHip: jp(hip),
        .neck: jp(neck), .nose: jp((x: neck.x, y: neck.y + 0.08)),
    ], aspect: aspect)
}

/// Feeds knee angles at 30 fps, holding each for `hold` frames (3 ≈ a realistic ~1 s squat).
/// `leadIn` adds 0.5 s of standing first, so the detector's post-acquisition settle period has passed.
@MainActor func feed(_ detector: inout SquatDetector, _ angles: [Double], hold: Int = 3, leadIn: Bool = true, t: inout Double) -> [SquatEvent] {
    var events: [SquatEvent] = []
    let prefix = leadIn ? [Double](repeating: 175, count: 15) : []
    for a in prefix { events += detector.update(pose: pose(kneeAngle: a), at: t); t += 1.0 / 30 }
    for a in angles {
        for _ in 0..<hold { events += detector.update(pose: pose(kneeAngle: a), at: t); t += 1.0 / 30 }
    }
    return events
}

// 1. Knee angle geometry is recovered correctly despite the non-square normalized space.
for angle in [170.0, 140.0, 100.0] {
    let measured = pose(kneeAngle: angle).kneeAngle ?? -1
    check(abs(measured - angle) < 0.5, "knee angle \(angle) measured as \(measured)")
}

// 2. A full squat produces descent → bottom → rep, in that order, once.
do {
    var detector = SquatDetector()
    var t = 0.0
    let events = feed(&detector, [160, 145, 125, 105, 95, 95, 110, 130, 150, 170, 175, 175], t: &t)
    let gameplay = events.filter { $0 != .found }
    check(gameplay == [.descentStarted, .bottomReached, .repCompleted], "full squat events: \(gameplay)")
    check(detector.phase == .standing, "ends standing")
}

// 3. A shallow dip is reported as aborted, never as a rep.
do {
    var detector = SquatDetector()
    var t = 0.0
    let events = feed(&detector, [160, 145, 140, 150, 170, 175, 175], t: &t)
    check(!events.contains(.repCompleted), "shallow dip must not count: \(events)")
    check(events.contains(.descentStarted) && events.contains(.aborted), "shallow dip acknowledged then aborted: \(events)")
}

// 4. Jitter around the bottom threshold does not create extra reps.
do {
    var detector = SquatDetector()
    var reps = 0
    var t = 0.0
    var depths = [Double](repeating: 0, count: 15) + [0.3, 0.6, 0.8]
    for _ in 0..<20 { depths += [0.48, 0.55, 0.45, 0.58] }
    depths += [0.3, 0.1, 0, 0]
    for d in depths {
        reps += detector.update(depth: d, at: t).filter { $0 == .repCompleted }.count
        t += 1.0 / 30
    }
    check(reps == 1, "jitter produced \(reps) reps")
}

// 5. Simulated squats drive the same detector and count every rep.
do {
    var detector = SquatDetector()
    var reps = 0
    var t = 0.0
    for i in 0..<5 {
        let sim = SimulatedSquat(start: 0.5 + Double(i) * 1.6)
        while t < sim.start + 1.6 {
            reps += detector.update(depth: sim.depth(at: t) ?? 0, at: t).filter { $0 == .repCompleted }.count
            t += 1.0 / 60
        }
    }
    check(reps == 5, "simulated reps \(reps)")
}

// 6. Losing the pose for longer than the timeout resets to standing and reports lost once.
do {
    var detector = SquatDetector()
    _ = detector.update(depth: 0.9, at: 0)
    var events: [SquatEvent] = []
    var t = 0.0
    while t < 1.0 { t += 0.1; events += detector.update(depth: nil, at: t) }
    check(events == [.lost], "lost events: \(events)")
    check(detector.phase == .standing && !detector.isTracking, "reset after loss")
    check(detector.update(depth: 0, at: 1.1) == [.found], "found again")
}

// 7. Hip-drop fallback works when ankles are hidden.
do {
    var detector = SquatDetector()
    var standing = pose(kneeAngle: 175)
    standing.joints[.leftAnkle] = nil
    standing.joints[.rightAnkle] = nil
    var t = 0.0
    for _ in 0..<20 { _ = detector.update(pose: standing, at: t); t += 1.0 / 30 }
    var squatting = standing
    for j in [Joint.leftHip, .rightHip, .neck, .nose] { squatting.joints[j]!.y -= 0.17 }
    var events: [SquatEvent] = []
    for _ in 0..<6 { events += detector.update(pose: squatting, at: t); t += 1.0 / 30 }
    check(events.contains(.bottomReached), "hip-drop fallback reaches bottom: \(events), depth \(detector.depth)")
}

// 8. Zone assignment: left/right by position; ignores a third, smaller person.
do {
    let a = pose(kneeAngle: 175, x: 0.7)
    let b = pose(kneeAngle: 175, x: 0.25)
    var small = pose(kneeAngle: 175, x: 0.5)
    for j in Joint.allCases { if let p = small.joints[j] { small.joints[j]!.y = 0.5 + (p.y - 0.5) * 0.3 } }
    let zones = ZoneAssigner.assign([a, small, b])
    check(zones[.left]?.centerX == b.centerX && zones[.right]?.centerX == a.centerX, "two-person assignment")
    check(ZoneAssigner.assign([a])[.right] != nil, "single person on the right")
    check(ZoneAssigner.assign([]).isEmpty, "nobody")
}

// 9. A person first detected seated (knees bent) earns nothing until they stand and squat again.
do {
    var detector = SquatDetector()
    var t = 0.0
    var events = feed(&detector, [95, 95, 96, 94, 95, 120, 150, 170, 175, 175], leadIn: false, t: &t)
    check(!events.contains(.descentStarted) && !events.contains(.repCompleted), "seated start must not score: \(events)")
    events += feed(&detector, [150, 120, 100, 95, 95, 120, 150, 170, 175, 175], leadIn: false, t: &t)
    check(events.filter { $0 == .repCompleted }.count == 1, "then a real squat counts once: \(events)")
}

// 10. Pose jitter that completes a "squat" faster than a person can is not a rep (seen on iPad: 0.37 s).
do {
    var detector = SquatDetector()
    var t = 0.0
    let events = feed(&detector, [130, 95, 95, 150, 175, 175], hold: 2, t: &t)
    check(events.contains(.bottomReached) && !events.contains(.repCompleted), "too-fast cycle must not count: \(events)")
}

// 11. Zone tracker: one person standing near the centre line keeps their zone despite jitter.
do {
    var tracker = ZoneTracker()
    var t = 0.0
    var zones: [Zone] = []
    for x in [0.40, 0.47, 0.53, 0.49, 0.55, 0.51, 0.46, 0.54] {
        zones += Array(tracker.assign([pose(kneeAngle: 175, x: x)], at: t).keys)
        t += 1.0 / 30
    }
    check(Set(zones) == [.left], "centre-line jitter must not flip zones: \(zones)")
    // A decisive move across the line does switch.
    for _ in 0..<5 { zones = Array(tracker.assign([pose(kneeAngle: 175, x: 0.72)], at: t).keys); t += 1.0 / 30 }
    check(zones == [.right], "clear crossing switches zone: \(zones)")
}

// 12. Zone tracker: with two people, the one who briefly drops out keeps their zone when they return.
do {
    var tracker = ZoneTracker()
    var t = 0.0
    let parent = pose(kneeAngle: 175, x: 0.35), child = pose(kneeAngle: 175, x: 0.62)
    _ = tracker.assign([parent, child], at: t); t += 0.1
    // Parent missed for a frame; the child alone, right of centre but near it, must stay right.
    let alone = tracker.assign([pose(kneeAngle: 175, x: 0.55)], at: t); t += 0.1
    check(alone[.right] != nil && alone[.left] == nil, "remaining person keeps zone: \(alone.keys)")
    let both = tracker.assign([parent, child], at: t)
    check(both[.left]?.centerX == parent.centerX && both[.right]?.centerX == child.centerX, "both restored")
}

// 13. Shared challenge: contributions are recorded once, survive a partner's miss, and award power once.
do {
    var c = TeamChallenge(id: 1, participants: [.left, .right])
    check(c.movementStarted(.left), "provisional start acknowledged")
    check(c.contribute(.left, at: 1.0) == 1, "first contribution banks power")
    check(c.contribute(.left, at: 1.2) == 0, "duplicate contribution ignored")
    check(c.contribute(.right, at: 9.0) == 1, "slower partner still contributes inside the window")
    let (outcome, bonus) = c.resolve()
    check(outcome == .team([.left, .right]) && bonus == TeamChallenge.teamBonus, "team outcome: \(outcome)")
    check(c.resolve().bonus == 0 && c.contribute(.right, at: 10) == 0, "resolves once; no late contributions")
}

// 14. Partial outcome keeps the successful player's contribution; non-participants are ignored.
do {
    var c = TeamChallenge(id: 2, participants: [.left, .right])
    _ = c.contribute(.right, at: 1)
    check(TeamChallenge(id: 3, participants: [.left]).contributed.isEmpty, "fresh challenge empty")
    var solo = TeamChallenge(id: 4, participants: [.left])
    check(solo.contribute(.right, at: 1) == 0, "non-participant ignored")
    let (outcome, bonus) = c.resolve()
    check(outcome == .partial(contributed: [.right], missing: [.left]) && bonus == 0, "partial: \(outcome)")
}

// 15. Cancelling keeps what was banked and blocks later contributions.
do {
    var c = TeamChallenge(id: 5, participants: [.left, .right])
    _ = c.contribute(.left, at: 1)
    c.cancel()
    check(c.outcome == .cancelled(contributed: [.left]), "cancelled keeps contribution")
    check(c.contribute(.right, at: 2) == 0 && c.resolve().bonus == 0, "no award after cancel")
}

// 16. Session flow: pause / tracking lost / explicit resume / countdown / replay.
do {
    var flow = SessionFlow(startingAt: 0)
    check(!flow.acceptsMovement, "countdown does not accept movement")
    flow.tick(at: 3.1)
    check(flow.state == .running && flow.acceptsMovement, "running after countdown")
    check(flow.pause() && flow.isHalted && !flow.acceptsMovement, "paused halts")
    check(flow.resume(at: 10) && flow.state == .countdown(endsAt: 13), "explicit resume counts down")
    flow.tick(at: 13)
    flow.trackingLost(.left)
    flow.trackingLost(.right)
    check(flow.state == .trackingLost([.left, .right]), "both lost")
    check(!flow.resume(at: 14), "cannot resume while someone is lost")
    flow.trackingRecovered(.left)
    check(flow.state == .trackingLost([.right]), "still waiting for right")
    flow.trackingRecovered(.right)
    check(flow.state == .ready && !flow.acceptsMovement, "recovered → ready, hazards still off")
    check(flow.resume(at: 20), "resume from ready")
    let session = flow.session
    flow.replay(at: 30)
    check(flow.session == session + 1 && flow.state == .countdown(endsAt: 33), "replay starts a new session")
}

// 17. Re-arming after a halt: a squat begun while paused cannot complete into a rep.
do {
    var detector = SquatDetector()
    var t = 0.0
    var events = feed(&detector, [150, 120, 95, 95], t: &t)
    check(events.contains(.bottomReached), "reached bottom before the pause")
    detector.rearm()
    events = feed(&detector, [120, 150, 170, 175, 175], leadIn: false, t: &t)
    check(!events.contains(.repCompleted), "no rep from a squat interrupted by a pause: \(events)")
    events = feed(&detector, [150, 120, 100, 95, 95, 120, 150, 170, 175, 175], leadIn: false, t: &t)
    check(events.filter { $0 == .repCompleted }.count == 1, "next full squat counts")
}

// 18. A shallow simulated squat is acknowledged but is not a contribution or a rep.
do {
    var detector = SquatDetector()
    var t = 0.0
    var events: [SquatEvent] = []
    let sim = SimulatedSquat(start: 0.6, peak: 0.35)
    while t < 2.5 { events += detector.update(depth: sim.depth(at: t) ?? 0, at: t); t += 1.0 / 60 }
    check(events.contains(.descentStarted) && !events.contains(.bottomReached) && !events.contains(.repCompleted),
          "shallow squat: \(events)")
}

// 19. Invariant: a squat held low across two challenges earns one contribution, in the first only.
//     Contributions come from the bottomReached *event*, which fires once per descent, never from the held pose.
do {
    var detector = SquatDetector()
    var t = 0.0
    var first = TeamChallenge(id: 1, participants: [.left])
    var second = TeamChallenge(id: 2, participants: [.left])
    var power = 0
    // Squat and hold through the first challenge, then through the second.
    for (i, a) in ([175.0] + [Double](repeating: 175, count: 14) + [150, 120, 95] + [Double](repeating: 95, count: 30)).enumerated() {
        for event in detector.update(pose: pose(kneeAngle: a), at: t) where event == .bottomReached {
            power += i < 30 ? first.contribute(.left, at: t) : second.contribute(.left, at: t)
        }
        t += 1.0 / 30
    }
    for _ in 0..<60 {   // still holding during the second challenge
        for event in detector.update(pose: pose(kneeAngle: 95), at: t) where event == .bottomReached {
            power += second.contribute(.left, at: t)
        }
        t += 1.0 / 30
    }
    check(power == 1 && first.contributed == [.left] && second.contributed.isEmpty, "held squat rewarded once: power \(power)")
}

// 20. Encounter phases come in order: warning (nothing to do) → approach → action window → passed.
do {
    let t = EncounterTiming()
    check(t.phase(at: 0) == .warning && t.phase(at: t.revealTime - 0.01) == .warning, "warning first")
    check(t.phase(at: t.revealTime) == .approach && t.phase(at: t.cueTime - 0.01) == .approach, "approach after reveal")
    check(t.phase(at: t.cueTime) == .action && t.phase(at: t.arrivalTime) == .action, "action until arrival")
    check(t.phase(at: t.arrivalTime + 0.01) == .passed, "passed right after arrival with no late grace")
    var graced = t; graced.lateGrace = 0.2
    check(graced.phase(at: graced.arrivalTime + 0.15) == .action && graced.phase(at: graced.arrivalTime + 0.25) == .passed, "late grace")
    check(t.revealTime < t.cueTime && t.cueTime < t.arrivalTime, "reveal before cue before arrival")
    check(t.minimumRestBetweenWindows >= 4, "at least 4 s between judging windows: \(t.minimumRestBetweenWindows)")
    var bad = t; bad.actionLead = 9
    check(!bad.isValid, "action lead longer than the approach is rejected")
}

// 21. Only squats that reach the bottom inside the action window contribute (early and late ones don't);
//     their full cycles still count as reps.
do {
    let timing = EncounterTiming()
    func runSquat(startingAt start: Double) -> (contributed: Bool, reps: Int) {
        var detector = SquatDetector()
        var challenge: TeamChallenge?
        var reps = 0
        var t = 0.0
        let sim = SimulatedSquat(start: start)
        while t < timing.arrivalTime + 2 {
            if challenge == nil, timing.phase(at: t) == .action { challenge = TeamChallenge(id: 1, participants: [.left]) }
            for event in detector.update(depth: sim.depth(at: t) ?? 0, at: t) {
                if event == .bottomReached, timing.phase(at: t) == .action { _ = challenge?.contribute(.left, at: t) }
                if event == .repCompleted { reps += 1 }
            }
            t += 1.0 / 60
        }
        return (challenge?.contributed.contains(.left) == true, reps)
    }
    let early = runSquat(startingAt: 0.5)                          // during the warning
    let inTime = runSquat(startingAt: timing.cueTime + 0.3)
    let late = runSquat(startingAt: timing.arrivalTime - 0.1)       // bottom lands after arrival
    check(!early.contributed && early.reps == 1, "early squat: no contribution, rep counted \(early)")
    check(inTime.contributed && inTime.reps == 1, "in-window squat contributes once \(inTime)")
    check(!late.contributed && late.reps == 1, "late squat: no contribution, rep counted \(late)")
}

// ===== Jungle Drift =====

/// Runs the raft for `seconds` with fixed leans; returns the raft and every event.
@MainActor func runRaft(_ raft: inout RaftBalance, seconds: Double, leans: [Double], torque: Double = 0, crouched: Int = 0) -> [RaftEvent] {
    var events: [RaftEvent] = []
    var t = 0.0
    while t < seconds { events += raft.step(dt: 1.0 / 60, leans: leans, crouched: crouched, externalTorque: torque); t += 1.0 / 60 }
    return events
}

// 22. Balance: the river current alone lists the raft visibly but never splashes; leaning against it levels it.
do {
    var ignored = RaftBalance()
    let events = runRaft(&ignored, seconds: 10, leans: [0, 0], torque: RiverCurrent.amplitude)
    check(!events.contains(.splash) && ignored.zone != .steady && ignored.zone != .danger, "current alone: listed, no splash (\(ignored.angle))")
    var helped = RaftBalance()
    _ = runRaft(&helped, seconds: 10, leans: [-0.25, -0.25], torque: RiverCurrent.amplitude)
    check(helped.zone == .steady, "two small leans against the current level it (\(helped.angle))")
    check(ignored.recoverDirection == -1, "recover direction points to the high side (lean left when right is down)")
}

// 23. Balance: an alligator hanging on — nobody leans → splash; one player → no splash but still tilted; both → steady.
do {
    let pull = -GatorTiming().clingTorque     // left side dragged down
    var nobody = RaftBalance(); nobody.impulse(-GatorTiming().strikeImpulse)
    check(runRaft(&nobody, seconds: GatorTiming().clingDuration, leans: [0, 0], torque: pull).contains(.splash), "nobody leans: splash")
    check(GatorTiming().clingDuration > RaftParams().splashAfter + 0.4, "the grip outlasts the splash timer")
    // Responsive players lean toward the high side in proportion to the tilt.
    func responsive(_ raft: inout RaftBalance, players: Int) -> (events: [RaftEvent], worst: Double) {
        var events: [RaftEvent] = [], worst = 0.0, t = 0.0
        while t < GatorTiming().clingDuration {
            let l = responsiveLean(raftAngle: raft.angle)
            events += raft.step(dt: 1.0 / 60, leans: players == 2 ? [l, l] : [l, 0], crouched: 0, externalTorque: pull)
            worst = max(worst, abs(raft.angle)); t += 1.0 / 60
        }
        return (events, worst)
    }
    var one = RaftBalance(); one.impulse(-45)
    let o = responsive(&one, players: 1)
    check(!o.events.contains(.splash) && one.zone != .steady, "one player: holds it above water, not level (\(one.angle))")
    var both = RaftBalance(); both.impulse(-45)
    let b = responsive(&both, players: 2)
    check(!b.events.contains(.splash) && abs(both.angle) < abs(one.angle) && b.worst < o.worst,
          "both players: clearly better than one (\(both.angle) vs \(one.angle), worst \(b.worst) vs \(o.worst))")
    var crouch = RaftBalance(); crouch.impulse(30)
    var free = RaftBalance(); free.impulse(30)
    _ = runRaft(&crouch, seconds: 0.6, leans: [0, 0], crouched: 2); _ = runRaft(&free, seconds: 0.6, leans: [0, 0])
    check(abs(crouch.velocity) < abs(free.velocity), "crouching damps the rocking")
}

// 24. Steady streak reward fires once per streak length, and splash recentres the raft with a cooldown.
do {
    var raft = RaftBalance()
    let events = runRaft(&raft, seconds: 12.5, leans: [0, 0])
    check(events.filter { $0 == .steadyStreak }.count == 2, "two STEADY rewards in 12.5 s: \(events)")
    var dunk = RaftBalance()
    let dunkEvents = runRaft(&dunk, seconds: 2.8, leans: [0, 0], torque: -120)
    check(dunkEvents.filter { $0 == .splash }.count == 1, "one splash, then cooldown: \(dunkEvents)")
}

// 25. Lean estimator: upright → 0, torso tilted right → positive, left → negative, small sway inside the dead zone.
do {
    func torso(_ degrees: Double) -> PersonPose {
        let a = 4.0 / 3.0, rad = degrees * .pi / 180
        let hip = JointPoint(x: 0.5, y: 0.4, confidence: 0.9)
        let neck = JointPoint(x: 0.5 + sin(rad) * 0.25 / a, y: 0.4 + cos(rad) * 0.25, confidence: 0.9)
        return PersonPose(joints: [.leftHip: hip, .rightHip: hip, .neck: neck], aspect: a)
    }
    let est = LeanEstimator()
    check(est.lean(for: torso(0)) == 0 && est.lean(for: torso(2)) == 0, "dead zone")
    check((est.lean(for: torso(12)) ?? 0) > 0.99 && (est.lean(for: torso(-7)) ?? 0) < -0.4, "direction and scale")
}

// 26. Alligator challenge: contributions need a held correct lean inside the window (once each); outcomes.
@MainActor func gatorRun(leanLeft: Double, leanRight: Double, side: Zone = .left, reaction: Double = 0.6) -> (GatorChallenge.Outcome?, Int, Int) {
    let timing = GatorTiming()
    var g = GatorChallenge(id: 1, side: side, participants: [.left, .right], timing: timing)
    var raft = RaftBalance()
    var t = 0.0, power = 0, bonus = 0
    var result: GatorChallenge.Outcome?
    let dir = g.correctDirection
    while t < timing.windowCloseTime + 0.5, result == nil {
        let dt = 1.0 / 60
        let phase = timing.phase(at: t)
        if t >= timing.strikeTime, t - dt < timing.strikeTime { raft.impulse(-dir * timing.strikeImpulse) }
        let pull = phase == .clinging ? -dir * timing.clingTorque : 0
        // Players react `reaction` s after the strike, leaning in proportion to the tilt (effort; negative = wrong way).
        let active = t >= timing.strikeTime + reaction
        let l = responsiveLean(raftAngle: raft.angle)
        let leans = [active ? l * leanLeft : 0, active ? l * leanRight : 0]
        let events = raft.step(dt: dt, leans: leans, crouched: 0, externalTorque: pull)
        power += g.record(.left, lean: leans[0], dt: dt, at: t) + g.record(.right, lean: leans[1], dt: dt, at: t)
        if let r = g.observe(angle: raft.angle, steadyAngle: raft.params.steadyAngle, splashed: events.contains(.splash), dt: dt, at: t) {
            result = r.0; bonus = r.bonus
        }
        t += dt
    }
    return (result, power, bonus)
}
do {
    let both = gatorRun(leanLeft: 1, leanRight: 1)
    check(both.0 == .teamSteady([.left, .right]) && both.1 == 2 && both.2 == 1, "both lean: TEAM STEADY, 2 contributions + bonus \(both)")
    let one = gatorRun(leanLeft: 1, leanRight: 0)
    if case .steady(let c, let m)? = one.0 { check(c == [.left] && m == [.right] && one.1 == 1, "one leans: steady, partial \(one)") }
    else { check(false, "one lean should still steady the raft: \(String(describing: one.0))") }
    let slow = gatorRun(leanLeft: 1, leanRight: 1, reaction: 0.9)
    check(slow.0 == .teamSteady([.left, .right]), "a team reacting after 0.9 s still makes it \(slow)")
    let none = gatorRun(leanLeft: 0, leanRight: 0)
    check(none.0 == .splashed(contributed: []) && none.1 == 0, "nobody leans: splashed \(none)")
    let wrong = gatorRun(leanLeft: -1, leanRight: -1)
    check(wrong.1 == 0, "leaning the wrong way never counts \(wrong)")
    let mirrored = gatorRun(leanLeft: 1, leanRight: 1, side: .right)
    check(mirrored.0 == .teamSteady([.left, .right]), "right-side strike mirrors \(mirrored)")
}

// 27. Director: cycle order, mirrored sides on the next lap, combo bird window never overlaps the gator window.
do {
    var d = JungleDirector()
    let first = (0..<JungleDirector.cycle.count).map { _ in d.next() }
    check(first == JungleDirector.cycle, "first lap in order")
    let second = d.next(); let third = d.next(); let fourth = d.next()
    check(second == .birds && third == .piranhas(from: .right, count: 2) && fourth == .gator(.right),
          "second lap mirrors sides and adds a fish to the burst: \(third), \(fourth)")
    check(JungleDirector.comboIsSequential(gator: GatorTiming(), birds: EncounterTiming(), delay: d.comboBirdDelay),
          "combo: bird duck window opens after the gator window closes")
    for side in Zone.allCases {
        check(JungleDirector.comboIsSequential(gator: GatorTiming(), piranhas: PiranhaTiming(), from: side, delay: d.comboPiranhaDelay),
              "combo: piranha JUMP cue comes after the gator window closes")
    }
    for _ in 0..<(JungleDirector.cycle.count * 3) {
        if case .piranhas(_, let count) = d.next() { check(count <= JungleDirector.maxBurst, "burst never exceeds \(JungleDirector.maxBurst)") }
    }
    d.reset()
    check(d.next() == .birds, "reset restarts the cycle")
}

// 28. Croc performance: states in order, the bite lands exactly on the gameplay strike, no pops between frames.
do {
    let timing = GatorTiming()
    let anim = CrocAnimator(timing: timing)
    var order: [CrocPose.State] = []
    var t = 0.0
    while t < timing.releaseTime + 2 { let s = anim.pose(at: t).state; if order.last != s { order.append(s) }; t += 1.0 / 120 }
    check(order == [.lurking, .surfacing, .swimming, .anticipation, .lunging, .impact, .clinging, .retreat, .gone], "croc states in order: \(order)")
    check(anim.pose(at: timing.revealTime - 0.01).view == .hidden && anim.pose(at: timing.revealTime + 0.01).view == .headOn,
          "nothing above water until the reveal")
    check(anim.pose(at: anim.lungeStart - 0.01).rise < -0.5, "anticipation: it sinks before exploding up")
    check(anim.pose(at: anim.anticipationStart + 0.2).lid > 0.4, "anticipation: eyes narrow")
    check(anim.pose(at: timing.strikeTime - 0.01).jaw > 0.9, "jaw wide just before the strike")
    check(anim.pose(at: timing.strikeTime + 0.08).jaw < 0.2, "jaw shut on the edge right after the strike")
    check(anim.pose(at: timing.releaseTime + 0.05).jaw > anim.pose(at: timing.releaseTime - 0.05).jaw, "retreat: lets go first")
    var maxBody = 0.0, maxJaw = 0.0
    var prev = anim.pose(at: 0)
    t = 0
    while t < timing.releaseTime + 2 {
        let p = anim.pose(at: t)
        if p.view == prev.view {
            maxBody = max(maxBody, abs(p.rise - prev.rise), abs(p.lid - prev.lid), abs(p.pitch - prev.pitch), abs(p.approach - prev.approach))
            maxJaw = max(maxJaw, abs(p.jaw - prev.jaw))
        }
        prev = p
        t += 1.0 / 60
    }
    check(maxBody < 0.45, "no body pops between 60 fps frames (max \(maxBody))")
    check(maxJaw < 0.6, "the jaw snap takes several frames (max step \(maxJaw))")
}

// 29. Croc performance scales to a short configured approach, and reacts to the players lifting the edge.
do {
    var timing = GatorTiming()
    timing.approachDuration = 1.2
    let anim = CrocAnimator(timing: timing)
    var order: [CrocPose.State] = []
    var t = 0.0
    while t < timing.releaseTime + 2 { let s = anim.pose(at: t).state; if order.last != s { order.append(s) }; t += 1.0 / 120 }
    check(order == [.lurking, .surfacing, .swimming, .anticipation, .lunging, .impact, .clinging, .retreat, .gone], "short approach keeps every state: \(order)")
    let mid = timing.strikeTime + 1.0
    let lifted = anim.pose(at: mid, lift: 1), dragged = anim.pose(at: mid, lift: -1)
    check(lifted.rise > dragged.rise && lifted.pitch > dragged.pitch, "lifting the edge hauls the croc up")
    var shakeLift = 0.0, shakeDrag = 0.0
    for i in 0..<60 { let tt = timing.strikeTime + 0.2 + Double(i) / 60; shakeLift = max(shakeLift, abs(anim.pose(at: tt, lift: 1).shake)); shakeDrag = max(shakeDrag, abs(anim.pose(at: tt, lift: -1).shake)) }
    check(shakeLift > shakeDrag, "it struggles harder when lifted")
}

// 30. Macaw flap cycle and flight: quicker downstroke, head height at arrival, tucked dive, flare before the pass.
do {
    check(abs(birdStroke(fromPhase: 0.42) - 0.5) < 1e-9 && birdStroke(fromPhase: 0.21) == 0.25, "downstroke takes 42% of the beat")
    var last = -1.0, monotonic = true
    for i in 0..<100 { let s = birdStroke(fromPhase: Double(i) / 100); if s < last { monotonic = false }; last = s }
    check(monotonic, "stroke advances monotonically through a beat")
    let frames = Set((0..<64).compactMap { BirdPose.flap(birdStroke(fromPhase: Double($0) / 64)).frameIndex })
    check(frames.count == BirdPose.flapFrames, "every flap frame is used: \(frames.sorted())")
    let timing = EncounterTiming()
    let flight = BirdFlight(timing: timing, traits: BirdTraits.make(index: 0, seed: 7), laneX: -1.2, hOffset: 0)
    check(abs(flight.sample(at: timing.arrivalTime).h - BirdFlight.headH) < 0.05, "arrives at head height")
    check(flight.sample(at: (flight.diveStart + flight.flareStart) / 2).pose == .tuck, "wings tucked in the dive")
    check(flight.sample(at: flight.flareStart + 0.1).pose == .flare, "flares (anticipation) before the pass")
    check(flight.sample(at: timing.revealTime - 0.1).alpha == 0, "not visible before the reveal")
    var maxStep = 0.0, prevH = flight.sample(at: timing.revealTime).h
    var t = timing.revealTime
    while t < timing.arrivalTime { let h = flight.sample(at: t).h; maxStep = max(maxStep, abs(h - prevH)); prevH = h; t += 1.0 / 60 }
    check(maxStep < 0.12, "smooth flight path (max height step \(maxStep))")
}

// 31. Flock variation stays controlled, and the reactions resolve cleanly.
do {
    let flock = (0..<5).map { BirdTraits.make(index: $0, seed: 21) }
    check(flock.allSatisfy { $0.rate >= 4.6 * 0.88 && $0.rate <= 4.6 * 1.12 && $0.size >= 0.94 && $0.size <= 1.06 }, "variation within ±12% rate, ±6% size")
    check(Set(flock.map(\.palette)).count == 2 && Set(flock.map { Int($0.phase * 1000) }).count == 5, "two palettes, no two birds in phase")
    check(BirdTraits.make(index: 2, seed: 21) == flock[2], "variation is deterministic per encounter")
    let timing = EncounterTiming()
    let flight = BirdFlight(timing: timing, traits: flock[0], laneX: 1.2, hOffset: 0)
    let at = timing.arrivalTime
    let hit = flight.sample(at: at + 1.0, reaction: .hit(at: at))
    check(abs(hit.spin - 2 * .pi) < 1e-6, "a clipped bird tumbles once and ends upright")
    check(flight.sample(at: at + 0.1, reaction: .hit(at: at)).pose == .startled, "a clipped bird looks startled")
    check(flight.sample(at: at + 0.9, reaction: .teamDucked(at: at)).h > flight.sample(at: at + 0.9).h + 0.7, "after a TEAM duck the flock pulls up over the heads")
}


// MARK: - Piranha Jump

/// A standing pose with hips at `hipY` and ankles at `footY` (torso length 0.25, legs straight).
@MainActor func jumpPose(hipY: Double, footY: Double, x: Double = 0.3) -> PersonPose {
    func jp(_ px: Double, _ py: Double) -> JointPoint { JointPoint(x: px, y: py, confidence: 0.9) }
    return PersonPose(joints: [
        .leftAnkle: jp(x, footY), .rightAnkle: jp(x, footY),
        .leftKnee: jp(x, (hipY + footY) / 2), .rightKnee: jp(x, (hipY + footY) / 2),
        .leftHip: jp(x, hipY), .rightHip: jp(x, hipY),
        .neck: jp(x, hipY + 0.25), .nose: jp(x, hipY + 0.33),
    ])
}

/// Runs one leap at 60 fps with simulated jumps. `takeoff[zone]` is relative to that zone's crossing (nil = no jump).
@MainActor func runLeap(_ takeoff: [Zone: Double?], side: Zone = .left, participants: Set<Zone> = [.left, .right],
                        timing: PiranhaTiming = PiranhaTiming()) -> (leap: PiranhaLeap, events: [PiranhaLeap.Event]) {
    var leap = PiranhaLeap(id: 1, index: 0, side: side, participants: participants, timing: timing)
    var detectors: [Zone: JumpDetector] = [.left: JumpDetector(), .right: JumpDetector()]
    var sims: [Zone: SimulatedJump] = [:]
    for (zone, offset) in takeoff { if let offset { sims[zone] = SimulatedJump(start: leap.crossing(zone) + offset - 0.12) } }
    var events: [PiranhaLeap.Event] = []
    var t = 0.0
    while t < leap.lastWindowClose + timing.lateLabelWindow + 0.3 {
        var airborne: [Zone: Bool] = [:]
        for zone in Zone.allCases {
            _ = detectors[zone]!.update(lift: sims[zone]?.lift(at: t) ?? 0, at: t)
            airborne[zone] = detectors[zone]!.isAirborne
        }
        events += leap.update(at: t, airborne: airborne)
        t += 1.0 / 60
    }
    return (leap, events)
}

// 32. Jump detector: a simulated hop is one takeoff and one landing; a shallow bob or jitter never takes off.
do {
    var d = JumpDetector()
    let hop = SimulatedJump(start: 1.0)
    var events: [JumpEvent] = []
    var t = 0.0
    while t < 2.5 { events += d.update(lift: hop.lift(at: t) ?? 0, at: t); t += 1.0 / 60 }
    check(events.count == 3 && events.first == .takeoff, "hop → takeoff, landed, settled: \(events)")
    if case .landed(let air)? = events.dropLast().last { check(air > 0.25 && air < 0.5, "airtime is a believable hop (\(air) s)") }
    if case .settled? = events.last {} else { check(false, "the cycle completes only after landing: \(events)") }
    var shallow = JumpDetector(); var bobEvents: [JumpEvent] = []
    t = 0
    while t < 3 { bobEvents += shallow.update(lift: 0.11 + 0.025 * sin(t * 40), at: t); t += 1.0 / 60 }
    check(bobEvents.isEmpty, "jitter just under the takeoff level never takes off: \(bobEvents)")
    var lost = JumpDetector()
    _ = lost.update(lift: 0, at: 0); _ = lost.update(lift: 0.4, at: 0.5)
    check(lost.isAirborne, "airborne")
    _ = lost.update(lift: nil, at: 0.7); _ = lost.update(lift: nil, at: 1.3)
    check(!lost.isAirborne && !lost.isTracking, "losing the person ends the jump")
}

// 33. Jump from poses: hips and feet up → jump; hips up with feet planted (tiptoes) → no; a squat → no; a person
//     who "floats" for longer than any hop (stepped closer) is recalibrated rather than left airborne.
do {
    func run(_ samples: [(hip: Double, foot: Double)]) -> (events: [JumpEvent], detector: JumpDetector) {
        var d = JumpDetector(); var e: [JumpEvent] = []
        for (i, s) in samples.enumerated() { e += d.update(pose: jumpPose(hipY: s.hip, footY: s.foot), at: Double(i) / 30) }
        return (e, d)
    }
    let stand = Array(repeating: (hip: 0.45, foot: 0.08), count: 30)
    let jump = stand + (0..<12).map { i in let k = sin(Double(i) / 11 * .pi); return (hip: 0.45 + 0.09 * k, foot: 0.08 + 0.09 * k) } + stand
    let r1 = run(jump)
    check(r1.events.first == .takeoff && r1.events.count == 3, "pose jump detected once (takeoff, landed, settled): \(r1.events)")
    let tiptoe = stand + Array(repeating: (hip: 0.49, foot: 0.085), count: 20) + stand
    check(run(tiptoe).events.isEmpty, "tiptoes (hips up, feet planted) are not a jump")
    let squat = stand + (0..<20).map { i in (hip: 0.45 - 0.12 * sin(Double(i) / 19 * .pi), foot: 0.08) } + stand
    check(run(squat).events.isEmpty, "a squat is not a jump")
    let drift = stand + Array(repeating: (hip: 0.55, foot: 0.18), count: 60)
    let r4 = run(drift)
    check(!r4.detector.isAirborne && r4.events.contains(.takeoff), "a stale baseline is recalibrated, not stuck airborne")
}

// 34. Leap path: low (the foot zone), crossing the near lane first, the far lane a readable beat later.
do {
    check(PiranhaPath.laneHeight > 0.22 && PiranhaPath.laneHeight < 0.42, "passes the lanes at shin height (\(PiranhaPath.laneHeight))")
    check(abs(PiranhaPath.h(0) - PiranhaPath.waterH) < 1e-9 && abs(PiranhaPath.h(1) - PiranhaPath.waterH) < 1e-9, "leaps out of and back into the water")
    check(abs(PiranhaPath.x(0, from: .left) + PiranhaPath.halfSpan) < 1e-9 && abs(PiranhaPath.x(1, from: .right) + PiranhaPath.halfSpan) < 1e-9,
          "launches on its own side, lands on the other")
    let timing = PiranhaTiming()
    for side in Zone.allCases {
        let other: Zone = side == .left ? .right : .left
        let near = timing.crossingTime(leap: 0, zone: side, from: side), far = timing.crossingTime(leap: 0, zone: other, from: side)
        check(far - near > 0.3 && far - near < 0.6, "far lane \(far - near) s after the near lane")
        check(timing.cueTime(from: side) > timing.revealTime, "JUMP! comes after the fish are revealed")
        check(timing.cueTime(from: side) < timing.launchTime(0), "JUMP! comes before the leap")
    }
    check(PiranhaPath.pitch(0.1) > 0 && PiranhaPath.pitch(0.9) < 0, "nose up on the way out, down into the splash")
    check(timing.isValid, "default timing is valid")
    var bad = timing; bad.burstSpacing = 0.6
    check(!bad.isValid, "leaps too close together are rejected")
}

// 35. Leap judging: on time → cleared, once, banking power; both → TEAM + bonus.
do {
    let (leap, events) = runLeap([.left: -0.3, .right: -0.3])
    let cleared = events.compactMap { if case .cleared(let z, let p) = $0 { return (z, p) } else { return nil } }
    check(cleared.count == 2 && cleared.allSatisfy { $0.1 == 1 }, "each player cleared once (+1): \(cleared)")
    check(events.contains(.resolved(.team([.left, .right]), bonus: TeamChallenge.teamBonus)), "both → TEAM with bonus")
    check(leap.results == [.left: .cleared, .right: .cleared], "results: \(leap.results)")
    check(!events.contains { if case .nipped = $0 { return true } else { return false } }, "nobody nipped")
}

// 36. Too early, too late, no jump: each is a nip with its own label; no power, no penalty; the partner keeps theirs.
do {
    let (early, e1) = runLeap([.left: -0.3, .right: -1.1])
    check(early.results[.right] == .tooEarly && early.results[.left] == .cleared, "early: \(early.results)")
    check(e1.contains(.resolved(.partial(contributed: [.left], missing: [.right]), bonus: 0)), "one cleared → partial, no bonus")
    check(e1.contains(.nipped(.right)), "early jumper gets nipped")
    let (late, _) = runLeap([.left: 0.32, .right: nil])
    check(late.results[.left] == .tooLate, "takeoff after the window → TOO LATE: \(late.results)")
    check(late.results[.right] == .noJump, "no jump → labelled: \(late.results)")
    check(late.team.contributed.isEmpty, "nothing banked")
    let (edge, _) = runLeap([.left: 0.1, .right: -0.7])
    check(edge.results[.left] == .cleared, "taking off at the very end of the window still counts (camera latency)")
    check(edge.results[.right] == .cleared, "a long early hop still airborne at the window start counts")
    // A jump during the warning (before the JUMP! cue) earns nothing and isn't called early.
    let warning = PiranhaTiming().revealTime - 0.5
    let (eager, _) = runLeap([.left: warning - PiranhaTiming().firstCrossing(from: .left), .right: -0.3])
    check(eager.results[.left] == .noJump, "a hop before the cue is neither credit nor TOO EARLY: \(eager.results)")
}

// 37. Solo play, and a cancelled leap (pause) keeps banked power and judges nothing more.
do {
    let (solo, e) = runLeap([.left: -0.3], participants: [.left])
    check(e.contains(.resolved(.team([.left]), bonus: TeamChallenge.teamBonus)) && solo.results[.right] == nil, "one player alone can earn the team result")
    var leap = PiranhaLeap(id: 2, index: 0, side: .right, participants: [.left, .right])
    let tc = leap.crossing(.right)
    let first = leap.update(at: tc, airborne: [.right: true])
    check(first.contains(.cleared(.right, power: 1)), "right cleared")
    leap.cancel()
    let after = leap.update(at: leap.crossing(.left), airborne: [.left: true])
    check(!after.contains { if case .cleared = $0 { return true } else { return false } } && leap.team.contributed == [.right],
          "after cancel nothing more is credited, banked credit stays")
}

// 38. A burst: every leap is judged on its own; spacing leaves time to land and reset between jumps.
do {
    let timing = PiranhaTiming()
    for i in 1..<JungleDirector.maxBurst {
        let gap = timing.crossingTime(leap: i, zone: .left, from: .left) - timing.windowClose(leap: i - 1, zone: .right, from: .left)
        check(gap > 0.5, "≥ 0.5 s between one leap's last window and the next leap's first crossing (\(gap))")
    }
    var second = PiranhaLeap(id: 5, index: 1, side: .left, participants: [.left])
    check(second.crossing(.left) > PiranhaLeap(id: 4, index: 0, side: .left, participants: [.left]).lastWindowClose, "leap 2 after leap 1")
    let e = second.update(at: second.crossing(.left), airborne: [.left: true])
    check(e.contains(.cleared(.left, power: 1)), "leap 2 judged at its own crossing")
}

// 39. Piranha performance: fins first (never the fish before the leap), the leap starts exactly at launch, the jaws
//     snap at each lane, splashdown on time; the arc has no pops between frames.
do {
    let timing = PiranhaTiming()
    let anim = PiranhaAnimator(timing: timing, side: .left, leap: 0)
    var order: [PiranhaPose.State] = []
    var t = 0.0
    while t < timing.endTime(count: 1) + 0.6 {
        let s = anim.pose(at: t).state
        if order.last != s { order.append(s) }
        t += 1.0 / 60
    }
    check(order == [.circling, .surging, .leaping, .splashed, .hidden], "states in order: \(order)")
    check(anim.pose(at: timing.launchTime(0) - 0.01).state == .surging && anim.pose(at: timing.launchTime(0) + 0.01).state == .leaping,
          "leap begins exactly at the gameplay launch")
    check(anim.pose(at: timing.launchTime(0) - 0.08).finRise < 0.5, "dips under just before bursting out (anticipation)")
    check(anim.pose(at: timing.crossingTime(leap: 0, zone: .left, from: .left)).jaw > 0.9, "snaps at the near lane")
    check(anim.pose(at: timing.crossingTime(leap: 0, zone: .right, from: .left)).jaw > 0.9, "snaps at the far lane")
    var maxStep = 0.0, prev = PiranhaPath.h(0)
    var u = 0.0
    while u <= 1 { let h = PiranhaPath.h(u); maxStep = max(maxStep, abs(h - prev)); prev = h; u += 1.0 / 60 / timing.flightDuration }
    check(maxStep < 0.06, "smooth arc (max height step \(maxStep))")
    // The warning and most of the approach stay in the gap between the players (|x| < 0.55 while still ahead of the
    // raft), so a body never hides the fins; only the last swing out to the edge passes beside them.
    var inGap = true
    t = 0
    while t < timing.launchTime(0) - 0.75 { let p = anim.pose(at: t); if p.finZ > 2.5, abs(p.finX) > 0.55 { inGap = false }; t += 1.0 / 60 }
    check(inGap, "fins approach down the gap between the players")
    let later = PiranhaAnimator(timing: timing, side: .right, leap: 2)
    check(later.pose(at: 0.5).state == .circling && later.pose(at: timing.launchTime(2) + 0.1).state == .leaping,
          "a burst's later fish circle with the school, then leap on their own launch")
}

// Helper: run a JumpSweepJudge over planned airborne spans (takeoff, landing) per player, at 60 Hz.
@MainActor func runSweep(crossings: [Zone: Double], cue: Double, window: JumpWindow = JumpWindow(), participants: Set<Zone> = [.left, .right],
                         spans: [Zone: [(Double, Double)]], until end: Double) -> (judge: JumpSweepJudge, events: [JumpJudgeEvent]) {
    var j = JumpSweepJudge(id: 1, crossings: crossings, cueTime: cue, participants: participants, window: window)
    var events: [JumpJudgeEvent] = []
    var t = cue
    while t <= end {
        let airborne = Dictionary(uniqueKeysWithValues: Zone.allCases.map { z in (z, spans[z, default: []].contains { t >= $0.0 && t < $0.1 }) })
        events += j.update(at: t, airborne: airborne)
        t += 1.0 / 60
    }
    return (j, events)
}

// 40. A rep is the complete cycle: landed AND back near standing for a moment; losing the person after landing,
//     or a bounce straight into another hop, never counts extra.
do {
    var d = JumpDetector()
    var e: [JumpEvent] = []
    var t = 0.0
    let hop = SimulatedJump(start: 1.0)
    while t < hop.end + 0.12 { e += d.update(lift: hop.lift(at: t) ?? 0, at: t); t += 1.0 / 60 }
    check(e.contains(.takeoff) && !e.contains { if case .settled = $0 { return true }; return false }, "no rep until the feet have been still: \(e)")
    while t < hop.end + 0.6 { e += d.update(lift: 0, at: t); t += 1.0 / 60 }
    check(e.filter { if case .settled = $0 { return true }; return false }.count == 1, "one rep once settled")
    var lost = JumpDetector(); var le: [JumpEvent] = []
    let hop2 = SimulatedJump(start: 1.0)
    t = 0
    while t < hop2.end + 0.05 { le += lost.update(lift: hop2.lift(at: t) ?? 0, at: t); t += 1.0 / 60 }
    while t < hop2.end + 1.5 { le += lost.update(lift: nil, at: t); t += 1.0 / 60 }
    check(!le.contains { if case .settled = $0 { return true }; return false }, "tracking lost on landing: no rep")
    var bounce = JumpDetector(); var be: [JumpEvent] = []
    let a = SimulatedJump(start: 1.0), b = SimulatedJump(start: a.end + 0.05)
    t = 0
    while t < b.end + 0.8 { be += bounce.update(lift: (t < b.start ? a.lift(at: t) : b.lift(at: t)) ?? 0, at: t); t += 1.0 / 60 }
    check(be.filter { $0 == .takeoff }.count == 2 && be.filter { if case .settled = $0 { return true }; return false }.count == 1,
          "a bounce into a second hop completes one cycle, after the last landing: \(be)")
}

// 41. River Log Sweep: warning first, the log in view well before the cue, both lanes at shin height on the deck,
//     the near-root lane a beat first, a heavy continuous motion, and the bow settling after it leaves.
do {
    let timing = LogSweepTiming()
    let anim = LogAnimator(timing: timing)
    check(timing.isValid, "default log timing valid")
    check(timing.cueTime > timing.revealTime + 1.5, "the log is in view for a while before JUMP! (cue \(timing.cueTime), reveal \(timing.revealTime))")
    check(anim.pose(at: timing.revealTime - 0.01).state == .churning, "warning: nothing to jump yet, only the rapids")
    let l = timing.crossingTime(.left), r = timing.crossingTime(.right)
    check(l < r && r - l < 0.15, "root end leads: left lane first, right a beat later (\(l), \(r))")
    for zone in Zone.allCases {
        let p = anim.pose(at: timing.crossingTime(zone))
        let top = p.h + LogPath.radius
        check(p.state == .rolling && top > 0.2 && top < 0.36, "\(zone): rolling on the deck, low on the shins, when it reaches the feet (top \(top))")
        check(abs(LogPath.axisZ(x: FootZone.x(zone), centre: p.zc) - FootZone.playerZ) < 0.03, "\(zone): the axis is at the feet at the crossing")
    }
    var order: [LogPose.State] = []
    var maxStep = 0.0
    var prev = anim.pose(at: timing.revealTime)
    var t = 0.0
    while t < timing.endTime {
        let p = anim.pose(at: t)
        if order.last != p.state { order.append(p.state) }
        if t > timing.revealTime + 0.05, p.state != .gone { maxStep = max(maxStep, abs(p.zc - prev.zc), abs(p.h - prev.h)) }
        prev = p
        t += 1.0 / 60
    }
    check(order == [.churning, .floating, .lifting, .rolling, .falling, .gone], "log states in order: \(order)")
    check(maxStep < 0.12, "no pops between 60 fps frames (max step \(maxStep))")
    check(anim.pose(at: l).bowLift > 0.9, "the bow is up while it rolls (why it rolls toward the players)")
    check(abs(anim.pose(at: timing.endTime).bowLift) < 0.05, "the bow settles back after it has gone")
    check(LogPath.deckH(z: FootZone.playerZ, bowLift: 1) == 0, "the deck pitches about the players' feet (they stay put)")
}

// 42. Log judging: on time → TEAM; one early, one late → partial with labels; nobody jumps → no power, no penalty.
do {
    let timing = LogSweepTiming()
    let c = timing.crossings
    let onTime: [Zone: [(Double, Double)]] = [.left: [(c[.left]! - 0.25, c[.left]! + 0.2)], .right: [(c[.right]! - 0.2, c[.right]! + 0.25)]]
    let team = runSweep(crossings: c, cue: timing.cueTime, spans: onTime, until: timing.endTime)
    check(team.events.contains(.resolved(.team([.left, .right]), bonus: 1)), "both on time → TEAM + bonus")
    check(team.events.filter { if case .cleared = $0 { return true }; return false }.count == 2, "each player banked once")
    let mixed: [Zone: [(Double, Double)]] = [.left: [(c[.left]! - 1.3, c[.left]! - 0.85)], .right: [(c[.right]! + 0.35, c[.right]! + 0.8)]]
    let m = runSweep(crossings: c, cue: timing.cueTime, spans: mixed, until: timing.endTime)
    check(m.judge.results[.left] == .tooEarly && m.judge.results[.right] == .tooLate, "early and late are labelled: \(m.judge.results)")
    check(m.events.contains(.resolved(.partial(contributed: [], missing: [.left, .right]), bonus: 0)), "nobody cleared → no power")
    let solo = runSweep(crossings: c, cue: timing.cueTime, spans: [.left: onTime[.left]!], until: timing.endTime)
    check(solo.events.contains(.resolved(.partial(contributed: [.left], missing: [.right]), bonus: 0)), "one clears: their credit stays, partner's miss costs nothing")
}

// 43. Crocodile Tail Sweep: warning and reveal before the coil, JUMP! during the coil, the tail really reaches both
//     lanes, low, the near lane first; mirrored for the left; the motion accelerates and overshoots.
do {
    let timing = TailSweepTiming()
    let anim = TailSweepAnimator(timing: timing)
    check(timing.isValid, "default tail timing valid")
    for side in Zone.allCases {
        let tl = timing.crossingTime(.left, side: side), tr = timing.crossingTime(.right, side: side)
        check(abs(tl - tr) < 0.25, "\(side): one swing reaches both lanes within a fraction of a second (\(tl - tr) s)")
        check(tl > timing.sweepStart && tr > timing.sweepStart, "\(side): nothing reaches the feet before the sweep starts")
        check(timing.cueTime(side: side) > timing.revealTime && timing.cueTime(side: side) < timing.sweepStart,
              "\(side): JUMP! comes after the reveal, during the coil (anticipation)")
        for zone in Zone.allCases {
            let lane = TailPath.lane(zone, side: side)
            check(lane.radius + 0.15 < TailPath.length, "\(side)/\(zone): the tail reaches that lane (r \(lane.radius))")
            let p = anim.pose(at: timing.crossingTime(zone, side: side))
            // The far lane is reached by the trailing part of the tail just as the hips finish the arc (follow-through).
            check((p.state == .sweeping || p.state == .reacting) && p.lift > 0 && p.lift < 0.3,
                  "\(side)/\(zone): low through the foot zone when it arrives (h \(p.lift), \(p.state))")
        }
    }
    var order: [TailPose.State] = []
    var t = 0.0
    while t < timing.endTime + 0.2 { let s = anim.pose(at: t).state; if order.last != s { order.append(s) }; t += 1.0 / 120 }
    check(order == [.hidden, .surfacing, .settling, .coiling, .sweeping, .reacting, .retreating, .gone], "tail states in order: \(order)")
    let a0 = anim.baseAngle(at: timing.sweepStart - 0.001), a1 = anim.baseAngle(at: timing.sweepStart + 0.001)
    check(abs(a0 - a1) < 0.01, "no jump at the release")
    let early = abs(anim.baseAngle(at: timing.sweepStart + 0.05) - anim.baseAngle(at: timing.sweepStart))
    let late = abs(anim.baseAngle(at: timing.sweepEnd - 0.05) - anim.baseAngle(at: timing.sweepEnd - 0.1))
    check(late > early * 2, "the whip accelerates out of the coil")
    check((anim.baseAngle(at: timing.sweepEnd + 0.15) - TailPath.endAngle) * TailPath.direction > 0, "overshoots past the end")
    check(abs(anim.baseAngle(at: timing.sweepEnd + 1.4) - TailPath.endAngle) < 0.02, "and settles")
    let mid = timing.sweepStart + timing.sweepDuration * 0.6
    let pose = anim.pose(at: mid)
    check((anim.angle(at: mid, fraction: 1, pose: pose) - anim.angle(at: mid, fraction: 0, pose: pose)) * TailPath.direction < 0,
          "the tip trails the hips (follow-through)")
    let coil = anim.pose(at: timing.sweepStart - 0.1)
    check(coil.lift > 0.4 && coil.curl > 0.5, "anticipation: the tail is up out of the water and wound back before the sweep")
}

// 44. Tail reactions: a TEAM jump leaves it dizzy (overshoot spin); catching someone leaves it pleased, not dizzy.
//     Judging uses the tail's own crossings through the shared judge.
do {
    let timing = TailSweepTiming()
    let anim = TailSweepAnimator(timing: timing)
    let react = timing.sweepEnd + 0.5
    check(anim.pose(at: react).dizzy > 0 && anim.pose(at: react).spin > 0, "after a TEAM jump: dizzy, spun round")
    check(anim.pose(at: react, hit: true).dizzy == 0 && anim.pose(at: react, hit: true).jaw > 0.3, "after a hit: pleased grin, not dizzy")
    let c = timing.crossings(side: .right)
    let both = runSweep(crossings: c, cue: timing.cueTime(side: .right),
                        spans: [.left: [(c[.left]! - 0.3, c[.left]! + 0.15)], .right: [(c[.right]! - 0.3, c[.right]! + 0.15)]], until: timing.endTime)
    check(both.events.contains(.resolved(.team([.left, .right]), bonus: 1)), "tail: both jump → TEAM")
    let parentOnly = runSweep(crossings: c, cue: timing.cueTime(side: .right), spans: [.left: [(c[.left]! - 0.3, c[.left]! + 0.15)]], until: timing.endTime)
    check(parentOnly.judge.results[.left] == .cleared && parentOnly.judge.results[.right] == .noJump, "tail: one clears, the other is swept (no jump)")
    var cancelled = JumpSweepJudge(id: 3, crossings: c, cueTime: timing.cueTime(side: .right), participants: [.left, .right], window: timing.window)
    _ = cancelled.update(at: c[.right]!, airborne: [.right: true])
    cancelled.cancel()
    let after = cancelled.update(at: c[.left]!, airborne: [.left: true])
    check(cancelled.team.contributed == [.right] && !after.contains { if case .cleared = $0 { return true }; return false },
          "a pause/tracking halt cancels: banked credit kept, nothing judged after")
}

// 45. Director: every jump hazard in the lap, never two jump beats back to back, sides mirror, the combo's tail
//     cue waits for the ram's recovery window; scripts can pin a playlist (or the Revision 9 lap) through a replay.
do {
    let lap = JungleDirector.cycle
    check(lap.contains(.logSweep) && lap.contains(.tailSweep(.right)) && lap.contains(.gatorThenTail(.right)), "log, tail and the ram→tail combo are in the lap")
    for i in lap.indices {
        let next = lap[(i + 1) % lap.count]
        check(!(lap[i].startsWithJump && next.startsWithJump), "no back-to-back jump beats at \(i): \(lap[i]) → \(next)")
    }
    var d = JungleDirector()
    for _ in 0..<lap.count { _ = d.next() }
    var second: [JungleBeat] = []
    for _ in 0..<lap.count { second.append(d.next()) }
    check(second.contains(.tailSweep(.left)) && second.contains(.gatorThenTail(.left)), "tail sides mirror on the next lap")
    for side in Zone.allCases {
        check(JungleDirector.comboIsSequential(gator: GatorTiming(), tail: TailSweepTiming(), side: side, delay: d.comboTailDelay),
              "combo: the tail's JUMP cue comes after the ram's recovery window (\(side))")
    }
    var pinned = JungleDirector()
    pinned.setPlaylist([.logSweep, .tailSweep(.left), .birds])
    _ = pinned.next()
    pinned.reset()
    check(pinned.next() == .tailSweep(.left) && pinned.next() == .birds, "a playlist keeps its place through a replay")
    var r9 = JungleDirector()
    r9.lap = JungleDirector.revision9Cycle
    check((0..<9).map { _ in r9.next() } == JungleDirector.revision9Cycle, "the Revision 9 lap is still available to the coop script")
}

// 46. Acting: the croc bares its teeth (head lifted) before it sinks to lunge; its recovery shows the result —
//     shaken off (eyes screwed shut, head-shake) when the team held, a slow pleased retreat after a splash.
do {
    let timing = GatorTiming()
    let anim = CrocAnimator(timing: timing)
    let bare = anim.pose(at: anim.anticipationStart + (anim.anticipation - anim.sinkTime) * 0.5)
    check(bare.grin > 0.9 && bare.rise > 1.15, "anticipation: teeth bared with the head up (grin \(bare.grin), rise \(bare.rise))")
    check(anim.pose(at: anim.lungeStart - 0.01).rise < -0.5, "still sinks before the lunge")
    let mid = timing.releaseTime + anim.retreatTime * 0.3
    let beaten = anim.pose(at: mid, outcome: .beaten), won = anim.pose(at: mid, outcome: .won)
    check(beaten.lid > 0.8 && abs(beaten.shake) > 0.01, "beaten: eyes shut, shaking it off")
    check(won.jaw >= 0.3 && won.back < anim.pose(at: mid).back && won.rise > beaten.rise, "won: grinning, in no hurry to leave")
    var maxStep = 0.0
    var prev = anim.pose(at: anim.anticipationStart - 0.05)
    var t = anim.anticipationStart - 0.05
    while t < anim.lungeStart { let p = anim.pose(at: t); maxStep = max(maxStep, abs(p.grin - prev.grin), abs(p.rise - prev.rise)); prev = p; t += 1.0 / 60 }
    check(maxStep < 0.45, "the threat lifts and sinks smoothly (max step \(maxStep))")
}

// 47. Flock choreography: wingbeats cascade from the leader back; after a TEAM duck the lanes peel apart over the
//     players instead of climbing as one block.
do {
    let flock = (0..<5).map { BirdTraits.make(index: $0, seed: 9) }
    for i in 1..<flock.count {
        let lag = (flock[i].phase - flock[i - 1].phase + 1).truncatingRemainder(dividingBy: 1)
        check(lag > 0.05 && lag < 0.25, "follower \(i) beats a fraction behind the bird ahead (\(lag))")
    }
    let timing = EncounterTiming()
    let at = timing.arrivalTime
    let left = BirdFlight(timing: timing, traits: flock[0], laneX: -1.2, hOffset: 0)
    let right = BirdFlight(timing: timing, traits: flock[1], laneX: 1.2, hOffset: 0)
    let dl = left.sample(at: at + 0.9, reaction: .teamDucked(at: at)).xOffset - left.sample(at: at + 0.9).xOffset
    let dr = right.sample(at: at + 0.9, reaction: .teamDucked(at: at)).xOffset - right.sample(at: at + 0.9).xOffset
    check(dl < -0.5 && dr > 0.5, "the flock splits to both sides over the players (\(dl), \(dr))")
}

print(failures == 0 ? "All logic tests passed" : "\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
