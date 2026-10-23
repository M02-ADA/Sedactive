import Foundation

/// Catches an upside-down camera feed from the picture itself, whatever caused it (an iPad model whose front camera
/// sits on another edge, the other landscape orientation, a mirroring/rotation order difference, a Mac emulating an
/// iPad orientation). An upside-down frame shows itself the same way every time: body-pose detection finds nobody
/// upright, while the same frame turned 180° does contain people. Segmentation still cuts those people out, so
/// without this guard they appear as a large inverted cutout hanging from the top of the screen.
///
/// Per processed frame the pipeline reports how many people the regular (current-orientation) pass found. After
/// `missFramesBeforeProbe` empty frames it probes the opposite orientation every `probeEvery` frames; only
/// `probesToFlip` consecutive successful probes toggle the correction, so a moment with nobody in view (or a
/// pose glitch) never flips the picture. The same rule turns the correction back off if the device is rotated.
nonisolated struct OrientationGuard: Sendable {
    var missFramesBeforeProbe = 15
    var probeEvery = 6
    var probesToFlip = 3
    /// The pipeline rotates every frame 180° before Vision and compositing while this is set.
    private(set) var flipped = false
    private var misses = 0
    private var sinceProbe = 0
    private var probeHits = 0

    enum Decision: Equatable, Sendable { case none, probe, flip }

    init(flipped: Bool = false) { self.flipped = flipped }

    /// After the regular pose pass. People found in the current orientation means it is right.
    mutating func observe(people: Int) -> Decision {
        if people > 0 {
            misses = 0
            sinceProbe = 0
            probeHits = 0
            return .none
        }
        misses += 1
        guard misses >= missFramesBeforeProbe else { return .none }
        sinceProbe += 1
        guard sinceProbe >= probeEvery else { return .none }
        sinceProbe = 0
        return .probe
    }

    /// After a probe of the opposite orientation.
    mutating func probeResult(people: Int) -> Decision {
        guard people > 0 else { probeHits = 0; return .none }
        probeHits += 1
        guard probeHits >= probesToFlip else { return .none }
        flipped.toggle()
        misses = 0
        sinceProbe = 0
        probeHits = 0
        return .flip
    }
}
