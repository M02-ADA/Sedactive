import Foundation

/// Thresholds are experimental starting points for the spike, not validated movement science.
nonisolated struct SquatConfig: Sendable {
    /// Normalized depth (0 = standing, 1 = deep squat) that starts a descent.
    var descendThreshold = 0.22
    var bottomThreshold = 0.50
    var riseThreshold = 0.40
    var standThreshold = 0.16
    /// Weight of each new sample in the exponential moving average (higher = less smoothing, less lag).
    var smoothing = 0.6
    /// Knee angle (degrees) treated as fully standing / fully squatted.
    var standingKneeAngle = 165.0
    var squatKneeAngle = 100.0
    /// Hip drop, as a fraction of torso length, treated as a full squat when ankles are not visible.
    var fullHipDrop = 0.55
    /// Seconds without a pose before the player counts as lost.
    var lostTimeout = 0.6
    /// Shortest believable squat, from descent start to standing again. Faster cycles are pose jitter
    /// (on iPad, 2 of 18 detected reps were 0.37 s and 0.97 s apart while players walked into position).
    var minRepDuration = 0.6
    /// After a person is (re)acquired, poses settle for this long before movement counts.
    var settleDuration = 0.4
}

nonisolated enum SquatPhase: Sendable, Equatable {
    case standing, descending, down, rising
}

nonisolated enum SquatEvent: Sendable, Equatable {
    case descentStarted   // earliest moment to acknowledge the movement
    case bottomReached    // squat is deep enough to count for the obstacle
    case repCompleted     // stood back up after reaching the bottom
    case aborted          // went partway down and came back up
    case found
    case lost
}

/// Turns a stream of poses (or simulated depth values) into squat phase events.
/// Hysteresis between thresholds prevents jitter around a threshold from producing extra reps.
nonisolated struct SquatDetector: Sendable {
    var config = SquatConfig()
    private(set) var phase: SquatPhase = .standing
    private(set) var depth: Double = 0
    private(set) var isTracking = false
    private var lastSeen = -Double.infinity
    private var reachedBottom = false
    private var descentStart = -Double.infinity
    private var settleUntil = -Double.infinity
    private var standingHipY: Double?

    init(config: SquatConfig = SquatConfig()) {
        self.config = config
    }

    mutating func update(pose: PersonPose?, at time: Double) -> [SquatEvent] {
        update(depth: pose.flatMap { estimateDepth($0) }, at: time)
    }

    mutating func update(depth raw: Double?, at time: Double) -> [SquatEvent] {
        var events: [SquatEvent] = []
        guard let raw else {
            if isTracking, time - lastSeen > config.lostTimeout {
                isTracking = false
                phase = .standing
                depth = 0
                reachedBottom = false
                events.append(.lost)
            }
            return events
        }

        let sample = max(0, min(1, raw))
        if isTracking {
            depth += (sample - depth) * config.smoothing
        } else {
            isTracking = true
            depth = sample
            events.append(.found)
            settleUntil = time + config.settleDuration
        }
        lastSeen = time

        if time < settleUntil {
            // Someone first seen already bent (e.g. seated) gets no credit until they stand up.
            phase = depth > config.descendThreshold ? .down : .standing
            reachedBottom = false
            return events
        }

        switch phase {
        case .standing:
            if depth > config.descendThreshold {
                phase = .descending
                descentStart = time
                events.append(.descentStarted)
                if depth > config.bottomThreshold {
                    phase = .down
                    reachedBottom = true
                    events.append(.bottomReached)
                }
            }
        case .descending:
            if depth > config.bottomThreshold {
                phase = .down
                reachedBottom = true
                events.append(.bottomReached)
            } else if depth < config.standThreshold {
                phase = .standing
                events.append(.aborted)
            }
        case .down:
            if depth < config.standThreshold {
                phase = .standing
                events.append(finishRep(at: time))
            } else if depth < config.riseThreshold {
                phase = .rising
            }
        case .rising:
            if depth > config.bottomThreshold {
                phase = .down
            } else if depth < config.standThreshold {
                phase = .standing
                events.append(finishRep(at: time))
            }
        }
        return events
    }

    /// Called when gameplay (re)starts after a pause or recovery: a squat already in progress earns nothing,
    /// so movement made while halted can never complete into a counted rep.
    mutating func rearm() {
        reachedBottom = false
        if phase != .standing { phase = .down }
    }

    /// A rep needs a real bottom and a believable duration; anything else is reported as aborted.
    private mutating func finishRep(at time: Double) -> SquatEvent {
        defer { reachedBottom = false }
        return reachedBottom && time - descentStart >= config.minRepDuration ? .repCompleted : .aborted
    }

    /// Knee angle is the primary signal; hip drop relative to a calibrated standing height is the
    /// fallback for frames where the ankles are cropped or occluded.
    mutating func estimateDepth(_ pose: PersonPose) -> Double? {
        let hip = pose.hipCenter
        let torso = pose.torsoLength

        if let hip, phase == .standing, depth < config.standThreshold {
            // Track standing hip height; rise quickly, fall slowly so a squat does not drag it down.
            if let current = standingHipY {
                standingHipY = hip.y > current ? current + (hip.y - current) * 0.5 : current + (hip.y - current) * 0.02
            } else {
                standingHipY = hip.y
            }
        }

        if let angle = pose.kneeAngle {
            let span = config.standingKneeAngle - config.squatKneeAngle
            return max(0, min(1, (config.standingKneeAngle - angle) / span))
        }
        if let hip, let torso, let standing = standingHipY {
            let drop = (standing - hip.y) / torso
            return max(0, min(1, drop / config.fullHipDrop))
        }
        return nil
    }
}

/// Smooth 0 → 1 → 0 depth curve used for simulated squats, so simulated and real input share one detector.
nonisolated struct SimulatedSquat: Sendable {
    var start: Double
    /// Peak depth. The default reaches the bottom threshold; 0.35 is a deliberately incomplete (shallow) squat.
    var peak = 0.85
    var downDuration = 0.45
    var holdDuration = 0.25
    var upDuration = 0.5

    var duration: Double { downDuration + holdDuration + upDuration }

    func depth(at time: Double) -> Double? {
        let t = time - start
        guard t >= 0, t <= duration + 0.1 else { return nil }
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if t < downDuration { return peak * ease(t / downDuration) }
        if t < downDuration + holdDuration { return peak }
        if t < duration { return peak * (1 - ease((t - downDuration - holdDuration) / upDuration)) }
        return 0
    }
}
