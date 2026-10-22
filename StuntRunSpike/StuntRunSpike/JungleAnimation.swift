import Foundation

// Creature performances for Jungle Drift, as pure functions of the encounter clock.
// The renderer only applies these poses to layered sprites, so timing and state order are unit-tested and the
// animation can never drift from the gameplay clock (the bite lands exactly at GatorTiming.strikeTime).

nonisolated func smoothstepD(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}
nonisolated func easeOutD(_ x: Double) -> Double { let t = max(0, min(1, x)); return 1 - (1 - t) * (1 - t) * (1 - t) }
nonisolated func easeInD(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * t }
nonisolated func mixD(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

// MARK: - Crocodile

nonisolated struct CrocPose: Equatable, Sendable {
    enum State: String, Sendable { case lurking, surfacing, swimming, anticipation, lunging, impact, clinging, retreat, gone }
    enum View: Sendable { case hidden, headOn, side }

    var state: State = .lurking
    var view: View = .hidden
    /// Head-on approach: 0 = where it surfaced (far), 1 = beside the raft.
    var approach: Double = 0
    /// Lurking shadow progress under the surface (0 far … 1 where it surfaces).
    var lurk: Double = 0
    /// Height out of the water: 1 = normal (eyes and snout above), 0 = awash, < 0 = under.
    var rise: Double = 0
    /// Eyelid: 0 open … 1 shut. Pupil: 0 slit … 1 round (dilated for the strike).
    var lid: Double = 0
    var pupil: Double = 0.15
    /// Swim S-motion (head-on yaw), jaw opening (0 shut … 1 wide), head pitch (+ = nose up), tail swing, thrash roll.
    var yaw: Double = 0
    var jaw: Double = 0
    var pitch: Double = 0
    var tail: Double = 0
    var shake: Double = 0
    /// Along-body scale: > 1 stretched (lunge), < 1 squashed (bite).
    var stretch: Double = 1
    /// Pushed back from the raft edge during the retreat (0 … 1 body lengths-ish).
    var back: Double = 0
    /// Opacity of the submerged silhouette (lurking / leaving).
    var shadow: Double = 0
    /// Water reaction cues for the renderer (0…1): bulge before the lunge, foam collar where the body breaks the surface.
    var bulge: Double = 0
    var collar: Double = 0
    /// Head-on mouth: 0 hidden … 0.5 a closed smug curve with tooth tips … 1 teeth bared.
    var grin: Double = 0
}

/// How the encounter went, from the croc's point of view: it shapes the recovery (acting, not rules).
nonisolated enum CrocOutcome: Sendable { case pending, beaten, won }

/// Maps the GatorChallenge clock onto a crocodile performance:
/// lurking → surfacing → swimming → anticipation → lunging → impact → clinging → retreat → gone.
nonisolated struct CrocAnimator: Sendable {
    let timing: GatorTiming
    /// Durations, shrunk proportionally if the approach is configured very short.
    var surfacing: Double { min(0.7, timing.approachDuration * 0.25) }
    var anticipation: Double { min(0.6, timing.approachDuration * 0.24) }
    var sinkTime: Double { anticipation * 0.45 }
    var lungeTime: Double { min(0.18, timing.approachDuration * 0.08) }
    let impactTime = 0.14
    let retreatTime = 0.9
    /// When the lunge starts (the bite lands at strikeTime).
    var lungeStart: Double { timing.strikeTime - lungeTime }
    var anticipationStart: Double { lungeStart - anticipation }

    init(timing: GatorTiming) { self.timing = timing }

    /// `lift`: how far the players have raised the bitten edge, -1 (dragged under) … 1 (lifted clear).
    func pose(at t: Double, lift: Double = 0, outcome: CrocOutcome = .pending) -> CrocPose {
        var p = CrocPose()
        let reveal = timing.revealTime, strike = timing.strikeTime, release = timing.releaseTime
        let lift = max(-1, min(1, lift))
        if t < reveal {
            // Lurking: only a dark shape gliding under the surface (and bubbles).
            p.state = .lurking
            p.lurk = t / max(reveal, 0.01)
            p.shadow = 0.55 * smoothstepD(0, 0.5, t) * (1 - smoothstepD(reveal - 0.25, reveal + 0.1, t))
            p.rise = -1
            return p
        }
        if t < lungeStart {
            p.view = .headOn
            // Steady approach that slows as it closes in; the counter-move (a small pull-back) sits in the anticipation.
            p.approach = easeOutD((t - reveal) / max(anticipationStart - reveal, 0.01) * 0.95)
            p.yaw = 0.08 * sin(2 * .pi * 0.85 * (t - reveal)) * (1 - smoothstepD(anticipationStart - 0.3, anticipationStart, t))
            p.rise = 1 + 0.05 * sin(2 * .pi * 1.1 * t)
            p.collar = 0.6
            if t < reveal + surfacing {
                // Surfacing: eyes first, then the snout; lids still heavy and opening.
                let k = (t - reveal) / surfacing
                p.state = .surfacing
                p.rise = mixD(-0.7, 1, easeOutD(k)) + 0.08 * sin(.pi * k)
                p.lid = 0.5 * (1 - smoothstepD(0.3, 1, k))
                p.collar = 1
                p.shadow = 0.3 * (1 - k)
            } else if t < anticipationStart {
                p.state = .swimming
                // One slow blink while it swims in: a living animal, not a moving prop.
                let blinkAt = reveal + surfacing + 0.9
                let b = abs(t - blinkAt)
                if b < 0.09 { p.lid = 1 - b / 0.09 }
            } else {
                // Anticipation: eyes narrow, a small pull-back, the head lifts to bare its teeth (the threat), then it
                // sinks (the water bulges where it went down).
                let k = (t - anticipationStart) / anticipation
                p.state = .anticipation
                p.lid = 0.55 * smoothstepD(0, 0.25, k)
                p.pupil = 0.15
                p.approach -= 0.05 * sin(.pi * min(1, k * 1.4))
                let sink = smoothstepD(1 - sinkTime / anticipation, 1, k)
                let bare = sin(.pi * min(1, k / (1 - sinkTime / anticipation)))
                p.grin = 0.5 * smoothstepD(0, 0.2, k) + 0.5 * bare
                p.rise = mixD(1 + 0.45 * bare, -0.9, easeInD(sink))
                p.collar = 0.6 + 0.4 * sink
                p.bulge = smoothstepD(0.4, 1, k)
            }
            return p
        }
        p.view = .side
        if t < strike {
            // Lunging: explodes out of the water, jaw wide, nose up, body stretched, pupils dilated.
            let k = (t - lungeStart) / lungeTime
            p.state = .lunging
            p.rise = mixD(-0.6, 1.05, easeOutD(k))
            p.jaw = easeOutD(k * 1.2)
            p.pitch = 0.38 * easeOutD(k)
            p.stretch = 1 + 0.13 * sin(.pi * min(1, k * 1.1))
            p.pupil = 1
            p.collar = 1
            p.bulge = 1 - k
            p.tail = -0.25 * k
            return p
        }
        if t < strike + impactTime {
            // Impact: jaw snaps shut on the raft edge (fast, ease-in), squash, nose drops.
            let k = (t - strike) / impactTime
            p.state = .impact
            p.jaw = max(0.08, 1 - easeInD(min(1, k / 0.45)) * 0.92)
            p.pitch = mixD(0.38, -0.04, easeOutD(k))
            p.stretch = 1 - 0.12 * sin(.pi * k)
            p.rise = 1
            p.pupil = 1 - 0.6 * k
            p.collar = 1
            p.tail = mixD(-0.25, 0.3, k)
            return p
        }
        if t < release {
            // Clinging: jaws clamped, thrashing (two incommensurate rhythms, never a fixed shake), tail working.
            // When the players lift the edge the croc is hauled up and struggles harder; dragged down, it settles in.
            let c = t - strike - impactTime
            p.state = .clinging
            let struggle = 0.7 + 0.5 * max(0, lift)
            // Each yank: the head wrenches sideways (roll) and tugs down (rise) on the same beat.
            let yank = sin(2 * .pi * 2.6 * c)
            p.shake = (0.09 * yank + 0.04 * sin(2 * .pi * 4.1 * c + 1.3)) * struggle
            p.tail = 0.36 * sin(2 * .pi * 1.5 * c + 0.4) * struggle
            p.jaw = 0.08 + 0.03 * max(0, yank)
            p.pitch = -0.04 + 0.22 * max(0, lift) - 0.08 * max(0, -lift)
            p.rise = 1 + 0.3 * lift - 0.07 * max(0, yank) * struggle
            p.lid = 0.42
            p.pupil = 0.4
            p.collar = 0.7 + 0.3 * abs(sin(2 * .pi * 1.5 * c))
            return p
        }
        if t < release + retreatTime {
            // Retreat: lets go (jaw opens), falls back into the river (ease-in), sinks with the eyes last.
            let k = (t - release) / retreatTime
            p.state = .retreat
            p.jaw = k < 0.12 ? mixD(0.1, 0.6, k / 0.12) : mixD(0.6, 0.2, smoothstepD(0.12, 0.6, k))
            p.pitch = mixD(-0.04, 0.3, easeOutD(min(1, k * 2)))
            p.back = easeInD(min(1, k * 1.3)) * 0.8
            p.rise = mixD(1, -1.3, easeInD(smoothstepD(0.1, 0.85, k)))
            p.lid = 0.2
            switch outcome {
            case .beaten:
                // Shaken off by the team: eyes screwed shut, a dazed head-shake as it drops back.
                p.lid = k < 0.55 ? 0.9 : 0.4
                p.shake = 0.13 * sin(2 * .pi * 6 * k) * (1 - k)
            case .won:
                // It got its splash: a pleased grin, lazy eyes, no hurry to leave.
                p.jaw = max(p.jaw, 0.3)
                p.lid = 0.55
                p.back *= 0.6
                p.rise = mixD(1, -1.3, easeInD(smoothstepD(0.25, 0.95, k)))
            case .pending:
                break
            }
            p.tail = -0.3 * sin(.pi * k)
            p.collar = 1 - smoothstepD(0.6, 1, k)
            p.shadow = 0.45 * smoothstepD(0.6, 1, k)
            return p
        }
        p.state = .gone
        p.rise = -1.3
        p.shadow = 0.45 * (1 - smoothstepD(release + retreatTime, release + retreatTime + 0.8, t))
        p.back = 0.8 + (t - release - retreatTime) * 0.6
        return p
    }
}

// MARK: - Birds

/// Per-bird natural variation: same species and proportions, different rhythm and line.
nonisolated struct BirdTraits: Equatable, Sendable {
    var rate: Double        // flaps per second (cruise)
    var phase: Double       // flap phase offset 0…1
    var size: Double        // ±6%
    var sway: Double        // lateral weave amplitude (world units)
    var swayFreq: Double
    var delay: Double       // staggered take-off
    var palette: Int        // 0 scarlet macaw, 1 blue-and-gold macaw

    static func make(index: Int, seed: UInt64) -> BirdTraits {
        var g = seed &+ UInt64(index) &* 0x9E3779B97F4A7C15
        func rnd() -> Double {
            g = g &* 6364136223846793005 &+ 1442695040888963407
            return Double((g >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        // Wingbeats cascade through the flock (leader first, each follower a beat-fraction behind), with a little
        // jitter so it never looks mechanical; rates stay close so the wave stays readable.
        let cascade = (Double(index) * 0.14 + 0.05 * rnd()).truncatingRemainder(dividingBy: 1)
        return BirdTraits(rate: 4.6 * (0.94 + 0.12 * rnd()), phase: cascade, size: 0.94 + 0.12 * rnd(),
                          sway: 0.12 + 0.18 * rnd(), swayFreq: 0.5 + 0.4 * rnd(), delay: Double(index) * 0.09 + 0.06 * rnd(),
                          palette: index % 3 == 1 ? 1 : 0)
    }
}

nonisolated enum BirdPose: Equatable, Sendable {
    /// Flap cycle position 0…1 in *stroke* space: 0 wings up → 0.5 wings down → 1 wings up.
    case flap(Double)
    case glide, tuck, flare, startled

    static let flapFrames = 8
    var frameIndex: Int? {
        if case .flap(let s) = self { return min(Self.flapFrames - 1, Int(s * Double(Self.flapFrames))) }
        return nil
    }
}

nonisolated enum BirdReaction: Equatable, Sendable { case none, teamDucked(at: Double), hit(at: Double), missedOver(at: Double) }

nonisolated struct BirdSample: Equatable, Sendable {
    var h: Double           // height above the deck (world units)
    var xOffset: Double     // added to the lane x
    var bank: Double        // roll, radians (into turns)
    var pitch: Double       // nose up +
    var pose: BirdPose
    var bob: Double         // body offset from the wing beat (world units)
    var spin: Double        // tumble after a hit (radians)
    var alpha: Double
}

/// Flap timing: the power downstroke is quicker than the recovery upstroke (42% / 58% of the beat).
nonisolated func birdStroke(fromPhase p: Double) -> Double {
    let f = p - floor(p)
    let down = 0.42
    return f < down ? 0.5 * f / down : 0.5 + 0.5 * (f - down) / (1 - down)
}

/// A flock bird's flight through one DUCK encounter, as a function of the hazard clock.
/// take-off from the canopy → flap-glide cruise → tucked dive → flare (anticipation) → pass at head height → react.
nonisolated struct BirdFlight: Sendable {
    let timing: EncounterTiming
    let traits: BirdTraits
    let laneX: Double
    let hOffset: Double
    /// Just above the canopy: high enough to read as "out of the trees", low enough to stay clear of the top HUD.
    static let perchH = 4.3
    static let headH = 1.15

    var diveStart: Double { timing.arrivalTime - min(1.7, timing.approachDuration * 0.4) }
    var flareStart: Double { timing.arrivalTime - 0.5 }

    /// Accumulated wing phase: flap rate changes with the flight state, so integrate it piecewise.
    func flapPhase(at t: Double) -> Double {
        let start = timing.revealTime + traits.delay
        let takeoffEnd = start + 0.9
        var phase = traits.phase
        func span(_ a: Double, _ b: Double) -> Double { max(0, min(t, b) - a) }
        phase += span(start, takeoffEnd) * traits.rate * 1.35
        phase += span(takeoffEnd, diveStart) * traits.rate
        phase += span(flareStart, .infinity) * traits.rate * 1.25
        return phase
    }

    func sample(at t: Double, reaction: BirdReaction = .none) -> BirdSample {
        let start = timing.revealTime + traits.delay
        let arrival = timing.arrivalTime
        var s = BirdSample(h: Self.perchH, xOffset: 0, bank: 0, pitch: 0, pose: .glide, bob: 0, spin: 0, alpha: 0)
        guard t >= start else { return s }
        s.alpha = min(1, (t - start) / 0.35)
        let stroke = birdStroke(fromPhase: flapPhase(at: t))
        let flapPose = BirdPose.flap(stroke)
        let bobAmp = 0.06 * traits.size
        // Lateral line: spread out from the trees, converging on the lane, with a gentle weave that settles for the pass.
        func x(_ time: Double) -> Double {
            let converge = 1 - smoothstepD(start, diveStart, time)
            let weave = traits.sway * sin(2 * .pi * traits.swayFreq * (time - start) + traits.phase * 6) * (1 - smoothstepD(flareStart - 0.4, arrival, time))
            return laneX * 0.9 * converge * converge + weave
        }
        s.xOffset = x(t)
        s.bank = max(-0.5, min(0.5, -(x(t + 0.05) - x(t - 0.05)) / 0.1 * 0.35))
        let takeoffEnd = start + 0.9
        if t < takeoffEnd {
            // Take-off: climb out of the canopy, fast beats, nose up.
            let k = (t - start) / 0.9
            s.h = Self.perchH + 0.35 * easeOutD(k)
            s.pitch = 0.25 * (1 - k)
            s.pose = flapPose
            s.bob = -cos(2 * .pi * stroke) * bobAmp * 1.3
        } else if t < diveStart {
            // Cruise: flap-glide rhythm (three beats, a short glide), easing down toward the dive.
            let k = smoothstepD(takeoffEnd, diveStart, t)
            s.h = Self.perchH + 0.35 - 0.45 * k
            let beat = flapPhase(at: t) - traits.phase
            let gliding = beat.truncatingRemainder(dividingBy: 4.5) > 3.0
            s.pose = gliding ? .glide : flapPose
            s.bob = gliding ? 0 : -cos(2 * .pi * stroke) * bobAmp
        } else if t < flareStart {
            // Dive: wings tucked, accelerating down (ease-in), nose down.
            let k = (t - diveStart) / (flareStart - diveStart)
            s.h = mixD(Self.perchH - 0.1, Self.headH + 0.45, easeInD(k) * 0.65 + k * 0.35)
            s.pitch = -0.35 * sin(.pi * min(1, k * 1.2))
            s.pose = .tuck
        } else {
            // Flare (anticipation, ~0.3 s): wings high, body pitched up — then hard beats through the pass.
            let k = (t - flareStart) / (arrival - flareStart)
            s.h = mixD(Self.headH + 0.45, Self.headH, easeOutD(k))
            if t < flareStart + 0.28 {
                s.pose = .flare
                s.pitch = 0.3 * sin(.pi * (t - flareStart) / 0.28)
            } else {
                s.pose = flapPose
                s.bob = -cos(2 * .pi * stroke) * bobAmp * 1.2
            }
        }
        s.h += hOffset
        switch reaction {
        case .none:
            break
        case .teamDucked(let at), .missedOver(let at):
            // Sail over the ducked players: skim just above their heads in a glide, then beat away and climb
            // (kept low so the flock never covers the HUD or the TEAM banner).
            guard t > at else { break }
            let k = t - at
            s.h += 0.8 * easeOutD(k / 0.7) + 0.7 * easeInD(max(0, k - 0.7) / 1.0)
            s.pitch = 0.35 * (1 - smoothstepD(0, 0.9, k))
            s.pose = k < 0.45 ? .glide : flapPose
            // The flock splits over the players: each lane peels away to its own side, banking into the turn.
            let peel: Double = laneX > 0.01 ? 1 : (laneX < -0.01 ? -1 : 0)
            s.xOffset += peel * 0.9 * easeOutD(k / 0.9)
            s.bank += -peel * 0.4 * sin(.pi * min(1, k / 0.9))
        case .hit(let at):
            // Clipped a standing player: startled, tumbles, recovers and flaps off.
            guard t > at else { break }
            let k = t - at
            // One full tumble that ends upright (never left upside down).
            s.spin = 2 * .pi * easeOutD(min(1, k / 0.7))
            if k < 0.45 {
                s.pose = .startled
                s.h += 0.3 * sin(.pi * k / 0.45)
            } else {
                s.h += 1.4 * easeInD(min(1, (k - 0.45) / 0.8))
                s.pose = flapPose
            }
        }
        return s
    }
}
