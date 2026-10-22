import Foundation
import Observation

/// Thin adapter between the shared, renderer-free rules (SquatDetector, SimulatedSquat, TeamChallenge — the same
/// files Revision 3 compiles) and the 3D view. No scoring rules live here: contributions, deduplication,
/// team/partial outcomes and bonuses all come from `TeamChallenge`.
@MainActor
final class Coop3D {
    enum Feedback {
        case provisional(Zone)
        case contributed(Zone, banked: Int)
        case rep(Zone, total: Int)
        case incomplete(Zone)
        case resolved(TeamChallenge.Outcome, bonus: Int)
    }

    private(set) var challenge: TeamChallenge?
    private var detectors: [Zone: SquatDetector] = [.left: SquatDetector(), .right: SquatDetector()]
    private var sims: [Zone: SimulatedSquat] = [:]
    private var plans: [Zone: (time: Double, peak: Double)] = [:]
    private(set) var squats: [Zone: Int] = [.left: 0, .right: 0]
    private(set) var depth: [Zone: Double] = [.left: 0, .right: 0]
    private var counter = 0
    var onFeedback: ((Feedback) -> Void)?

    /// Deterministic demo script: Parent at +0.3 s, Child at +1.3 s; every third gate the Child sits it out.
    func challengeWarned(at time: Double) {
        counter += 1
        challenge = TeamChallenge(id: counter, participants: [.left, .right])
        plans[.left] = (time + 0.3, 0.85)
        if counter % 3 != 0 { plans[.right] = (time + 1.3, 0.85) }
        log("challenge #\(counter) warning", time)
    }

    func resolve(at time: Double) {
        guard var c = challenge else { return }
        let (outcome, bonus) = c.resolve()
        challenge = c
        log("challenge #\(c.id) resolved: \(outcome) bonus \(bonus)", time)
        onFeedback?(.resolved(outcome, bonus: bonus))
    }

    /// Same event semantics as Revision 3's `handle(_:)`: descent = provisional, bottom = contribution (once),
    /// stand-up = completed rep. Visual feedback never feeds back into counts.
    func update(at time: Double) {
        for zone in Zone.allCases {
            if let plan = plans[zone], time >= plan.time {
                sims[zone] = SimulatedSquat(start: time, peak: plan.peak)
                plans[zone] = nil
            }
            let d = sims[zone]?.depth(at: time) ?? 0
            if let sim = sims[zone], time - sim.start > sim.duration + 0.2 { sims[zone] = nil }
            guard var detector = detectors[zone] else { continue }
            let events = detector.update(depth: d, at: time)
            detectors[zone] = detector
            depth[zone] = detector.depth
            for event in events {
                switch event {
                case .descentStarted:
                    if challenge?.movementStarted(zone) == true { onFeedback?(.provisional(zone)) }
                case .bottomReached:
                    if let banked = challenge?.contribute(zone, at: time), banked > 0 {
                        log("\(zone == .left ? "PARENT" : "CHILD") contributed", time)
                        onFeedback?(.contributed(zone, banked: banked))
                    }
                case .repCompleted:
                    squats[zone, default: 0] += 1
                    onFeedback?(.rep(zone, total: squats[zone] ?? 0))
                case .aborted:
                    if let c = challenge, c.isOpen, c.started.contains(zone), !c.contributed.contains(zone) {
                        onFeedback?(.incomplete(zone))
                    }
                case .found, .lost:
                    break
                }
            }
        }
    }

    private func log(_ message: String, _ time: Double) {
        print(String(format: "[GAME3D] t=%7.2f %@", time, message))
    }
}

/// SwiftUI-facing HUD state (low-frequency; the 3D scene itself is updated by RealityKit, not SwiftUI).
@Observable
final class HUD3DModel {
    var banner: String = ""
    var subBanner: String = ""
    var bannerColor: UIColorBox = .yellow
    var bannerID = 0
    var lockVisible = false
    var lockFilled: Set<Zone> = []
    var squats: [Zone: Int] = [.left: 0, .right: 0]
    var teamPower = 0
    var flashID = 0
    var metrics = "measuring…"
}

enum UIColorBox { case yellow, mint, coral, white }
